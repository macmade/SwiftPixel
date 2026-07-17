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
