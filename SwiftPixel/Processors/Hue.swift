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
import SwiftUtilities

public extension Processors
{
    /// Rotates the hue of every pixel by a fixed angle on a 3-channel normalized
    /// buffer.
    ///
    /// Each pixel is converted from RGB to HSV, its hue is advanced by `angle`
    /// degrees (wrapping around the colour wheel), and it is converted back to
    /// RGB. Value and saturation are preserved, so only the colour rotates: red
    /// becomes green at `+120`, green becomes blue, and so on. An angle of `0`
    /// (or any multiple of `360`) is an identity, and a neutral (gray) pixel —
    /// which has no hue — is left untouched. Requires a normalized, 3-channel
    /// buffer.
    struct Hue: PixelProcessor
    {
        /// The hue-rotation angle, in degrees. `0` is neutral; positive angles
        /// advance the hue (red → green → blue), negative angles reverse it.
        public let angle: Double

        /// A human-readable name including the angle.
        public var name: String
        {
            String( format: "Hue (%.02f°)", self.angle )
        }

        /// Creates a hue-rotation stage.
        ///
        /// - Parameter angle: The rotation angle in degrees.
        public init( angle: Double )
        {
            self.angle = angle
        }

        /// Applies the hue rotation in place.
        ///
        /// - Parameter buffer: The normalized, 3-channel buffer to transform.
        ///
        /// - Throws: A `RuntimeError` if the buffer is not normalized or is not
        ///           3-channel.
        public func process( buffer: inout PixelBuffer ) throws
        {
            guard buffer.isNormalized
            else
            {
                throw RuntimeError( message: "Buffer needs to be normalized" )
            }

            guard buffer.channels == 3
            else
            {
                throw RuntimeError( message: "Hue requires a 3-channel buffer: \( buffer.channels )" )
            }

            let degrees    = self.angle
            let pixelCount = buffer.width * buffer.height

            buffer.withUnsafeMutablePixels
            {
                let pixels = UnsafeMutableSendable( $0 )

                PixelUtilities.parallelOrSerial( iterations: pixelCount )
                {
                    let base = $0 * 3
                    let r    = pixels.value[ base + 0 ]
                    let g    = pixels.value[ base + 1 ]
                    let b    = pixels.value[ base + 2 ]

                    let hsv     = Self.rgbToHSV( r: r, g: g, b: b )
                    let rotated = Self.wrap( hsv.h + degrees )
                    let rgb     = Self.hsvToRGB( h: rotated, s: hsv.s, v: hsv.v )

                    pixels.value[ base + 0 ] = min( 1.0, max( 0.0, rgb.r ) )
                    pixels.value[ base + 1 ] = min( 1.0, max( 0.0, rgb.g ) )
                    pixels.value[ base + 2 ] = min( 1.0, max( 0.0, rgb.b ) )
                }
            }
        }

        /// Wraps an angle in degrees into the `[0, 360)` range.
        ///
        /// - Parameter degrees: The angle to wrap.
        /// - Returns: The equivalent angle in `[0, 360)`.
        private static func wrap( _ degrees: Double ) -> Double
        {
            let remainder = degrees.truncatingRemainder( dividingBy: 360 )

            return remainder < 0 ? remainder + 360 : remainder
        }

        /// Converts an RGB triple to hue/saturation/value.
        ///
        /// - Parameters:
        ///   - r: The red channel, in `[0, 1]`.
        ///   - g: The green channel, in `[0, 1]`.
        ///   - b: The blue channel, in `[0, 1]`.
        /// - Returns: The hue in `[0, 360)` degrees (`0` when achromatic), the
        ///   saturation in `[0, 1]`, and the value in `[0, 1]`.
        private static func rgbToHSV( r: Double, g: Double, b: Double ) -> ( h: Double, s: Double, v: Double )
        {
            let maximum = max( r, g, b )
            let minimum = min( r, g, b )
            let delta   = maximum - minimum

            let value      = maximum
            let saturation = maximum <= 0 ? 0 : delta / maximum

            guard delta > 0
            else
            {
                // An achromatic pixel has no defined hue; use 0.
                return ( h: 0, s: 0, v: value )
            }

            let hue: Double

            if maximum == r
            {
                hue = 60 * ( ( ( g - b ) / delta ).truncatingRemainder( dividingBy: 6 ) )
            }
            else if maximum == g
            {
                hue = 60 * ( ( b - r ) / delta + 2 )
            }
            else
            {
                hue = 60 * ( ( r - g ) / delta + 4 )
            }

            return ( h: hue < 0 ? hue + 360 : hue, s: saturation, v: value )
        }

        /// Converts a hue/saturation/value triple to RGB.
        ///
        /// - Parameters:
        ///   - h: The hue in `[0, 360)` degrees.
        ///   - s: The saturation in `[0, 1]`.
        ///   - v: The value in `[0, 1]`.
        /// - Returns: The red, green and blue channels, each in `[0, 1]`.
        private static func hsvToRGB( h: Double, s: Double, v: Double ) -> ( r: Double, g: Double, b: Double )
        {
            guard s > 0
            else
            {
                // No saturation: a gray at the given value, regardless of hue.
                return ( r: v, g: v, b: v )
            }

            let sector    = h / 60
            let chroma    = v * s
            let secondary = chroma * ( 1 - abs( sector.truncatingRemainder( dividingBy: 2 ) - 1 ) )
            let match     = v - chroma

            let rgb: ( Double, Double, Double ) = switch Int( sector ) % 6
            {
                case 0:  ( chroma, secondary, 0 )
                case 1:  ( secondary, chroma, 0 )
                case 2:  ( 0, chroma, secondary )
                case 3:  ( 0, secondary, chroma )
                case 4:  ( secondary, 0, chroma )
                default: ( chroma, 0, secondary )
            }

            return ( r: rgb.0 + match, g: rgb.1 + match, b: rgb.2 + match )
        }
    }
}
