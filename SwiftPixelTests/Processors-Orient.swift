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

struct Test_Processors_Orient
{
    /// A 2-wide, 3-tall, single-channel buffer with distinct sample values:
    ///
    ///     0 1
    ///     2 3
    ///     4 5
    private func sample() throws -> PixelBuffer
    {
        try PixelBuffer( width: 2, height: 3, channels: 1, pixels: [ 0, 1, 2, 3, 4, 5 ], isNormalized: false )
    }

    @Test
    func identityIsANoOp() async throws
    {
        var buffer = try self.sample()

        try Processors.Orient( orientation: .identity ).process( buffer: &buffer )

        #expect( buffer.width  == 2 )
        #expect( buffer.height == 3 )
        #expect( buffer.pixels == [ 0, 1, 2, 3, 4, 5 ] )
    }

    @Test
    func rotateClockwise90() async throws
    {
        var buffer = try self.sample()

        try Processors.Orient( orientation: .init( rotation: .clockwise90, mirroredHorizontally: false ) ).process( buffer: &buffer )

        // 3 wide, 2 tall:
        //   4 2 0
        //   5 3 1
        #expect( buffer.width  == 3 )
        #expect( buffer.height == 2 )
        #expect( buffer.pixels == [ 4, 2, 0, 5, 3, 1 ] )
    }

    @Test
    func rotate180() async throws
    {
        var buffer = try self.sample()

        try Processors.Orient( orientation: .init( rotation: .rotate180, mirroredHorizontally: false ) ).process( buffer: &buffer )

        // 2 wide, 3 tall, reversed:
        //   5 4
        //   3 2
        //   1 0
        #expect( buffer.width  == 2 )
        #expect( buffer.height == 3 )
        #expect( buffer.pixels == [ 5, 4, 3, 2, 1, 0 ] )
    }

    @Test
    func rotateCounterClockwise90() async throws
    {
        var buffer = try self.sample()

        try Processors.Orient( orientation: .init( rotation: .counterClockwise90, mirroredHorizontally: false ) ).process( buffer: &buffer )

        // 3 wide, 2 tall:
        //   1 3 5
        //   0 2 4
        #expect( buffer.width  == 3 )
        #expect( buffer.height == 2 )
        #expect( buffer.pixels == [ 1, 3, 5, 0, 2, 4 ] )
    }

    @Test
    func mirrorHorizontally() async throws
    {
        var buffer = try self.sample()

        try Processors.Orient( orientation: .init( rotation: .none, mirroredHorizontally: true ) ).process( buffer: &buffer )

        // 2 wide, 3 tall, columns swapped:
        //   1 0
        //   3 2
        //   5 4
        #expect( buffer.width  == 2 )
        #expect( buffer.height == 3 )
        #expect( buffer.pixels == [ 1, 0, 3, 2, 5, 4 ] )
    }

    @Test
    func keepsChannelsGroupedWhenMirroring() async throws
    {
        // Two RGB pixels in a row: (10,11,12) then (20,21,22).
        var buffer = try PixelBuffer( width: 2, height: 1, channels: 3, pixels: [ 10, 11, 12, 20, 21, 22 ], isNormalized: false )

        try Processors.Orient( orientation: .init( rotation: .none, mirroredHorizontally: true ) ).process( buffer: &buffer )

        #expect( buffer.width    == 2 )
        #expect( buffer.height   == 1 )
        #expect( buffer.channels == 3 )
        #expect( buffer.pixels   == [ 20, 21, 22, 10, 11, 12 ] )
    }

    @Test
    func preservesNormalizationFlag() async throws
    {
        var normalized = try PixelBuffer( width: 2, height: 1, channels: 1, pixels: [ 0.25, 0.75 ], isNormalized: true )
        try Processors.Orient( orientation: .init( rotation: .clockwise90, mirroredHorizontally: false ) ).process( buffer: &normalized )

        #expect( normalized.isNormalized )

        var raw = try PixelBuffer( width: 2, height: 1, channels: 1, pixels: [ 10, 20 ], isNormalized: false )
        try Processors.Orient( orientation: .init( rotation: .clockwise90, mirroredHorizontally: false ) ).process( buffer: &raw )

        #expect( raw.isNormalized == false )
    }

    @Test
    func largeMultiChannelRotationIsAnExactPermutation() async throws
    {
        // A large RGB buffer (past the parallel-row threshold) rotated 90° clockwise,
        // checked against an explicit rotation formula written independently of the
        // processor's `map` logic: for a source W×H, the output is H×W with
        // out[r][c] = src[H − 1 − c][r]. Being a pure permutation, it must match
        // bit-for-bit.
        let width    = 128
        let height   = 96
        let channels = 3
        let source   = ( 0 ..< width * height * channels ).map { Double( $0 ) }
        var buffer   = try PixelBuffer( width: width, height: height, channels: channels, pixels: source, isNormalized: false )

        try Processors.Orient( orientation: .init( rotation: .clockwise90, mirroredHorizontally: false ) ).process( buffer: &buffer )

        try #require( buffer.width  == height )
        try #require( buffer.height == width )

        var expected = [ Double ]( repeating: .nan, count: source.count )

        for r in 0 ..< width
        {
            for c in 0 ..< height
            {
                let sourceX = r
                let sourceY = height - 1 - c

                for channel in 0 ..< channels
                {
                    expected[ ( r * height + c ) * channels + channel ] = source[ ( sourceY * width + sourceX ) * channels + channel ]
                }
            }
        }

        #expect( buffer.pixels == expected )
    }

    @Test
    func largeMultiChannelMirrorIsAnExactPermutation() async throws
    {
        // A large RGB buffer mirrored horizontally, checked against the explicit
        // formula out[y][x] = src[y][W − 1 − x] (independent of `map`). The geometry
        // is unchanged and the samples are a pure permutation.
        let width    = 128
        let height   = 96
        let channels = 3
        let source   = ( 0 ..< width * height * channels ).map { Double( $0 ) }
        var buffer   = try PixelBuffer( width: width, height: height, channels: channels, pixels: source, isNormalized: false )

        try Processors.Orient( orientation: .init( rotation: .none, mirroredHorizontally: true ) ).process( buffer: &buffer )

        try #require( buffer.width  == width )
        try #require( buffer.height == height )

        var expected = [ Double ]( repeating: .nan, count: source.count )

        for y in 0 ..< height
        {
            for x in 0 ..< width
            {
                for channel in 0 ..< channels
                {
                    expected[ ( y * width + x ) * channels + channel ] = source[ ( y * width + ( width - 1 - x ) ) * channels + channel ]
                }
            }
        }

        #expect( buffer.pixels == expected )
    }

    @Test
    func zeroAreaSwapsGeometryWithoutCrashing() async throws
    {
        // A zero-area buffer has no samples to move, but a quarter-turn must still
        // rebuild its geometry (a 0×3 image rotated clockwise becomes 3×0). This
        // exercises the empty-buffer early-out (no per-row work, no threshold divide)
        // and confirms the geometry swap is still applied.
        var buffer = try PixelBuffer( width: 0, height: 3, channels: 1, pixels: [], isNormalized: false )

        try Processors.Orient( orientation: .init( rotation: .clockwise90, mirroredHorizontally: false ) ).process( buffer: &buffer )

        #expect( buffer.width  == 3 )
        #expect( buffer.height == 0 )
        #expect( buffer.pixels.isEmpty )
    }

    @Test
    func name() async throws
    {
        #expect( Processors.Orient( orientation: .identity ).name.isEmpty == false )
    }

    // MARK: - Orientation value type

    @Test
    func identityIsIdentity() async throws
    {
        #expect( Processors.Orient.Orientation.identity.isIdentity )
        #expect( Processors.Orient.Orientation( rotation: .clockwise90, mirroredHorizontally: false ).isIdentity == false )
        #expect( Processors.Orient.Orientation( rotation: .none, mirroredHorizontally: true ).isIdentity == false )
    }

    @Test
    func rotateClockwiseSteps() async throws
    {
        let identity = Processors.Orient.Orientation.identity

        #expect( identity.rotatedClockwise()                                         == .init( rotation: .clockwise90,        mirroredHorizontally: false ) )
        #expect( identity.rotatedClockwise().rotatedClockwise()                      == .init( rotation: .rotate180,          mirroredHorizontally: false ) )
        #expect( identity.rotatedClockwise().rotatedClockwise().rotatedClockwise()   == .init( rotation: .counterClockwise90, mirroredHorizontally: false ) )
        #expect( identity.rotatedClockwise().rotatedClockwise().rotatedClockwise().rotatedClockwise() == identity )
    }

    @Test
    func rotateCounterClockwiseStep() async throws
    {
        #expect( Processors.Orient.Orientation.identity.rotatedCounterClockwise() == .init( rotation: .counterClockwise90, mirroredHorizontally: false ) )
    }

    @Test
    func flipFromIdentity() async throws
    {
        #expect( Processors.Orient.Orientation.identity.flippedHorizontally() == .init( rotation: .none,      mirroredHorizontally: true ) )
        #expect( Processors.Orient.Orientation.identity.flippedVertically()   == .init( rotation: .rotate180, mirroredHorizontally: true ) )
    }

    /// A flip composes against what is currently *shown*, not the original
    /// orientation: flipping a clockwise-rotated image horizontally is a
    /// transpose, not the original transform with a mirror tacked on.
    @Test
    func flipIsScreenRelative() async throws
    {
        let composed = Processors.Orient.Orientation.identity.rotatedClockwise().flippedHorizontally()

        // Apply it to the sample and confirm it transposes the image.
        var buffer = try self.sample()

        try Processors.Orient( orientation: composed ).process( buffer: &buffer )

        // Transpose of the 2x3 sample is 3 wide, 2 tall:
        //   0 2 4
        //   1 3 5
        #expect( buffer.width  == 3 )
        #expect( buffer.height == 2 )
        #expect( buffer.pixels == [ 0, 2, 4, 1, 3, 5 ] )
    }

    /// A stored Orientation that is *both* mirrored and rotated, driven through
    /// `process` and checked against an independently hand-derived buffer — a
    /// stronger guarantee than `sourceCoordinateInvertsTheTransform`, which only
    /// checks that `map` and its inverse agree (a matched pair of bugs in the two
    /// would slip past that self-consistency check).
    @Test
    func mirroredThenRotatedPermutesPixels() async throws
    {
        // 3 wide, 2 tall:
        //   0 1 2
        //   3 4 5
        var buffer = try PixelBuffer( width: 3, height: 2, channels: 1, pixels: [ 0, 1, 2, 3, 4, 5 ], isNormalized: false )

        try Processors.Orient( orientation: .init( rotation: .clockwise90, mirroredHorizontally: true ) ).process( buffer: &buffer )

        // Mirror first (2 1 0 / 5 4 3), then rotate clockwise 90° → 2 wide, 3 tall:
        //   5 2
        //   4 1
        //   3 0
        #expect( buffer.width  == 2 )
        #expect( buffer.height == 3 )
        #expect( buffer.pixels == [ 5, 2, 4, 1, 3, 0 ] )
    }

    @Test
    func outputSizeSwapsForQuarterTurns() async throws
    {
        #expect( Processors.Orient.Orientation( rotation: .none,               mirroredHorizontally: false ).outputSize( sourceWidth: 2, sourceHeight: 3 ) == ( width: 2, height: 3 ) )
        #expect( Processors.Orient.Orientation( rotation: .rotate180,          mirroredHorizontally: true  ).outputSize( sourceWidth: 2, sourceHeight: 3 ) == ( width: 2, height: 3 ) )
        #expect( Processors.Orient.Orientation( rotation: .clockwise90,        mirroredHorizontally: false ).outputSize( sourceWidth: 2, sourceHeight: 3 ) == ( width: 3, height: 2 ) )
        #expect( Processors.Orient.Orientation( rotation: .counterClockwise90, mirroredHorizontally: true  ).outputSize( sourceWidth: 2, sourceHeight: 3 ) == ( width: 3, height: 2 ) )
    }

    /// `sourceCoordinate` must be the exact inverse of the pixel transform: the
    /// value the processor places at a display coordinate must be the source
    /// value found by mapping that display coordinate back.
    @Test
    func sourceCoordinateInvertsTheTransform() async throws
    {
        let orientations: [ Processors.Orient.Orientation ] =
            [
                .identity,
                .init( rotation: .clockwise90,        mirroredHorizontally: false ),
                .init( rotation: .rotate180,          mirroredHorizontally: false ),
                .init( rotation: .counterClockwise90, mirroredHorizontally: false ),
                .init( rotation: .none,               mirroredHorizontally: true  ),
                .init( rotation: .clockwise90,        mirroredHorizontally: true  ),
                .init( rotation: .rotate180,          mirroredHorizontally: true  ),
                .init( rotation: .counterClockwise90, mirroredHorizontally: true  ),
            ]

        let source = try self.sample()

        for orientation in orientations
        {
            var oriented = source

            try Processors.Orient( orientation: orientation ).process( buffer: &oriented )

            let size = orientation.outputSize( sourceWidth: source.width, sourceHeight: source.height )

            #expect( oriented.width  == size.width )
            #expect( oriented.height == size.height )

            for dy in 0 ..< oriented.height
            {
                for dx in 0 ..< oriented.width
                {
                    let src = orientation.sourceCoordinate( displayX: dx, displayY: dy, sourceWidth: source.width, sourceHeight: source.height )

                    #expect( src.x >= 0, "source x in range" )
                    #expect( src.y >= 0, "source y in range" )
                    #expect( src.x < source.width,  "source x in range" )
                    #expect( src.y < source.height, "source y in range" )

                    let displayValue = oriented.pixels[ dy * oriented.width + dx ]
                    let sourceValue  = source.pixels[ src.y * source.width + src.x ]

                    #expect( displayValue == sourceValue, "display (\( dx ),\( dy )) maps to source (\( src.x ),\( src.y )) for \( orientation )" )
                }
            }
        }
    }
}
