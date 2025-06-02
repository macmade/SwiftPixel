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
@testable import SwiftPixel
import Testing

struct Test_PixelBuffer
{
    @Test
    func initialize()
    {
        let width      = 4
        let height     = 3
        let channels   = 2
        let pixelData  = Array( stride( from: 0.0, to: Double( width * height * channels ), by: 1.0 ))
        let normalized = true

        let buffer = PixelBuffer(
            width: width,
            height: height,
            channels: channels,
            pixels: pixelData,
            isNormalized: normalized
        )

        #expect( buffer.width        == width )
        #expect( buffer.height       == height )
        #expect( buffer.channels     == channels )
        #expect( buffer.pixels       == pixelData )
        #expect( buffer.pixels.count == width * height * channels )
        #expect( buffer.pixels.first == 0.0 )
        #expect( buffer.pixels.last  == Double( pixelData.count - 1 ) )
        #expect( buffer.isNormalized == normalized )
    }

    @Test
    func description()
    {
        let buffer = PixelBuffer(
            width:        10,
            height:       20,
            channels:     1,
            pixels:       [ 0.0, 0.5, 1.0, 0.75 ],
            isNormalized: true
        )

        #expect( buffer.description == "PixelBuffer( width: 10, height: 20, channels: 1, pixels: 4, isNormalized: true )" )
    }
}
