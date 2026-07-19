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

struct Test_Processors_Saturation
{
    /// The Rec. 709 luma of an RGB triple, matching `Histogram`.
    private func luma( _ r: Double, _ g: Double, _ b: Double ) -> Double
    {
        0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    @Test
    func zeroSaturationProducesGray() async throws
    {
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: [ 0.2, 0.5, 0.9 ], isNormalized: true )

        try Processors.Saturation( saturation: 0.0 ).process( buffer: &buffer )

        let l = self.luma( 0.2, 0.5, 0.9 )

        // All channels collapse to the pixel's luma: a neutral gray.
        #expect( abs( buffer.pixels[ 0 ] - l ) < 1e-12 )
        #expect( abs( buffer.pixels[ 1 ] - l ) < 1e-12 )
        #expect( abs( buffer.pixels[ 2 ] - l ) < 1e-12 )
    }

    @Test
    func unitSaturationIsIdentity() async throws
    {
        let input  = [ 0.2, 0.5, 0.9 ]
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: input, isNormalized: true )

        try Processors.Saturation( saturation: 1.0 ).process( buffer: &buffer )

        #expect( zip( buffer.pixels, input ).allSatisfy { abs( $0 - $1 ) < 1e-12 } )
    }

    @Test
    func increasedSaturationSpreadsAroundLumaAndClips() async throws
    {
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: [ 0.2, 0.5, 0.9 ], isNormalized: true )

        try Processors.Saturation( saturation: 2.0 ).process( buffer: &buffer )

        let l        = self.luma( 0.2, 0.5, 0.9 )
        let expected = [ 0.2, 0.5, 0.9 ].map { max( 0.0, min( 1.0, l + ( $0 - l ) * 2.0 ) ) }

        #expect( zip( buffer.pixels, expected ).allSatisfy { abs( $0 - $1 ) < 1e-12 }, "got \( buffer.pixels ), expected \( expected )" )
    }

    @Test
    func fractionalSaturationMovesPartwayTowardGray() async throws
    {
        // At s = 0.5 the lerp toward luma reduces to the midpoint between each
        // channel and the luma — an independent form of the production
        // `l + (c − l)·s` — pinning partial desaturation, which only the s = 0 and
        // s = 1 endpoints otherwise cover.
        let input  = [ 0.2, 0.5, 0.9 ]
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: input, isNormalized: true )

        try Processors.Saturation( saturation: 0.5 ).process( buffer: &buffer )

        let l = self.luma( 0.2, 0.5, 0.9 )

        #expect( abs( buffer.pixels[ 0 ] - ( input[ 0 ] + l ) / 2 ) < 1e-12 )
        #expect( abs( buffer.pixels[ 1 ] - ( input[ 1 ] + l ) / 2 ) < 1e-12 )
        #expect( abs( buffer.pixels[ 2 ] - ( input[ 2 ] + l ) / 2 ) < 1e-12 )
    }

    @Test
    func boostedSaturationStaysInRangeForLowContrast() async throws
    {
        // A low-contrast pixel boosted at s = 1.5 spreads around its luma
        // (0.48596) without clipping — an interior boost the existing s = 2 test,
        // which clips two of three channels, never reaches. Values hand-computed.
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: [ 0.4, 0.5, 0.6 ], isNormalized: true )

        try Processors.Saturation( saturation: 1.5 ).process( buffer: &buffer )

        #expect( abs( buffer.pixels[ 0 ] - 0.35702 ) < 1e-9 )
        #expect( abs( buffer.pixels[ 1 ] - 0.50702 ) < 1e-9 )
        #expect( abs( buffer.pixels[ 2 ] - 0.65702 ) < 1e-9 )
    }

    @Test
    func appliesPerPixel() async throws
    {
        // Two distinct pixels: each desaturates to its own luma at s = 0.
        var buffer = try PixelBuffer( width: 2, height: 1, channels: 3, pixels: [ 0.2, 0.5, 0.9, 0.8, 0.1, 0.4 ], isNormalized: true )

        try Processors.Saturation( saturation: 0.0 ).process( buffer: &buffer )

        let l0 = self.luma( 0.2, 0.5, 0.9 )
        let l1 = self.luma( 0.8, 0.1, 0.4 )

        #expect( abs( buffer.pixels[ 0 ] - l0 ) < 1e-12 )
        #expect( abs( buffer.pixels[ 3 ] - l1 ) < 1e-12 )
    }

    /// The exact scalar formula, computed independently of the production code, for
    /// the large-buffer parity check below.
    private func referenceSaturation( _ input: [ Double ], factor: Double ) -> [ Double ]
    {
        Swift.stride( from: 0, to: input.count, by: 3 ).flatMap
        {
            base -> [ Double ] in

            let r = input[ base + 0 ]
            let g = input[ base + 1 ]
            let b = input[ base + 2 ]
            let l = 0.2126 * r + 0.7152 * g + 0.0722 * b

            return [ r, g, b ].map { max( 0.0, min( 1.0, l + ( $0 - l ) * factor ) ) }
        }
    }

    @Test
    func largeBufferMatchesScalarReferenceWithinTolerance() async throws
    {
        // A many-pixel buffer with values that both stay in range and clip, checked
        // against an independent scalar implementation of `luma + (c − luma)·factor`
        // clipped to [0, 1]. This exercises the whole-buffer vectorized path (the
        // other tests use 1–2 pixels) and pins parity to within floating-point noise.
        let count  = 4_096
        let input  = ( 0 ..< count * 3 ).map { Double( ( $0 * 37 ) % 100 ) / 99.0 }
        var buffer = try PixelBuffer( width: count, height: 1, channels: 3, pixels: input, isNormalized: true )

        try Processors.Saturation( saturation: 1.8 ).process( buffer: &buffer )

        let expected = self.referenceSaturation( input, factor: 1.8 )

        #expect( zip( buffer.pixels, expected ).allSatisfy { abs( $0 - $1 ) < 1e-12 } )
    }

    @Test
    func remainsNormalized() async throws
    {
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: [ 0.2, 0.5, 0.9 ], isNormalized: true )

        try Processors.Saturation( saturation: 1.5 ).process( buffer: &buffer )

        #expect( buffer.isNormalized )
    }

    @Test
    func nonThreeChannelThrows() async throws
    {
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 1, pixels: [ 0.5 ], isNormalized: true )

        #expect( throws: PixelBufferError.self )
        {
            try Processors.Saturation( saturation: 0.5 ).process( buffer: &buffer )
        }
    }

    @Test
    func notNormalizedThrows() async throws
    {
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: [ 0.2, 0.5, 0.9 ], isNormalized: false )

        #expect( throws: PixelBufferError.self )
        {
            try Processors.Saturation( saturation: 0.5 ).process( buffer: &buffer )
        }
    }

    @Test
    func name() async throws
    {
        #expect( Processors.Saturation( saturation: 1.0 ).name.isEmpty == false )
    }
}
