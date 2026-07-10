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

struct Test_Processors_Curves
{
    private func sample() throws -> PixelBuffer
    {
        try PixelBuffer( width: 3, height: 1, channels: 1, pixels: [ 0.0, 0.5, 1.0 ], isNormalized: true )
    }

    private func expect( _ buffer: PixelBuffer, equals expected: [ Double ], tolerance: Double = 1e-9 )
    {
        #expect( buffer.pixels.count == expected.count )
        #expect( zip( buffer.pixels, expected ).allSatisfy { abs( $0 - $1 ) < tolerance }, "got \( buffer.pixels ), expected \( expected )" )
    }

    @Test
    func identityValueIsLinear() async throws
    {
        let curve = Processors.Curves.Curve.identity

        #expect( abs( curve.value( at: 0.0 ) - 0.0 ) < 1e-12 )
        #expect( abs( curve.value( at: 0.3 ) - 0.3 ) < 1e-12 )
        #expect( abs( curve.value( at: 1.0 ) - 1.0 ) < 1e-12 )
    }

    @Test
    func valuePassesThroughControlPoints() async throws
    {
        let curve = Processors.Curves.Curve( points:
            [
                .init( x: 0.0, y: 0.0 ),
                .init( x: 0.5, y: 0.8 ),
                .init( x: 1.0, y: 1.0 ),
            ]
        )

        #expect( abs( curve.value( at: 0.0 ) - 0.0 ) < 1e-9 )
        #expect( abs( curve.value( at: 0.5 ) - 0.8 ) < 1e-9 )
        #expect( abs( curve.value( at: 1.0 ) - 1.0 ) < 1e-9 )
    }

    @Test
    func valueIsMonotonicForAMonotonicCurve() async throws
    {
        // A steep midtone lift: monotone cubic must not introduce a dip.
        let curve = Processors.Curves.Curve( points:
            [
                .init( x: 0.0, y: 0.0 ),
                .init( x: 0.5, y: 0.9 ),
                .init( x: 1.0, y: 1.0 ),
            ]
        )

        var previous = -1.0

        for step in 0 ... 200
        {
            let value = curve.value( at: Double( step ) / 200.0 )

            #expect( value >= previous - 1e-12, "curve dipped at \( step ): \( value ) < \( previous )" )

            previous = value
        }
    }

    @Test
    func valueClampsBeyondEndpoints() async throws
    {
        let curve = Processors.Curves.Curve( points:
            [
                .init( x: 0.2, y: 0.1 ),
                .init( x: 0.8, y: 0.9 ),
            ]
        )

        #expect( abs( curve.value( at: 0.0 ) - 0.1 ) < 1e-12 )
        #expect( abs( curve.value( at: 1.0 ) - 0.9 ) < 1e-12 )
    }

    @Test
    func processIdentityIsNoOp() async throws
    {
        var buffer = try self.sample()

        try Processors.Curves( channels: .uniform( .identity ) ).process( buffer: &buffer )

        self.expect( buffer, equals: [ 0.0, 0.5, 1.0 ] )
    }

    @Test
    func processAppliesCurveAtControlPoints() async throws
    {
        var buffer = try self.sample()

        let curve = Processors.Curves.Curve( points:
            [
                .init( x: 0.0, y: 0.0 ),
                .init( x: 0.5, y: 0.9 ),
                .init( x: 1.0, y: 1.0 ),
            ]
        )

        try Processors.Curves( channels: .uniform( curve ) ).process( buffer: &buffer )

        // The sample values sit on control points, so they map exactly (the LUT
        // node for 0.0 / 0.5 / 1.0 lands on a control point).
        self.expect( buffer, equals: [ 0.0, 0.9, 1.0 ], tolerance: 1e-9 )
    }

    @Test
    func perChannelAppliesIndependently() async throws
    {
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: [ 0.5, 0.5, 0.5 ], isNormalized: true )

        let red   = Processors.Curves.Curve( points: [ .init( x: 0.0, y: 0.0 ), .init( x: 0.5, y: 0.9 ), .init( x: 1.0, y: 1.0 ) ] )
        let green = Processors.Curves.Curve.identity
        let blue  = Processors.Curves.Curve( points: [ .init( x: 0.0, y: 0.0 ), .init( x: 0.5, y: 0.2 ), .init( x: 1.0, y: 1.0 ) ] )

        try Processors.Curves( channels: .perChannel( red: red, green: green, blue: blue ) ).process( buffer: &buffer )

        self.expect( buffer, equals: [ 0.9, 0.5, 0.2 ], tolerance: 1e-9 )
    }

    @Test
    func matchesTheScalarReferenceAcrossTheRange() async throws
    {
        let curve = Processors.Curves.Curve( points:
            [
                .init( x: 0.0, y: 0.05 ),
                .init( x: 0.3, y: 0.60 ),
                .init( x: 0.7, y: 0.65 ),
                .init( x: 1.0, y: 0.98 ),
            ]
        )
        let lut    = curve.lookupTable()
        let input  = stride( from: 0.0, through: 1.0, by: 1.0 / 97.0 ).map { $0 } // off-node values
        var buffer = try PixelBuffer( width: input.count, height: 1, channels: 1, pixels: input, isNormalized: true )

        try Processors.Curves( channels: .uniform( curve ) ).process( buffer: &buffer )

        let expected = input.map { Processors.Curves.sample( $0, lut: lut ) }

        #expect( zip( buffer.pixels, expected ).allSatisfy { abs( $0 - $1 ) < 1e-12 } )
    }

    @Test
    func matchesTheScalarReferencePerChannel() async throws
    {
        let red    = Processors.Curves.Curve( points: [ .init( x: 0.0, y: 0.0 ), .init( x: 0.4, y: 0.7 ), .init( x: 1.0, y: 1.0 ) ] )
        let green  = Processors.Curves.Curve( points: [ .init( x: 0.0, y: 0.1 ), .init( x: 0.6, y: 0.5 ), .init( x: 1.0, y: 0.9 ) ] )
        let blue   = Processors.Curves.Curve( points: [ .init( x: 0.0, y: 0.0 ), .init( x: 0.5, y: 0.2 ), .init( x: 1.0, y: 1.0 ) ] )
        let mono   = stride( from: 0.0, through: 1.0, by: 1.0 / 40.0 ).map { $0 }
        let input  = mono.flatMap { [ $0, $0, $0 ] }
        var buffer = try PixelBuffer( width: mono.count, height: 1, channels: 3, pixels: input, isNormalized: true )

        try Processors.Curves( channels: .perChannel( red: red, green: green, blue: blue ) ).process( buffer: &buffer )

        let redLUT   = red.lookupTable()
        let greenLUT = green.lookupTable()
        let blueLUT  = blue.lookupTable()
        let expected = mono.flatMap { [ Processors.Curves.sample( $0, lut: redLUT ), Processors.Curves.sample( $0, lut: greenLUT ), Processors.Curves.sample( $0, lut: blueLUT ) ] }

        #expect( zip( buffer.pixels, expected ).allSatisfy { abs( $0 - $1 ) < 1e-12 } )
    }

    @Test
    func perChannelRequiresThreeChannels() async throws
    {
        var buffer = try self.sample()

        #expect( throws: RuntimeError.self )
        {
            try Processors.Curves( channels: .perChannel( red: .identity, green: .identity, blue: .identity ) ).process( buffer: &buffer )
        }
    }

    @Test
    func tooFewPointsThrows() async throws
    {
        var buffer = try self.sample()

        #expect( throws: RuntimeError.self )
        {
            try Processors.Curves( channels: .uniform( Processors.Curves.Curve( points: [ .init( x: 0.0, y: 0.0 ) ] ) ) ).process( buffer: &buffer )
        }
    }

    @Test
    func nonIncreasingXThrows() async throws
    {
        var buffer = try self.sample()

        #expect( throws: RuntimeError.self )
        {
            try Processors.Curves( channels: .uniform( Processors.Curves.Curve( points: [ .init( x: 0.5, y: 0.0 ), .init( x: 0.5, y: 1.0 ) ] ) ) ).process( buffer: &buffer )
        }
    }

    @Test
    func outOfRangePointThrows() async throws
    {
        var buffer = try self.sample()

        #expect( throws: RuntimeError.self )
        {
            try Processors.Curves( channels: .uniform( Processors.Curves.Curve( points: [ .init( x: 0.0, y: 0.0 ), .init( x: 1.0, y: 1.5 ) ] ) ) ).process( buffer: &buffer )
        }
    }

    @Test
    func notNormalizedThrows() async throws
    {
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 1, pixels: [ 0.5 ], isNormalized: false )

        #expect( throws: RuntimeError.self )
        {
            try Processors.Curves( channels: .uniform( .identity ) ).process( buffer: &buffer )
        }
    }

    @Test
    func identityCurveIsIdentity() async throws
    {
        #expect( Processors.Curves.Curve.identity.isIdentity )
        #expect( Processors.Curves.Curve( points: [ .init( x: 0.0, y: 0.0 ), .init( x: 0.5, y: 0.8 ), .init( x: 1.0, y: 1.0 ) ] ).isIdentity == false )
    }

    @Test
    func name() async throws
    {
        #expect( Processors.Curves( channels: .uniform( .identity ) ).name.isEmpty == false )
        #expect( Processors.Curves( channels: .perChannel( red: .identity, green: .identity, blue: .identity ) ).name.isEmpty == false )
    }
}
