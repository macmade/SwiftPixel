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
import Testing

struct Test_Processors_Normalize
{
    @Test
    func minMax() async throws
    {
        var buffer = PixelBuffer(
            width:        2,
            height:       2,
            channels:     1,
            pixels:       [ 0, 25, 50, 75, 100 ],
            isNormalized: false
        )

        let processor = Processors.Normalize( mode: .minMax )

        try processor.process( buffer: &buffer )

        #expect( buffer.isNormalized == true )
        #expect( buffer.pixels == [ 0.0, 0.25, 0.5, 0.75, 1.0 ] )
    }

    @Test
    func percentile() async throws
    {
        var buffer = PixelBuffer(
            width:        2,
            height:       2,
            channels:     1,
            pixels:       [ 0, 25, 50, 75, 100 ],
            isNormalized: false
        )

        let processor = Processors.Normalize( mode: .percentile( 0.0, 100.0 ) )

        try processor.process( buffer: &buffer )

        #expect( buffer.isNormalized == true )
        #expect( buffer.pixels == [ 0.0, 0.25, 0.5, 0.75, 1.0 ] )
    }

    @Test
    func empty() async throws
    {
        var buffer = PixelBuffer(
            width:        0,
            height:       0,
            channels:     1,
            pixels:       [],
            isNormalized: false
        )

        let processor = Processors.Normalize( mode: .minMax )

        try processor.process( buffer: &buffer )

        #expect( buffer.isNormalized == true )
        #expect( buffer.pixels == [] )
    }

    @Test
    func minMaxRandom() async throws
    {
        var buffer = PixelBuffer(
            width:        1000,
            height:       1,
            channels:     1,
            pixels:       ( 0 ..< 1000 ).map { _ in Double.random( in: 0 ... 5000 ) },
            isNormalized: false
        )

        let processor = Processors.Normalize( mode: .minMax )

        try processor.process( buffer: &buffer )

        #expect( buffer.isNormalized == true )
        #expect( buffer.pixels.allSatisfy { $0 >= 0.0 && $0 <= 1.0 } )
    }

    @Test
    func percentileRandom() async throws
    {
        var buffer = PixelBuffer(
            width:        1000,
            height:       1,
            channels:     1,
            pixels:       ( 0 ..< 1000 ).map { _ in Double.random( in: 0 ... 5000 ) },
            isNormalized: false
        )

        let processor = Processors.Normalize( mode: .minMax )

        try processor.process( buffer: &buffer )

        #expect( buffer.isNormalized == true )
        #expect( buffer.pixels.allSatisfy { $0 >= 0.0 && $0 <= 1.0 } )
    }
}
