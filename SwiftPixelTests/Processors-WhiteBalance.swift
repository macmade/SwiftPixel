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

struct Test_Processors_WhiteBalance
{
    @Test
    func manualGain() async throws
    {
        var buffer = try PixelBuffer(
            width:        1,
            height:       1,
            channels:     3,
            pixels:       [ 0.2, 0.3, 0.4 ],
            isNormalized: true
        )

        let processor = Processors.WhiteBalance( mode: .manual( red: 2.0, green: 1.0, blue: 0.5 ) )

        try processor.process( buffer: &buffer )

        #expect( buffer.pixels == [ 0.4, 0.3, 0.2 ] )
    }

    @Test
    func manualGainClipsToRange() async throws
    {
        var buffer = try PixelBuffer(
            width:        1,
            height:       1,
            channels:     3,
            pixels:       [ 0.5, 0.5, 0.5 ],
            isNormalized: true
        )

        let processor = Processors.WhiteBalance( mode: .manual( red: 4.0, green: 1.0, blue: 1.0 ) )

        try processor.process( buffer: &buffer )

        #expect( buffer.pixels == [ 1.0, 0.5, 0.5 ] )
    }

    @Test
    func autoGainNormalImage() async throws
    {
        var buffer = try PixelBuffer(
            width:        2,
            height:       1,
            channels:     3,
            pixels:       [ 0.2, 0.4, 0.6, 0.3, 0.5, 0.7 ],
            isNormalized: true
        )

        let processor = Processors.WhiteBalance( mode: .auto )

        try processor.process( buffer: &buffer )

        #expect( buffer.pixels.allSatisfy { $0.isFinite } )
        #expect( buffer.pixels.allSatisfy { $0 >= 0.0 && $0 <= 1.0 } )
    }

    @Test
    func autoGainZeroChannel() async throws
    {
        var buffer = try PixelBuffer(
            width:        2,
            height:       1,
            channels:     3,
            pixels:       [ 0.5, 0.5, 0.0, 0.5, 0.5, 0.0 ],
            isNormalized: true
        )

        let processor = Processors.WhiteBalance( mode: .auto )

        try processor.process( buffer: &buffer )

        #expect( buffer.pixels.allSatisfy { $0.isFinite } )
        #expect( buffer.pixels.allSatisfy { $0 >= 0.0 && $0 <= 1.0 } )
    }

    @Test
    func notNormalizedThrows() async throws
    {
        var buffer = try PixelBuffer(
            width:        1,
            height:       1,
            channels:     3,
            pixels:       [ 0.2, 0.3, 0.4 ],
            isNormalized: false
        )

        let processor = Processors.WhiteBalance( mode: .auto )

        #expect( throws: PixelBufferError.self )
        {
            try processor.process( buffer: &buffer )
        }
    }

    @Test
    func name() async throws
    {
        #expect( Processors.WhiteBalance( mode: .auto ).name == "White Balance (Auto)" )
        #expect( Processors.WhiteBalance( mode: .manual( red: 1.0, green: 2.0, blue: 0.5 ) ).name == "White Balance (Manual - R: 1.00, G: 2.00, B: 0.50)" )
    }

    @Test
    func equatable() async throws
    {
        #expect( Processors.WhiteBalance.Mode.auto == .auto )
        #expect( Processors.WhiteBalance.Mode.auto != .manual( red: 1.0, green: 1.0, blue: 1.0 ) )

        #expect( Processors.WhiteBalance.Mode.manual( red: 1.0, green: 2.0, blue: 0.5 ) == .manual( red: 1.0, green: 2.0, blue: 0.5 ) )
        #expect( Processors.WhiteBalance.Mode.manual( red: 1.0, green: 2.0, blue: 0.5 ) != .manual( red: 1.0, green: 2.0, blue: 1.0 ) )
    }
}
