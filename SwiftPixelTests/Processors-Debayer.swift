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

struct Test_Processors_Debayer
{
    @Test
    func colorAtClampsBorderCoordinates() async throws
    {
        // A neighbour one step off the top/left/right edge classifies as the
        // clamped edge pixel, matching the edge-clamped sample reads. This
        // guards against the negative-modulo parity bug, e.g. (-1) % 2 == -1.
        #expect( Processors.Debayer.colorAt( x: -1, y:  0, width: 4, height: 4, pattern: .rggb ) == Processors.Debayer.colorAt( x: 0, y: 0, width: 4, height: 4, pattern: .rggb ) )
        #expect( Processors.Debayer.colorAt( x:  0, y: -1, width: 4, height: 4, pattern: .rggb ) == Processors.Debayer.colorAt( x: 0, y: 0, width: 4, height: 4, pattern: .rggb ) )
        #expect( Processors.Debayer.colorAt( x:  4, y:  0, width: 4, height: 4, pattern: .rggb ) == Processors.Debayer.colorAt( x: 3, y: 0, width: 4, height: 4, pattern: .rggb ) )
    }

    @Test
    func name() async throws
    {
        #expect( Processors.Debayer( mode: .bilinear, pattern: .bggr ).name == "Debayer (Bilinear BGGR)" )
        #expect( Processors.Debayer( mode: .bilinear, pattern: .grbg ).name == "Debayer (Bilinear GRBG)" )
        #expect( Processors.Debayer( mode: .bilinear, pattern: .rgbg ).name == "Debayer (Bilinear RGBG)" )
        #expect( Processors.Debayer( mode: .bilinear, pattern: .rggb ).name == "Debayer (Bilinear RGGB)" )
        #expect( Processors.Debayer( mode: .bilinear, pattern: .gbrg ).name == "Debayer (Bilinear GBRG)" )
    }

    @Test
    func colorAtGBRG() async throws
    {
        // The GBRG 2×2 tile: Green, Blue / Red, Green.
        #expect( Processors.Debayer.colorAt( x: 0, y: 0, width: 4, height: 4, pattern: .gbrg ) == .green )
        #expect( Processors.Debayer.colorAt( x: 1, y: 0, width: 4, height: 4, pattern: .gbrg ) == .blue )
        #expect( Processors.Debayer.colorAt( x: 0, y: 1, width: 4, height: 4, pattern: .gbrg ) == .red )
        #expect( Processors.Debayer.colorAt( x: 1, y: 1, width: 4, height: 4, pattern: .gbrg ) == .green )
    }

    @Test
    func invalidChannels() async throws
    {
        var buffer = try PixelBuffer(
            width:        2,
            height:       2,
            channels:     3,
            pixels:       [ 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120 ],
            isNormalized: false
        )

        let debayer = Processors.Debayer( mode: .bilinear, pattern: .bggr )

        #expect( throws: RuntimeError.self )
        {
            try debayer.process( buffer: &buffer )
        }
    }

    @Test
    func invalidNormalize() async throws
    {
        var buffer = try PixelBuffer(
            width:        2,
            height:       2,
            channels:     1,
            pixels:       [ 10, 20, 30, 40 ],
            isNormalized: true
        )

        let debayer = Processors.Debayer( mode: .bilinear, pattern: .bggr )

        #expect( throws: RuntimeError.self )
        {
            try debayer.process( buffer: &buffer )
        }
    }

    @Test
    func equatable() async throws
    {
        #expect( Processors.Debayer.Pattern.rggb == .rggb )
        #expect( Processors.Debayer.Pattern.rggb != .bggr )

        #expect( Processors.Debayer.Mode.bilinear == .bilinear )
        #expect( Processors.Debayer.Mode.bilinear != .vng )
    }
}
