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

struct Test_Processors_BrightnessContrast
{
    private func sample() throws -> PixelBuffer
    {
        try PixelBuffer( width: 5, height: 1, channels: 1, pixels: [ 0.0, 0.25, 0.5, 0.75, 1.0 ], isNormalized: true )
    }

    private func expect( _ buffer: PixelBuffer, equals expected: [ Double ] )
    {
        #expect( buffer.pixels.count == expected.count )
        #expect( zip( buffer.pixels, expected ).allSatisfy { abs( $0 - $1 ) < 1e-12 }, "got \( buffer.pixels ), expected \( expected )" )
    }

    @Test
    func identityAtNeutral() async throws
    {
        var buffer = try self.sample()

        try Processors.BrightnessContrast( brightness: 0.0, contrast: 1.0 ).process( buffer: &buffer )

        self.expect( buffer, equals: [ 0.0, 0.25, 0.5, 0.75, 1.0 ] )
    }

    @Test
    func contrastScalesAroundMidpoint() async throws
    {
        var buffer = try self.sample()

        try Processors.BrightnessContrast( brightness: 0.0, contrast: 2.0 ).process( buffer: &buffer )

        // (v - 0.5) * 2 + 0.5, clipped to [0, 1].
        self.expect( buffer, equals: [ 0.0, 0.0, 0.5, 1.0, 1.0 ] )
    }

    @Test
    func zeroContrastFlattensToMidpoint() async throws
    {
        var buffer = try self.sample()

        try Processors.BrightnessContrast( brightness: 0.0, contrast: 0.0 ).process( buffer: &buffer )

        self.expect( buffer, equals: [ 0.5, 0.5, 0.5, 0.5, 0.5 ] )
    }

    @Test
    func positiveBrightnessShiftsUpAndClips() async throws
    {
        var buffer = try self.sample()

        try Processors.BrightnessContrast( brightness: 0.25, contrast: 1.0 ).process( buffer: &buffer )

        // v + 0.25, clipped to [0, 1].
        self.expect( buffer, equals: [ 0.25, 0.5, 0.75, 1.0, 1.0 ] )
    }

    @Test
    func negativeBrightnessShiftsDownAndClips() async throws
    {
        var buffer = try self.sample()

        try Processors.BrightnessContrast( brightness: -0.5, contrast: 1.0 ).process( buffer: &buffer )

        // v - 0.5, clipped to [0, 1].
        self.expect( buffer, equals: [ 0.0, 0.0, 0.0, 0.25, 0.5 ] )
    }

    @Test
    func appliesToEveryChannel() async throws
    {
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: [ 0.25, 0.5, 0.75 ], isNormalized: true )

        try Processors.BrightnessContrast( brightness: 0.0, contrast: 2.0 ).process( buffer: &buffer )

        self.expect( buffer, equals: [ 0.0, 0.5, 1.0 ] )
    }

    @Test
    func remainsNormalized() async throws
    {
        var buffer = try self.sample()

        try Processors.BrightnessContrast( brightness: 0.3, contrast: 1.5 ).process( buffer: &buffer )

        #expect( buffer.isNormalized )
    }

    @Test
    func notNormalizedThrows() async throws
    {
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 1, pixels: [ 0.5 ], isNormalized: false )

        #expect( throws: PixelBufferError.self )
        {
            try Processors.BrightnessContrast( brightness: 0.0, contrast: 1.0 ).process( buffer: &buffer )
        }
    }

    @Test
    func preservesAlphaChannelForRGBA() async throws
    {
        // A 4-channel (premultiplied RGBA) buffer has brightness/contrast applied
        // to its RGB, but the alpha channel is left untouched.
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 4, pixels: [ 0.25, 0.5, 0.75, 0.3 ], isNormalized: true )

        try Processors.BrightnessContrast( brightness: 0.0, contrast: 2.0 ).process( buffer: &buffer )

        // RGB scaled about the midpoint (0.25 -> 0, 0.5 -> 0.5, 0.75 -> 1); alpha unchanged.
        self.expect( buffer, equals: [ 0.0, 0.5, 1.0, 0.3 ] )
    }

    @Test
    func name() async throws
    {
        #expect( Processors.BrightnessContrast( brightness: 0.0, contrast: 1.0 ).name.isEmpty == false )
    }
}
