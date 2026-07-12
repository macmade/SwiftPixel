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
    /// Adjusts brightness and contrast on a normalized buffer.
    ///
    /// Contrast scales each sample about the `0.5` midpoint and brightness
    /// shifts it, with the result clipped back into `[0, 1]`:
    /// `clip((v - 0.5) · contrast + 0.5 + brightness)`. Neutral parameters
    /// (`brightness == 0`, `contrast == 1`) leave the image unchanged. Applies
    /// uniformly to every channel and requires a normalized buffer.
    struct BrightnessContrast: PixelProcessor
    {
        /// The additive brightness offset (`0` is neutral).
        public let brightness: Double

        /// The multiplicative contrast factor about the midpoint (`1` is
        /// neutral, `0` flattens to mid-gray).
        public let contrast: Double

        /// A human-readable name including the parameters.
        public var name: String
        {
            String( format: "Brightness/Contrast (%.02f %.02f)", self.brightness, self.contrast )
        }

        /// Creates a brightness/contrast stage.
        ///
        /// - Parameters:
        ///   - brightness: The additive brightness offset (`0` is neutral).
        ///   - contrast:   The contrast factor about the midpoint (`1` is neutral).
        public init( brightness: Double, contrast: Double )
        {
            self.brightness = brightness
            self.contrast   = contrast
        }

        /// Applies the brightness/contrast transform in place and clips to
        /// `[0, 1]`.
        ///
        /// - Parameter buffer: The normalized buffer to transform.
        ///
        /// - Throws: A `PixelBufferError` if the buffer is not normalized or its data
        ///           cannot be accessed.
        public func process( buffer: inout PixelBuffer ) throws
        {
            guard buffer.isNormalized
            else
            {
                throw PixelBufferError.notNormalized
            }

            // (v - 0.5)·c + 0.5 + b  ==  v·c + (0.5·(1 - c) + b), then clip.
            var multiplier = self.contrast
            var offset     = 0.5 * ( 1.0 - self.contrast ) + self.brightness

            try buffer.withUnsafeMutablePixels
            {
                guard let baseAddress = $0.baseAddress
                else
                {
                    throw PixelBufferError.bufferAccessFailed( role: .data )
                }

                vDSP_vsmsaD( baseAddress, 1, &multiplier, &offset, baseAddress, 1, vDSP_Length( $0.count ) )
                vDSP_vclipD( baseAddress, 1, [ 0.0 ], [ 1.0 ], baseAddress, 1, vDSP_Length( $0.count ) )
            }
        }
    }
}
