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

struct Test_Processors_Resample
{
    @Test
    func nameIncludesTheMode() async throws
    {
        #expect( Processors.Resample( maxDimension: 1024 ).name == "Resample (max 1024 px, average)" )
        #expect( Processors.Resample( maxDimension: 1024, mode: .nearest( blockSize: 2 ) ).name == "Resample (max 1024 px, nearest 2×2)" )
    }

    @Test
    func factorAlreadyFits() async throws
    {
        // The image is already within the cap on both axes: no downsampling.
        #expect( Processors.Resample.factor( width: 100, height: 100, maxDimension: 1024 ) == 1 )
        #expect( Processors.Resample.factor( width: 1024, height: 512, maxDimension: 1024 ) == 1 )
    }

    @Test
    func factorDisabledForNonPositiveMax() async throws
    {
        #expect( Processors.Resample.factor( width: 6000, height: 4000, maxDimension: 0 ) == 1 )
        #expect( Processors.Resample.factor( width: 6000, height: 4000, maxDimension: -10 ) == 1 )
    }

    @Test
    func factorSmallestBringingSideWithinCap() async throws
    {
        // 6000 / 1024 = 5.86 -> factor 6 brings the long side to ceil( 6000 / 6 ) = 1000 <= 1024.
        #expect( Processors.Resample.factor( width: 6000, height: 4000, maxDimension: 1024 ) == 6 )

        // Exactly divisible: 2048 / 1024 = 2.
        #expect( Processors.Resample.factor( width: 2048, height: 1024, maxDimension: 1024 ) == 2 )
    }

    @Test
    func outputSizeRoundsUp() async throws
    {
        let size = Processors.Resample.outputSize( width: 6000, height: 4000, factor: 6 )

        #expect( size.width == 1000 )
        #expect( size.height == 667 )
    }

    @Test
    func outputSizeUnchangedForUnitFactor() async throws
    {
        let size = Processors.Resample.outputSize( width: 123, height: 45, factor: 1 )

        #expect( size.width == 123 )
        #expect( size.height == 45 )
    }

    // MARK: - Average mode

    @Test
    func averageBlockMean() async throws
    {
        // A 4x4 ramp downsampled by factor 2 (maxDimension 2) yields the mean of
        // each aligned 2x2 block.
        var buffer = try PixelBuffer(
            width:        4,
            height:       4,
            channels:     1,
            pixels:       [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 ].map { Double( $0 ) },
            isNormalized: false
        )

        try Processors.Resample( maxDimension: 2 ).process( buffer: &buffer )

        #expect( buffer.width == 2 )
        #expect( buffer.height == 2 )
        #expect( buffer.channels == 1 )
        #expect( buffer.pixels == [ 3.5, 5.5, 11.5, 13.5 ] )
    }

    @Test
    func averagePartialEdgeBlocks() async throws
    {
        // A 3x3 ramp downsampled by factor 2 (maxDimension 2) yields a 2x2 image
        // whose right column, bottom row and corner cover partial blocks — each is
        // the mean of the samples it actually covers, not divided by a full 2x2.
        var buffer = try PixelBuffer(
            width:        3,
            height:       3,
            channels:     1,
            pixels:       [ 0, 1, 2, 3, 4, 5, 6, 7, 8 ].map { Double( $0 ) },
            isNormalized: false
        )

        try Processors.Resample( maxDimension: 2 ).process( buffer: &buffer )

        #expect( buffer.width == 2 )
        #expect( buffer.height == 2 )
        // (0,0): mean(0,1,3,4)=2 ; (1,0): mean(2,5)=3.5 ; (0,1): mean(6,7)=6.5 ; (1,1): mean(8)=8.
        #expect( buffer.pixels == [ 2, 3.5, 6.5, 8 ] )
    }

    @Test
    func averageNonSquareWithPartialColumnAndRow() async throws
    {
        // A 5×3 frame downsampled by factor 2 (maxDimension 3, taken from the long
        // side 5) yields 3×2: an interior full block, a partial-X column, a partial-Y
        // row and a both-axes-partial corner all in one image, each divided by its
        // actual sample count. A square frame cannot separate the X and Y extents.
        var buffer = try PixelBuffer(
            width:        5,
            height:       3,
            channels:     1,
            pixels:       ( 0 ..< 15 ).map { Double( $0 ) },
            isNormalized: false
        )

        try Processors.Resample( maxDimension: 3 ).process( buffer: &buffer )

        #expect( buffer.width  == 3 )
        #expect( buffer.height == 2 )
        // Row 0: mean(0,1,5,6)=3, mean(2,3,7,8)=5, mean(4,9)=6.5 (partial X).
        // Row 1: mean(10,11)=10.5, mean(12,13)=12.5 (partial Y), mean(14)=14 (corner).
        #expect( buffer.pixels == [ 3, 5, 6.5, 10.5, 12.5, 14 ] )
    }

    @Test
    func averageNonSquareCollapsesToASingleRow() async throws
    {
        // A 3×2 frame downsampled by factor 2 (long side 3 > maxDimension 2) yields
        // 2×1, with the second column a partial-X block over a single column.
        var buffer = try PixelBuffer(
            width:        3,
            height:       2,
            channels:     1,
            pixels:       ( 0 ..< 6 ).map { Double( $0 ) },
            isNormalized: false
        )

        try Processors.Resample( maxDimension: 2 ).process( buffer: &buffer )

        #expect( buffer.width  == 2 )
        #expect( buffer.height == 1 )
        // mean(0,1,3,4)=2 ; mean(2,5)=3.5.
        #expect( buffer.pixels == [ 2, 3.5 ] )
    }

    @Test
    func averageChannelsIndependently() async throws
    {
        // A 2x2 RGB image averaged to a single pixel: each channel is the mean of
        // its four samples, independent of the others.
        var buffer = try PixelBuffer(
            width:        2,
            height:       2,
            channels:     3,
            pixels: [
                1, 10, 100,   2, 20, 200,
                3, 30, 300,   4, 40, 400,
            ].map { Double( $0 ) },
            isNormalized: false
        )

        try Processors.Resample( maxDimension: 1 ).process( buffer: &buffer )

        #expect( buffer.width == 1 )
        #expect( buffer.height == 1 )
        #expect( buffer.channels == 3 )
        #expect( buffer.pixels == [ 2.5, 25.0, 250.0 ] )
    }

    @Test
    func averageNoOpWhenAlreadyWithinCap() async throws
    {
        let pixels = [ 1, 2, 3, 4 ].map { Double( $0 ) }
        var buffer = try PixelBuffer( width: 2, height: 2, channels: 1, pixels: pixels, isNormalized: true )

        try Processors.Resample( maxDimension: 8 ).process( buffer: &buffer )

        #expect( buffer.width == 2 )
        #expect( buffer.height == 2 )
        #expect( buffer.pixels == pixels )

        // The normalization flag is untouched by a no-op.
        #expect( buffer.isNormalized == true )
    }

    @Test
    func averagePreservesNormalizationFlag() async throws
    {
        var buffer = try PixelBuffer(
            width:        4,
            height:       4,
            channels:     1,
            pixels:       [ Double ]( repeating: 0.5, count: 16 ),
            isNormalized: true
        )

        try Processors.Resample( maxDimension: 2 ).process( buffer: &buffer )

        #expect( buffer.isNormalized == true )
    }

    // MARK: - Nearest (decimation) mode

    @Test
    func nearestKeepsTopLeftOfEachBlock() async throws
    {
        // A 4x4 ramp decimated by factor 2 keeps the top-left sample of each 2x2
        // block: indices 0, 2, 8, 10.
        var buffer = try PixelBuffer( width: 4, height: 4, channels: 1, pixels: ( 0 ..< 16 ).map { Double( $0 ) }, isNormalized: false )

        try Processors.Resample( maxDimension: 2, mode: .nearest( blockSize: 1 ) ).process( buffer: &buffer )

        #expect( buffer.width == 2 )
        #expect( buffer.height == 2 )
        #expect( buffer.pixels == [ 0, 2, 8, 10 ] )
    }

    @Test
    func nearestNoOpWhenAlreadyWithinCap() async throws
    {
        let pixels = ( 0 ..< 16 ).map { Double( $0 ) }
        var buffer = try PixelBuffer( width: 4, height: 4, channels: 1, pixels: pixels, isNormalized: true )

        try Processors.Resample( maxDimension: 8, mode: .nearest( blockSize: 1 ) ).process( buffer: &buffer )

        #expect( buffer.width == 4 )
        #expect( buffer.pixels == pixels )
        #expect( buffer.isNormalized == true )
    }

    @Test
    func nearestNoOpForNonPositiveBlockSize() async throws
    {
        var buffer = try PixelBuffer( width: 4, height: 4, channels: 1, pixels: ( 0 ..< 16 ).map { Double( $0 ) }, isNormalized: false )

        try Processors.Resample( maxDimension: 2, mode: .nearest( blockSize: 0 ) ).process( buffer: &buffer )

        #expect( buffer.width == 4 )
        #expect( buffer.height == 4 )
    }

    @Test
    func nearestChannelsKeptTogether() async throws
    {
        // A 2x2 RGB image decimated to a single pixel keeps the first pixel's three
        // interleaved channels.
        let pixels = [ 1, 10, 100, 2, 20, 200, 3, 30, 300, 4, 40, 400 ].map { Double( $0 ) }
        var buffer = try PixelBuffer( width: 2, height: 2, channels: 3, pixels: pixels, isNormalized: false )

        try Processors.Resample( maxDimension: 1, mode: .nearest( blockSize: 1 ) ).process( buffer: &buffer )

        #expect( buffer.width == 1 )
        #expect( buffer.height == 1 )
        #expect( buffer.channels == 3 )
        #expect( buffer.pixels == [ 1, 10, 100 ] )
    }

    @Test
    func nearestBlockSizeTwoKeepsWholeCells() async throws
    {
        // A 4x4 mosaic decimated by factor 2 keeps a single 2x2 cell — the top-left
        // cell's four samples (indices 0, 1, 4, 5), preserving the pattern.
        var buffer = try PixelBuffer( width: 4, height: 4, channels: 1, pixels: ( 0 ..< 16 ).map { Double( $0 ) }, isNormalized: false )

        try Processors.Resample( maxDimension: 2, mode: .nearest( blockSize: 2 ) ).process( buffer: &buffer )

        #expect( buffer.width == 2 )
        #expect( buffer.height == 2 )
        #expect( buffer.pixels == [ 0, 1, 4, 5 ] )
    }

    @Test
    func nearestBlockSizeTwoPreservesPhaseAcrossMultipleCells() async throws
    {
        // An 8x8 mosaic decimated by factor 2 keeps every other 2x2 cell. Each kept
        // cell is copied whole and starts at an even column/row, so every colour
        // site lands on the same parity it had in the source.
        var buffer = try PixelBuffer( width: 8, height: 8, channels: 1, pixels: ( 0 ..< 64 ).map { Double( $0 ) }, isNormalized: false )

        try Processors.Resample( maxDimension: 4, mode: .nearest( blockSize: 2 ) ).process( buffer: &buffer )

        #expect( buffer.width == 4 )
        #expect( buffer.height == 4 )
        #expect( buffer.pixels == [ 0, 1, 4, 5, 8, 9, 12, 13, 32, 33, 36, 37, 40, 41, 44, 45 ] )
    }
}
