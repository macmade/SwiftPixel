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

import Foundation
import SwiftUtilities

public extension Processors
{
    struct MonoToRGB: PixelProcessor
    {
        public var name: String
        {
            "Mono to RGB"
        }

        public func process( buffer: inout PixelBuffer ) throws
        {
            guard buffer.pixels.count == buffer.width * buffer.height
            else
            {
                throw RuntimeError( message: "Data size does not match expected size: \( buffer.pixels.count ) != \( buffer.width * buffer.height )" )
            }

            guard buffer.channels == 1
            else
            {
                throw RuntimeError( message: "Unsupported channel count: \( buffer.channels )" )
            }

            guard buffer.isNormalized == false
            else
            {
                throw RuntimeError( message: "Input buffer must not be normalized" )
            }

            let count          = buffer.pixels.count
            let rgb            = UnsafeMutableSendable( [ Double ]( repeating: 0.0, count: count * 3 ) )
            let sendableBuffer = UnsafeMutableSendable( buffer )

            rgb.value.withUnsafeMutableBufferPointer
            {
                let sendableRGBBuffer = UnsafeMutableSendable( $0 )

                DispatchQueue.concurrentPerform( iterations: count )
                {
                    let value = sendableBuffer.value.pixels[ $0 ]
                    let base  = $0 * 3

                    sendableRGBBuffer.value[ base + 0 ] = value
                    sendableRGBBuffer.value[ base + 1 ] = value
                    sendableRGBBuffer.value[ base + 2 ] = value
                }
            }

            buffer.pixels   = rgb.value
            buffer.channels = 3
        }
    }
}
