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
@testable import SwiftPixel
import Testing

struct Test_Processors_Debayer_Bilinear
{
    @Test
    func testBilinear_RGGB_2x2_GoldenOutput() async throws
    {
        // Simulated 2x2 Bayer pattern (RGGB):
        // [ R, G ]
        // [ G, B ]
        var buffer = try PixelBuffer(
            width:        2,
            height:       2,
            channels:     1,
            pixels:       [ 10, 20, 30, 40 ],
            isNormalized: false
        )

        let debayer = Processors.Debayer( mode: .bilinear, pattern: .rggb )

        try debayer.process( buffer: &buffer )

        // Every pixel is on the border, so each missing colour averages only the
        // in-bounds same-colour neighbours (CR-17: no edge-clamped wrong-colour
        // contamination). The 2x2 has a single red site (10) and a single blue
        // site (40), so red and blue are constant across the image and only the
        // green varies.
        #expect( buffer.pixels ==
            [
                10.0, 25.0, 40.0,
                10.0, 20.0, 40.0,
                10.0, 30.0, 40.0,
                10.0, 25.0, 40.0,
            ]
        )
    }

    @Test
    func testBilinear_BGGR_2x2() async throws
    {
        // Simulated 2x2 Bayer pattern (BGGR):
        // [ B, G ]
        // [ G, R ]
        var buffer = try PixelBuffer(
            width:        2,
            height:       2,
            channels:     1,
            pixels:       [ 10, 20, 30, 40 ],
            isNormalized: false
        )

        let debayer = Processors.Debayer( mode: .bilinear, pattern: .bggr )

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
    func testBilinear_GRBG_2x2() async throws
    {
        // Simulated 2x2 Bayer pattern (GRBG):
        // [ G, R ]
        // [ B, G ]
        var buffer = try PixelBuffer(
            width:        2,
            height:       2,
            channels:     1,
            pixels:       [ 10, 20, 30, 40 ],
            isNormalized: false
        )

        let debayer = Processors.Debayer( mode: .bilinear, pattern: .grbg )

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
    func testBilinear_RGGB_2x2() async throws
    {
        // Simulated 2x2 Bayer pattern (RGGB):
        // [ R, G ]
        // [ G, B ]
        var buffer = try PixelBuffer(
            width:        2,
            height:       2,
            channels:     1,
            pixels:       [ 10, 20, 30, 40 ],
            isNormalized: false
        )

        let debayer = Processors.Debayer( mode: .bilinear, pattern: .rggb )

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
}
