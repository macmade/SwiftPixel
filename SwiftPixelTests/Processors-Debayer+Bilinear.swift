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

    @Test
    func testBilinear_RGGB_5x5_Interior() async throws
    {
        // A 5×5 RGGB mosaic exercises interior sites where every same-colour
        // neighbour is in bounds — the divide-by-4 cross/diagonal and divide-by-2
        // horizontal/vertical averages a 2×2 (all-border) golden never reaches.
        var buffer = try PixelBuffer(
            width:        5,
            height:       5,
            channels:     1,
            pixels:
            [
                1,  2,  50,  3,   4,
                5,  8,   6, 16,   7,
                20, 10, 100, 14,  60,
                9, 32,  18, 40,  22,
                11, 13,  80, 26, 120,
            ],
            isNormalized: false
        )

        try Processors.Debayer( mode: .bilinear, pattern: .rggb ).process( buffer: &buffer )

        // Red site (2,2)=100: R own; G = mean of the cross greens (10,14,6,18)=12;
        // B = mean of the diagonal blues (8,16,32,40)=24.
        #expect( Array( buffer.pixels[ 36 ..< 39 ] ) == [ 100, 12, 24 ] )

        // Blue site (3,3)=40: R = mean of the diagonal reds (100,60,80,120)=90;
        // G = mean of the cross greens (18,22,14,26)=20; B own.
        #expect( Array( buffer.pixels[ 54 ..< 57 ] ) == [ 90, 20, 40 ] )

        // Green on a red row (1,2)=10: R = mean of the horizontal reds (20,100)=60;
        // B = mean of the vertical blues (8,32)=20; G own.
        #expect( Array( buffer.pixels[ 33 ..< 36 ] ) == [ 60, 10, 20 ] )

        // Green on a blue row (2,1)=6: R = mean of the vertical reds (50,100)=75;
        // B = mean of the horizontal blues (8,16)=12; G own.
        #expect( Array( buffer.pixels[ 21 ..< 24 ] ) == [ 75, 6, 12 ] )
    }

    @Test
    func testBilinear_GBRG_2x2() async throws
    {
        // GBRG is the one pattern never run through the demosaic; verify each site's
        // own colour passes straight through. Tile: G B / R B — (0,0)=green 10,
        // (1,0)=blue 20, (0,1)=red 30, (1,1)=green 40.
        var buffer = try PixelBuffer(
            width:        2,
            height:       2,
            channels:     1,
            pixels:       [ 10, 20, 30, 40 ],
            isNormalized: false
        )

        try Processors.Debayer( mode: .bilinear, pattern: .gbrg ).process( buffer: &buffer )

        try #require( buffer.channels     == 3 )
        try #require( buffer.pixels.count == 12 )

        let pix1 = ( r: buffer.pixels[ 0 ], g: buffer.pixels[  1 ], b: buffer.pixels[  2 ] )
        let pix2 = ( r: buffer.pixels[ 3 ], g: buffer.pixels[  4 ], b: buffer.pixels[  5 ] )
        let pix3 = ( r: buffer.pixels[ 6 ], g: buffer.pixels[  7 ], b: buffer.pixels[  8 ] )
        let pix4 = ( r: buffer.pixels[ 9 ], g: buffer.pixels[ 10 ], b: buffer.pixels[ 11 ] )

        #expect( pix1.g == 10 )
        #expect( pix2.b == 20 )
        #expect( pix3.r == 30 )
        #expect( pix4.g == 40 )
    }
}
