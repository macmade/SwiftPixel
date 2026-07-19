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
    /// Scales colour saturation about each pixel's luma on a 3-channel
    /// normalized buffer.
    ///
    /// Each channel is moved toward or away from the pixel's Rec. 709 luma:
    /// `out = luma + (channel − luma) · saturation`, clipped to
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

            let factor     = self.saturation
            let pixelCount = buffer.width * buffer.height

            guard pixelCount > 0
            else
            {
                return
            }

            // Build the per-pixel Rec. 709 luma plane, then apply
            // `out = luma + (channel − luma)·factor`, rewritten as
            // `channel·factor + luma·(1 − factor)` so each channel is a single
            // vectorized multiply-add against the shared luma plane; the whole buffer
            // is then clipped to [0, 1]. Algebraically identical to the scalar form,
            // to within floating-point rounding.
            var luma = [ Double ]( repeating: 0.0, count: pixelCount )

            buffer.withUnsafeMutablePixels
            {
                pixels in

                luma.withUnsafeMutableBufferPointer
                {
                    lumaBuffer in

                    guard let rgb = pixels.baseAddress, let l = lumaBuffer.baseAddress
                    else
                    {
                        return
                    }

                    let n = vDSP_Length( pixelCount )

                    // Rec. 709 luma, matching Histogram's luma channel, read strided
                    // from the interleaved buffer.
                    var weightRed   = 0.2126
                    var weightGreen = 0.7152
                    var weightBlue  = 0.0722

                    vDSP_vsmulD( rgb + 0, 3, &weightRed,   l, 1, n )       // luma  = R · 0.2126
                    vDSP_vsmaD(  rgb + 1, 3, &weightGreen, l, 1, l, 1, n ) // luma += G · 0.7152
                    vDSP_vsmaD(  rgb + 2, 3, &weightBlue,  l, 1, l, 1, n ) // luma += B · 0.0722

                    var scale      = factor
                    var complement = 1.0 - factor

                    // luma ← luma · (1 − factor); the shared additive term per channel.
                    vDSP_vsmulD( l, 1, &complement, l, 1, n )

                    // channel ← channel · factor + luma · (1 − factor)
                    ( 0 ..< 3 ).forEach
                    {
                        channel in

                        vDSP_vsmaD( rgb + channel, 3, &scale, l, 1, rgb + channel, 3, n )
                    }

                    var low  = 0.0
                    var high = 1.0

                    vDSP_vclipD( rgb, 1, &low, &high, rgb, 1, vDSP_Length( pixelCount * 3 ) )
                }
            }
        }
    }
}
