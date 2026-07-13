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

struct Test_Processors_Bin
{
    @Test
    func name() async throws
    {
        #expect( Processors.Bin( factor: 2 ).name == "Bin (2×2)" )
    }

    @Test
    func outputSizeReducesTheCellGrid() async throws
    {
        #expect( Processors.Bin.outputSize( width: 8, height: 8, factor: 2 ).width == 4 )
        #expect( Processors.Bin.outputSize( width: 3008, height: 3008, factor: 2 ).width == 1504 )
        #expect( Processors.Bin.outputSize( width: 4, height: 4, factor: 1 ).width == 4 )
    }

    @Test
    func binsOneCellAveragingSameColourSites() async throws
    {
        // A 4x4 mosaic binned by 2 collapses to one 2x2 cell; each output site is the
        // mean of the four same-position (same-colour) sites in the frame.
        var buffer = try PixelBuffer( width: 4, height: 4, channels: 1, pixels: ( 0 ..< 16 ).map { Double( $0 ) }, isNormalized: false )

        try Processors.Bin( factor: 2 ).process( buffer: &buffer )

        #expect( buffer.width == 2 )
        #expect( buffer.height == 2 )
        #expect( buffer.channels == 1 )
        // R=avg(0,2,8,10)=5, G=avg(1,3,9,11)=6, G=avg(4,6,12,14)=9, B=avg(5,7,13,15)=10.
        #expect( buffer.pixels == [ 5, 6, 9, 10 ] )
    }

    @Test
    func preservesMosaicPhaseAcrossCells() async throws
    {
        // An 8x8 mosaic binned by 2 → 4x4: still a valid RGGB mosaic, each site the
        // mean of its four same-colour sites (hand-verified).
        var buffer = try PixelBuffer( width: 8, height: 8, channels: 1, pixels: ( 0 ..< 64 ).map { Double( $0 ) }, isNormalized: false )

        try Processors.Bin( factor: 2 ).process( buffer: &buffer )

        #expect( buffer.width == 4 )
        #expect( buffer.height == 4 )
        #expect( buffer.pixels == [ 9, 10, 13, 14, 17, 18, 21, 22, 41, 42, 45, 46, 49, 50, 53, 54 ] )
    }

    @Test
    func noOpForUnitFactor() async throws
    {
        let pixels = ( 0 ..< 16 ).map { Double( $0 ) }
        var buffer = try PixelBuffer( width: 4, height: 4, channels: 1, pixels: pixels, isNormalized: true )

        try Processors.Bin( factor: 1 ).process( buffer: &buffer )

        #expect( buffer.width == 4 )
        #expect( buffer.pixels == pixels )
        #expect( buffer.isNormalized == true )
    }

    @Test
    func preservesNormalizationFlag() async throws
    {
        var buffer = try PixelBuffer( width: 8, height: 8, channels: 1, pixels: [ Double ]( repeating: 0.25, count: 64 ), isNormalized: true )

        try Processors.Bin( factor: 2 ).process( buffer: &buffer )

        #expect( buffer.isNormalized == true )
    }

    @Test
    func requiresSingleChannel() async throws
    {
        var buffer = try PixelBuffer( width: 4, height: 4, channels: 3, pixels: [ Double ]( repeating: 0.5, count: 48 ), isNormalized: false )

        #expect( throws: PixelBufferError.self )
        {
            try Processors.Bin( factor: 2 ).process( buffer: &buffer )
        }
    }

    @Test
    func throwsForNonPositiveFactor() async throws
    {
        var buffer = try PixelBuffer( width: 4, height: 4, channels: 1, pixels: ( 0 ..< 16 ).map { Double( $0 ) }, isNormalized: false )

        #expect( throws: Processors.Bin.ValidationError.nonPositiveFactor( 0 ) )
        {
            try Processors.Bin( factor: 0 ).process( buffer: &buffer )
        }

        #expect( throws: Processors.Bin.ValidationError.nonPositiveFactor( -3 ) )
        {
            try Processors.Bin( factor: -3 ).process( buffer: &buffer )
        }
    }

    @Test
    func throwsWhenFactorIsTooLargeForTheImage() async throws
    {
        var buffer = try PixelBuffer( width: 4, height: 4, channels: 1, pixels: ( 0 ..< 16 ).map { Double( $0 ) }, isNormalized: false )

        // A 4x4 image is a 2x2 cell grid; a factor of 3 yields no output cells.
        #expect( throws: Processors.Bin.ValidationError.factorTooLarge( factor: 3, width: 4, height: 4 ) )
        {
            try Processors.Bin( factor: 3 ).process( buffer: &buffer )
        }
    }

    @Test
    func defaultFactorIsIdentity() async throws
    {
        let pixels = ( 0 ..< 16 ).map { Double( $0 ) }
        var buffer = try PixelBuffer( width: 4, height: 4, channels: 1, pixels: pixels, isNormalized: false )

        try Processors.Bin().process( buffer: &buffer )

        #expect( buffer.width == 4 )
        #expect( buffer.pixels == pixels )
    }
}
