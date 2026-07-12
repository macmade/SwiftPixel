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

struct Test_Processors_STFParameters
{
    private typealias STF     = Processors.Stretch.STFParameters
    private typealias Channel = Processors.Stretch.STFParameters.Channel

    @Test
    func identityChannelLeavesSamplesUnchanged() async throws
    {
        let channel = Channel.identity
        let inputs  = [ 0.0, 0.1, 0.25, 0.5, 0.75, 1.0 ]

        #expect( channel.isIdentity )
        #expect( inputs.allSatisfy { abs( channel.map( $0 ) - $0 ) < 1e-12 } )
    }

    @Test
    func mapClipsShadowsAndHighlights() async throws
    {
        let channel = Channel( shadows: 0.2, midtones: 0.5, highlights: 0.8, low: 0, high: 1 )

        #expect( channel.map( 0.1 ) == 0.0 )
        #expect( channel.map( 0.9 ) == 1.0 )
        #expect( abs( channel.map( 0.5 ) - 0.5 ) < 1e-12 )
    }

    @Test
    func computedFromStatsMapsMedianToTargetBackground() async throws
    {
        let median  = 0.1
        let mad     = 0.02
        let target  = 0.25
        let channel = Channel.computed( median: median, mad: mad, shadowClipFactor: 2.8, targetBackground: target )

        #expect( abs( channel.map( median ) - target ) < 1e-6 )
    }

    @Test
    func computedFromStatsClipsShadowsBelowTheMedian() async throws
    {
        let median  = 0.3
        let mad     = 0.05
        let channel = Channel.computed( median: median, mad: mad, shadowClipFactor: 2.8, targetBackground: 0.25 )

        #expect( abs( channel.shadows - ( median - 2.8 * mad ) ) < 1e-12 )
        #expect( channel.highlights == 1.0 )
        #expect( channel.low == 0.0 )
        #expect( channel.high == 1.0 )
    }

    @Test
    func computedFromStatsIsIdentityWithoutSpread() async throws
    {
        let channel = Channel.computed( median: 0.4, mad: 0.0, shadowClipFactor: 2.8, targetBackground: 0.25 )

        #expect( channel.isIdentity )
    }

    @Test
    func computedFromBufferBrightensAndStaysInRange() async throws
    {
        let pixels  = ( 0 ..< 400 ).map { Double( $0 ) / 4000.0 } // faint samples in [0, 0.1)
        var buffer  = try PixelBuffer( width: 400, height: 1, channels: 1, pixels: pixels, isNormalized: true )
        let median  = try #require( PixelUtilities.median( pixels ) )

        let params  = try STF.computed( from: buffer, shadowClipFactor: 2.8, targetBackground: 0.25 )

        try Processors.Stretch( parameters: params ).process( buffer: &buffer )

        #expect( buffer.pixels.allSatisfy { $0.isFinite && $0 >= 0.0 && $0 <= 1.0 } )

        let stretchedMedian = try #require( PixelUtilities.median( buffer.pixels ) )

        #expect( stretchedMedian > median ) // faint background lifted
    }

    @Test
    func computedFromBufferMapsMedianNearTargetBackground() async throws
    {
        let pixels = ( 0 ..< 400 ).map { Double( $0 ) / 4000.0 }
        let buffer = try PixelBuffer( width: 400, height: 1, channels: 1, pixels: pixels, isNormalized: true )
        let params = try STF.computed( from: buffer, shadowClipFactor: 2.8, targetBackground: 0.25 )

        guard case .uniform( let channel ) = params
        else
        {
            Issue.record( "Expected a uniform result for a single-channel buffer" )

            return
        }

        let median = try #require( PixelUtilities.median( pixels ) )

        #expect( abs( channel.map( median ) - 0.25 ) < 1e-6 )
    }

    @Test
    func computedFromThreeChannelBufferIsPerChannel() async throws
    {
        let red    = ( 0 ..< 100 ).map { _ in 0.05 }
        let green  = ( 0 ..< 100 ).map { _ in 0.10 }
        let blue   = ( 0 ..< 100 ).map { _ in 0.15 }
        let planes = zip( red, zip( green, blue ) ).flatMap { [ $0.0, $0.1.0, $0.1.1 ] }
        let buffer = try PixelBuffer( width: 100, height: 1, channels: 3, pixels: planes, isNormalized: true )

        let params = try STF.computed( from: buffer, shadowClipFactor: 2.8, targetBackground: 0.25 )

        guard case .perChannel = params
        else
        {
            Issue.record( "Expected per-channel parameters for a 3-channel buffer" )

            return
        }
    }

    @Test
    func computedRequiresANormalizedBuffer() async throws
    {
        let buffer = try PixelBuffer( width: 2, height: 1, channels: 1, pixels: [ 3.0, 9.0 ], isNormalized: false )

        #expect( throws: PixelBufferError.self )
        {
            _ = try STF.computed( from: buffer, shadowClipFactor: 2.8, targetBackground: 0.25 )
        }
    }

    @Test
    func computedNormalizingHandlesRawSamples() async throws
    {
        let buffer = try PixelBuffer( width: 4, height: 1, channels: 1, pixels: [ 10.0, 20.0, 30.0, 1000.0 ], isNormalized: false )

        let params = try STF.computed( normalizing: buffer, using: .minMax, shadowClipFactor: 2.8, targetBackground: 0.25 )

        #expect( params.isIdentity == false )
    }

    @Test
    func roundTripsExplicitParametersThroughTheStretch() async throws
    {
        let channel = Channel( shadows: 0.05, midtones: 0.3, highlights: 0.95, low: 0.0, high: 1.0 )
        let input   = [ 0.0, 0.2, 0.4, 0.6, 0.8, 1.0 ]
        var buffer  = try PixelBuffer( width: input.count, height: 1, channels: 1, pixels: input, isNormalized: true )

        try Processors.Stretch( parameters: .uniform( channel ) ).process( buffer: &buffer )

        #expect( zip( buffer.pixels, input ).allSatisfy { abs( $0 - channel.map( $1 ) ) < 1e-12 } )
    }

    @Test
    func perChannelStretchRequiresThreeChannels() async throws
    {
        var buffer = try PixelBuffer( width: 2, height: 1, channels: 1, pixels: [ 0.4, 0.6 ], isNormalized: true )
        let params = STF.perChannel( red: .identity, green: .identity, blue: .identity )

        #expect( throws: PixelBufferError.self )
        {
            try Processors.Stretch( parameters: params ).process( buffer: &buffer )
        }
    }

    @Test
    func computedFromMosaicDerivesEachChannelFromItsOwnSites() async throws
    {
        let width   = 4
        let height  = 4
        let pattern = Processors.Debayer.Pattern.rggb
        let pixels  = ( 0 ..< ( width * height ) ).map { Double( $0 ) / 16.0 }
        let buffer  = try PixelBuffer( width: width, height: height, channels: 1, pixels: pixels, isNormalized: true )

        let params = try STF.computed( fromMosaic: buffer, pattern: pattern, shadowClipFactor: 2.8, targetBackground: 0.25 )

        guard case .perChannel( let red, let green, let blue ) = params
        else
        {
            Issue.record( "Expected per-channel parameters from a mosaic" )

            return
        }

        // Each channel must reproduce the STF derived from that channel's own
        // deinterleaved sites — the median / MAD of its filter positions only.
        let sets = try Processors.Debayer.deinterleave( mosaic: pixels, width: width, height: height, pattern: pattern )

        #expect( red   == Self.channel( from: sets.red ) )
        #expect( green == Self.channel( from: sets.green ) )
        #expect( blue  == Self.channel( from: sets.blue ) )

        // Green is derived from a different (larger, brighter) sample set, so an
        // unlinked derivation must give it a different mapping than red.
        #expect( red != green )
    }

    @Test
    func computedFromMosaicRejectsNonNormalizedOrMultiChannel() async throws
    {
        let raw = try PixelBuffer( width: 2, height: 2, channels: 1, pixels: [ 0.1, 0.2, 0.3, 0.4 ], isNormalized: false )

        #expect( throws: PixelBufferError.self )
        {
            _ = try STF.computed( fromMosaic: raw, pattern: .rggb )
        }

        let rgb = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: [ 0.1, 0.2, 0.3 ], isNormalized: true )

        #expect( throws: PixelBufferError.self )
        {
            _ = try STF.computed( fromMosaic: rgb, pattern: .rggb )
        }
    }

    @Test
    func computedFromMosaicLeavesAFlatFrameAsIdentity() async throws
    {
        let buffer = try PixelBuffer( width: 4, height: 4, channels: 1, pixels: [ Double ]( repeating: 0.3, count: 16 ), isNormalized: true )
        let params = try STF.computed( fromMosaic: buffer, pattern: .rggb )

        #expect( params.isIdentity )
    }

    @Test
    func computedFromMosaicLeavesAColourWithNoSitesAsIdentity() async throws
    {
        // A single-row GRBG mosaic samples only green and red (G R G R …): blue has
        // no sites at all, so its channel must fall back to the identity while the
        // sampled channels still derive a real, non-identity mapping.
        let buffer = try PixelBuffer( width: 4, height: 1, channels: 1, pixels: [ 0.1, 0.5, 0.3, 0.9 ], isNormalized: true )
        let params = try STF.computed( fromMosaic: buffer, pattern: .grbg )

        guard case .perChannel( let red, let green, let blue ) = params
        else
        {
            Issue.record( "Expected per-channel parameters from a mosaic" )

            return
        }

        #expect( blue.isIdentity )
        #expect( red.isIdentity  == false )
        #expect( green.isIdentity == false )
    }

    /// The channel mapping derived from a sample set the same way the mosaic
    /// derivation does, so a test can assert exact per-channel reproduction.
    ///
    /// - Parameter samples: The channel's samples.
    /// - Returns: The derived channel, or the identity for an empty set.
    private static func channel( from samples: [ Double ] ) -> Channel
    {
        guard let median = PixelUtilities.median( samples ), let mad = PixelUtilities.medianAbsoluteDeviation( samples, around: median )
        else
        {
            return .identity
        }

        return Channel.computed( median: median, mad: mad, shadowClipFactor: 2.8, targetBackground: 0.25 )
    }
}
