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

struct Test_Processors_Stretch
{
    private static func makeBuffer( _ pixels: [ Double ] ) -> PixelBuffer
    {
        PixelBuffer( width: pixels.count, height: 1, channels: 1, pixels: pixels, isNormalized: true )
    }

    @Test
    func logStretch() async throws
    {
        let n        = 1.0
        let input    = [ 0.0, 0.25, 0.5, 0.75, 1.0 ]
        var buffer   = Self.makeBuffer( input )
        let expected = input.map { log( 1.0 + n * $0 ) / log( 1.0 + n ) }

        try Processors.Stretch( algorithm: .log( n ) ).process( buffer: &buffer )

        #expect( zip( buffer.pixels, expected ).allSatisfy { abs( $0 - $1 ) < 1e-9 } )
        #expect( buffer.pixels.allSatisfy { $0.isFinite } )
    }

    @Test
    func arcsinhStretch() async throws
    {
        let n        = 3.0
        let input    = [ 0.0, 0.25, 0.5, 0.75, 1.0 ]
        var buffer   = Self.makeBuffer( input )
        let expected = input.map { asinh( n * $0 ) / asinh( n ) }

        try Processors.Stretch( algorithm: .arcsinh( n ) ).process( buffer: &buffer )

        #expect( zip( buffer.pixels, expected ).allSatisfy { abs( $0 - $1 ) < 1e-9 } )
        #expect( buffer.pixels.allSatisfy { $0.isFinite } )
    }

    @Test
    func sigmoidStretch() async throws
    {
        var buffer = Self.makeBuffer( [ 0.0, 0.25, 0.5, 0.75, 1.0 ] )

        try Processors.Stretch( algorithm: .sigmoid( 10.0, 0.5 ) ).process( buffer: &buffer )

        #expect( buffer.pixels.allSatisfy { $0.isFinite } )
        #expect( buffer.pixels.allSatisfy { $0 >= 0.0 && $0 <= 1.0 } )
        #expect( abs( buffer.pixels[ 2 ] - 0.5 ) < 1e-9 )
    }

    @Test
    func logRejectsNonPositiveN() async throws
    {
        var zero     = Self.makeBuffer( [ 0.5 ] )
        var negative = Self.makeBuffer( [ 0.5 ] )

        #expect( throws: RuntimeError.self )
        {
            try Processors.Stretch( algorithm: .log( 0.0 ) ).process( buffer: &zero )
        }

        #expect( throws: RuntimeError.self )
        {
            try Processors.Stretch( algorithm: .log( -1.0 ) ).process( buffer: &negative )
        }
    }

    @Test
    func arcsinhRejectsZeroN() async throws
    {
        var buffer = Self.makeBuffer( [ 0.5 ] )

        #expect( throws: RuntimeError.self )
        {
            try Processors.Stretch( algorithm: .arcsinh( 0.0 ) ).process( buffer: &buffer )
        }
    }

    @Test
    func notNormalizedThrows() async throws
    {
        var buffer = PixelBuffer( width: 1, height: 1, channels: 1, pixels: [ 0.5 ], isNormalized: false )

        #expect( throws: RuntimeError.self )
        {
            try Processors.Stretch( algorithm: .log( 1.0 ) ).process( buffer: &buffer )
        }
    }
}
