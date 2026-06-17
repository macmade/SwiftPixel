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

struct Test_Processors_CorrectGamma
{
    @Test
    func transform() async throws
    {
        var buffer = try PixelBuffer(
            width:        3,
            height:       1,
            channels:     1,
            pixels:       [ 0.0, 0.25, 1.0 ],
            isNormalized: true
        )

        let processor = Processors.CorrectGamma( gamma: 2.0 )

        try processor.process( buffer: &buffer )

        let expected = [ 0.0, 0.5, 1.0 ]

        #expect( zip( buffer.pixels, expected ).allSatisfy { abs( $0 - $1 ) < 1e-9 } )
    }

    @Test
    func transformAcrossChunkBoundary() async throws
    {
        // Larger than the internal exponent-scratch chunk so multiple chunks
        // (including a partial last one) are exercised.
        let count  = 10_000
        let input  = ( 0 ..< count ).map { Double( $0 ) / Double( count - 1 ) }
        var buffer = try PixelBuffer( width: count, height: 1, channels: 1, pixels: input, isNormalized: true )

        try Processors.CorrectGamma( gamma: 2.0 ).process( buffer: &buffer )

        let expected = input.map { pow( $0, 0.5 ) }

        #expect( zip( buffer.pixels, expected ).allSatisfy { abs( $0 - $1 ) < 1e-12 } )
    }

    @Test
    func zeroGammaThrows() async throws
    {
        var buffer = try PixelBuffer(
            width:        1,
            height:       1,
            channels:     1,
            pixels:       [ 0.5 ],
            isNormalized: true
        )

        let processor = Processors.CorrectGamma( gamma: 0.0 )

        #expect( throws: RuntimeError.self )
        {
            try processor.process( buffer: &buffer )
        }
    }

    @Test
    func negativeGammaThrows() async throws
    {
        var buffer = try PixelBuffer(
            width:        1,
            height:       1,
            channels:     1,
            pixels:       [ 0.5 ],
            isNormalized: true
        )

        let processor = Processors.CorrectGamma( gamma: -2.0 )

        #expect( throws: RuntimeError.self )
        {
            try processor.process( buffer: &buffer )
        }
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

        let processor = Processors.CorrectGamma( gamma: 2.0 )

        #expect( throws: RuntimeError.self )
        {
            try processor.process( buffer: &buffer )
        }
    }

    @Test
    func name() async throws
    {
        #expect( Processors.CorrectGamma( gamma: 2.0 ).name == "Gamma Correction (2.00)" )
    }
}
