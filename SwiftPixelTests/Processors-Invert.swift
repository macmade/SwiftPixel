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

struct Test_Processors_Invert
{
    @Test
    func transform() async throws
    {
        var buffer = try PixelBuffer(
            width:        4,
            height:       1,
            channels:     1,
            pixels:       [ 0.0, 0.25, 0.75, 1.0 ],
            isNormalized: true
        )

        try Processors.Invert().process( buffer: &buffer )

        let expected = [ 1.0, 0.75, 0.25, 0.0 ]

        #expect( zip( buffer.pixels, expected ).allSatisfy { abs( $0 - $1 ) < 1e-12 } )
    }

    @Test
    func invertsEveryChannel() async throws
    {
        var buffer = try PixelBuffer(
            width:        1,
            height:       1,
            channels:     3,
            pixels:       [ 0.2, 0.5, 0.8 ],
            isNormalized: true
        )

        try Processors.Invert().process( buffer: &buffer )

        let expected = [ 0.8, 0.5, 0.2 ]

        #expect( zip( buffer.pixels, expected ).allSatisfy { abs( $0 - $1 ) < 1e-12 } )
    }

    @Test
    func appliedTwiceRestoresOriginal() async throws
    {
        let input  = [ 0.1, 0.4, 0.6, 0.9 ]
        var buffer = try PixelBuffer( width: 4, height: 1, channels: 1, pixels: input, isNormalized: true )

        try Processors.Invert().process( buffer: &buffer )
        try Processors.Invert().process( buffer: &buffer )

        #expect( zip( buffer.pixels, input ).allSatisfy { abs( $0 - $1 ) < 1e-12 } )
    }

    @Test
    func remainsNormalized() async throws
    {
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 1, pixels: [ 0.3 ], isNormalized: true )

        try Processors.Invert().process( buffer: &buffer )

        #expect( buffer.isNormalized )
    }

    @Test
    func notNormalizedThrows() async throws
    {
        var buffer = try PixelBuffer(
            width:        1,
            height:       1,
            channels:     1,
            pixels:       [ 0.5 ],
            isNormalized: false
        )

        #expect( throws: PixelBufferError.self )
        {
            try Processors.Invert().process( buffer: &buffer )
        }
    }

    @Test
    func name() async throws
    {
        #expect( Processors.Invert().name == "Invert" )
    }
}
