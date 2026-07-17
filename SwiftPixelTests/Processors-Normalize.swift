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

struct Test_Processors_Normalize
{
    @Test
    func minMax() async throws
    {
        var buffer = try PixelBuffer(
            width:        5,
            height:       1,
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
    func minMaxRangeSpansAllChannels() async throws
    {
        // The range is taken globally across all channels (preserving colour
        // ratios), not per channel: the single global min (0) and max (100) map to
        // 0 and 1, and every channel is scaled by that same affine map.
        var buffer = try PixelBuffer(
            width:        2,
            height:       1,
            channels:     3,
            pixels:       [ 0, 50, 100, 25, 75, 50 ],
            isNormalized: false
        )

        try Processors.Normalize( mode: .minMax ).process( buffer: &buffer )

        #expect( buffer.isNormalized == true )
        #expect( buffer.pixels       == [ 0.0, 0.5, 1.0, 0.25, 0.75, 0.5 ] )
    }

    @Test
    func percentile() async throws
    {
        var buffer = try PixelBuffer(
            width:        5,
            height:       1,
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
    func minMaxConstant() async throws
    {
        var buffer = try PixelBuffer(
            width:        2,
            height:       2,
            channels:     1,
            pixels:       [ 42, 42, 42, 42 ],
            isNormalized: false
        )

        let processor = Processors.Normalize( mode: .minMax )

        try processor.process( buffer: &buffer )

        #expect( buffer.isNormalized == true )
        #expect( buffer.pixels == [ 0.0, 0.0, 0.0, 0.0 ] )
    }

    @Test
    func percentileConstant() async throws
    {
        var buffer = try PixelBuffer(
            width:        2,
            height:       2,
            channels:     1,
            pixels:       [ 42, 42, 42, 42 ],
            isNormalized: false
        )

        let processor = Processors.Normalize( mode: .percentile( 0.0, 100.0 ) )

        try processor.process( buffer: &buffer )

        #expect( buffer.isNormalized == true )
        #expect( buffer.pixels == [ 0.0, 0.0, 0.0, 0.0 ] )
    }

    @Test
    func empty() async throws
    {
        var buffer = try PixelBuffer(
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
        var buffer = try PixelBuffer(
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
        var buffer = try PixelBuffer(
            width:        1000,
            height:       1,
            channels:     1,
            pixels:       ( 0 ..< 1000 ).map { _ in Double.random( in: 0 ... 5000 ) },
            isNormalized: false
        )

        let processor = Processors.Normalize( mode: .percentile( 5.0, 95.0 ) )

        try processor.process( buffer: &buffer )

        #expect( buffer.isNormalized == true )
        #expect( buffer.pixels.allSatisfy { $0 >= 0.0 && $0 <= 1.0 } )
    }

    @Test
    func identity() async throws
    {
        var buffer = try PixelBuffer(
            width:        5,
            height:       1,
            channels:     1,
            pixels:       [ 0.0, 0.25, 0.5, 0.75, 1.0 ],
            isNormalized: false
        )

        let processor = Processors.Normalize( mode: .identity )

        try processor.process( buffer: &buffer )

        // Samples already in [0, 1] are left untouched; the buffer is simply
        // marked normalized so the 8-bit conversion can proceed.
        #expect( buffer.isNormalized == true )
        #expect( buffer.pixels == [ 0.0, 0.25, 0.5, 0.75, 1.0 ] )
    }

    @Test
    func identityClips() async throws
    {
        var buffer = try PixelBuffer(
            width:        4,
            height:       1,
            channels:     1,
            pixels:       [ -0.5, 0.25, 1.0, 1.5 ],
            isNormalized: false
        )

        let processor = Processors.Normalize( mode: .identity )

        try processor.process( buffer: &buffer )

        // Out-of-range samples are clamped to [0, 1]; in-range samples are kept.
        #expect( buffer.isNormalized == true )
        #expect( buffer.pixels == [ 0.0, 0.25, 1.0, 1.0 ] )
    }

    @Test
    func identityEmpty() async throws
    {
        var buffer = try PixelBuffer(
            width:        0,
            height:       0,
            channels:     1,
            pixels:       [],
            isNormalized: false
        )

        let processor = Processors.Normalize( mode: .identity )

        try processor.process( buffer: &buffer )

        #expect( buffer.isNormalized == true )
        #expect( buffer.pixels == [] )
    }

    @Test
    func minMaxIgnoresNonFiniteBlanks() async throws
    {
        // A NaN blank must not defeat the `min != max` guard (NaN != NaN is true)
        // nor poison the whole buffer: the finite range [0, 8] drives the scale and
        // the blank maps to 0 (black).
        var buffer = try PixelBuffer(
            width:        4,
            height:       1,
            channels:     1,
            pixels:       [ .nan, 0, 4, 8 ],
            isNormalized: false
        )

        try Processors.Normalize( mode: .minMax ).process( buffer: &buffer )

        #expect( buffer.isNormalized == true )
        #expect( buffer.pixels == [ 0.0, 0.0, 0.5, 1.0 ] )
        #expect( buffer.pixels.allSatisfy { $0.isFinite } )
    }

    @Test
    func minMaxMapsInfinityBlanksToBlack() async throws
    {
        // +Inf previously produced [NaN, 0, 0, 0]; it is now treated as a blank
        // and mapped to 0, leaving the finite samples correctly normalized.
        var buffer = try PixelBuffer(
            width:        4,
            height:       1,
            channels:     1,
            pixels:       [ .infinity, 0, 4, 8 ],
            isNormalized: false
        )

        try Processors.Normalize( mode: .minMax ).process( buffer: &buffer )

        #expect( buffer.isNormalized == true )
        #expect( buffer.pixels == [ 0.0, 0.0, 0.5, 1.0 ] )
    }

    @Test
    func minMaxAllNonFiniteIsZero() async throws
    {
        // With no finite samples there is no range to map to; the buffer collapses
        // to all-0, like a constant image.
        var buffer = try PixelBuffer(
            width:        2,
            height:       1,
            channels:     1,
            pixels:       [ .nan, .infinity ],
            isNormalized: false
        )

        try Processors.Normalize( mode: .minMax ).process( buffer: &buffer )

        #expect( buffer.isNormalized == true )
        #expect( buffer.pixels == [ 0.0, 0.0 ] )
    }

    @Test
    func percentileIgnoresNonFiniteBlanks() async throws
    {
        // The percentile bounds are computed over the finite samples, and the
        // blank maps to the lower bound (→ 0) rather than poisoning the output.
        var buffer = try PixelBuffer(
            width:        4,
            height:       1,
            channels:     1,
            pixels:       [ .nan, 0, 4, 8 ],
            isNormalized: false
        )

        try Processors.Normalize( mode: .percentile( 0.0, 100.0 ) ).process( buffer: &buffer )

        #expect( buffer.isNormalized == true )
        #expect( buffer.pixels == [ 0.0, 0.0, 0.5, 1.0 ] )
        #expect( buffer.pixels.allSatisfy { $0.isFinite } )
    }

    @Test
    func identityMapsNonFiniteBlanksToBlack() async throws
    {
        // Identity clamps to [0, 1]; a NaN blank is mapped to 0 rather than left
        // as NaN.
        var buffer = try PixelBuffer(
            width:        4,
            height:       1,
            channels:     1,
            pixels:       [ .nan, 0.25, 0.5, 1.5 ],
            isNormalized: false
        )

        try Processors.Normalize( mode: .identity ).process( buffer: &buffer )

        #expect( buffer.isNormalized == true )
        #expect( buffer.pixels == [ 0.0, 0.25, 0.5, 1.0 ] )
    }

    @Test
    func equatable() async throws
    {
        #expect( Processors.Normalize.Mode.minMax == .minMax )
        #expect( Processors.Normalize.Mode.minMax != .percentile( 0.0, 100.0 ) )

        #expect( Processors.Normalize.Mode.percentile( 5.0, 95.0 ) == .percentile( 5.0, 95.0 ) )
        #expect( Processors.Normalize.Mode.percentile( 5.0, 95.0 ) != .percentile( 1.0, 99.0 ) )

        #expect( Processors.Normalize.Mode.identity == .identity )
        #expect( Processors.Normalize.Mode.identity != .minMax )
    }

    @Test
    func description() async throws
    {
        #expect( Processors.Normalize.Mode.minMax.description == "Min/Max" )
        #expect( Processors.Normalize.Mode.identity.description == "Identity" )
        #expect( Processors.Normalize.Mode.percentile( 5.0, 95.0 ).description == "Percentile - 5.00 95.00" )
    }
}
