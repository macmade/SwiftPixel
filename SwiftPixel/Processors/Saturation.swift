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
    /// Scales colour saturation about each pixel's luminance on a 3-channel
    /// normalized buffer.
    ///
    /// Each channel is moved toward or away from the pixel's Rec. 709 luminance:
    /// `out = luminance + (channel − luminance) · saturation`, clipped to
    /// `[0, 1]`. A factor of `0` desaturates to gray, `1` is an identity, and
    /// values above `1` boost saturation. Requires a normalized, 3-channel
    /// buffer.
    struct Saturation: PixelProcessor
    {
        /// The saturation factor (`0` gray, `1` neutral, `> 1` boosted).
        public let saturation: Double

        /// A human-readable name including the factor.
        public var name: String
        {
            String( format: "Saturation (%.02f)", self.saturation )
        }

        /// Creates a saturation stage.
        ///
        /// - Parameter saturation: The saturation factor.
        public init( saturation: Double )
        {
            self.saturation = saturation
        }

        /// Applies the saturation scale in place, clipping to `[0, 1]`.
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
                throw RuntimeError( message: "Saturation requires a 3-channel buffer: \( buffer.channels )" )
            }

            let factor     = self.saturation
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

                    // Rec. 709 luminance, matching Histogram's luminance channel.
                    let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b

                    pixels[ base + 0 ] = min( 1.0, max( 0.0, luminance + ( r - luminance ) * factor ) )
                    pixels[ base + 1 ] = min( 1.0, max( 0.0, luminance + ( g - luminance ) * factor ) )
                    pixels[ base + 2 ] = min( 1.0, max( 0.0, luminance + ( b - luminance ) * factor ) )
                }
            }
        }
    }
}
