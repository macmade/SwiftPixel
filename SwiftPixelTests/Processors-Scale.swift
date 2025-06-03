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

struct Test_Processors_Scale
{
    @Test
    func name() async throws
    {
        #expect( Processors.Scale( scale: 2.0, offset: 1.0 ).name == "Scale (2.00 1.00)" )
    }

    @Test
    func scaleAndOffset() async throws
    {
        let scale  = Processors.Scale( scale: 2.0, offset: 1.0 )
        var buffer = PixelBuffer(
            width:        2,
            height:       2,
            channels:     1,
            pixels:       [ 1.0, 2.0, 3.0, 4.0 ],
            isNormalized: false
        )

        try scale.process( buffer: &buffer )

        #expect( buffer.pixels       == [ 3.0, 5.0, 7.0, 9.0 ] )
        #expect( buffer.width        == 2 )
        #expect( buffer.height       == 2 )
        #expect( buffer.channels     == 1 )
        #expect( buffer.isNormalized == false )
    }

    @Test
    func scaleOnly() async throws
    {
        let scale  = Processors.Scale( scale: 0.5, offset: 0.0 )
        var buffer = PixelBuffer(
            width:        2,
            height:       2,
            channels:     1,
            pixels:       [ 1.0, 2.0, 3.0, 4.0 ],
            isNormalized: false
        )

        try scale.process( buffer: &buffer )

        #expect( buffer.pixels       == [ 0.5, 1.0, 1.5, 2.0 ] )
        #expect( buffer.width        == 2 )
        #expect( buffer.height       == 2 )
        #expect( buffer.channels     == 1 )
        #expect( buffer.isNormalized == false )
    }

    @Test
    func offsetOnly() async throws
    {
        let scale  = Processors.Scale( scale: 1.0, offset: 2.0 )
        var buffer = PixelBuffer(
            width:        2,
            height:       2,
            channels:     1,
            pixels:       [ 1.0, 2.0, 3.0, 4.0 ],
            isNormalized: false
        )

        try scale.process( buffer: &buffer )

        #expect( buffer.pixels       == [ 3.0, 4.0, 5.0, 6.0 ] )
        #expect( buffer.width        == 2 )
        #expect( buffer.height       == 2 )
        #expect( buffer.channels     == 1 )
        #expect( buffer.isNormalized == false )
    }

    @Test
    func noScaleOrOffset() async throws
    {
        let scale  = Processors.Scale( scale: 1.0, offset: 0.0 )
        var buffer = PixelBuffer(
            width:        2,
            height:       2,
            channels:     1,
            pixels:       [ 1.0, 2.0, 3.0, 4.0 ],
            isNormalized: false
        )

        try scale.process( buffer: &buffer )

        #expect( buffer.pixels       == [ 1.0, 2.0, 3.0, 4.0 ] )
        #expect( buffer.width        == 2 )
        #expect( buffer.height       == 2 )
        #expect( buffer.channels     == 1 )
        #expect( buffer.isNormalized == false )
    }

    @Test
    func zeroScaleZeroOffset() async throws
    {
        let scale  = Processors.Scale( scale: 0.0, offset: 0.0 )
        var buffer = PixelBuffer(
            width:        2,
            height:       2,
            channels:     1,
            pixels:       [ 1.0, 2.0, 3.0, 4.0 ],
            isNormalized: false
        )

        try scale.process( buffer: &buffer )

        #expect( buffer.pixels       == [ 0.0, 0.0, 0.0, 0.0 ] )
        #expect( buffer.width        == 2 )
        #expect( buffer.height       == 2 )
        #expect( buffer.channels     == 1 )
        #expect( buffer.isNormalized == false )
    }

    @Test
    func zeroScale() async throws
    {
        let scale  = Processors.Scale( scale: 0.0, offset: 2.0 )
        var buffer = PixelBuffer(
            width:        2,
            height:       2,
            channels:     1,
            pixels:       [ 1.0, 2.0, 3.0, 4.0 ],
            isNormalized: false
        )

        try scale.process( buffer: &buffer )

        #expect( buffer.pixels       == [ 2.0, 2.0, 2.0, 2.0 ] )
        #expect( buffer.width        == 2 )
        #expect( buffer.height       == 2 )
        #expect( buffer.channels     == 1 )
        #expect( buffer.isNormalized == false )
    }

    @Test
    func negativeScale() async throws
    {
        let scale  = Processors.Scale( scale: -1.0, offset: 0.0 )
        var buffer = PixelBuffer(
            width:        2,
            height:       2,
            channels:     1,
            pixels:       [ 1.0, 2.0, 3.0, 4.0 ],
            isNormalized: false
        )

        try scale.process( buffer: &buffer )

        #expect( buffer.pixels       == [ -1.0, -2.0, -3.0, -4.0 ] )
        #expect( buffer.width        == 2 )
        #expect( buffer.height       == 2 )
        #expect( buffer.channels     == 1 )
        #expect( buffer.isNormalized == false )
    }

    @Test
    func negativeOffset() async throws
    {
        let scale  = Processors.Scale( scale: 1.0, offset: -2.0 )
        var buffer = PixelBuffer(
            width:        2,
            height:       2,
            channels:     1,
            pixels:       [ 1.0, 2.0, 3.0, 4.0 ],
            isNormalized: false
        )

        try scale.process( buffer: &buffer )

        #expect( buffer.pixels       == [ -1.0, 0.0, 1.0, 2.0 ] )
        #expect( buffer.width        == 2 )
        #expect( buffer.height       == 2 )
        #expect( buffer.channels     == 1 )
        #expect( buffer.isNormalized == false )
    }

    @Test
    func negativeScaleAndOffset() async throws
    {
        let scale  = Processors.Scale( scale: -1.0, offset: -2.0 )
        var buffer = PixelBuffer(
            width:        2,
            height:       2,
            channels:     1,
            pixels:       [ 1.0, 2.0, 3.0, 4.0 ],
            isNormalized: false
        )

        try scale.process( buffer: &buffer )

        #expect( buffer.pixels       == [ -3.0, -4.0, -5.0, -6.0 ] )
        #expect( buffer.width        == 2 )
        #expect( buffer.height       == 2 )
        #expect( buffer.channels     == 1 )
        #expect( buffer.isNormalized == false )
    }

    @Test
    func emptyBuffer() async throws
    {
        let scale  = Processors.Scale( scale: 2.0, offset: 1.0 )
        var buffer = PixelBuffer(
            width:        0,
            height:       0,
            channels:     1,
            pixels:       [],
            isNormalized: false
        )

        try scale.process( buffer: &buffer )

        #expect( buffer.pixels       == [] )
        #expect( buffer.width        == 0 )
        #expect( buffer.height       == 0 )
        #expect( buffer.channels     == 1 )
        #expect( buffer.isNormalized == false )
    }
}
