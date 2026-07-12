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
    /// Expands a single-channel buffer to 3-channel RGB by replicating the gray
    /// value into each channel.
    ///
    /// Requires a non-normalized, 1-channel buffer; the result has 3 channels.
    struct MonoToRGB: PixelProcessor
    {
        /// The fixed name `"Mono to RGB"`.
        public var name: String
        {
            "Mono to RGB"
        }

        /// Creates a mono-to-RGB stage.
        public init()
        {}

        /// Replicates each gray sample into R, G and B, producing a 3-channel
        /// buffer.
        ///
        /// - Parameter buffer: A non-normalized, 1-channel buffer.
        ///
        /// - Throws: A `PixelBufferError` if the buffer is normalized, is not
        ///           single-channel, or its sample count does not match its
        ///           geometry.
        public func process( buffer: inout PixelBuffer ) throws
        {
            let expected = try PixelUtilities.checkedSampleCount( width: buffer.width, height: buffer.height, channels: 1 )

            guard buffer.pixels.count == expected
            else
            {
                throw PixelBufferError.dataSizeMismatch( expected: expected, actual: buffer.pixels.count )
            }

            guard buffer.channels == 1
            else
            {
                throw PixelBufferError.unsupportedChannelCount( actual: buffer.channels, supported: [ 1 ] )
            }

            guard buffer.isNormalized == false
            else
            {
                throw PixelBufferError.mustNotBeNormalized
            }

            let count       = buffer.pixels.count
            let inputPixels = buffer.pixels
            var rgb         = [ Double ]( repeating: 0.0, count: count * 3 )

            rgb.withUnsafeMutableBufferPointer
            {
                nonisolated( unsafe ) let sendableRGBBuffer = $0

                PixelUtilities.parallelOrSerial( iterations: count )
                {
                    let value = inputPixels[ $0 ]
                    let base  = $0 * 3

                    sendableRGBBuffer[ base + 0 ] = value
                    sendableRGBBuffer[ base + 1 ] = value
                    sendableRGBBuffer[ base + 2 ] = value
                }
            }

            buffer = try PixelBuffer( width: buffer.width, height: buffer.height, channels: 3, pixels: rgb, isNormalized: buffer.isNormalized )
        }
    }
}
