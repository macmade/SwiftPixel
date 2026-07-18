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

/// Tests for ``GaussianKernel``.
struct Test_GaussianKernel
{
    /// The normalized kernel's weights sum to one.
    @Test
    func normalizedWeightsSumToOne() throws
    {
        let kernel = GaussianKernel( sigma: 2 )
        let sum    = kernel.values.reduce( 0, + )

        #expect( abs( sum - 1 ) < 1e-9 )
    }

    /// The zero-sum variant's weights sum to (approximately) zero, so it produces
    /// no response to a constant region.
    @Test
    func zeroSumWeightsSumToZero() throws
    {
        let kernel = GaussianKernel( sigma: 2 )
        let sum    = kernel.zeroSumValues.reduce( 0, + )

        #expect( abs( sum ) < 1e-12 )
    }

    /// The kernel has an odd, square footprint sized from its radius.
    @Test
    func footprintIsSquareAndOddFromRadius() throws
    {
        let kernel = GaussianKernel( sigma: 1.5 )

        #expect( kernel.size == ( 2 * kernel.radius ) + 1 )
        #expect( kernel.values.count == kernel.size * kernel.size )
        #expect( kernel.zeroSumValues.count == kernel.size * kernel.size )
    }

    /// The kernel is symmetric about both axes.
    @Test
    func kernelIsSymmetric() throws
    {
        let kernel = GaussianKernel( sigma: 2 )
        let size   = kernel.size

        ( 0 ..< size ).forEach
        {
            y in

            ( 0 ..< size ).forEach
            {
                x in

                let value     = kernel.values[ ( y * size ) + x ]
                let mirroredX = kernel.values[ ( y * size ) + ( size - 1 - x ) ]
                let mirroredY = kernel.values[ ( ( size - 1 - y ) * size ) + x ]

                #expect( abs( value - mirroredX ) < 1e-12 )
                #expect( abs( value - mirroredY ) < 1e-12 )
            }
        }
    }

    /// The kernel's central weight is its maximum.
    @Test
    func centerIsTheMaximumWeight() throws
    {
        let kernel = GaussianKernel( sigma: 2 )
        let center = kernel.values[ ( kernel.radius * kernel.size ) + kernel.radius ]
        let max    = kernel.values.max() ?? 0

        #expect( center == max )
    }

    /// A non-finite standard deviation clamps to the small positive minimum
    /// instead of trapping in the `Int(sigma …)` conversion, yielding a valid
    /// minimal kernel.
    @Test
    func nonFiniteSigmaClampsToMinimum() throws
    {
        // Before the fix, `.nan` and `+.infinity` crash in `Int(_:)`; all three
        // must now degrade to the 1e-6 minimum and build a valid 3×3 kernel.
        [ Double.nan, .infinity, -.infinity ].forEach
        {
            sigma in

            let kernel = GaussianKernel( sigma: sigma )

            #expect( kernel.sigma == 1e-6 )
            #expect( kernel.radius == 1 )
            #expect( kernel.size == 3 )
            #expect( kernel.values.count == 9 )
            #expect( kernel.values.allSatisfy { $0.isFinite } )
            #expect( abs( kernel.values.reduce( 0, + ) - 1 ) < 1e-9 )
        }
    }

    /// A non-finite `radiusInSigmas` does not trap either: the span becomes
    /// non-finite and falls back to the minimal footprint.
    @Test
    func nonFiniteRadiusInSigmasClampsToMinimum() throws
    {
        // Before the fix, a finite sigma with a non-finite radiusInSigmas reached
        // `Int(sigma · radiusInSigmas)` and crashed.
        [ Double.nan, .infinity, -.infinity ].forEach
        {
            radiusInSigmas in

            let kernel = GaussianKernel( sigma: 5, radiusInSigmas: radiusInSigmas )

            #expect( kernel.radius == 1 )
            #expect( kernel.size == 3 )
            #expect( kernel.values.allSatisfy { $0.isFinite } )
            #expect( abs( kernel.values.reduce( 0, + ) - 1 ) < 1e-9 )
        }
    }

    /// A pathologically large but finite scale does not trap: the radius is
    /// bounded so `Int(_:)` and the `(2·radius + 1)²` footprint arithmetic stay in
    /// range, and the kernel is still valid.
    @Test
    func pathologicallyLargeScaleIsBounded() throws
    {
        // `Int((1e300 · 2).rounded(.up))` traps (out of Int range) without the
        // bound; an in-range-but-enormous radius would also overflow the footprint.
        let kernel = GaussianKernel( sigma: 1e300 )

        #expect( kernel.radius >= 1 )
        #expect( kernel.radius <= 4096 )
        #expect( kernel.size == ( 2 * kernel.radius ) + 1 )
        #expect( kernel.values.count == kernel.size * kernel.size )
        #expect( kernel.values.allSatisfy { $0.isFinite } )
        #expect( abs( kernel.values.reduce( 0, + ) - 1 ) < 1e-9 )
    }

    /// The weight values match the sampled Gaussian: the centre is `1 / Σ` and each
    /// ring is the centre scaled by `exp(-(x²+y²)/(2σ²))`, pinning the exponent and
    /// the normalization that the sum/symmetry invariants leave open.
    @Test
    func weightsMatchTheSampledGaussian() throws
    {
        // sigma 0.5, radiusInSigmas 2 → span 1 → radius 1: a 3×3 kernel with
        // 2σ² = 0.5, so the ring ratios are exp(-2) (edge) and exp(-4) (corner).
        let kernel = GaussianKernel( sigma: 0.5 )

        try #require( kernel.radius == 1 )
        try #require( kernel.size   == 3 )

        let center = kernel.values[ 4 ]
        let edge   = kernel.values[ 1 ]
        let corner = kernel.values[ 0 ]

        // The centre weight is 1 / Σ of the raw samples over the 3×3 footprint.
        #expect( abs( center - 0.6193470305571772 ) < 1e-12 )
        #expect( abs( edge   - center * Foundation.exp( -2.0 ) ) < 1e-12 )
        #expect( abs( corner - center * Foundation.exp( -4.0 ) ) < 1e-12 )

        // zeroSumValues subtract the mean weight, which is 1 / count because the
        // values already sum to one.
        #expect( abs( kernel.zeroSumValues[ 4 ] - ( center - 1.0 / 9.0 ) ) < 1e-12 )
        #expect( abs( kernel.zeroSumValues[ 1 ] - ( edge   - 1.0 / 9.0 ) ) < 1e-12 )
    }

    /// A finite, non-positive or sub-minimum sigma clamps up to the 1e-6 floor via
    /// the `max(sigma, 1e-6)` branch — distinct from the non-finite path.
    @Test
    func finiteSubMinimumSigmaClampsToFloor() throws
    {
        [ 0.0, -5.0, 1e-9 ].forEach
        {
            sigma in

            let kernel = GaussianKernel( sigma: sigma )

            #expect( kernel.sigma == 1e-6 )
            #expect( kernel.radius == 1 )
            #expect( kernel.size == 3 )
            #expect( abs( kernel.values.reduce( 0, + ) - 1 ) < 1e-9 )
        }
    }

    /// The radius is pinned at both ends of the finite branch, plus the
    /// finite-sigma / overflowing-span fallback.
    @Test
    func radiusIsClampedToItsBounds() throws
    {
        // Lower floor via the finite branch: a tiny span rounds up to radius 1.
        #expect( GaussianKernel( sigma: 0.1 ).radius == 1 )

        // Upper cap: an enormous but finite span saturates at maximumRadius (512).
        #expect( GaussianKernel( sigma: 1e300 ).radius == 512 )

        // A finite sigma whose span overflows to non-finite falls to radius 1 — a
        // different branch from the finite upper cap above.
        let overflow = GaussianKernel( sigma: .greatestFiniteMagnitude )

        #expect( overflow.radius == 1 )
        #expect( overflow.values.allSatisfy { $0.isFinite } )
        #expect( abs( overflow.values.reduce( 0, + ) - 1 ) < 1e-9 )
    }
}
