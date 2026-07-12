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

public extension Processors
{
    /// Rescales a buffer's samples into the `[0, 1]` range and marks it
    /// normalized.
    ///
    /// A flat (constant) image has no dynamic range and is mapped to all-`0.0`.
    /// After processing, `isNormalized` is `true`.
    struct Normalize: PixelProcessor
    {
        /// The strategy used to choose the input range that maps to `[0, 1]`.
        public enum Mode: Sendable, Equatable, CustomStringConvertible
        {
            /// Maps the buffer's minimum and maximum sample values to `0` and `1`.
            case minMax

            /// Maps the given lower and upper percentiles to `0` and `1`,
            /// clipping values outside that range.
            ///
            /// The associated values are percentages in `0...100` (lower, upper).
            case percentile( Double, Double )

            /// Leaves the samples' values unchanged, assuming they already lie in
            /// `[0, 1]` (clamping any that do not), and marks the buffer normalized.
            ///
            /// The identity mapping, for sources whose samples are already in the
            /// display range — e.g. a photographic image scaled by its bit depth —
            /// so they are shown exactly as authored rather than range-stretched.
            case identity

            /// A human-readable description of the mode and its parameters.
            public var description: String
            {
                switch self
                {
                    case .minMax:                       return "Min/Max"
                    case .percentile( let p1, let p2 ): return String( format: "Percentile - %.02f %.02f", p1, p2 )
                    case .identity:                     return "Identity"
                }
            }
        }

        /// The normalization mode.
        public let mode: Mode

        /// A human-readable name including the mode.
        public var name: String
        {
            "Normalize (\( self.mode ))"
        }

        /// Creates a normalization stage.
        ///
        /// - Parameter mode: The strategy used to choose the input range that
        ///                   maps to `[0, 1]`.
        public init( mode: Mode )
        {
            self.mode = mode
        }

        /// Rescales `buffer` into `[0, 1]` and marks it normalized.
        ///
        /// An empty buffer is simply marked normalized; a constant buffer (no
        /// dynamic range) is mapped to all-`0.0`.
        ///
        /// - Parameter buffer: The buffer to normalize.
        ///
        /// - Note: This stage never fails; it is `throws` only to satisfy the
        ///         ``PixelProcessor`` requirement.
        public func process( buffer: inout PixelBuffer ) throws
        {
            guard buffer.pixels.isEmpty == false
            else
            {
                buffer.withUnsafeMutablePixels( isNormalized: true ) { _ in }

                return
            }

            let count = vDSP_Length( buffer.pixels.count )

            switch self.mode
            {
                case .minMax:

                    var minValue: Double = 0
                    var maxValue: Double = 0

                    vDSP_minvD( buffer.pixels, 1, &minValue, count )
                    vDSP_maxvD( buffer.pixels, 1, &maxValue, count )

                    guard minValue != maxValue
                    else
                    {
                        buffer.withUnsafeMutablePixels( isNormalized: true ) { $0.update( repeating: 0.0 ) }

                        return
                    }

                    let range  = maxValue - minValue
                    let scale  = 1.0 / range
                    let offset = -minValue / range

                    buffer.withUnsafeMutablePixels( isNormalized: true )
                    {
                        guard let base = $0.baseAddress
                        else
                        {
                            return
                        }

                        vDSP_vsmsaD( base, 1, [ scale ], [ offset ], base, 1, count )
                        vDSP_vclipD( base, 1, [ 0.0 ],   [ 1.0 ],    base, 1, count )
                    }

                case .percentile( let lowerPercentile, let upperPercentile ):

                    let bounds = PixelUtilities.percentileBounds( in: buffer.pixels, lower: lowerPercentile, upper: upperPercentile )

                    guard bounds.lower != bounds.upper
                    else
                    {
                        buffer.withUnsafeMutablePixels( isNormalized: true ) { $0.update( repeating: 0.0 ) }

                        return
                    }

                    let range  = bounds.upper - bounds.lower
                    let scale  = 1.0 / range
                    let offset = -bounds.lower / range

                    buffer.withUnsafeMutablePixels( isNormalized: true )
                    {
                        guard let base = $0.baseAddress
                        else
                        {
                            return
                        }

                        vDSP_vclipD( base, 1, [ bounds.lower ], [ bounds.upper ], base, 1, count )
                        vDSP_vsmsaD( base, 1, [ scale ],        [ offset ],       base, 1, count )
                        vDSP_vclipD( base, 1, [ 0.0 ],          [ 1.0 ],          base, 1, count )
                    }

                case .identity:

                    // The samples are assumed already in the display range; clamp
                    // any strays into [0, 1] and mark the buffer normalized without
                    // remapping the range.
                    buffer.withUnsafeMutablePixels( isNormalized: true )
                    {
                        guard let base = $0.baseAddress
                        else
                        {
                            return
                        }

                        vDSP_vclipD( base, 1, [ 0.0 ], [ 1.0 ], base, 1, count )
                    }
            }
        }
    }
}
