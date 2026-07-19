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

struct Test_Processors_ColorBalance
{
    /// The tolerance for comparing shifted channels. The tonal weights are exact
    /// at black, mid-gray and white, so only floating-point rounding is absorbed.
    private let tolerance = 1e-9

    /// A convenience for the common single-range balances used by the tests.
    private func ranges( shadows: Processors.ColorBalance.Shift = .identity, midtones: Processors.ColorBalance.Shift = .identity, highlights: Processors.ColorBalance.Shift = .identity ) -> Processors.ColorBalance.Ranges
    {
        Processors.ColorBalance.Ranges( shadows: shadows, midtones: midtones, highlights: highlights )
    }

    @Test
    func neutralIsIdentity() async throws
    {
        let input  = [ 0.2, 0.5, 0.9 ]
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: input, isNormalized: true )

        try Processors.ColorBalance( ranges: .identity ).process( buffer: &buffer )

        #expect( zip( buffer.pixels, input ).allSatisfy { abs( $0 - $1 ) < self.tolerance }, "got \( buffer.pixels ), expected \( input )" )
    }

    @Test
    func shadowsShiftMovesDarkPixelsAndSparesBrightOnes() async throws
    {
        let ranges = self.ranges( shadows: .init( red: 0.5 ) )

        // A black pixel is all shadows: its red rises by the full shift.
        var dark = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: [ 0, 0, 0 ], isNormalized: true )

        try Processors.ColorBalance( ranges: ranges ).process( buffer: &dark )

        #expect( abs( dark.pixels[ 0 ] - 0.5 ) < self.tolerance )
        #expect( abs( dark.pixels[ 1 ] - 0.0 ) < self.tolerance )
        #expect( abs( dark.pixels[ 2 ] - 0.0 ) < self.tolerance )

        // A white pixel carries no shadow weight, so it is untouched.
        var bright = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: [ 1, 1, 1 ], isNormalized: true )

        try Processors.ColorBalance( ranges: ranges ).process( buffer: &bright )

        #expect( zip( bright.pixels, [ 1.0, 1.0, 1.0 ] ).allSatisfy { abs( $0 - $1 ) < self.tolerance }, "got \( bright.pixels )" )
    }

    @Test
    func highlightsShiftMovesBrightPixelsAndSparesDarkOnes() async throws
    {
        let ranges = self.ranges( highlights: .init( red: -0.5 ) )

        // A white pixel is all highlights: its red falls by the full shift.
        var bright = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: [ 1, 1, 1 ], isNormalized: true )

        try Processors.ColorBalance( ranges: ranges ).process( buffer: &bright )

        #expect( abs( bright.pixels[ 0 ] - 0.5 ) < self.tolerance )
        #expect( abs( bright.pixels[ 1 ] - 1.0 ) < self.tolerance )
        #expect( abs( bright.pixels[ 2 ] - 1.0 ) < self.tolerance )

        // A black pixel carries no highlight weight, so it is untouched.
        var dark = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: [ 0, 0, 0 ], isNormalized: true )

        try Processors.ColorBalance( ranges: ranges ).process( buffer: &dark )

        #expect( zip( dark.pixels, [ 0.0, 0.0, 0.0 ] ).allSatisfy { abs( $0 - $1 ) < self.tolerance }, "got \( dark.pixels )" )
    }

    @Test
    func midtonesShiftMovesMidPixelsWhileShadowsAndHighlightsDoNot() async throws
    {
        // Mid-gray carries only midtone weight, so the shadow and highlight red
        // shifts must not touch it, while the midtone green shift fully applies.
        let ranges = self.ranges( shadows: .init( red: 0.5 ), midtones: .init( green: 0.3 ), highlights: .init( red: 0.5 ) )
        var mid    = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: [ 0.5, 0.5, 0.5 ], isNormalized: true )

        try Processors.ColorBalance( ranges: ranges ).process( buffer: &mid )

        #expect( abs( mid.pixels[ 0 ] - 0.5 ) < self.tolerance )
        #expect( abs( mid.pixels[ 1 ] - 0.8 ) < self.tolerance )
        #expect( abs( mid.pixels[ 2 ] - 0.5 ) < self.tolerance )
    }

    @Test
    func nonPivotLumaBlendsShadowsAndMidtonesCubically() async throws
    {
        // A dark gray at luma 0.125 sits between the shadow and midtone ranges.
        // The cubic smoothstep gives wShadow = 1 − 0.25²·(3 − 0.5) = 0.84375 and
        // wMidtone = 0.15625 — a linear ramp would give 0.75 / 0.25 — so this pins
        // the curve's shape, which the black/mid-gray/white pivot tests cannot.
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: [ 0.125, 0.125, 0.125 ], isNormalized: true )

        try Processors.ColorBalance( ranges: self.ranges( shadows: .init( red: 1.0 ), midtones: .init( green: 1.0 ) ) ).process( buffer: &buffer )

        // out_r = 0.125 + 1.0·0.84375, out_g = 0.125 + 1.0·0.15625, out_b unchanged.
        #expect( abs( buffer.pixels[ 0 ] - 0.96875 ) < self.tolerance )
        #expect( abs( buffer.pixels[ 1 ] - 0.28125 ) < self.tolerance )
        #expect( abs( buffer.pixels[ 2 ] - 0.125   ) < self.tolerance )
    }

    @Test
    func nonPivotLumaBlendsMidtonesAndHighlightsCubically() async throws
    {
        // A light gray at luma 0.875 sits between the midtone and highlight
        // ranges: wHighlight = 0.75²·(3 − 1.5) = 0.84375, wMidtone = 0.15625.
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: [ 0.875, 0.875, 0.875 ], isNormalized: true )

        try Processors.ColorBalance( ranges: self.ranges( midtones: .init( blue: 0.1 ), highlights: .init( red: 0.1 ) ) ).process( buffer: &buffer )

        #expect( abs( buffer.pixels[ 0 ] - 0.959375 ) < self.tolerance )
        #expect( abs( buffer.pixels[ 1 ] - 0.875    ) < self.tolerance )
        #expect( abs( buffer.pixels[ 2 ] - 0.890625 ) < self.tolerance )
    }

    @Test
    func clipsToUnitRange() async throws
    {
        // A large positive highlight shift saturates white; a large negative
        // shadow shift bottoms out black.
        let ranges = self.ranges( shadows: .init( blue: -1 ), highlights: .init( red: 1 ) )

        var white = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: [ 1, 1, 1 ], isNormalized: true )

        try Processors.ColorBalance( ranges: ranges ).process( buffer: &white )

        #expect( abs( white.pixels[ 0 ] - 1.0 ) < self.tolerance )

        var black = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: [ 0, 0, 0 ], isNormalized: true )

        try Processors.ColorBalance( ranges: ranges ).process( buffer: &black )

        #expect( abs( black.pixels[ 2 ] - 0.0 ) < self.tolerance )
    }

    @Test
    func appliesPerPixel() async throws
    {
        // A dark and a bright pixel, with a shadows-only shift: only the dark one
        // moves.
        var buffer = try PixelBuffer( width: 2, height: 1, channels: 3, pixels: [ 0, 0, 0, 1, 1, 1 ], isNormalized: true )

        try Processors.ColorBalance( ranges: self.ranges( shadows: .init( red: 0.5 ) ) ).process( buffer: &buffer )

        #expect( abs( buffer.pixels[ 0 ] - 0.5 ) < self.tolerance )
        #expect( abs( buffer.pixels[ 3 ] - 1.0 ) < self.tolerance )
    }

    /// The exact scalar formula, computed independently of the production code, for
    /// the large-buffer parity check below.
    private func referenceColorBalance( _ input: [ Double ], ranges: Processors.ColorBalance.Ranges ) -> [ Double ]
    {
        func smoothstep( _ edge0: Double, _ edge1: Double, _ x: Double ) -> Double
        {
            let t = min( 1.0, max( 0.0, ( x - edge0 ) / ( edge1 - edge0 ) ) )

            return t * t * ( 3.0 - 2.0 * t )
        }

        return Swift.stride( from: 0, to: input.count, by: 3 ).flatMap
        {
            base -> [ Double ] in

            let r               = input[ base + 0 ]
            let g               = input[ base + 1 ]
            let b               = input[ base + 2 ]
            let luma            = 0.2126 * r + 0.7152 * g + 0.0722 * b
            let shadowWeight    = 1.0 - smoothstep( 0.0, 0.5, luma )
            let highlightWeight = smoothstep( 0.5, 1.0, luma )
            let midtoneWeight   = 1.0 - shadowWeight - highlightWeight

            return
                [
                    ( r, ranges.shadows.red,   ranges.midtones.red,   ranges.highlights.red   ),
                    ( g, ranges.shadows.green, ranges.midtones.green, ranges.highlights.green ),
                    ( b, ranges.shadows.blue,  ranges.midtones.blue,  ranges.highlights.blue  ),
                ]
                .map { channel, shadow, midtone, highlight in max( 0.0, min( 1.0, channel + shadow * shadowWeight + midtone * midtoneWeight + highlight * highlightWeight ) ) }
        }
    }

    @Test
    func largeBufferMatchesScalarReferenceWithinTolerance() async throws
    {
        // A many-pixel buffer spanning the full luma range (so every tonal weight is
        // exercised, including the smoothstep transitions and the [0, 1] clip),
        // checked against an independent scalar implementation. This drives the
        // whole-buffer vectorized path the 1-pixel pivot tests never reach.
        let count  = 4_096
        let input  = ( 0 ..< count * 3 ).map { Double( ( $0 * 53 ) % 100 ) / 99.0 }
        var buffer = try PixelBuffer( width: count, height: 1, channels: 3, pixels: input, isNormalized: true )
        let ranges = self.ranges( shadows: .init( red: 0.3, green: -0.1, blue: 0.05 ), midtones: .init( red: -0.05, green: 0.2, blue: 0.1 ), highlights: .init( red: 0.1, green: -0.15, blue: -0.2 ) )

        try Processors.ColorBalance( ranges: ranges ).process( buffer: &buffer )

        let expected = self.referenceColorBalance( input, ranges: ranges )

        #expect( zip( buffer.pixels, expected ).allSatisfy { abs( $0 - $1 ) < self.tolerance } )
    }

    @Test
    func remainsNormalized() async throws
    {
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: [ 0.2, 0.5, 0.9 ], isNormalized: true )

        try Processors.ColorBalance( ranges: self.ranges( midtones: .init( blue: 0.2 ) ) ).process( buffer: &buffer )

        #expect( buffer.isNormalized )
    }

    @Test
    func nonThreeChannelThrows() async throws
    {
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 1, pixels: [ 0.5 ], isNormalized: true )

        #expect( throws: PixelBufferError.self )
        {
            try Processors.ColorBalance( ranges: self.ranges( midtones: .init( red: 0.2 ) ) ).process( buffer: &buffer )
        }
    }

    @Test
    func notNormalizedThrows() async throws
    {
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: [ 0.2, 0.5, 0.9 ], isNormalized: false )

        #expect( throws: PixelBufferError.self )
        {
            try Processors.ColorBalance( ranges: self.ranges( midtones: .init( red: 0.2 ) ) ).process( buffer: &buffer )
        }
    }

    @Test
    func name() async throws
    {
        #expect( Processors.ColorBalance( ranges: self.ranges( midtones: .init( red: 0.2 ) ) ).name.isEmpty == false )
    }

    @Test
    func identityHelpers() async throws
    {
        #expect( Processors.ColorBalance.Shift.identity.isIdentity )
        #expect( Processors.ColorBalance.Shift( red: 0.1 ).isIdentity == false )
        #expect( Processors.ColorBalance.Ranges.identity.isIdentity )
        #expect( self.ranges( highlights: .init( blue: 0.1 ) ).isIdentity == false )
    }
}
