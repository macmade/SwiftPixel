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

struct Test_Processors_Stretch
{
    private static func makeBuffer( _ pixels: [ Double ] ) throws -> PixelBuffer
    {
        try PixelBuffer( width: pixels.count, height: 1, channels: 1, pixels: pixels, isNormalized: true )
    }

    @Test
    func logStretch() async throws
    {
        let n        = 1.0
        let input    = [ 0.0, 0.25, 0.5, 0.75, 1.0 ]
        var buffer   = try Self.makeBuffer( input )
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
        var buffer   = try Self.makeBuffer( input )
        let expected = input.map { asinh( n * $0 ) / asinh( n ) }

        try Processors.Stretch( algorithm: .arcsinh( n ) ).process( buffer: &buffer )

        #expect( zip( buffer.pixels, expected ).allSatisfy { abs( $0 - $1 ) < 1e-9 } )
        #expect( buffer.pixels.allSatisfy { $0.isFinite } )
    }

    @Test
    func sigmoidStretch() async throws
    {
        var buffer = try Self.makeBuffer( [ 0.0, 0.25, 0.5, 0.75, 1.0 ] )

        try Processors.Stretch( algorithm: .sigmoid( 10.0, 0.5 ) ).process( buffer: &buffer )

        #expect( buffer.pixels.allSatisfy { $0.isFinite } )
        #expect( buffer.pixels.allSatisfy { $0 >= 0.0 && $0 <= 1.0 } )
        #expect( abs( buffer.pixels[ 2 ] - 0.5 ) < 1e-9 )
    }

    @Test
    func logRejectsNonPositiveN() async throws
    {
        var zero     = try Self.makeBuffer( [ 0.5 ] )
        var negative = try Self.makeBuffer( [ 0.5 ] )

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
        var buffer = try Self.makeBuffer( [ 0.5 ] )

        #expect( throws: RuntimeError.self )
        {
            try Processors.Stretch( algorithm: .arcsinh( 0.0 ) ).process( buffer: &buffer )
        }
    }

    @Test
    func notNormalizedThrows() async throws
    {
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 1, pixels: [ 0.5 ], isNormalized: false )

        #expect( throws: RuntimeError.self )
        {
            try Processors.Stretch( algorithm: .log( 1.0 ) ).process( buffer: &buffer )
        }
    }

    @Test
    func equatable() async throws
    {
        #expect( Processors.Stretch.Algorithm.log( 1.0 ) == .log( 1.0 ) )
        #expect( Processors.Stretch.Algorithm.log( 1.0 ) != .log( 2.0 ) )
        #expect( Processors.Stretch.Algorithm.log( 1.0 ) != .arcsinh( 1.0 ) )

        #expect( Processors.Stretch.Algorithm.sigmoid( 1.0, 2.0 ) == .sigmoid( 1.0, 2.0 ) )
        #expect( Processors.Stretch.Algorithm.sigmoid( 1.0, 2.0 ) != .sigmoid( 1.0, 3.0 ) )
    }

    @Test
    func screenTransferEquatable() async throws
    {
        let a = Processors.Stretch.Algorithm.screenTransfer( .uniform( .identity ) )
        let b = Processors.Stretch.Algorithm.screenTransfer( .uniform( .identity ) )
        let c = Processors.Stretch.Algorithm.screenTransfer( .uniform( .init( shadows: 0.1 ) ) )

        #expect( a == b )
        #expect( a != c )
        #expect( a != .log( 1.0 ) )
    }

    @Test
    func screenTransferDescriptionMentionsScreenTransfer() async throws
    {
        let description = Processors.Stretch.Algorithm.screenTransfer( .uniform( .identity ) ).description

        #expect( description.contains( "Screen Transfer" ) )
    }

    @Test
    func screenTransferRejectsADegenerateChannel() async throws
    {
        var buffer  = try Self.makeBuffer( [ 0.4, 0.6 ] )
        let channel = Processors.Stretch.STFParameters.Channel( shadows: 0.8, midtones: 0.5, highlights: 0.2, low: 0, high: 1 )

        #expect( throws: RuntimeError.self )
        {
            try Processors.Stretch( algorithm: .screenTransfer( .uniform( channel ) ) ).process( buffer: &buffer )
        }
    }

    @Test
    func screenTransferRequiresANormalizedBuffer() async throws
    {
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 1, pixels: [ 0.5 ], isNormalized: false )

        #expect( throws: RuntimeError.self )
        {
            try Processors.Stretch( algorithm: .screenTransfer( .uniform( .identity ) ) ).process( buffer: &buffer )
        }
    }

    @Test
    func screenTransferHandlesAnEmptyBuffer() async throws
    {
        let degenerate = Processors.Stretch.STFParameters.Channel( shadows: 0, midtones: 0, highlights: 1, low: 0, high: 1 )
        var buffer     = try PixelBuffer( width: 0, height: 0, channels: 1, pixels: [], isNormalized: true )

        try Processors.Stretch( algorithm: .screenTransfer( .uniform( degenerate ) ) ).process( buffer: &buffer )

        #expect( buffer.pixels.isEmpty )
    }

    @Test
    func screenTransferMatchesTheScalarReferenceOnAPerChannelBuffer() async throws
    {
        let red    = Processors.Stretch.STFParameters.Channel( shadows: 0.02, midtones: 0.35, highlights: 0.98, low: 0.0, high: 1.0 )
        let green  = Processors.Stretch.STFParameters.Channel( shadows: 0.05, midtones: 0.25, highlights: 0.95, low: 0.1, high: 0.9 )
        let blue   = Processors.Stretch.STFParameters.Channel( shadows: 0.00, midtones: 0.60, highlights: 1.00, low: 0.0, high: 1.0 )
        let input  = [ 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9 ]
        var buffer = try PixelBuffer( width: 3, height: 1, channels: 3, pixels: input, isNormalized: true )

        try Processors.Stretch( algorithm: .screenTransfer( .perChannel( red: red, green: green, blue: blue ) ) ).process( buffer: &buffer )

        let expected = stride( from: 0, to: input.count, by: 3 ).flatMap
        {
            [ red.map( input[ $0 ] ), green.map( input[ $0 + 1 ] ), blue.map( input[ $0 + 2 ] ) ]
        }

        #expect( zip( buffer.pixels, expected ).allSatisfy { abs( $0 - $1 ) < 1e-12 } )
    }
}
