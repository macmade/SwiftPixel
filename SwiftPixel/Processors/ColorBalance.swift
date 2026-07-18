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
    /// Applies a tonal-range colour balance to a 3-channel normalized buffer,
    /// shifting the red, green and blue channels independently within the
    /// shadows, midtones and highlights.
    ///
    /// Each pixel's Rec. 709 luma selects how strongly it belongs to each
    /// tonal range, via smooth weights that peak at black (shadows), mid-gray
    /// (midtones) and white (highlights) and always sum to `1`. The matching
    /// per-channel shifts, scaled by those weights, are added to the channels and
    /// the result is clipped to `[0, 1]`:
    /// `out = channel + shadow·wShadow + midtone·wMid + highlight·wHigh`. A shift
    /// of `0` everywhere is an identity. Requires a normalized, 3-channel buffer.
    struct ColorBalance: PixelProcessor
    {
        /// An additive per-channel shift for one tonal range. A positive component
        /// pushes toward that primary (red/green/blue), a negative one toward its
        /// complement (cyan/magenta/yellow). All-zero is neutral.
        public struct Shift: Sendable, Equatable
        {
            /// The red-channel shift (`+` toward red, `−` toward cyan).
            public var red: Double

            /// The green-channel shift (`+` toward green, `−` toward magenta).
            public var green: Double

            /// The blue-channel shift (`+` toward blue, `−` toward yellow).
            public var blue: Double

            /// The neutral shift, which leaves the channels unchanged.
            public static let identity = Shift()

            /// Creates a per-channel shift.
            ///
            /// - Parameters:
            ///   - red:   The red-channel shift. Defaults to `0`.
            ///   - green: The green-channel shift. Defaults to `0`.
            ///   - blue:  The blue-channel shift. Defaults to `0`.
            public init( red: Double = 0, green: Double = 0, blue: Double = 0 )
            {
                self.red   = red
                self.green = green
                self.blue  = blue
            }

            /// Whether this shift is neutral (and so a no-op).
            public var isIdentity: Bool
            {
                self == .identity
            }
        }

        /// The per-channel shifts for the three tonal ranges.
        public struct Ranges: Sendable, Equatable
        {
            /// The shift applied most strongly to the darkest pixels.
            public var shadows: Shift

            /// The shift applied most strongly to the mid-gray pixels.
            public var midtones: Shift

            /// The shift applied most strongly to the brightest pixels.
            public var highlights: Shift

            /// The neutral balance, which leaves every pixel unchanged.
            public static let identity = Ranges()

            /// Creates a set of tonal-range shifts.
            ///
            /// - Parameters:
            ///   - shadows:    The shadows shift. Defaults to the identity.
            ///   - midtones:   The midtones shift. Defaults to the identity.
            ///   - highlights: The highlights shift. Defaults to the identity.
            public init( shadows: Shift = .identity, midtones: Shift = .identity, highlights: Shift = .identity )
            {
                self.shadows    = shadows
                self.midtones   = midtones
                self.highlights = highlights
            }

            /// Whether every range is neutral (and so the whole stage is a no-op).
            public var isIdentity: Bool
            {
                self == .identity
            }
        }

        /// The per-tonal-range shifts to apply.
        public let ranges: Ranges

        /// A human-readable name.
        public var name: String
        {
            "Color Balance"
        }

        /// Creates a colour-balance stage.
        ///
        /// - Parameter ranges: The per-tonal-range shifts to apply.
        public init( ranges: Ranges )
        {
            self.ranges = ranges
        }

        /// Applies the colour balance in place, clipping to `[0, 1]`.
        ///
        /// - Parameter buffer: The normalized, 3-channel buffer to transform.
        ///
        /// - Throws: A `PixelBufferError` if the buffer is not normalized or is not
        ///           3-channel.
        public func process( buffer: inout PixelBuffer ) throws
        {
            guard buffer.isNormalized
            else
            {
                throw PixelBufferError.notNormalized
            }

            guard buffer.channels == 3
            else
            {
                throw PixelBufferError.unsupportedChannelCount( actual: buffer.channels, supported: [ 3 ] )
            }

            let shadows    = self.ranges.shadows
            let midtones   = self.ranges.midtones
            let highlights = self.ranges.highlights
            let pixelCount = buffer.width * buffer.height

            buffer.withUnsafeMutablePixels
            {
                nonisolated( unsafe ) let pixels = $0

                PixelUtilities.parallelOrSerial( iterations: pixelCount )
                {
                    let base = $0 * 3
                    let r    = pixels[ base + 0 ]
                    let g    = pixels[ base + 1 ]
                    let b    = pixels[ base + 2 ]

                    // Rec. 709 luma, matching the Saturation stage's channel.
                    let luma            = 0.2126 * r + 0.7152 * g + 0.0722 * b
                    let shadowWeight    = 1.0 - Self.smoothstep( 0.0, 0.5, luma )
                    let highlightWeight = Self.smoothstep( 0.5, 1.0, luma )
                    let midtoneWeight   = 1.0 - shadowWeight - highlightWeight

                    pixels[ base + 0 ] = min( 1.0, max( 0.0, r + shadows.red   * shadowWeight + midtones.red   * midtoneWeight + highlights.red   * highlightWeight ) )
                    pixels[ base + 1 ] = min( 1.0, max( 0.0, g + shadows.green * shadowWeight + midtones.green * midtoneWeight + highlights.green * highlightWeight ) )
                    pixels[ base + 2 ] = min( 1.0, max( 0.0, b + shadows.blue  * shadowWeight + midtones.blue  * midtoneWeight + highlights.blue  * highlightWeight ) )
                }
            }
        }

        /// Smooth Hermite interpolation between two edges, clamped to `[0, 1]`.
        ///
        /// Returns `0` at or below `edge0`, `1` at or above `edge1`, and a smooth
        /// S-curve between, with zero slope at both ends so the tonal weights meet
        /// seamlessly.
        ///
        /// - Parameters:
        ///   - edge0: The lower edge, mapped to `0`.
        ///   - edge1: The upper edge, mapped to `1`.
        ///   - x:     The value to interpolate.
        /// - Returns: The interpolated weight in `[0, 1]`.
        private static func smoothstep( _ edge0: Double, _ edge1: Double, _ x: Double ) -> Double
        {
            let t = min( 1.0, max( 0.0, ( x - edge0 ) / ( edge1 - edge0 ) ) )

            return t * t * ( 3.0 - 2.0 * t )
        }
    }
}
