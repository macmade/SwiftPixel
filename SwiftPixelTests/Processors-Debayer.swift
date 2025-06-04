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

struct Test_Processors_Debayer
{
    @Test
    func name() async throws
    {
        #expect( Processors.Debayer( mode: .vng, pattern: .bggr ).name == "Debayer (VNG BGGR)" )
        #expect( Processors.Debayer( mode: .vng, pattern: .grbg ).name == "Debayer (VNG GRBG)" )
        #expect( Processors.Debayer( mode: .vng, pattern: .rgbg ).name == "Debayer (VNG RGBG)" )
        #expect( Processors.Debayer( mode: .vng, pattern: .rggb ).name == "Debayer (VNG RGGB)" )
    }

    @Test
    func testVNG_BGGR_2x2() async throws
    {
        // Simulated 2x2 Bayer pattern (BGGR):
        // [ B, G ]
        // [ G, R ]
        var buffer = PixelBuffer(
            width:        2,
            height:       2,
            channels:     1,
            pixels:       [ 10, 20, 30, 40 ],
            isNormalized: false
        )

        let debayer = Processors.Debayer( mode: .vng, pattern: .bggr )

        try debayer.process( buffer: &buffer )

        try #require( buffer.channels     == 3 )
        try #require( buffer.pixels.count == 12 )

        buffer.pixels.forEach
        {
            #expect( $0 > 0 )
        }

        let pix1 = ( r: buffer.pixels[ 0 ], g: buffer.pixels[  1 ], b: buffer.pixels[  2 ] )
        let pix2 = ( r: buffer.pixels[ 3 ], g: buffer.pixels[  4 ], b: buffer.pixels[  5 ] )
        let pix3 = ( r: buffer.pixels[ 6 ], g: buffer.pixels[  7 ], b: buffer.pixels[  8 ] )
        let pix4 = ( r: buffer.pixels[ 9 ], g: buffer.pixels[ 10 ], b: buffer.pixels[ 11 ] )

        #expect( pix1.b == 10 )
        #expect( pix2.g == 20 )
        #expect( pix3.g == 30 )
        #expect( pix4.r == 40 )
    }

    @Test
    func testVNG_GRBG_2x2() async throws
    {
        // Simulated 2x2 Bayer pattern (GRBG):
        // [ G, R ]
        // [ B, G ]
        var buffer = PixelBuffer(
            width:        2,
            height:       2,
            channels:     1,
            pixels:       [ 10, 20, 30, 40 ],
            isNormalized: false
        )

        let debayer = Processors.Debayer( mode: .vng, pattern: .grbg )

        try debayer.process( buffer: &buffer )

        try #require( buffer.channels     == 3 )
        try #require( buffer.pixels.count == 12 )

        buffer.pixels.forEach
        {
            #expect( $0 > 0 )
        }

        let pix1 = ( r: buffer.pixels[ 0 ], g: buffer.pixels[  1 ], b: buffer.pixels[  2 ] )
        let pix2 = ( r: buffer.pixels[ 3 ], g: buffer.pixels[  4 ], b: buffer.pixels[  5 ] )
        let pix3 = ( r: buffer.pixels[ 6 ], g: buffer.pixels[  7 ], b: buffer.pixels[  8 ] )
        let pix4 = ( r: buffer.pixels[ 9 ], g: buffer.pixels[ 10 ], b: buffer.pixels[ 11 ] )

        #expect( pix1.g == 10 )
        #expect( pix2.r == 20 )
        #expect( pix3.b == 30 )
        #expect( pix4.g == 40 )
    }

    @Test
    func testVNG_RGBG_2x2() async throws
    {
        // Simulated 2x2 Bayer pattern (RGBG):
        // [ R, G ]
        // [ B, G ]
        var buffer = PixelBuffer(
            width:        2,
            height:       2,
            channels:     1,
            pixels:       [ 10, 20, 30, 40 ],
            isNormalized: false
        )

        let debayer = Processors.Debayer( mode: .vng, pattern: .rgbg )

        try debayer.process( buffer: &buffer )

        try #require( buffer.channels     == 3 )
        try #require( buffer.pixels.count == 12 )

        buffer.pixels.forEach
        {
            #expect( $0 > 0 )
        }

        let pix1 = ( r: buffer.pixels[ 0 ], g: buffer.pixels[  1 ], b: buffer.pixels[  2 ] )
        let pix2 = ( r: buffer.pixels[ 3 ], g: buffer.pixels[  4 ], b: buffer.pixels[  5 ] )
        let pix3 = ( r: buffer.pixels[ 6 ], g: buffer.pixels[  7 ], b: buffer.pixels[  8 ] )
        let pix4 = ( r: buffer.pixels[ 9 ], g: buffer.pixels[ 10 ], b: buffer.pixels[ 11 ] )

        #expect( pix1.r == 10 )
        #expect( pix2.g == 20 )
        #expect( pix3.b == 30 )
        #expect( pix4.g == 40 )
    }

    @Test
    func testVNG_RGGB_2x2() async throws
    {
        // Simulated 2x2 Bayer pattern (RGGB):
        // [ R, G ]
        // [ G, B ]
        var buffer = PixelBuffer(
            width:        2,
            height:       2,
            channels:     1,
            pixels:       [ 10, 20, 30, 40 ],
            isNormalized: false
        )

        let debayer = Processors.Debayer( mode: .vng, pattern: .rggb )

        try debayer.process( buffer: &buffer )

        try #require( buffer.channels     == 3 )
        try #require( buffer.pixels.count == 12 )

        buffer.pixels.forEach
        {
            #expect( $0 > 0 )
        }

        let pix1 = ( r: buffer.pixels[ 0 ], g: buffer.pixels[  1 ], b: buffer.pixels[  2 ] )
        let pix2 = ( r: buffer.pixels[ 3 ], g: buffer.pixels[  4 ], b: buffer.pixels[  5 ] )
        let pix3 = ( r: buffer.pixels[ 6 ], g: buffer.pixels[  7 ], b: buffer.pixels[  8 ] )
        let pix4 = ( r: buffer.pixels[ 9 ], g: buffer.pixels[ 10 ], b: buffer.pixels[ 11 ] )

        #expect( pix1.r == 10 )
        #expect( pix2.g == 20 )
        #expect( pix3.g == 30 )
        #expect( pix4.b == 40 )
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
