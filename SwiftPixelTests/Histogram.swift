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

struct Test_Histogram
{
    @Test
    func equatable() async throws
    {
        let a = Histogram( bytes: [ 10, 20, 30 ], channels: 3, mode: .rgb )
        let b = Histogram( bytes: [ 10, 20, 30 ], channels: 3, mode: .rgb )
        let c = Histogram( bytes: [ 10, 20, 40 ], channels: 3, mode: .rgb )

        #expect( a == b )
        #expect( a != c )
    }

    @Test
    func rgb() async throws
    {
        let bytes = [
            UInt8( 10 ), UInt8( 20 ), UInt8( 30 ),
            UInt8( 40 ), UInt8( 50 ), UInt8( 60 ),
            UInt8( 70 ), UInt8( 80 ), UInt8( 90 ),
        ]

        let histogram = Histogram( bytes: bytes, channels: 3, mode: .rgb )

        try #require( histogram.data.count == 3 )

        #expect( histogram.data[ 0 ][ 10 ] == 1 )
        #expect( histogram.data[ 1 ][ 20 ] == 1 )
        #expect( histogram.data[ 2 ][ 30 ] == 1 )
        #expect( histogram.data[ 0 ][ 40 ] == 1 )
        #expect( histogram.data[ 1 ][ 50 ] == 1 )
        #expect( histogram.data[ 2 ][ 60 ] == 1 )
        #expect( histogram.data[ 0 ][ 70 ] == 1 )
        #expect( histogram.data[ 1 ][ 80 ] == 1 )
        #expect( histogram.data[ 2 ][ 90 ] == 1 )
    }

    @Test
    func luma() async throws
    {
        let bytes = [
            UInt8( 10 ), UInt8( 20 ), UInt8( 30 ),
            UInt8( 40 ), UInt8( 50 ), UInt8( 60 ),
            UInt8( 70 ), UInt8( 80 ), UInt8( 90 ),
        ]

        let histogram = Histogram( bytes: bytes, channels: 3, mode: .luma )

        try #require( histogram.data.count == 1 )

        let expectedValues = [
            ( 2126 * 10 + 7152 * 20 + 722 * 30 ) / 10000,
            ( 2126 * 40 + 7152 * 50 + 722 * 60 ) / 10000,
            ( 2126 * 70 + 7152 * 80 + 722 * 90 ) / 10000,
        ]

        expectedValues.forEach
        {
            #expect( histogram.data[ 0 ][ $0 ] == 1 )
        }
    }

    @Test
    func emptyRGB() async throws
    {
        let histogram = Histogram( bytes: [], channels: 3, mode: .rgb )

        try #require( histogram.data.count == 3 )

        #expect( histogram.data[ 0 ].allSatisfy { $0 == 0 } )
        #expect( histogram.data[ 1 ].allSatisfy { $0 == 0 } )
        #expect( histogram.data[ 2 ].allSatisfy { $0 == 0 } )
    }

    @Test
    func emptyLuma() async throws
    {
        let histogram = Histogram( bytes: [], channels: 3, mode: .luma )

        try #require( histogram.data.count == 1 )

        #expect( histogram.data[ 0 ].allSatisfy { $0 == 0 } )
    }

    @Test
    func incompleteRGB() async throws
    {
        let bytes = [
            UInt8( 10 ), UInt8( 20 ), UInt8( 30 ),
            UInt8( 40 ), UInt8( 50 ),
        ]

        let histogram = Histogram( bytes: bytes, channels: 3, mode: .rgb )

        try #require( histogram.data.count == 3 )

        #expect( histogram.data[ 0 ][ 10 ] == 1 )
        #expect( histogram.data[ 1 ][ 20 ] == 1 )
        #expect( histogram.data[ 2 ][ 30 ] == 1 )
        #expect( histogram.data[ 0 ][ 40 ] == 0 )
        #expect( histogram.data[ 1 ][ 50 ] == 0 )
    }

    @Test
    func incompleteLuma() async throws
    {
        let bytes = [
            UInt8( 10 ), UInt8( 20 ), UInt8( 30 ),
            UInt8( 40 ), UInt8( 50 ),
        ]

        let histogram = Histogram( bytes: bytes, channels: 3, mode: .luma )

        try #require( histogram.data.count == 1 )

        let expectedY = ( 2126 * 10 + 7152 * 20 + 722 * 30 ) / 10000
        let missingY  = ( 2126 * 40 + 7152 * 50 + 722 * 0  ) / 10000

        #expect( histogram.data[ 0 ][ expectedY ] == 1 )
        #expect( histogram.data[ 0 ][ missingY  ] == 0 )
    }

    @Test
    func grayscale() async throws
    {
        let bytes = [ UInt8( 10 ), UInt8( 20 ), UInt8( 30 ) ]

        let histogram = Histogram( bytes: bytes, channels: 1, mode: .rgb )

        try #require( histogram.data.count == 3 )

        #expect( histogram.data[ 0 ][ 10 ] == 1 )
        #expect( histogram.data[ 1 ][ 10 ] == 1 )
        #expect( histogram.data[ 2 ][ 10 ] == 1 )
        #expect( histogram.data[ 0 ][ 20 ] == 1 )
        #expect( histogram.data[ 1 ][ 20 ] == 1 )
        #expect( histogram.data[ 2 ][ 30 ] == 1 )
    }

    @Test
    func grayscaleLuma() async throws
    {
        let bytes = [ UInt8( 10 ), UInt8( 20 ), UInt8( 30 ) ]

        let histogram = Histogram( bytes: bytes, channels: 1, mode: .luma )

        try #require( histogram.data.count == 1 )

        #expect( histogram.data[ 0 ][ 10 ] == 1 )
        #expect( histogram.data[ 0 ][ 20 ] == 1 )
        #expect( histogram.data[ 0 ][ 30 ] == 1 )
    }

    @Test
    func mono() async throws
    {
        let bytes = [ UInt8( 10 ), UInt8( 20 ), UInt8( 30 ) ]

        let histogram = Histogram( bytes: bytes, channels: 1, mode: .mono )

        try #require( histogram.data.count == 1 )

        #expect( histogram.data[ 0 ][ 10 ] == 1 )
        #expect( histogram.data[ 0 ][ 20 ] == 1 )
        #expect( histogram.data[ 0 ][ 30 ] == 1 )
    }

    @Test
    func monoFromMultiChannelReadsFirstChannel() async throws
    {
        let bytes = [
            UInt8( 10 ), UInt8( 20 ), UInt8( 30 ),
            UInt8( 40 ), UInt8( 50 ), UInt8( 60 ),
        ]

        let histogram = Histogram( bytes: bytes, channels: 3, mode: .mono )

        try #require( histogram.data.count == 1 )

        // Only the first sample of each pixel (channel 0) is counted.
        #expect( histogram.data[ 0 ][ 10 ] == 1 )
        #expect( histogram.data[ 0 ][ 40 ] == 1 )

        // The green and blue samples are ignored.
        #expect( histogram.data[ 0 ][ 20 ] == 0 )
        #expect( histogram.data[ 0 ][ 30 ] == 0 )
        #expect( histogram.data[ 0 ][ 50 ] == 0 )
        #expect( histogram.data[ 0 ][ 60 ] == 0 )
    }

    @Test
    func emptyMono() async throws
    {
        let histogram = Histogram( bytes: [], channels: 1, mode: .mono )

        try #require( histogram.data.count == 1 )

        #expect( histogram.data[ 0 ].allSatisfy { $0 == 0 } )
    }

    @Test
    func rgba() async throws
    {
        let bytes = [
            UInt8( 10 ), UInt8( 20 ), UInt8( 30 ), UInt8( 255 ),
            UInt8( 40 ), UInt8( 50 ), UInt8( 60 ), UInt8( 128 ),
        ]

        let histogram = Histogram( bytes: bytes, channels: 4, mode: .rgb )

        try #require( histogram.data.count == 3 )

        #expect( histogram.data[ 0 ][ 10 ] == 1 )
        #expect( histogram.data[ 1 ][ 20 ] == 1 )
        #expect( histogram.data[ 2 ][ 30 ] == 1 )
        #expect( histogram.data[ 0 ][ 40 ] == 1 )
        #expect( histogram.data[ 1 ][ 50 ] == 1 )
        #expect( histogram.data[ 2 ][ 60 ] == 1 )

        #expect( histogram.data[ 0 ][ 255 ] == 0 )
        #expect( histogram.data[ 0 ][ 128 ] == 0 )
    }
}
