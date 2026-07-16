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
    func underDeterminedPixelsAreLeftUntouched() async throws
    {
        // A 3×1 gradient: the two ends have a single neighbour and the middle two,
        // so none reaches the minimum neighbour count. An ordinary gradient here
        // must not be mistaken for hot/cold defects (regression: on-by-default
        // correction corrupting tiny images).
        let pixels: [ Double ] = [ 0.4, 0.5, 0.6 ]
        var buffer             = try PixelBuffer( width: 3, height: 1, channels: 1, pixels: pixels, isNormalized: false )

        try Processors.CosmeticCorrection( layout: .mono, parameters: .default ).process( buffer: &buffer )

        #expect( buffer.pixels == pixels )
    }

    @Test
    func smoothGradientIsNotFlagged() async throws
    {
        // A smooth linear gradient: the two opposite corners are strict local
        // extremes whose 3-neighbour neighbourhoods have zero MAD. With an absolute
        // robust-scale floor these gentle corners were wrongly "corrected"; the
        // relative floor makes the margin track the local level, so an ordinary
        // gradient is left entirely untouched.
        let pixels: [ Double ] =
        [
            0.50, 0.51, 0.52,
            0.51, 0.52, 0.53,
            0.52, 0.53, 0.54,
        ]

        var buffer = try PixelBuffer( width: 3, height: 3, channels: 1, pixels: pixels, isNormalized: false )

        try Processors.CosmeticCorrection( layout: .mono, parameters: .default ).process( buffer: &buffer )

        #expect( buffer.pixels == pixels )
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

    // MARK: - End-to-end (realistic synthetic frame)

    /// On a realistic frame — a noisy background with a multi-pixel star and
    /// injected hot/cold defects — the conservative default repairs the defects
    /// (restoring the value range) while leaving the star intact.
    @Test
    func restoresRangeAndPreservesStarOnANoisyFrame() async throws
    {
        let width  = 48
        let height = 48

        // Deterministic pseudo-noise so the neighbourhoods have a real spread (a
        // perfectly flat field would make the robust scale degenerate).
        var state  = UInt64( 0x9E3779B97F4A7C15 )
        var pixels = [ Double ]( repeating: 0, count: width * height )

        ( 0 ..< pixels.count ).forEach
        {
            state   = state &* 6364136223846793005 &+ 1442695040888963407
            let unit = Double( state >> 40 ) / Double( 1 << 24 )

            pixels[ $0 ] = 100.0 + unit * 20.0
        }

        // A multi-pixel star (a small Gaussian): its neighbours are also bright, so
        // it must survive the conservative threshold.
        let starX     = 24
        let starY     = 24
        let amplitude = 500.0
        let sigma     = 1.2

        ( -3 ... 3 ).forEach
        {
            dy in ( -3 ... 3 ).forEach
            {
                dx in

                let x = starX + dx
                let y = starY + dy

                pixels[ y * width + x ] += amplitude * exp( -( Double( dx * dx + dy * dy ) ) / ( 2.0 * sigma * sigma ) )
            }
        }

        // Isolated defects, well clear of the star and of each other.
        let hot  = [ ( 6, 6 ), ( 40, 8 ), ( 8, 40 ), ( 41, 41 ) ]
        let cold = [ ( 12, 30 ), ( 34, 14 ) ]

        hot.forEach  { pixels[ $0.1 * width + $0.0 ] = 5000.0 }
        cold.forEach { pixels[ $0.1 * width + $0.0 ] = 0.0 }

        let starIndex     = starY * width + starX
        let starPeakBefore = pixels[ starIndex ]

        var buffer = try PixelBuffer( width: width, height: height, channels: 1, pixels: pixels, isNormalized: false )

        try Processors.CosmeticCorrection( layout: .mono, parameters: .default ).process( buffer: &buffer )

        // Every injected defect is repaired back into the background range.
        hot.forEach  { #expect( buffer.pixels[ $0.1 * width + $0.0 ] < 200.0, "hot pixel not repaired" ) }
        cold.forEach { #expect( buffer.pixels[ $0.1 * width + $0.0 ] > 80.0,  "cold pixel not repaired" ) }

        // The star's peak is untouched …
        #expect( buffer.pixels[ starIndex ] == starPeakBefore )

        // … and with the defects gone the range collapses back to the real content:
        // the maximum is the star (~600), far below the 5000 hot value, and the
        // minimum is back in the background band rather than the injected 0.
        let maximum = try #require( buffer.pixels.max() )
        let minimum = try #require( buffer.pixels.min() )

        #expect( maximum == starPeakBefore )
        #expect( maximum < 1000.0 )
        #expect( minimum > 80.0 )
    }

    // MARK: - Non-finite neighbours

    @Test
    func hotPixelAdjacentToNaNNeighbourStillRepaired() async throws
    {
        // A 3×3 flat field of 0.2 with a hot centre (0.9) and a NaN blank in the
        // bottom-right corner. The NaN is gathered last, so before the fix it
        // lands at the top of the neighbour sort and makes the neighbour maximum
        // NaN — `value > maximum` is then false and the genuine hot pixel is left
        // uncorrected. Non-finite neighbours must be treated as absent.
        var buffer = try PixelBuffer(
            width:        3,
            height:       3,
            channels:     1,
            pixels:       [ 0.2, 0.2, 0.2, 0.2, 0.9, 0.2, 0.2, 0.2, .nan ],
            isNormalized: false
        )

        try Processors.CosmeticCorrection( layout: .mono, parameters: .default ).process( buffer: &buffer )

        // The hot centre is repaired to the finite-neighbour median …
        #expect( buffer.pixels[ 4 ] == 0.2 )

        // … and the NaN sample itself passes through unchanged (this stage repairs
        // hot/cold outliers, not blanks).
        #expect( buffer.pixels[ 8 ].isNaN )
    }

    @Test
    func hotPixelAdjacentToInfinityNeighbourStillRepaired() async throws
    {
        // The same guarantee for an infinite blank neighbour.
        var buffer = try PixelBuffer(
            width:        3,
            height:       3,
            channels:     1,
            pixels:       [ 0.2, 0.2, 0.2, 0.2, 0.9, 0.2, 0.2, 0.2, .infinity ],
            isNormalized: false
        )

        try Processors.CosmeticCorrection( layout: .mono, parameters: .default ).process( buffer: &buffer )

        #expect( buffer.pixels[ 4 ] == 0.2 )
    }
}
