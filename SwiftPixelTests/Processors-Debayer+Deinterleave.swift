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
import SwiftUtilities
import Testing

struct Test_Processors_Debayer_Deinterleave
{
    private typealias Debayer = Processors.Debayer

    /// The four samples of a single 2×2 tile, `[ topLeft, topRight, bottomLeft,
    /// bottomRight ]`, so every pattern's positions can be asserted explicitly.
    private let tile: [ Double ] = [ 0, 1, 2, 3 ]

    /// Every supported Bayer arrangement, so a test can sweep them all.
    private let patterns: [ Debayer.Pattern ] = [ .bggr, .rgbg, .grbg, .rggb, .gbrg ]

    @Test
    func deinterleaveRGGB() async throws
    {
        // R G / G B
        let result = try Debayer.deinterleave( mosaic: self.tile, width: 2, height: 2, pattern: .rggb )

        #expect( result.red   == [ 0 ] )
        #expect( result.green == [ 1, 2 ] )
        #expect( result.blue  == [ 3 ] )
    }

    @Test
    func deinterleaveBGGR() async throws
    {
        // B G / G R
        let result = try Debayer.deinterleave( mosaic: self.tile, width: 2, height: 2, pattern: .bggr )

        #expect( result.red   == [ 3 ] )
        #expect( result.green == [ 1, 2 ] )
        #expect( result.blue  == [ 0 ] )
    }

    @Test
    func deinterleaveGRBG() async throws
    {
        // G R / B G
        let result = try Debayer.deinterleave( mosaic: self.tile, width: 2, height: 2, pattern: .grbg )

        #expect( result.red   == [ 1 ] )
        #expect( result.green == [ 0, 3 ] )
        #expect( result.blue  == [ 2 ] )
    }

    @Test
    func deinterleaveGBRG() async throws
    {
        // G B / R G
        let result = try Debayer.deinterleave( mosaic: self.tile, width: 2, height: 2, pattern: .gbrg )

        #expect( result.red   == [ 2 ] )
        #expect( result.green == [ 0, 3 ] )
        #expect( result.blue  == [ 1 ] )
    }

    @Test
    func deinterleaveRGBG() async throws
    {
        // R G / B G
        let result = try Debayer.deinterleave( mosaic: self.tile, width: 2, height: 2, pattern: .rgbg )

        #expect( result.red   == [ 0 ] )
        #expect( result.green == [ 1, 3 ] )
        #expect( result.blue  == [ 2 ] )
    }

    @Test
    func deinterleaveMatchesColorMapOnALargerMosaic() async throws
    {
        // On a full frame the split must agree, site by site and in row-major
        // order, with the demosaic's own color classification.
        let width  = 6
        let height = 4
        let pixels = ( 0 ..< ( width * height ) ).map { Double( $0 ) }

        try self.patterns.forEach
        {
            pattern in

            let result = try Debayer.deinterleave( mosaic: pixels, width: width, height: height, pattern: pattern )

            var expectedRed   = [ Double ]()
            var expectedGreen = [ Double ]()
            var expectedBlue  = [ Double ]()

            ( 0 ..< height ).forEach
            {
                y in ( 0 ..< width ).forEach
                {
                    x in

                    let value = pixels[ y * width + x ]

                    switch Debayer.colorAt( x: x, y: y, width: width, height: height, pattern: pattern )
                    {
                        case .red:   expectedRed.append(   value )
                        case .green: expectedGreen.append( value )
                        case .blue:  expectedBlue.append(  value )
                    }
                }
            }

            #expect( result.red   == expectedRed )
            #expect( result.green == expectedGreen )
            #expect( result.blue  == expectedBlue )

            // Every 2×2 tile has one red, two green and one blue site.
            let tiles = ( width * height ) / 4

            #expect( result.red.count   == tiles )
            #expect( result.green.count == tiles * 2 )
            #expect( result.blue.count  == tiles )
        }
    }

    @Test
    func deinterleaveRejectsAMismatchedSampleCount() async throws
    {
        #expect( throws: RuntimeError.self )
        {
            try Debayer.deinterleave( mosaic: [ 0, 1, 2 ], width: 2, height: 2, pattern: .rggb )
        }
    }
}
