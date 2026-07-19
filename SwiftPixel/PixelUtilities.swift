/*******************************************************************************
 * The MIT License (MIT)
 *
 * Copyright (c) 2026, Jean-David Gadina - www.xs-labs.com
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the Software), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 ******************************************************************************/

import Accelerate
import Foundation

/// A namespace of helpers for decoding and analyzing raw pixel data.
public enum PixelUtilities
{
    /// Returns `width × height × channels`, throwing instead of trapping if the
    /// product overflows `Int`.
    ///
    /// Used to validate image geometry before allocating or comparing sample
    /// counts, so a pathological dimension reports a `PixelBufferError` rather than
    /// crashing on multiplication overflow.
    ///
    /// - Parameters:
    ///   - width:    The image width in pixels.
    ///   - height:   The image height in pixels.
    ///   - channels: The number of samples per pixel.
    ///
    /// - Returns: The total sample count.
    ///
    /// - Throws: A `PixelBufferError` if the product overflows `Int`.
    internal static func checkedSampleCount( width: Int, height: Int, channels: Int ) throws -> Int
    {
        let ( pixels, pixelsOverflow ) = width.multipliedReportingOverflow( by: height )
        let ( total,  totalOverflow  ) = pixels.multipliedReportingOverflow( by: channels )

        guard pixelsOverflow == false, totalOverflow == false
        else
        {
            throw PixelBufferError.geometryOverflow( width: width, height: height, channels: channels )
        }

        return total
    }

    /// Runs `body` for each index in `0 ..< iterations`, serially below
    /// `threshold` and via `DispatchQueue.concurrentPerform` at or above it.
    ///
    /// Small passes skip the fan-out/join overhead of `concurrentPerform`; the
    /// result is identical regardless of the path taken, so `body` must remain
    /// safe to run concurrently (each index writing its own output).
    ///
    /// - Parameters:
    ///   - iterations: The number of indices to process.
    ///   - threshold:  The iteration count at or above which to parallelize.
    ///   - body:       The work to run for each index.
    internal static func parallelOrSerial( iterations: Int, threshold: Int = 4096, _ body: @Sendable ( Int ) -> Void )
    {
        if iterations < threshold
        {
            for index in 0 ..< iterations
            {
                body( index )
            }
        }
        else
        {
            DispatchQueue.concurrentPerform( iterations: iterations, execute: body )
        }
    }

    /// Decodes raw, single-channel image data into an array of `Double` samples.
    ///
    /// The bytes are interpreted according to the FITS `BITPIX` convention
    /// described by `bitsPerPixel`: 8-bit samples are unsigned, 16- and 32-bit
    /// integer samples are signed, and all multi-byte samples (integer and
    /// floating-point) are decoded big-endian. No `BZERO`/`BSCALE` rescaling is
    /// applied — each sample is converted to `Double` at its stored value.
    ///
    /// Decoding is parallelized across samples.
    ///
    /// - Parameters:
    ///   - data:         The raw sample bytes. Its length must equal
    ///                   `bitsPerPixel.size( numberOfPixels: width × height )`.
    ///   - width:        The image width in pixels.
    ///   - height:       The image height in pixels.
    ///   - bitsPerPixel: The sample format of `data`.
    ///   - blank:        The FITS `BLANK` sentinel raw value for an integer image
    ///                   (FITS 4.0 §5.4.2.2): a sample equal to it is an undefined
    ///                   pixel and decodes to NaN, as a float image's blanks
    ///                   already do. `nil` (the default) masks nothing, and it is
    ///                   ignored for floating-point formats.
    ///
    /// - Returns: `width × height` samples as `Double`s, in row-major order, or an
    ///            empty array for a zero-area image.
    ///
    /// - Throws: A `PixelBufferError` if `data`'s length does not match the expected
    ///           size for the given geometry and format, or the byte size overflows
    ///           `Int`.
    public static func readRawPixels( data: Data, width: Int, height: Int, bitsPerPixel: BitsPerPixel, blank: Int64? = nil ) throws -> [ Double ]
    {
        let count = try Self.checkedSampleCount( width: width, height: height, channels: 1 )

        guard let size = bitsPerPixel.size( numberOfPixels: count )
        else
        {
            throw PixelBufferError.sizeOverflow( sampleCount: count )
        }

        guard data.count == size
        else
        {
            throw PixelBufferError.dataSizeMismatch( expected: size, actual: data.count )
        }

        guard count > 0
        else
        {
            // A zero-area image has no samples to read; return an empty array rather
            // than reaching the nil-baseAddress guard on empty `data`, which some
            // platforms trip.
            return []
        }

        var result = [ Double ]( repeating: 0.0, count: count )

        try result.withUnsafeMutableBufferPointer
        {
            nonisolated( unsafe ) let resultBuffer = $0

            try data.withUnsafeBytes
            {
                guard let baseAddress = $0.baseAddress
                else
                {
                    throw PixelBufferError.bufferAccessFailed( role: .data )
                }

                nonisolated( unsafe ) let base = baseAddress

                switch bitsPerPixel
                {
                    case .uint8:

                        Self.parallelOrSerial( iterations: count )
                        {
                            resultBuffer[ $0 ] = Double( base.loadUnaligned( fromByteOffset: $0, as: UInt8.self ) )
                        }

                    case .int16:

                        Self.parallelOrSerial( iterations: count )
                        {
                            resultBuffer[ $0 ] = Double( Int16( bigEndian: base.loadUnaligned( fromByteOffset: $0 * 2, as: Int16.self ) ) )
                        }

                    case .int32:

                        Self.parallelOrSerial( iterations: count )
                        {
                            resultBuffer[ $0 ] = Double( Int32( bigEndian: base.loadUnaligned( fromByteOffset: $0 * 4, as: Int32.self ) ) )
                        }

                    case .float32:

                        Self.parallelOrSerial( iterations: count )
                        {
                            resultBuffer[ $0 ] = Double( Float32( bitPattern: UInt32( bigEndian: base.loadUnaligned( fromByteOffset: $0 * 4, as: UInt32.self ) ) ) )
                        }

                    case .float64:

                        Self.parallelOrSerial( iterations: count )
                        {
                            resultBuffer[ $0 ] = Double( bitPattern: UInt64( bigEndian: base.loadUnaligned( fromByteOffset: $0 * 8, as: UInt64.self ) ) )
                        }
                }
            }
        }

        // FITS marks undefined pixels in an integer image with a BLANK sentinel
        // raw value (FITS 4.0 §5.4.2.2); map them to NaN — the same read step that
        // already yields NaN for a float image's blanks — so the non-finite
        // filtering statistics downstream skip them. A float image marks blanks
        // with NaN directly, so BLANK does not apply to .float32 / .float64.
        if let blank, bitsPerPixel.isInteger
        {
            let sentinel = Double( blank )

            result.withUnsafeMutableBufferPointer
            {
                nonisolated( unsafe ) let buffer = $0

                Self.parallelOrSerial( iterations: count )
                {
                    if buffer[ $0 ] == sentinel { buffer[ $0 ] = Double.nan }
                }
            }
        }

        return result
    }

    /// Interleaves separate channel planes into a single sample array.
    ///
    /// Each plane holds one channel's samples in row-major order (e.g. the red,
    /// green and blue planes of a band-sequential colour image); the result packs
    /// them per pixel — `[p0c0, p0c1, …, p1c0, p1c1, …]` — the interleaved layout
    /// ``PixelBuffer`` and the pixel pipeline expect. Each plane is scattered with a
    /// single strided Accelerate move (contiguous read, `channels`-strided write).
    ///
    /// - Parameter planes: The channel planes, all the same non-zero length.
    /// - Returns: The interleaved samples, `planes.count × planeLength` long.
    /// - Throws: A `PixelInterleaveError` when there are no planes, a plane is empty, or the
    ///           planes differ in length.
    public static func interleave( planes: [ [ Double ] ] ) throws -> [ Double ]
    {
        guard let first = planes.first, first.isEmpty == false
        else
        {
            throw PixelInterleaveError.noNonEmptyPlane
        }

        let count    = first.count
        let channels = planes.count

        guard planes.allSatisfy( { $0.count == count } )
        else
        {
            throw PixelInterleaveError.unequalPlaneLengths
        }

        var result = [ Double ]( repeating: 0, count: count * channels )

        result.withUnsafeMutableBufferPointer
        {
            output in

            guard let destination = output.baseAddress
            else
            {
                return
            }

            // Scatter each contiguous plane into every `channels`-th output slot, so
            // channel `c` fills indices c, c + channels, c + 2·channels, …
            planes.enumerated().forEach
            {
                channel, plane in

                plane.withUnsafeBufferPointer
                {
                    source in

                    guard let base = source.baseAddress
                    else
                    {
                        return
                    }

                    // Copy `count` samples as an M=1 column, N=count rows "matrix" from
                    // the contiguous plane (row stride 1) into the output starting at
                    // `channel` with a row stride of `channels`, i.e. every channels-th
                    // slot. `vDSP_mmovD` is the non-deprecated Accelerate strided move.
                    vDSP_mmovD( base, destination + channel, 1, vDSP_Length( count ), 1, vDSP_Length( channels ) )
                }
            }
        }

        return result
    }

    /// Returns the values at the given lower and upper percentiles of `array`.
    ///
    /// The bounds are linearly interpolated between adjacent order statistics at
    /// position `(n − 1)·p/100`. Rather than fully sorting, only the two (or four)
    /// bracketing order statistics are located with an `O(n)` in-place selection
    /// (quickselect), reproducing the sorted result exactly. `lower` and `upper`
    /// are percentages in `0...100`; values outside that range are clamped, and if
    /// `lower` exceeds `upper` they are reordered, so the call never traps on
    /// out-of-range input.
    ///
    /// Non-finite samples (NaN / ±Inf, e.g. FITS blank pixels) are ignored, so
    /// they cannot give the ordering an undefined comparison; an array with no
    /// finite samples is treated like an empty one.
    ///
    /// - Parameters:
    ///   - array: The samples to analyze. An empty array — or one with no finite
    ///            samples — yields `(0, 0)`.
    ///   - lower: The lower percentile, as a percentage in `0...100`.
    ///   - upper: The upper percentile, as a percentage in `0...100`.
    ///
    /// - Returns: The interpolated values at the lower and upper percentiles.
    public static func percentileBounds( in array: [ Double ], lower: Double, upper: Double ) -> ( lower: Double, upper: Double )
    {
        // Drop non-finite blanks before selecting; the common all-finite case skips
        // the filtering copy entirely.
        let finite = array.contains { $0.isFinite == false } ? array.filter { $0.isFinite } : array

        guard finite.isEmpty == false
        else
        {
            return ( 0, 0 )
        }

        let clampedLower  = Swift.min( Swift.max( lower, 0.0 ), 100.0 )
        let clampedUpper  = Swift.min( Swift.max( upper, 0.0 ), 100.0 )
        let orderedLower  = Swift.min( clampedLower, clampedUpper )
        let orderedUpper  = Swift.max( clampedLower, clampedUpper )
        let lowerPosition = Double( finite.count - 1 ) * ( orderedLower / 100.0 )
        let upperPosition = Double( finite.count - 1 ) * ( orderedUpper / 100.0 )

        // One mutable copy (the same a full sort would need) is partitioned in place
        // by the selections below. When both percentiles coincide (e.g. the median),
        // the single result is reused rather than selected twice.
        var buffer = finite

        let lowerValue = Self.interpolatedOrderStatistic( &buffer, at: lowerPosition )
        let upperValue = upperPosition == lowerPosition ? lowerValue : Self.interpolatedOrderStatistic( &buffer, at: upperPosition )

        return ( lower: lowerValue, upper: upperValue )
    }

    /// The smallest and largest finite values in a set of samples.
    ///
    /// Non-finite samples (NaN / ±Inf, e.g. FITS blank pixels) are ignored,
    /// matching the sibling robust helpers ``median(_:)`` /
    /// ``medianAbsoluteDeviation(_:around:)`` /
    /// ``percentileBounds(in:lower:upper:)``: unlike the standard-library `min()` /
    /// `max()`, a leading `NaN` cannot poison the result and a `±Inf` cannot leak
    /// into the extremes. The common all-finite case skips the filtering copy
    /// entirely, so callers that need blank-safe extremes can route through this
    /// single layer rather than touching raw `min()` / `max()`.
    ///
    /// - Parameter values: The samples to summarize.
    /// - Returns: The minimum and maximum finite samples, or `nil` for an empty
    ///   input or one with no finite samples.
    public static func finiteExtent( _ values: [ Double ] ) -> ( minimum: Double, maximum: Double )?
    {
        // Drop non-finite blanks before scanning; the common all-finite case
        // reuses the input without a copy, exactly as the median / percentile
        // helpers do.
        let finite = values.contains { $0.isFinite == false } ? values.filter { $0.isFinite } : values

        guard let minimum = finite.min(), let maximum = finite.max()
        else
        {
            return nil
        }

        return ( minimum: minimum, maximum: maximum )
    }

    /// The median of a set of values: the middle value for an odd count, the
    /// average of the two middle values for an even count, or `nil` when empty.
    ///
    /// Generic over `BinaryFloatingPoint` (and not integers) because the
    /// even-count case averages the two middle values, which integer division
    /// would truncate. A concrete, Accelerate-backed overload exists for
    /// `[Double]`.
    ///
    /// Non-finite samples (NaN / ±Inf) are ignored, matching the `[Double]`
    /// overload; an input with no finite samples has no median.
    ///
    /// - Parameter values: The values to summarize.
    /// - Returns: The median, or `nil` for an empty input or one with no finite
    ///   samples.
    public static func median< T: BinaryFloatingPoint >( _ values: [ T ] ) -> T?
    {
        let finite = values.contains { $0.isFinite == false } ? values.filter { $0.isFinite } : values

        guard finite.isEmpty == false
        else
        {
            return nil
        }

        let sorted = finite.sorted()
        let middle = sorted.count / 2

        if sorted.count.isMultiple( of: 2 )
        {
            return ( sorted[ middle - 1 ] + sorted[ middle ] ) / 2
        }

        return sorted[ middle ]
    }

    /// The median of a set of `Double` values — an Accelerate-backed fast path.
    ///
    /// The median is the 50th percentile, so this reuses
    /// ``percentileBounds(in:lower:upper:)`` (an `O(n)` in-place selection +
    /// interpolation) rather than carrying its own. Its interpolation matches the
    /// generic ``median(_:)``: the exact middle value for an odd count, the
    /// average of the two middle values for an even count.
    ///
    /// Non-finite samples (NaN / ±Inf) are ignored via
    /// ``percentileBounds(in:lower:upper:)``; an input with no finite samples has
    /// no median, so the two overloads agree on `nil` there.
    ///
    /// - Parameter values: The values to summarize.
    /// - Returns: The median, or `nil` for an empty input or one with no finite
    ///   samples.
    public static func median( _ values: [ Double ] ) -> Double?
    {
        guard values.contains( where: { $0.isFinite } )
        else
        {
            return nil
        }

        return self.percentileBounds( in: values, lower: 50, upper: 50 ).lower
    }

    /// The median absolute deviation of a set of values about a center — a robust
    /// measure of spread.
    ///
    /// Non-finite samples (NaN / ±Inf) are ignored: a non-finite deviation is
    /// dropped by the underlying median.
    ///
    /// - Parameters:
    ///   - values: The values to summarize.
    ///   - center: The center to measure deviations from (typically the median).
    /// - Returns: The median of the absolute deviations, or `nil` for an empty
    ///   input or one with no finite samples.
    public static func medianAbsoluteDeviation< T: BinaryFloatingPoint >( _ values: [ T ], around center: T ) -> T?
    {
        self.median( values.map { abs( $0 - center ) } )
    }

    /// The median absolute deviation of a set of `Double` values about a center —
    /// the Accelerate-backed counterpart to the generic
    /// ``medianAbsoluteDeviation(_:around:)``.
    ///
    /// The absolute deviations `|value − center|` are formed with Accelerate into a
    /// single buffer (a `vsadd` + `vabs` pair, avoiding the generic overload's extra
    /// allocation), then their median is taken with the same `O(n)` selection as
    /// ``median(_:)``. Non-finite samples (NaN / ±Inf) are ignored, as in the
    /// generic overload.
    ///
    /// - Parameters:
    ///   - values: The values to summarize.
    ///   - center: The center to measure deviations from (typically the median).
    /// - Returns: The median of the absolute deviations, or `nil` for an empty
    ///   input or one with no finite samples.
    public static func medianAbsoluteDeviation( _ values: [ Double ], around center: Double ) -> Double?
    {
        guard values.isEmpty == false
        else
        {
            return nil
        }

        // Form |values − center| into a single buffer with Accelerate, dropping the
        // extra full-array allocation the generic `median(values.map { … })` path
        // makes. `a − b` equals `a + (−b)` and `vDSP_vabsD` clears the sign bit, so
        // each deviation is bit-identical to the scalar `abs($0 − center)`.
        var deviations = [ Double ]( repeating: 0.0, count: values.count )

        values.withUnsafeBufferPointer
        {
            input in

            deviations.withUnsafeMutableBufferPointer
            {
                output in

                guard let source = input.baseAddress, let destination = output.baseAddress
                else
                {
                    return
                }

                let count = vDSP_Length( output.count )

                vDSP_vsaddD( source, 1, [ -center ], destination, 1, count )
                vDSP_vabsD( destination, 1, destination, 1, count )
            }
        }

        // Drop non-finite deviations (|±Inf − c|, or any value when the center is
        // non-finite), matching the sort-based median; the common all-finite case
        // keeps the buffer as-is.
        if deviations.contains( where: { $0.isFinite == false } )
        {
            deviations = deviations.filter { $0.isFinite }
        }

        guard deviations.isEmpty == false
        else
        {
            return nil
        }

        // The median is the 50th percentile: interpolate at the midpoint of the
        // finite deviations, exactly as `median(_:)` does via `percentileBounds`.
        return Self.interpolatedOrderStatistic( &deviations, at: Double( deviations.count - 1 ) * 0.5 )
    }

    /// The value at fractional `position` in the ascending order of `buffer`,
    /// linearly interpolated between the two bracketing order statistics — the
    /// exact arithmetic a full ascending sort followed by interpolation would
    /// produce, but via an `O(n)` in-place selection instead of an `O(n log n)`
    /// sort.
    ///
    /// `buffer` is partitioned in place as a side effect. It must be non-empty and
    /// hold only finite values (callers filter non-finite samples first), and
    /// `position` must lie in `0 ... buffer.count − 1`.
    ///
    /// - Parameters:
    ///   - buffer:   The finite samples to select from; reordered in place.
    ///   - position: The fractional index into the ascending order.
    ///
    /// - Returns: The interpolated value at `position`.
    private static func interpolatedOrderStatistic( _ buffer: inout [ Double ], at position: Double ) -> Double
    {
        let index  = Int( floor( position ) )
        let weight = position - Double( index )
        let last   = buffer.count - 1

        Self.quickSelect( &buffer, k: index, low: 0, high: last )

        let lowerValue = buffer[ index ]

        guard index < last
        else
        {
            // The top order statistic: `position` equals `last`, so the weight is
            // zero and the upper term contributes nothing.
            return lowerValue
        }

        // After selecting `index`, every element to its right is ≥ it, so the next
        // order statistic is simply the minimum of that upper partition.
        let upperValue = buffer[ ( index + 1 )... ].min() ?? lowerValue

        return lowerValue * ( 1.0 - weight ) + upperValue * weight
    }

    /// Partitions `buffer[low ... high]` in place until `buffer[k]` holds the
    /// `k`-th smallest value over that range (0-based), with every element to its
    /// left `≤` it and every element to its right `≥` it — the exact value a full
    /// ascending sort would place at index `k`.
    ///
    /// Median-of-three pivoting keeps sorted and reverse-sorted inputs off the
    /// quadratic worst case, and a three-way (Dutch-national-flag) partition keeps
    /// heavily duplicated inputs — a flat calibration frame is the extreme — linear
    /// rather than quadratic. The loop is iterative (it recurses into neither
    /// side), so a multi-megapixel frame cannot overflow the stack; each pass
    /// either returns or strictly shrinks the active range, so it always
    /// terminates.
    ///
    /// - Parameters:
    ///   - buffer: The samples to partition, reordered in place.
    ///   - k:      The 0-based rank to resolve.
    ///   - low:    The inclusive lower bound of the active range.
    ///   - high:   The inclusive upper bound of the active range.
    private static func quickSelect( _ buffer: inout [ Double ], k: Int, low: Int, high: Int )
    {
        var lo = low
        var hi = high

        while lo < hi
        {
            let mid   = lo + ( hi - lo ) / 2
            let pivot = Self.medianOfThree( buffer[ lo ], buffer[ mid ], buffer[ hi ] )

            // Three-way partition: [lo, lt) < pivot, [lt, gt] == pivot, (gt, hi] > pivot.
            var lt = lo
            var gt = hi
            var i  = lo

            while i <= gt
            {
                let value = buffer[ i ]

                if value < pivot
                {
                    buffer.swapAt( lt, i )

                    lt += 1
                    i  += 1
                }
                else if value > pivot
                {
                    buffer.swapAt( i, gt )

                    gt -= 1
                }
                else
                {
                    i += 1
                }
            }

            // The equal block [lt, gt] is now in its final sorted position.
            if k < lt
            {
                hi = lt - 1
            }
            else if k > gt
            {
                lo = gt + 1
            }
            else
            {
                return
            }
        }
    }

    /// The median of three values, used to pick a quickselect pivot that resists
    /// the sorted / reverse-sorted worst case. The result is always one of the
    /// three inputs, so the pivot is a value actually present in the range being
    /// partitioned.
    ///
    /// - Parameters:
    ///   - a: The first value.
    ///   - b: The second value.
    ///   - c: The third value.
    ///
    /// - Returns: The middle of the three by value.
    private static func medianOfThree( _ a: Double, _ b: Double, _ c: Double ) -> Double
    {
        if a < b
        {
            if b < c { return b }

            return a < c ? c : a
        }

        if a < c { return a }

        return b < c ? c : b
    }

    /// The scale factor that converts a median absolute deviation (MAD) into a
    /// robust estimate of the standard deviation for normally distributed data —
    /// the *normalized* MAD, `MADN = 1.4826 · MAD`.
    ///
    /// Robust image pipelines (notably PixInsight's Screen Transfer Function)
    /// express their clip thresholds in units of this normalized deviation, not
    /// the raw MAD, so a `k`-sigma clip is `k · MADN` rather than `k · MAD`.
    public static let madStandardDeviationScale = 1.4826

    /// The PixInsight-style midtones transfer function (MTF),
    /// `mtf(m, x) = ((m − 1)·x) / ((2m − 1)·x − m)`.
    ///
    /// This is the non-linear curve at the heart of a Screen Transfer Function
    /// (STF): the midtones balance `m` bends the tonal response without moving
    /// the black and white points. Its behavior at the degenerate midtones is
    /// well defined for interior inputs — `m = 0` lifts everything to `1`,
    /// `m = 0.5` is the identity, and `m = 1` pushes everything to `0` — and the
    /// input boundaries are fixed points (`x ≤ 0 → 0`, `x ≥ 1 → 1`). For `m` and
    /// `x` both in `(0, 1)` the denominator is never zero, so no divide-by-zero
    /// guard is required.
    ///
    /// - Parameters:
    ///   - m: The midtones balance, expected in `[0, 1]`.
    ///   - x: The input sample, expected in `[0, 1]`.
    /// - Returns: The transferred sample in `[0, 1]`.
    public static func mtf( _ m: Double, _ x: Double ) -> Double
    {
        guard x > 0
        else
        {
            return 0
        }

        guard x < 1
        else
        {
            return 1
        }

        if m <= 0
        {
            return 1
        }

        if m >= 1
        {
            return 0
        }

        return ( ( m - 1.0 ) * x ) / ( ( 2.0 * m - 1.0 ) * x - m )
    }
}

/// A failure originating from interleaving separate channel planes into a single
/// interleaved sample array (see ``PixelUtilities/interleave(planes:)``).
public enum PixelInterleaveError: LocalizedError, Equatable, Sendable
{
    /// No plane, or only empty planes, were provided; at least one non-empty plane
    /// is required.
    case noNonEmptyPlane

    /// The planes differ in length; interleaving requires equal-length planes.
    case unequalPlaneLengths

    /// A human-readable description of the failure.
    public var errorDescription: String?
    {
        switch self
        {
            case .noNonEmptyPlane:

                return "Cannot interleave: at least one non-empty plane is required."

            case .unequalPlaneLengths:

                return "Cannot interleave planes of unequal length."
        }
    }
}
