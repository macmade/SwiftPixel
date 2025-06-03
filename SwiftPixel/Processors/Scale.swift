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

import Accelerate
import Foundation
import SwiftUtilities

public extension Processors
{
    struct Scale: PixelProcessor
    {
        public let scale:  Double
        public let offset: Double

        public var name: String
        {
            String( format: "Scale (%.02f %.02f)", self.scale, self.offset )
        }

        public func process( buffer: inout PixelBuffer ) throws
        {
            let count = vDSP_Length( buffer.pixels.count )

            try buffer.pixels.withUnsafeMutableBufferPointer
            {
                guard let baseAddress = $0.baseAddress
                else
                {
                    throw RuntimeError( message: "Failed to access data buffer" )
                }

                var scalar = self.scale
                var addend = self.offset

                vDSP_vsmulD( baseAddress, 1, &scalar, baseAddress, 1, count )
                vDSP_vsaddD( baseAddress, 1, &addend, baseAddress, 1, count )
            }
        }
    }
}
