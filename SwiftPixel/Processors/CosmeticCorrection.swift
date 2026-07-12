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

import Foundation

public extension Processors
{
    /// Repairs isolated defective (hot/cold) pixels on a raw buffer.
    ///
    /// Each sample is compared against its *same-kind* neighbours — the lattice of
    /// which depends on the source ``Layout`` — using a robust outlier test (the
    /// neighbour median and a MAD-based scale). A sample flagged as a defect is
    /// replaced with the neighbour median; every other sample is left untouched.
    /// The pass reads from the original samples and writes into a copy, so a
    /// correction never influences the detection of an adjacent pixel.
    ///
    /// The stage is value-range-agnostic: it neither requires nor changes
    /// normalization, and is intended to run on the raw mosaic/luminance samples,
    /// before any channel-forming or normalization stage, so a defect is repaired
    /// before demosaicing can smear it across its neighbours.
    struct CosmeticCorrection: PixelProcessor, Equatable
    {
        /// The neighbour lattice used to gather a sample's same-kind neighbours.
        ///
        /// Selects both the sampling *step* (1 or 2) and how many interleaved
        /// channels the buffer must carry: a shift of 2 lands on the same cell of a
        /// 2×2 CFA tile — i.e. the same Bayer colour — for any pattern, so the CFA
        /// case needs no knowledge of the concrete pattern.
        public enum Layout: Sendable, Equatable, CustomStringConvertible
        {
            /// A single-channel monochrome frame: 8 step-1 neighbours.
            case mono

            /// A single-channel colour-filter-array frame: 8 step-2 neighbours, so
            /// only same-colour sites are compared regardless of Bayer pattern.
            case cfa

            /// An interleaved 3-channel RGB frame: 8 step-1 neighbours, each read
            /// from the matching channel.
            case rgb

            /// The neighbour sampling step: 2 for ``cfa`` (skip to the same CFA
            /// colour), 1 otherwise.
            public var step: Int
            {
                self == .cfa ? 2 : 1
            }

            /// The number of interleaved channels a buffer of this layout carries:
            /// 3 for ``rgb``, 1 otherwise.
            public var channels: Int
            {
                self == .rgb ? 3 : 1
            }

            /// A short, human-readable name for the layout.
            public var description: String
            {
                switch self
                {
                    case .mono: return "Mono"
                    case .cfa:  return "CFA"
                    case .rgb:  return "RGB"
                }
            }
        }

        /// The detection and correction parameters.
        ///
        /// Hot- and cold-pixel correction are independently togglable, each with
        /// its own robust threshold `k` (higher is more conservative), under a
        /// master ``isEnabled`` switch.
        public struct Parameters: Sendable, Equatable, CustomStringConvertible
        {
            /// Whether the stage runs at all. When `false`, ``process(buffer:)`` is
            /// a no-op.
            public var isEnabled: Bool

            /// Whether bright outliers (hot pixels) are repaired.
            public var correctHot: Bool

            /// The robust threshold `k` for hot detection: a sample is hot when it
            /// exceeds its neighbour median by more than `k · σ` (and is a strict
            /// local maximum). Higher values flag fewer, stronger outliers.
            public var hotThreshold: Double

            /// Whether dark outliers (cold pixels) are repaired.
            public var correctCold: Bool

            /// The robust threshold `k` for cold detection: a sample is cold when it
            /// falls below its neighbour median by more than `k · σ` (and is a
            /// strict local minimum). Higher values flag fewer, stronger outliers.
            public var coldThreshold: Double

            /// A conservative, enabled default.
            ///
            /// Both corrections are on with a high threshold, so — together with the
            /// strict-local-extreme guard — only unambiguous, isolated single-pixel
            /// spikes are touched and multi-pixel features (e.g. faint stars) are
            /// preserved. The concrete thresholds are provisional and are settled
            /// empirically in a later milestone.
            public static let `default` = Parameters( isEnabled: true, correctHot: true, hotThreshold: 8.0, correctCold: true, coldThreshold: 8.0 )

            /// Creates a set of parameters.
            ///
            /// - Parameters:
            ///   - isEnabled:     Whether the stage runs at all.
            ///   - correctHot:    Whether bright outliers are repaired.
            ///   - hotThreshold:  The robust threshold `k` for hot detection.
            ///   - correctCold:   Whether dark outliers are repaired.
            ///   - coldThreshold: The robust threshold `k` for cold detection.
            public init( isEnabled: Bool, correctHot: Bool, hotThreshold: Double, correctCold: Bool, coldThreshold: Double )
            {
                self.isEnabled     = isEnabled
                self.correctHot    = correctHot
                self.hotThreshold  = hotThreshold
                self.correctCold   = correctCold
                self.coldThreshold = coldThreshold
            }

            /// A human-readable summary of the parameters.
            public var description: String
            {
                "isEnabled: \( self.isEnabled ), hot: \( self.correctHot ) (\( self.hotThreshold )), cold: \( self.correctCold ) (\( self.coldThreshold ))"
            }
        }

        /// The unit neighbour directions (the 8-connected ring), scaled by the
        /// layout's step to form the actual sampling offsets.
        private static let neighbourOffsets: [ ( dx: Int, dy: Int ) ] =
            [
                ( -1, -1 ), ( 0, -1 ), ( 1, -1 ),
                ( -1,  0 ),            ( 1,  0 ),
                ( -1,  1 ), ( 0,  1 ), ( 1,  1 ),
            ]

        /// The scale factor converting a median absolute deviation into a robust
        /// estimate of the standard deviation for normally distributed data.
        private static let robustScaleFactor = 1.4826

        /// A small floor on the robust scale, so a perfectly uniform neighbourhood
        /// (zero MAD) still requires a real margin before a sample is flagged,
        /// rather than any infinitesimal deviation. Provisional; revisited when the
        /// thresholds are settled empirically.
        private static let sigmaFloor = 1e-6

        /// The source layout, selecting the neighbour lattice.
        public let layout: Layout

        /// The detection and correction parameters.
        public let parameters: Parameters

        /// A human-readable name including the active corrections and layout.
        public var name: String
        {
            guard self.parameters.isEnabled
            else
            {
                return "Cosmetic Correction (disabled)"
            }

            let hot  = self.parameters.correctHot  ? String( format: "hot %.02f",  self.parameters.hotThreshold )  : "hot off"
            let cold = self.parameters.correctCold ? String( format: "cold %.02f", self.parameters.coldThreshold ) : "cold off"

            return "Cosmetic Correction (\( hot ), \( cold ), \( self.layout ))"
        }

        /// Creates a cosmetic-correction stage.
        ///
        /// - Parameters:
        ///   - layout:     The source layout, selecting the neighbour lattice.
        ///   - parameters: The detection and correction parameters.
        public init( layout: Layout, parameters: Parameters )
        {
            self.layout     = layout
            self.parameters = parameters
        }

        /// Detects and repairs defective pixels in `buffer`, in place.
        ///
        /// A no-op when the parameters are disabled or neither correction is
        /// requested. The buffer's channel count must match the layout, and its
        /// normalization flag is preserved (the repaired samples stay within the
        /// existing value range).
        ///
        /// - Parameter buffer: The buffer to repair. Its channel count must equal
        ///                     the layout's ``Layout/channels``.
        ///
        /// - Throws: A `PixelBufferError` if the channel count does not match the
        ///           layout or the sample count does not match the geometry.
        public func process( buffer: inout PixelBuffer ) throws
        {
            guard self.parameters.isEnabled, self.parameters.correctHot || self.parameters.correctCold
            else
            {
                return
            }

            guard buffer.channels == self.layout.channels
            else
            {
                throw PixelBufferError.unsupportedChannelCount( actual: buffer.channels, supported: [ self.layout.channels ] )
            }

            let expected = try PixelUtilities.checkedSampleCount( width: buffer.width, height: buffer.height, channels: buffer.channels )

            guard buffer.pixels.count == expected
            else
            {
                throw PixelBufferError.dataSizeMismatch( expected: expected, actual: buffer.pixels.count )
            }

            let corrected = Self.corrected( pixels: buffer.pixels, width: buffer.width, height: buffer.height, channels: buffer.channels, step: self.layout.step, parameters: self.parameters )

            buffer = try PixelBuffer( width: buffer.width, height: buffer.height, channels: buffer.channels, pixels: corrected, isNormalized: buffer.isNormalized )
        }

        /// Returns a copy of `pixels` with every detected defect replaced by its
        /// neighbour median.
        ///
        /// Detection reads only from the original `pixels`, so a correction never
        /// feeds back into an adjacent pixel's detection. The work is parallelized
        /// across samples; each sample writes only its own output slot.
        ///
        /// - Parameters:
        ///   - pixels:     The interleaved source samples, in row-major order.
        ///   - width:      The image width in pixels.
        ///   - height:     The image height in pixels.
        ///   - channels:   The number of interleaved channels.
        ///   - step:       The neighbour sampling step (1 or 2).
        ///   - parameters: The detection and correction parameters.
        ///
        /// - Returns: The repaired samples.
        static func corrected( pixels: [ Double ], width: Int, height: Int, channels: Int, step: Int, parameters: Parameters ) -> [ Double ]
        {
            guard pixels.isEmpty == false
            else
            {
                return pixels
            }

            var output           = pixels
            let sampleCount      = pixels.count
            let neighbourOffsets = Self.neighbourOffsets

            output.withUnsafeMutableBufferPointer
            {
                outputBuffer in

                nonisolated( unsafe ) let out = outputBuffer

                pixels.withUnsafeBufferPointer
                {
                    sourceBuffer in

                    guard let sourceBase = sourceBuffer.baseAddress
                    else
                    {
                        return
                    }

                    nonisolated( unsafe ) let source = sourceBase

                    PixelUtilities.parallelOrSerial( iterations: sampleCount )
                    {
                        sample in

                        let channel = sample % channels
                        let pixel   = sample / channels
                        let x       = pixel % width
                        let y       = pixel / width
                        let value   = source[ sample ]

                        let neighbours = neighbourOffsets.compactMap
                        {
                            offset -> Double? in

                            let nx = x + offset.dx * step
                            let ny = y + offset.dy * step

                            guard nx >= 0, nx < width, ny >= 0, ny < height
                            else
                            {
                                return nil
                            }

                            return source[ ( ny * width + nx ) * channels + channel ]
                        }

                        out[ sample ] = Self.repairedValue( value: value, neighbours: neighbours, parameters: parameters )
                    }
                }
            }

            return output
        }

        /// Returns the repaired value for a single sample: the neighbour median if
        /// the sample is a flagged defect, otherwise the sample unchanged.
        ///
        /// A sample is *hot* when hot correction is enabled, it is a strict local
        /// maximum (exceeds every neighbour), and it exceeds the neighbour median by
        /// more than `hotThreshold · σ`; *cold* is the symmetric condition. The
        /// strict-local-extreme requirement keeps multi-pixel bright features (e.g.
        /// stars) safe, since their peak's neighbours are also bright; the robust
        /// `k · σ` margin keeps textured regions safe.
        ///
        /// - Parameters:
        ///   - value:      The sample under test.
        ///   - neighbours: Its same-kind neighbour samples.
        ///   - parameters: The detection and correction parameters.
        ///
        /// - Returns: The neighbour median if flagged, otherwise `value`.
        static func repairedValue( value: Double, neighbours: [ Double ], parameters: Parameters ) -> Double
        {
            guard neighbours.isEmpty == false
            else
            {
                return value
            }

            // The neighbour set is tiny (at most 8 samples), so a plain sort is
            // cheaper than the Accelerate-backed `PixelUtilities.median`, whose
            // per-call `vDSP.sort` setup would dominate at this size and run once
            // per sample on a multi-megapixel frame. Sorting once yields the
            // median, the minimum and the maximum; a second small sort of the
            // absolute deviations yields the MAD.
            let sorted     = neighbours.sorted()
            let median     = Self.median( ofSorted: sorted )
            let deviations = sorted.map { abs( $0 - median ) }.sorted()
            let mad        = Self.median( ofSorted: deviations )
            let sigma      = Swift.max( Self.robustScaleFactor * mad, Self.sigmaFloor )
            let minimum    = sorted[ 0 ]
            let maximum    = sorted[ sorted.count - 1 ]

            if parameters.correctHot, value > maximum, value - median > parameters.hotThreshold * sigma
            {
                return median
            }

            if parameters.correctCold, value < minimum, median - value > parameters.coldThreshold * sigma
            {
                return median
            }

            return value
        }

        /// The median of an already-ascending-sorted, non-empty set of values: the
        /// middle value for an odd count, the average of the two middle values for
        /// an even count.
        ///
        /// A small-array helper matching ``PixelUtilities/median(_:)``'s
        /// interpolation, used to avoid that helper's per-call `vDSP.sort` on the
        /// tiny neighbour set. The caller guarantees `sorted` is non-empty.
        ///
        /// - Parameter sorted: The values in ascending order; must not be empty.
        ///
        /// - Returns: The median value.
        private static func median( ofSorted sorted: [ Double ] ) -> Double
        {
            let middle = sorted.count / 2

            if sorted.count.isMultiple( of: 2 )
            {
                return ( sorted[ middle - 1 ] + sorted[ middle ] ) / 2.0
            }

            return sorted[ middle ]
        }
    }
}
