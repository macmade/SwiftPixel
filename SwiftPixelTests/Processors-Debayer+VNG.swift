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

struct Test_Processors_Debayer_VNG
{
    @Test
    func vngRGGB_4x4_GoldenOutput() async throws
    {
        let pixels = ( 0 ..< 16 ).map { Double( $0 + 1 ) }
        var buffer = try PixelBuffer( width: 4, height: 4, channels: 1, pixels: pixels, isNormalized: false )

        try Processors.Debayer( mode: .vng, pattern: .rggb ).process( buffer: &buffer )

        #expect( buffer.pixels ==
            [
                1.0,                1.3333333333333333, 1.5833333333333333,
                1.8333333333333335, 2.0,                3.333333333333333,
                3.0,                3.0,                3.458333333333333,
                4.0,                4.0,                4.5,
                4.583333333333333,  5.0,                6.333333333333333,
                4.125,              4.666666666666667,  6.0,
                6.333333333333333,  7.0,                7.916666666666666,
                7.166666666666666,  7.5,                8.0,
                9.0,                9.5,                9.833333333333334,
                9.083333333333332, 10.0,               10.666666666666666,
                11.0,               12.333333333333334, 12.875,
                10.666666666666666, 12.0,               12.416666666666668,
                12.5,               13.0,               13.0,
                13.541666666666666, 14.0,               14.0,
                13.666666666666666, 15.0,               15.166666666666668,
                15.416666666666666, 15.666666666666666, 16.0,
            ]
        )
    }

    @Test
    func gradientsFlatRegionAreZero() async throws
    {
        let pixels = [ Double ]( repeating: 100.0, count: 5 * 5 )

        let gradients = Processors.Debayer.gradients( pixels: pixels, x: 2, y: 2, width: 5, height: 5 )

        #expect( gradients.count == 8 )
        #expect( gradients.allSatisfy { $0 == 0.0 } )
    }

    @Test
    func gradientThresholdExcludesAcrossEdgeDirections() async throws
    {
        // Vertical edge: columns 0-1 are dark, columns 2-4 are bright.
        let row    = [ 0.0, 0.0, 100.0, 100.0, 100.0 ]
        let pixels = ( 0 ..< 5 ).flatMap { _ in row }

        // Centre at (2,2), on the bright side adjacent to the edge.
        let gradients = Processors.Debayer.gradients( pixels: pixels, x: 2, y: 2, width: 5, height: 5 )
        let good      = Processors.Debayer.goodGradients( gradients )

        // Index order: N, NE, E, SE, S, SW, W, NW.
        #expect( good[ 2 ] == true )  // east, along the flat bright region -> retained
        #expect( good[ 6 ] == false ) // west, across the edge into the dark region -> excluded
    }

    @Test
    func greenInterpolationFlatMatchesValue() async throws
    {
        let pixels = [ Double ]( repeating: 50.0, count: 5 * 5 )

        let green = Processors.Debayer.interpolateGreen( pixels: pixels, x: 2, y: 2, width: 5, height: 5 )

        #expect( green == 50.0 )
    }

    @Test
    func greenInterpolationReducesEdgeErrorVsBilinear() async throws
    {
        // 6x6, vertical edge: columns 0-2 are dark (10), columns 3-5 are bright (90).
        let row    = [ 10.0, 10.0, 10.0, 90.0, 90.0, 90.0 ]
        let pixels = ( 0 ..< 6 ).flatMap { _ in row }

        // Site (2,2) lies on the dark side of the edge, so its true green is 10.
        let trueGreen = 10.0

        let vngGreen      = Processors.Debayer.interpolateGreen( pixels: pixels, x: 2, y: 2, width: 6, height: 6 )
        let bilinear      = try Processors.Debayer.bilinear( pixels: pixels, pattern: .rggb, width: 6, height: 6 )
        let bilinearGreen = bilinear[ ( 2 * 6 + 2 ) * 3 + 1 ]

        // VNG drops the across-edge neighbour, so its green is closer to the truth.
        #expect( abs( vngGreen - trueGreen ) < abs( bilinearGreen - trueGreen ) )
    }

    @Test
    func vngBGGR_2x2() async throws
    {
        var buffer = try PixelBuffer( width: 2, height: 2, channels: 1, pixels: [ 10, 20, 30, 40 ], isNormalized: false )

        try Processors.Debayer( mode: .vng, pattern: .bggr ).process( buffer: &buffer )

        try #require( buffer.channels     == 3 )
        try #require( buffer.pixels.count == 12 )

        #expect( buffer.pixels.allSatisfy { $0.isFinite } )

        // Present colour at each BGGR site is taken directly from the mosaic.
        #expect( buffer.pixels[  2 ] == 10 ) // (0,0) blue
        #expect( buffer.pixels[  4 ] == 20 ) // (1,0) green
        #expect( buffer.pixels[  7 ] == 30 ) // (0,1) green
        #expect( buffer.pixels[  9 ] == 40 ) // (1,1) red
    }

    @Test
    func vngRGGB_2x2() async throws
    {
        var buffer = try PixelBuffer( width: 2, height: 2, channels: 1, pixels: [ 10, 20, 30, 40 ], isNormalized: false )

        try Processors.Debayer( mode: .vng, pattern: .rggb ).process( buffer: &buffer )

        try #require( buffer.channels     == 3 )
        try #require( buffer.pixels.count == 12 )

        #expect( buffer.pixels.allSatisfy { $0.isFinite } )

        // Present colour at each RGGB site is taken directly from the mosaic.
        #expect( buffer.pixels[  0 ] == 10 ) // (0,0) red
        #expect( buffer.pixels[  4 ] == 20 ) // (1,0) green
        #expect( buffer.pixels[  7 ] == 30 ) // (0,1) green
        #expect( buffer.pixels[ 11 ] == 40 ) // (1,1) blue
    }

    @Test
    func vngAndBilinearBothSelectable() async throws
    {
        let pixels = ( 0 ..< 16 ).map { Double( $0 + 1 ) }

        for mode in [ Processors.Debayer.Mode.bilinear, .vng ]
        {
            var buffer = try PixelBuffer( width: 4, height: 4, channels: 1, pixels: pixels, isNormalized: false )

            try Processors.Debayer( mode: mode, pattern: .rggb ).process( buffer: &buffer )

            #expect( buffer.channels     == 3 )
            #expect( buffer.pixels.count == 48 )
            #expect( buffer.pixels.allSatisfy { $0.isFinite } )
        }
    }

    @Test
    func vngEdgeErrorNotWorseThanBilinear() async throws
    {
        // 6x6 luminance edge (every channel equal): columns 0-2 = 10, 3-5 = 90.
        // The true image is flat (v, v, v) per side, so reconstruction error
        // measures edge blurring.
        let width  = 6
        let height = 6
        let row    = [ 10.0, 10.0, 10.0, 90.0, 90.0, 90.0 ]
        let mosaic = ( 0 ..< height ).flatMap { _ in row }

        func error( mode: Processors.Debayer.Mode ) throws -> Double
        {
            var buffer = try PixelBuffer( width: width, height: height, channels: 1, pixels: mosaic, isNormalized: false )

            try Processors.Debayer( mode: mode, pattern: .rggb ).process( buffer: &buffer )

            return ( 0 ..< width * height ).reduce( 0.0 )
            {
                let truth = row[ $1 % width ]

                return $0 + abs( buffer.pixels[ $1 * 3 + 0 ] - truth )
                    + abs( buffer.pixels[ $1 * 3 + 1 ] - truth )
                    + abs( buffer.pixels[ $1 * 3 + 2 ] - truth )
            }
        }

        let vngError      = try error( mode: .vng )
        let bilinearError = try error( mode: .bilinear )

        #expect( vngError <= bilinearError )
    }
}
