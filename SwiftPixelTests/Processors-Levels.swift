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

struct Test_Processors_Levels
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
    func identityLeavesBufferUnchanged() async throws
    {
        var buffer = try self.sample()

        try Processors.Levels( channels: .uniform( .identity ) ).process( buffer: &buffer )

        self.expect( buffer, equals: [ 0.0, 0.25, 0.5, 0.75, 1.0 ] )
    }

    @Test
    func inputBlackAndWhiteRemapLinearlyAndClip() async throws
    {
        var buffer = try self.sample()

        // Window [0.25, 0.75]: values at/below 0.25 -> 0, at/above 0.75 -> 1, and
        // 0.5 sits at the centre -> 0.5.
        let parameters = Processors.Levels.Parameters( inputBlack: 0.25, inputWhite: 0.75 )

        try Processors.Levels( channels: .uniform( parameters ) ).process( buffer: &buffer )

        self.expect( buffer, equals: [ 0.0, 0.0, 0.5, 1.0, 1.0 ] )
    }

    @Test
    func midtoneGammaBrightens() async throws
    {
        var buffer = try self.sample()

        // gamma = 2 raises each sample to 1/2, i.e. its square root.
        try Processors.Levels( channels: .uniform( Processors.Levels.Parameters( gamma: 2.0 ) ) ).process( buffer: &buffer )

        self.expect( buffer, equals: [ 0.0, 0.25, 0.5, 0.75, 1.0 ].map { Foundation.pow( $0, 1.0 / 2.0 ) } )
    }

    @Test
    func outputRangeCompresses() async throws
    {
        var buffer = try self.sample()

        // Output mapped into [0.2, 0.8]: out = 0.2 + v * 0.6.
        let parameters = Processors.Levels.Parameters( outputBlack: 0.2, outputWhite: 0.8 )

        try Processors.Levels( channels: .uniform( parameters ) ).process( buffer: &buffer )

        self.expect( buffer, equals: [ 0.2, 0.35, 0.5, 0.65, 0.8 ] )
    }

    @Test
    func perChannelAppliesIndependently() async throws
    {
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: [ 0.25, 0.5, 0.75 ], isNormalized: true )

        let red   = Processors.Levels.Parameters( inputBlack: 0.0, inputWhite: 0.5 )    // 0.25 / 0.5 = 0.5
        let green = Processors.Levels.Parameters( outputBlack: 0.2, outputWhite: 0.8 )  // 0.2 + 0.5 * 0.6 = 0.5
        let blue  = Processors.Levels.Parameters( gamma: 2.0 )                          // sqrt( 0.75 )

        try Processors.Levels( channels: .perChannel( red: red, green: green, blue: blue ) ).process( buffer: &buffer )

        self.expect( buffer, equals: [ 0.5, 0.5, Foundation.pow( 0.75, 0.5 ) ] )
    }

    @Test
    func matchesTheScalarReferenceAcrossTheRange() async throws
    {
        let parameters = Processors.Levels.Parameters( inputBlack: 0.1, inputWhite: 0.85, gamma: 1.8, outputBlack: 0.05, outputWhite: 0.92 )
        let input      = stride( from: 0.0, through: 1.0, by: 1.0 / 64.0 ).map { $0 }
        var buffer     = try PixelBuffer( width: input.count, height: 1, channels: 1, pixels: input, isNormalized: true )

        try Processors.Levels( channels: .uniform( parameters ) ).process( buffer: &buffer )

        let expected = input.map { parameters.map( $0 ) }

        #expect( zip( buffer.pixels, expected ).allSatisfy { abs( $0 - $1 ) < 1e-12 } )
    }

    @Test
    func matchesTheScalarReferencePerChannel() async throws
    {
        let red    = Processors.Levels.Parameters( inputBlack: 0.05, inputWhite: 0.9, gamma: 2.2 )
        let green  = Processors.Levels.Parameters( gamma: 0.6, outputBlack: 0.1, outputWhite: 0.95 )
        let blue   = Processors.Levels.Parameters( inputBlack: 0.2, inputWhite: 0.8, gamma: 1.4, outputBlack: 0.0, outputWhite: 0.8 )
        let mono   = stride( from: 0.0, through: 1.0, by: 1.0 / 32.0 ).map { $0 }
        let input  = mono.flatMap { [ $0, $0, $0 ] }
        var buffer = try PixelBuffer( width: mono.count, height: 1, channels: 3, pixels: input, isNormalized: true )

        try Processors.Levels( channels: .perChannel( red: red, green: green, blue: blue ) ).process( buffer: &buffer )

        let expected = mono.flatMap { [ red.map( $0 ), green.map( $0 ), blue.map( $0 ) ] }

        #expect( zip( buffer.pixels, expected ).allSatisfy { abs( $0 - $1 ) < 1e-12 } )
    }

    @Test
    func perChannelRequiresThreeChannels() async throws
    {
        var buffer = try self.sample()

        #expect( throws: PixelBufferError.self )
        {
            try Processors.Levels( channels: .perChannel( red: .identity, green: .identity, blue: .identity ) ).process( buffer: &buffer )
        }
    }

    @Test
    func nonPositiveGammaThrows() async throws
    {
        var buffer = try self.sample()

        #expect( throws: Processors.Levels.ValidationError.self )
        {
            try Processors.Levels( channels: .uniform( Processors.Levels.Parameters( gamma: 0.0 ) ) ).process( buffer: &buffer )
        }
    }

    @Test
    func inputWhiteNotAboveInputBlackThrows() async throws
    {
        var buffer = try self.sample()

        #expect( throws: Processors.Levels.ValidationError.self )
        {
            try Processors.Levels( channels: .uniform( Processors.Levels.Parameters( inputBlack: 0.6, inputWhite: 0.6 ) ) ).process( buffer: &buffer )
        }
    }

    @Test
    func outputWhiteBelowOutputBlackThrows() async throws
    {
        var buffer = try self.sample()

        // An inverted output range (outputBlack > outputWhite) contradicts the
        // darkest/brightest contract, so it is rejected — mirroring the enforced
        // input range.
        #expect( throws: Processors.Levels.ValidationError.self )
        {
            try Processors.Levels( channels: .uniform( Processors.Levels.Parameters( outputBlack: 0.8, outputWhite: 0.2 ) ) ).process( buffer: &buffer )
        }
    }

    @Test
    func equalOutputRangeMapsToConstant() async throws
    {
        var buffer = try self.sample()

        // outputBlack == outputWhite is a valid constant output (no divide-by-zero,
        // unlike the input window), so it is accepted rather than rejected.
        try Processors.Levels( channels: .uniform( Processors.Levels.Parameters( outputBlack: 0.5, outputWhite: 0.5 ) ) ).process( buffer: &buffer )

        self.expect( buffer, equals: [ 0.5, 0.5, 0.5, 0.5, 0.5 ] )
    }

    @Test
    func remainsNormalized() async throws
    {
        var buffer = try self.sample()

        try Processors.Levels( channels: .uniform( Processors.Levels.Parameters( inputBlack: 0.1, inputWhite: 0.9, gamma: 1.5, outputBlack: 0.05, outputWhite: 0.95 ) ) ).process( buffer: &buffer )

        #expect( buffer.isNormalized )
    }

    @Test
    func notNormalizedThrows() async throws
    {
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 1, pixels: [ 0.5 ], isNormalized: false )

        #expect( throws: PixelBufferError.self )
        {
            try Processors.Levels( channels: .uniform( .identity ) ).process( buffer: &buffer )
        }
    }

    @Test
    func identityParametersAreIdentity() async throws
    {
        #expect( Processors.Levels.Parameters.identity.isIdentity )
        #expect( Processors.Levels.Parameters( gamma: 2.0 ).isIdentity == false )
    }

    @Test
    func name() async throws
    {
        #expect( Processors.Levels( channels: .uniform( .identity ) ).name.isEmpty == false )
        #expect( Processors.Levels( channels: .perChannel( red: .identity, green: .identity, blue: .identity ) ).name.isEmpty == false )
    }
}
