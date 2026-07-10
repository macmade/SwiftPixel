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

        try Processors.Stretch( algorithm: .screenTransfer( params ) ).process( buffer: &buffer )

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

        #expect( throws: RuntimeError.self )
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

        try Processors.Stretch( algorithm: .screenTransfer( .uniform( channel ) ) ).process( buffer: &buffer )

        #expect( zip( buffer.pixels, input ).allSatisfy { abs( $0 - channel.map( $1 ) ) < 1e-12 } )
    }

    @Test
    func perChannelStretchRequiresThreeChannels() async throws
    {
        var buffer = try PixelBuffer( width: 2, height: 1, channels: 1, pixels: [ 0.4, 0.6 ], isNormalized: true )
        let params = STF.perChannel( red: .identity, green: .identity, blue: .identity )

        #expect( throws: RuntimeError.self )
        {
            try Processors.Stretch( algorithm: .screenTransfer( params ) ).process( buffer: &buffer )
        }
    }
}
