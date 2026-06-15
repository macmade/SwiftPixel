/*******************************************************************************
 * The MIT License (MIT)
 *
 * Copyright (c) 2025, Jean-David Gadina - www.xs-labs.com
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
import SwiftUtilities

/// A namespace of helpers for decoding and analyzing raw pixel data.
public enum PixelUtilities
{
    /// Returns `width × height × channels`, throwing instead of trapping if the
    /// product overflows `Int`.
    ///
    /// Used to validate image geometry before allocating or comparing sample
    /// counts, so a pathological dimension reports a `RuntimeError` rather than
    /// crashing on multiplication overflow.
    ///
    /// - Parameters:
    ///   - width:    The image width in pixels.
    ///   - height:   The image height in pixels.
    ///   - channels: The number of samples per pixel.
    ///
    /// - Returns: The total sample count.
    ///
    /// - Throws: A `RuntimeError` if the product overflows `Int`.
    internal static func checkedSampleCount( width: Int, height: Int, channels: Int ) throws -> Int
    {
        let ( pixels, pixelsOverflow ) = width.multipliedReportingOverflow( by: height )
        let ( total,  totalOverflow  ) = pixels.multipliedReportingOverflow( by: channels )

        guard pixelsOverflow == false, totalOverflow == false
        else
        {
            throw RuntimeError( message: "Image geometry overflows Int: \( width ) x \( height ) x \( channels )" )
        }

        return total
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
    ///
    /// - Returns: `width × height` samples as `Double`s, in row-major order.
    ///
    /// - Throws: A `RuntimeError` if `data`'s length does not match the expected
    ///           size for the given geometry and format.
    public static func readRawPixels( data: Data, width: Int, height: Int, bitsPerPixel: BitsPerPixel ) throws -> [ Double ]
    {
        let count = try Self.checkedSampleCount( width: width, height: height, channels: 1 )
        let size  = bitsPerPixel.size( numberOfPixels: count )

        guard data.count == size
        else
        {
            throw RuntimeError( message: "Data size does not match expected size: \( data.count ) != \( size )" )
        }

        var result = [ Double ]( repeating: 0.0, count: count )

        try result.withUnsafeMutableBufferPointer
        {
            let resultBuffer = UnsafeMutableSendable( $0 )

            try data.withUnsafeBytes
            {
                guard let baseAddress = $0.baseAddress
                else
                {
                    throw RuntimeError( message: "Failed to access data buffer" )
                }

                let base = UnsafeSendable( baseAddress )

                switch bitsPerPixel
                {
                    case .uint8:

                        DispatchQueue.concurrentPerform( iterations: count )
                        {
                            resultBuffer.value[ $0 ] = Double( base.value.loadUnaligned( fromByteOffset: $0, as: UInt8.self ) )
                        }

                    case .int16:

                        DispatchQueue.concurrentPerform( iterations: count )
                        {
                            resultBuffer.value[ $0 ] = Double( Int16( bigEndian: base.value.loadUnaligned( fromByteOffset: $0 * 2, as: Int16.self ) ) )
                        }

                    case .int32:

                        DispatchQueue.concurrentPerform( iterations: count )
                        {
                            resultBuffer.value[ $0 ] = Double( Int32( bigEndian: base.value.loadUnaligned( fromByteOffset: $0 * 4, as: Int32.self ) ) )
                        }

                    case .float32:

                        DispatchQueue.concurrentPerform( iterations: count )
                        {
                            resultBuffer.value[ $0 ] = Double( Float32( bitPattern: UInt32( bigEndian: base.value.loadUnaligned( fromByteOffset: $0 * 4, as: UInt32.self ) ) ) )
                        }

                    case .float64:

                        DispatchQueue.concurrentPerform( iterations: count )
                        {
                            resultBuffer.value[ $0 ] = Double( bitPattern: UInt64( bigEndian: base.value.loadUnaligned( fromByteOffset: $0 * 8, as: UInt64.self ) ) )
                        }
                }
            }
        }

        return result
    }

    /// Returns the values at the given lower and upper percentiles of `array`.
    ///
    /// The array is sorted and the bounds are linearly interpolated between
    /// adjacent samples. `lower` and `upper` are percentages in `0...100`; values
    /// outside that range are clamped, and if `lower` exceeds `upper` they are
    /// reordered, so the call never traps on out-of-range input.
    ///
    /// - Parameters:
    ///   - array: The samples to analyze. An empty array yields `(0, 0)`.
    ///   - lower: The lower percentile, as a percentage in `0...100`.
    ///   - upper: The upper percentile, as a percentage in `0...100`.
    ///
    /// - Returns: The interpolated values at the lower and upper percentiles.
    public static func percentileBounds( in array: [ Double ], lower: Double, upper: Double ) -> ( lower: Double, upper: Double )
    {
        guard array.isEmpty == false
        else
        {
            return ( 0, 0 )
        }

        var sorted = array

        vDSP.sort( &sorted, sortOrder: .ascending )

        let clampedLower = Swift.min( Swift.max( lower, 0.0 ), 100.0 )
        let clampedUpper = Swift.min( Swift.max( upper, 0.0 ), 100.0 )
        let orderedLower = Swift.min( clampedLower, clampedUpper )
        let orderedUpper = Swift.max( clampedLower, clampedUpper )

        let lowerPosition = Double( sorted.count - 1 ) * ( orderedLower / 100.0 )
        let upperPosition = Double( sorted.count - 1 ) * ( orderedUpper / 100.0 )
        let lowerIndex    = Int( floor( lowerPosition ) )
        let upperIndex    = Int( floor( upperPosition ) )
        let lowerWeight   = lowerPosition - Double( lowerIndex )
        let upperWeight   = upperPosition - Double( upperIndex )
        let lowerValue    = sorted[ lowerIndex ] * ( 1.0 - lowerWeight ) + sorted[ Swift.min( lowerIndex + 1, sorted.count - 1 ) ] * lowerWeight
        let upperValue    = sorted[ upperIndex ] * ( 1.0 - upperWeight ) + sorted[ Swift.min( upperIndex + 1, sorted.count - 1 ) ] * upperWeight

        return ( lower: lowerValue, upper: upperValue )
    }
}
