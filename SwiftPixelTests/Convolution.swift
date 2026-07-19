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

/// Tests for ``Convolution`` and its zero-sum (high-pass) response.
struct Test_Convolution
{
    /// Builds a single-channel buffer of raw (non-normalized) samples.
    ///
    /// - Parameters:
    ///   - width:  The image width, in pixels.
    ///   - height: The image height, in pixels.
    ///   - pixels: The row-major samples.
    /// - Returns: The single-channel pixel buffer.
    /// - Throws: An error if the geometry is inconsistent.
    private func buffer( width: Int, height: Int, pixels: [ Double ] ) throws -> PixelBuffer
    {
        try PixelBuffer( width: width, height: height, channels: 1, pixels: pixels, isNormalized: false )
    }

    /// A flat region produces a ≈ 0 response everywhere — including the borders,
    /// thanks to edge extension — since the zero-sum kernel has no response to a
    /// constant.
    @Test
    func flatFieldYieldsZeroResponse() throws
    {
        let width  = 40
        let height = 30
        let image  = try self.buffer( width: width, height: height, pixels: [ Double ]( repeating: 200, count: width * height ) )

        let kernel   = GaussianKernel( sigma: 2 )
        let response = Convolution.zeroSumResponse( of: image, kernel: kernel )

        #expect( response.count == width * height )
        #expect( response.allSatisfy { abs( $0 ) < 1e-6 } )
    }

    /// Convolving a single spike with the zero-sum kernel reproduces that kernel,
    /// scaled by the spike's amplitude, centred on the spike.
    @Test
    func deltaReproducesTheZeroSumKernel() throws
    {
        let width      = 41
        let height     = 41
        let background = 100.0
        let amplitude  = 1000.0
        let cx         = 20
        let cy         = 20

        var pixels = [ Double ]( repeating: background, count: width * height )

        pixels[ ( cy * width ) + cx ] = background + amplitude

        let image    = try self.buffer( width: width, height: height, pixels: pixels )
        let kernel   = GaussianKernel( sigma: 2 )
        let response = Convolution.zeroSumResponse( of: image, kernel: kernel )
        let radius   = kernel.radius
        let size     = kernel.size

        ( -radius ... radius ).forEach
        {
            dy in

            ( -radius ... radius ).forEach
            {
                dx in

                let actual   = response[ ( ( cy + dy ) * width ) + ( cx + dx ) ]
                let expected = amplitude * kernel.zeroSumValues[ ( ( radius + dy ) * size ) + ( radius + dx ) ]

                #expect( abs( actual - expected ) < 1e-6 )
            }
        }
    }

    /// A Gaussian blob matched by the kernel produces a positive response that
    /// peaks at the blob's centre.
    @Test
    func gaussianBlobPeaksAtItsCenter() throws
    {
        let width      = 61
        let height     = 61
        let background = 100.0
        let peak       = 2000.0
        let sigma      = 2.0
        let cx         = 30
        let cy         = 30

        let pixels = ( 0 ..< ( width * height ) ).map
        {
            index -> Double in

            let dx       = Double( index % width ) - Double( cx )
            let dy       = Double( index / width ) - Double( cy )
            let exponent = ( ( dx * dx ) + ( dy * dy ) ) / ( 2 * sigma * sigma )

            return background + ( peak * exp( -exponent ) )
        }

        let image    = try self.buffer( width: width, height: height, pixels: pixels )
        let kernel   = GaussianKernel( sigma: sigma )
        let response = Convolution.zeroSumResponse( of: image, kernel: kernel )

        let centerIndex = ( cy * width ) + cx
        let centerValue = response[ centerIndex ]
        let peakIndex   = try #require( response.indices.max { response[ $0 ] < response[ $1 ] } )

        #expect( centerValue > 0 )
        #expect( peakIndex == centerIndex )
    }

    /// A multi-channel image returns an empty response rather than convolving a
    /// geometrically incoherent channel mix (CR-12).
    @Test
    func zeroSumResponseRejectsMultiChannelInput() throws
    {
        let image = try PixelBuffer( width: 2, height: 2, channels: 3, pixels: [ Double ]( repeating: 1, count: 12 ), isNormalized: false )

        #expect( Convolution.zeroSumResponse( of: image, kernel: GaussianKernel( sigma: 1 ) ).isEmpty )
    }

    /// Border samples come from extending the image with replicated edge pixels,
    /// and the central block is cropped back at exactly the padding offset. A 3×3
    /// box mean over a ramp has hand-computable edge and corner values, so a wrong
    /// vDSP valid-region offset would surface here (IMP-8).
    @Test
    func convolveExtendsBordersByReplication() throws
    {
        // A 3×3 ramp and a 3×3 box-mean kernel (radius 1).
        let values = [ 1.0, 2, 3, 4, 5, 6, 7, 8, 9 ]
        let kernel = [ Double ]( repeating: 1.0 / 9.0, count: 9 )

        let result = Convolution.convolve( values, width: 3, height: 3, kernel: kernel, radius: 1 )

        // Each output is the mean of the 3×3 window centred on it, with out-of-image
        // neighbours replicated from the nearest edge pixel — e.g. the top-left
        // window is { 1, 1, 2 / 1, 1, 2 / 4, 4, 5 } = 21/9, and the centre is the
        // full-image mean 45/9 = 5.
        let expected = [ 21.0, 27, 33, 39, 45, 51, 57, 63, 69 ].map { $0 / 9.0 }

        try #require( result.count == expected.count )

        result.indices.forEach
        {
            #expect( abs( result[ $0 ] - expected[ $0 ] ) < 1e-9 )
        }
    }

    /// The separable ``Convolution/zeroSumResponse(of:kernel:)`` reproduces a dense
    /// 2D convolution with the same zero-sum kernel, to floating-point rounding,
    /// across small and large kernels and structured content — so the matched-filter
    /// response the star detector reads is unchanged by the separable optimization.
    ///
    /// This is an equivalence lock, not a red→green test: both paths are correct, and
    /// a structural error in the separable form (a transposed axis, a wrong border, a
    /// missing DC term) would differ from the dense reference by ~the response
    /// magnitude — hundreds to thousands here — not the ~1e-11 of reordered sums.
    @Test
    func zeroSumResponseMatchesADenseConvolution() throws
    {
        let width  = 96
        let height = 72

        // A deterministic mix of a gradient, a pedestal, noise and Gaussian blobs —
        // the structure a real star field carries — so the comparison exercises the
        // interior and the replicated borders alike.
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15

        func noise() -> Double
        {
            seed = ( seed &* 6_364_136_223_846_793_005 ) &+ 1_442_695_040_888_963_407

            return Double( seed >> 11 ) / Double( 1 << 53 )
        }

        var pixels = ( 0 ..< ( width * height ) ).map
        {
            index -> Double in

            let x = Double( index % width )
            let y = Double( index / width )

            return 100 + ( 0.5 * x ) + ( 0.3 * y ) + ( 20 * noise() )
        }

        [ ( x: 24, y: 18, amplitude: 3000.0, sigma: 2.0 ), ( x: 70, y: 50, amplitude: 1500.0, sigma: 4.0 ), ( x: 10, y: 60, amplitude: 800.0, sigma: 1.2 ) ].forEach
        {
            star in

            ( 0 ..< ( width * height ) ).forEach
            {
                index in

                let dx       = Double( index % width ) - Double( star.x )
                let dy       = Double( index / width ) - Double( star.y )
                let exponent = ( ( dx * dx ) + ( dy * dy ) ) / ( 2 * star.sigma * star.sigma )

                pixels[ index ] += star.amplitude * exp( -exponent )
            }
        }

        let image = try self.buffer( width: width, height: height, pixels: pixels )

        [ 1.0, 2.5, 5.0, 7.5 ].forEach
        {
            sigma in

            let kernel    = GaussianKernel( sigma: sigma )
            let separable = Convolution.zeroSumResponse( of: image, kernel: kernel )
            let dense     = Convolution.convolve( image.pixels, width: width, height: height, kernel: kernel.zeroSumValues, radius: kernel.radius )

            #expect( separable.count == dense.count )

            let maxDiff = zip( separable, dense ).map { abs( $0 - $1 ) }.max() ?? 0

            #expect( maxDiff < 1e-6 )
        }
    }

    /// `zeroSumResponse` must stay crash-free and correct on small single-channel
    /// images: the separable path's `vDSP.convolve` requires a minimum signal size
    /// (≥ 3 rows / ≥ 4 columns), so below the 4×3 boundary the method falls back to
    /// the dense path — which pads to that minimum, so even a 1-pixel-wide image with
    /// a radius-1 kernel (padded width 3) no longer traps. Each small geometry both
    /// avoids the trap and matches the dense reference — identically for the fallback
    /// sizes, to rounding at the separable boundary — across kernels down to radius 1.
    @Test
    func zeroSumResponseHandlesSmallImagesWithoutTrapping() throws
    {
        let geometries = [ ( 1, 1 ), ( 2, 2 ), ( 3, 3 ), ( 3, 5 ), ( 5, 3 ), ( 4, 2 ), ( 2, 4 ), ( 1, 10 ), ( 10, 1 ), ( 4, 3 ), ( 4, 4 ), ( 6, 5 ) ]

        try geometries.forEach
        {
            geometry in

            let ( width, height ) = geometry
            let pixels            = ( 0 ..< ( width * height ) ).map { 100 + Double( ( $0 * 37 ) % 19 ) }
            let image             = try self.buffer( width: width, height: height, pixels: pixels )

            // sigma 0.3 / 0.5 give a radius-1 kernel (padded width 3 for width 1) —
            // the case that trapped before the dense path was hardened.
            [ 0.3, 0.5, 1.0, 5.0 ].forEach
            {
                sigma in

                let kernel    = GaussianKernel( sigma: sigma )
                let separable = Convolution.zeroSumResponse( of: image, kernel: kernel )
                let dense     = Convolution.convolve( image.pixels, width: width, height: height, kernel: kernel.zeroSumValues, radius: kernel.radius )

                #expect( separable.count == width * height )
                #expect( separable.count == dense.count )

                let maxDiff = zip( separable, dense ).map { abs( $0 - $1 ) }.max() ?? 0

                #expect( maxDiff < 1e-6 )
            }
        }
    }

    /// The public `convolve` validates its preconditions, returning [] instead of
    /// trapping on a short sample array, over-reading a wrong-sized kernel, or
    /// mishandling a negative radius (CR-11).
    @Test
    func convolveRejectsInconsistentArguments() throws
    {
        let kernel3x3 = [ Double ]( repeating: 1.0 / 9.0, count: 9 ) // A radius-1 (3×3) kernel.

        #expect( Convolution.convolve( [ 1, 2, 3 ], width: 2, height: 2, kernel: kernel3x3, radius: 1 ).isEmpty )      // values.count 3 ≠ 4
        #expect( Convolution.convolve( [ 1, 2, 3, 4 ], width: 2, height: 2, kernel: [ 1, 2, 3 ], radius: 1 ).isEmpty ) // kernel.count 3 ≠ 9
        #expect( Convolution.convolve( [ 1, 2, 3, 4 ], width: 2, height: 2, kernel: kernel3x3, radius: -1 ).isEmpty )  // radius < 0
    }
}
