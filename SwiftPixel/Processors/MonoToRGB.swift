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
    /// Expands a single-channel buffer to 3-channel RGB by replicating the gray
    /// value into each channel.
    ///
    /// Requires a 1-channel buffer; the result has 3 channels. Channel replication
    /// is range-independent, so the buffer's `isNormalized` flag is preserved (a
    /// normalized mono buffer yields a normalized RGB buffer).
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
        /// buffer and preserving the normalized flag.
        ///
        /// - Parameter buffer: A 1-channel buffer.
        ///
        /// - Throws: A `PixelBufferError` if the buffer is not single-channel or its
        ///           sample count does not match its geometry.
        public func process( buffer: inout PixelBuffer ) throws
        {
            guard buffer.channels == 1
            else
            {
                throw PixelBufferError.unsupportedChannelCount( actual: buffer.channels, supported: [ 1 ] )
            }

            let expected = try PixelUtilities.checkedSampleCount( width: buffer.width, height: buffer.height, channels: 1 )

            guard buffer.pixels.count == expected
            else
            {
                throw PixelBufferError.dataSizeMismatch( expected: expected, actual: buffer.pixels.count )
            }

            let count = buffer.pixels.count
            var rgb   = [ Double ]( repeating: 0.0, count: count * 3 )

            buffer.pixels.withUnsafeBufferPointer
            {
                source in

                rgb.withUnsafeMutableBufferPointer
                {
                    destination in

                    guard let base = source.baseAddress, let output = destination.baseAddress
                    else
                    {
                        // A zero-sample buffer has no plane to scatter; the empty
                        // result is already correct.
                        return
                    }

                    // Scatter the single mono plane into each of the three interleaved
                    // channels with one strided Accelerate move apiece — a contiguous
                    // read into every third output slot — so channel `c` fills
                    // indices c, c + 3, c + 6, … This replicates each gray sample into
                    // R, G and B exactly (a pure copy), the same idiom as
                    // ``PixelUtilities/interleave(planes:)``.
                    ( 0 ..< 3 ).forEach
                    {
                        channel in

                        vDSP_mmovD( base, output + channel, 1, vDSP_Length( count ), 1, 3 )
                    }
                }
            }

            buffer = try PixelBuffer( width: buffer.width, height: buffer.height, channels: 3, pixels: rgb, isNormalized: buffer.isNormalized )
        }
    }
}
