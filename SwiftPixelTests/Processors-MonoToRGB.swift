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
import SwiftUtilities
import Testing

struct Test_Processors_MonoToRGB
{
    @Test
    func name() async throws
    {
        #expect( Processors.MonoToRGB().name == "Mono to RGB" )
    }

    @Test
    func conversion() async throws
    {
        var buffer = PixelBuffer(
            width:        2,
            height:       2,
            channels:     1,
            pixels:       [ 10, 20, 30, 40 ],
            isNormalized: false
        )

        let processor = Processors.MonoToRGB()

        try processor.process( buffer: &buffer )

        try #require( buffer.channels     == 3 )
        try #require( buffer.pixels.count == 12 )

        #expect( buffer.pixels[ 0 ]  == 10 )
        #expect( buffer.pixels[ 1 ]  == 10 )
        #expect( buffer.pixels[ 2 ]  == 10 )

        #expect( buffer.pixels[ 3 ]  == 20 )
        #expect( buffer.pixels[ 4 ]  == 20 )
        #expect( buffer.pixels[ 5 ]  == 20 )

        #expect( buffer.pixels[ 6 ]  == 30 )
        #expect( buffer.pixels[ 7 ]  == 30 )
        #expect( buffer.pixels[ 8 ]  == 30 )

        #expect( buffer.pixels[ 9 ]  == 40 )
        #expect( buffer.pixels[ 10 ] == 40 )
        #expect( buffer.pixels[ 11 ] == 40 )
    }

    @Test
    func invalidSize() async throws
    {
        var buffer = PixelBuffer(
            width:        2,
            height:       2,
            channels:     1,
            pixels:       [ 10, 20 ],
            isNormalized: false
        )

        let debayer = Processors.Debayer( mode: .vng, pattern: .bggr )

        #expect( throws: RuntimeError.self )
        {
            try debayer.process( buffer: &buffer )
        }
    }

    @Test
    func invalidChannels() async throws
    {
        var buffer = PixelBuffer(
            width:        2,
            height:       2,
            channels:     3,
            pixels:       [ 10, 20, 30, 40 ],
            isNormalized: false
        )

        let debayer = Processors.Debayer( mode: .vng, pattern: .bggr )

        #expect( throws: RuntimeError.self )
        {
            try debayer.process( buffer: &buffer )
        }
    }

    @Test
    func invalidNormalize() async throws
    {
        var buffer = PixelBuffer(
            width:        2,
            height:       2,
            channels:     1,
            pixels:       [ 10, 20, 30, 40 ],
            isNormalized: true
        )

        let debayer = Processors.Debayer( mode: .vng, pattern: .bggr )

        #expect( throws: RuntimeError.self )
        {
            try debayer.process( buffer: &buffer )
        }
    }
}
