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

struct Test_Processors_CosmeticCorrection
{
    // MARK: - Metadata

    @Test
    func nameReflectsParameters() async throws
    {
        let processor = Processors.CosmeticCorrection( layout: .mono, parameters: .default )

        #expect( processor.name == "Cosmetic Correction (hot 8.00, cold 8.00, Mono)" )
        #expect( processor.description == processor.name )
    }

    @Test
    func nameReflectsDisabledAndToggles() async throws
    {
        let disabled = Processors.CosmeticCorrection.Parameters( isEnabled: false, correctHot: true, hotThreshold: 8.0, correctCold: true, coldThreshold: 8.0 )
        let hotOnly  = Processors.CosmeticCorrection.Parameters( isEnabled: true, correctHot: true, hotThreshold: 5.0, correctCold: false, coldThreshold: 8.0 )

        #expect( Processors.CosmeticCorrection( layout: .cfa, parameters: disabled ).name == "Cosmetic Correction (disabled)" )
        #expect( Processors.CosmeticCorrection( layout: .rgb, parameters: hotOnly ).name == "Cosmetic Correction (hot 5.00, cold off, RGB)" )
    }

    // MARK: - Equatable

    @Test
    func equatable() async throws
    {
        let a = Processors.CosmeticCorrection( layout: .mono, parameters: .default )
        let b = Processors.CosmeticCorrection( layout: .mono, parameters: .default )
        let c = Processors.CosmeticCorrection( layout: .cfa, parameters: .default )
        let d = Processors.CosmeticCorrection( layout: .mono, parameters: Processors.CosmeticCorrection.Parameters( isEnabled: true, correctHot: true, hotThreshold: 3.0, correctCold: true, coldThreshold: 8.0 ) )

        #expect( a == b )
        #expect( a != c )
        #expect( a != d )
        #expect( Processors.CosmeticCorrection.Parameters.default == Processors.CosmeticCorrection.Parameters( isEnabled: true, correctHot: true, hotThreshold: 8.0, correctCold: true, coldThreshold: 8.0 ) )
    }

    @Test
    func defaultParametersAreConservativeAndEnabled() async throws
    {
        let parameters = Processors.CosmeticCorrection.Parameters.default

        #expect( parameters.isEnabled )
        #expect( parameters.correctHot )
        #expect( parameters.correctCold )
        #expect( parameters.hotThreshold >= 5.0 )
        #expect( parameters.coldThreshold >= 5.0 )
    }

    // MARK: - Mono detection & repair

    @Test
    func singleHotPixelRepairedToNeighbourMedian() async throws
    {
        // A 3×3 flat field of 0.2 with one isolated hot spike at the centre.
        var buffer = try PixelBuffer(
            width:        3,
            height:       3,
            channels:     1,
            pixels:       [ 0.2, 0.2, 0.2, 0.2, 0.9, 0.2, 0.2, 0.2, 0.2 ],
            isNormalized: false
        )

        try Processors.CosmeticCorrection( layout: .mono, parameters: .default ).process( buffer: &buffer )

        #expect( buffer.pixels == [ 0.2, 0.2, 0.2, 0.2, 0.2, 0.2, 0.2, 0.2, 0.2 ] )
    }

    @Test
    func singleColdPixelRepairedToNeighbourMedian() async throws
    {
        var buffer = try PixelBuffer(
            width:        3,
            height:       3,
            channels:     1,
            pixels:       [ 0.6, 0.6, 0.6, 0.6, 0.05, 0.6, 0.6, 0.6, 0.6 ],
            isNormalized: false
        )

        try Processors.CosmeticCorrection( layout: .mono, parameters: .default ).process( buffer: &buffer )

        #expect( buffer.pixels == [ 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6 ] )
    }

    @Test
    func hotToggleDisabledLeavesHotPixel() async throws
    {
        let parameters = Processors.CosmeticCorrection.Parameters( isEnabled: true, correctHot: false, hotThreshold: 8.0, correctCold: true, coldThreshold: 8.0 )
        var buffer     = try PixelBuffer(
            width:        3,
            height:       3,
            channels:     1,
            pixels:       [ 0.2, 0.2, 0.2, 0.2, 0.9, 0.2, 0.2, 0.2, 0.2 ],
            isNormalized: false
        )

        try Processors.CosmeticCorrection( layout: .mono, parameters: parameters ).process( buffer: &buffer )

        #expect( buffer.pixels[ 4 ] == 0.9 )
    }

    @Test
    func coldToggleDisabledLeavesColdPixel() async throws
    {
        let parameters = Processors.CosmeticCorrection.Parameters( isEnabled: true, correctHot: true, hotThreshold: 8.0, correctCold: false, coldThreshold: 8.0 )
        var buffer     = try PixelBuffer(
            width:        3,
            height:       3,
            channels:     1,
            pixels:       [ 0.6, 0.6, 0.6, 0.6, 0.05, 0.6, 0.6, 0.6, 0.6 ],
            isNormalized: false
        )

        try Processors.CosmeticCorrection( layout: .mono, parameters: parameters ).process( buffer: &buffer )

        #expect( buffer.pixels[ 4 ] == 0.05 )
    }

    @Test
    func multiPixelStarLeftIntact() async throws
    {
        // A 2×2 block of equal-bright pixels on a dark field: no pixel is a strict
        // local maximum (each bright pixel has an equally bright neighbour), so the
        // star must survive at the conservative default threshold.
        let pixels: [ Double ] =
            [
                0.2, 0.2, 0.2, 0.2, 0.2,
                0.2, 0.9, 0.9, 0.2, 0.2,
                0.2, 0.9, 0.9, 0.2, 0.2,
                0.2, 0.2, 0.2, 0.2, 0.2,
                0.2, 0.2, 0.2, 0.2, 0.2,
            ]

        var buffer = try PixelBuffer( width: 5, height: 5, channels: 1, pixels: pixels, isNormalized: false )

        try Processors.CosmeticCorrection( layout: .mono, parameters: .default ).process( buffer: &buffer )

        #expect( buffer.pixels == pixels )
    }

    @Test
    func flatRegionWithNoiseHasNoFalsePositives() async throws
    {
        // A centre pixel that deviates from its neighbours by less than k·σ, where
        // the neighbours carry genuine variation, must not be flagged.
        var buffer = try PixelBuffer(
            width:        3,
            height:       3,
            channels:     1,
            pixels:       [ 0.48, 0.49, 0.50, 0.50, 0.55, 0.50, 0.51, 0.52, 0.52 ],
            isNormalized: false
        )

        try Processors.CosmeticCorrection( layout: .mono, parameters: .default ).process( buffer: &buffer )

        #expect( buffer.pixels[ 4 ] == 0.55 )
    }

    @Test
    func cornerHotPixelRepairedFromAvailableNeighbours() async throws
    {
        // The top-left corner spike is repaired using its three in-bounds neighbours.
        var buffer = try PixelBuffer(
            width:        3,
            height:       3,
            channels:     1,
            pixels:       [ 0.95, 0.2, 0.2, 0.2, 0.2, 0.2, 0.2, 0.2, 0.2 ],
            isNormalized: false
        )

        try Processors.CosmeticCorrection( layout: .mono, parameters: .default ).process( buffer: &buffer )

        #expect( buffer.pixels[ 0 ] == 0.2 )
    }

    // MARK: - CFA (step-2) sampling

    @Test
    func cfaUsesStepTwoSameColourNeighbours() async throws
    {
        // Value depends only on column parity, mimicking two Bayer colours: even
        // columns carry 0.3, odd columns 0.6. Step-2 neighbours always share a
        // column parity (same colour), so a genuine 0.6 site is never an outlier,
        // while a hot pixel injected on an even (0.3) site is repaired to 0.3.
        // A step-1 sampler would mix the two colours and misjudge both.
        var pixels = [ Double ]( repeating: 0.0, count: 25 )

        ( 0 ..< 5 ).forEach
        {
            y in ( 0 ..< 5 ).forEach
            {
                x in pixels[ y * 5 + x ] = x % 2 == 0 ? 0.3 : 0.6
            }
        }

        // Inject a hot pixel at an even-column (0.3) site.
        pixels[ 2 * 5 + 2 ] = 0.95

        var buffer = try PixelBuffer( width: 5, height: 5, channels: 1, pixels: pixels, isNormalized: false )

        try Processors.CosmeticCorrection( layout: .cfa, parameters: .default ).process( buffer: &buffer )

        // The hot pixel is repaired to the same-colour median (0.3)…
        #expect( buffer.pixels[ 2 * 5 + 2 ] == 0.3 )

        // …and every ordinary site is untouched (0.6 sites are not outliers under
        // step-2 sampling even though their step-1 neighbours are all 0.3).
        var expected = pixels
        expected[ 2 * 5 + 2 ] = 0.3

        #expect( buffer.pixels == expected )
    }

    // MARK: - RGB (per-channel) sampling

    @Test
    func rgbRepairsPerChannel() async throws
    {
        // A 3×3 RGB field: every pixel is (0.2, 0.4, 0.6) except the centre's RED
        // channel, which is a hot spike. Only the red centre sample must change.
        var pixels = [ Double ]()

        ( 0 ..< 9 ).forEach { _ in pixels.append( contentsOf: [ 0.2, 0.4, 0.6 ] ) }

        // Centre pixel index 4 → red sample at 4*3 = 12.
        pixels[ 12 ] = 0.95

        var buffer = try PixelBuffer( width: 3, height: 3, channels: 3, pixels: pixels, isNormalized: false )

        try Processors.CosmeticCorrection( layout: .rgb, parameters: .default ).process( buffer: &buffer )

        var expected = pixels
        expected[ 12 ] = 0.2

        #expect( buffer.pixels == expected )
    }

    // MARK: - No-op paths

    @Test
    func disabledIsNoOp() async throws
    {
        let parameters = Processors.CosmeticCorrection.Parameters( isEnabled: false, correctHot: true, hotThreshold: 8.0, correctCold: true, coldThreshold: 8.0 )
        let pixels: [ Double ] = [ 0.2, 0.2, 0.2, 0.2, 0.9, 0.2, 0.2, 0.2, 0.2 ]
        var buffer             = try PixelBuffer( width: 3, height: 3, channels: 1, pixels: pixels, isNormalized: false )

        try Processors.CosmeticCorrection( layout: .mono, parameters: parameters ).process( buffer: &buffer )

        #expect( buffer.pixels == pixels )
    }

    @Test
    func constantBufferHasNoFalsePositives() async throws
    {
        let pixels = [ Double ]( repeating: 0.5, count: 16 )
        var buffer = try PixelBuffer( width: 4, height: 4, channels: 1, pixels: pixels, isNormalized: false )

        try Processors.CosmeticCorrection( layout: .mono, parameters: .default ).process( buffer: &buffer )

        #expect( buffer.pixels == pixels )
    }

    @Test
    func emptyBufferIsHandled() async throws
    {
        var buffer = try PixelBuffer( width: 0, height: 0, channels: 1, pixels: [], isNormalized: false )

        try Processors.CosmeticCorrection( layout: .mono, parameters: .default ).process( buffer: &buffer )

        #expect( buffer.pixels == [] )
        #expect( buffer.width == 0 )
        #expect( buffer.height == 0 )
    }

    @Test
    func preservesNormalizationFlag() async throws
    {
        var buffer = try PixelBuffer(
            width:        3,
            height:       3,
            channels:     1,
            pixels:       [ 0.2, 0.2, 0.2, 0.2, 0.9, 0.2, 0.2, 0.2, 0.2 ],
            isNormalized: true
        )

        try Processors.CosmeticCorrection( layout: .mono, parameters: .default ).process( buffer: &buffer )

        #expect( buffer.isNormalized )
    }

    @Test
    func wrongChannelCountForLayoutThrows() async throws
    {
        // An RGB layout requires a 3-channel buffer.
        var buffer = try PixelBuffer( width: 2, height: 2, channels: 1, pixels: [ 0.2, 0.2, 0.2, 0.2 ], isNormalized: false )

        #expect( throws: PixelBufferError.self )
        {
            try Processors.CosmeticCorrection( layout: .rgb, parameters: .default ).process( buffer: &buffer )
        }
    }
}
