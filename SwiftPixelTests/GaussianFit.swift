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

/// Tests for ``GaussianFit``.
struct Test_GaussianFit
{
    /// Samples a Gaussian over a square window centred on the model.
    ///
    /// - Parameters:
    ///   - truth:  The Gaussian parameters to sample.
    ///   - radius: The half-size of the square window, in pixels.
    /// - Returns: The samples, in row-major order over the window.
    private func samples( of truth: GaussianFit.Parameters, radius: Int ) -> [ ( x: Double, y: Double, value: Double ) ]
    {
        let size = ( 2 * radius ) + 1

        return ( 0 ..< ( size * size ) ).map
        {
            index in

            let x = truth.x - Double( radius ) + Double( index % size )
            let y = truth.y - Double( radius ) + Double( index / size )

            return ( x: x, y: y, value: truth.value( atX: x, y: y ) )
        }
    }

    /// A normally-distributed noise sample drawn from `generator`.
    ///
    /// A Box–Muller transform of two uniform deviates; paired with a fixed-seed
    /// generator it makes a noisy fit reproducible from run to run.
    ///
    /// - Parameters:
    ///   - generator: The (seeded) source of randomness.
    ///   - sigma:     The standard deviation of the noise.
    /// - Returns: A sample with mean `0` and standard deviation `sigma`.
    private func gaussianNoise( using generator: inout some RandomNumberGenerator, sigma: Double ) -> Double
    {
        // 1 − u maps [0, 1) onto (0, 1], keeping the logarithm finite.
        let u1 = 1.0 - Double.random( in: 0 ..< 1, using: &generator )
        let u2 = Double.random( in: 0 ..< 1, using: &generator )

        return sigma * ( -2.0 * Foundation.log( u1 ) ).squareRoot() * Foundation.cos( 2.0 * Double.pi * u2 )
    }

    /// A clean round Gaussian is recovered from a rough initial guess.
    @Test
    func recoversARoundGaussianFromARoughGuess() throws
    {
        let truth   = GaussianFit.Parameters( amplitude: 3000, x: 15.3, y: 14.7, sigmaX: 3, sigmaY: 3, theta: 0, background: 200 )
        let samples = self.samples( of: truth, radius: 12 )
        let guess   = GaussianFit.Parameters( amplitude: 2500, x: 15, y: 15, sigmaX: 2.5, sigmaY: 3.5, theta: 0, background: 180 )

        let fit = try #require( GaussianFit.fit( samples: samples, initialGuess: guess ) )

        #expect( abs( fit.x - truth.x ) < 0.05 )
        #expect( abs( fit.y - truth.y ) < 0.05 )
        #expect( abs( fit.amplitude - truth.amplitude ) < 0.02 * truth.amplitude )
        #expect( abs( fit.background - truth.background ) < 2 )
        #expect( abs( abs( fit.sigmaX ) - 3 ) < 0.1 )
        #expect( abs( abs( fit.sigmaY ) - 3 ) < 0.1 )
    }

    /// A profile with no positive peak (a central dip) is rejected as non-physical.
    @Test
    func returnsNilForANonPositivePeak() throws
    {
        let dip     = GaussianFit.Parameters( amplitude: -1500, x: 12, y: 12, sigmaX: 3, sigmaY: 3, theta: 0, background: 2000 )
        let samples = self.samples( of: dip, radius: 12 )
        let guess   = GaussianFit.Parameters( amplitude: 1000, x: 12, y: 12, sigmaX: 3, sigmaY: 3, theta: 0, background: 1500 )

        let fit = GaussianFit.fit( samples: samples, initialGuess: guess )

        #expect( fit == nil )
    }

    /// A flat field carries no Gaussian to fit, so the fit is rejected.
    @Test
    func returnsNilForAFlatField() throws
    {
        let samples = ( 0 ..< ( 25 * 25 ) ).map
        {
            index -> ( x: Double, y: Double, value: Double ) in

            ( x: Double( index % 25 ), y: Double( index / 25 ), value: 500 )
        }

        let guess = GaussianFit.Parameters( amplitude: 200, x: 12, y: 12, sigmaX: 3, sigmaY: 3, theta: 0, background: 500 )
        let fit   = GaussianFit.fit( samples: samples, initialGuess: guess )

        #expect( fit == nil )
    }

    /// The parameter model evaluates a Gaussian at its centre as
    /// `background + amplitude`.
    @Test
    func modelPeaksAtTheCenter() throws
    {
        let parameters = GaussianFit.Parameters( amplitude: 1000, x: 10, y: 20, sigmaX: 2, sigmaY: 3, theta: 0.4, background: 50 )

        #expect( abs( parameters.value( atX: 10, y: 20 ) - 1050 ) < 1e-9 )
    }

    /// The model matches values hand-computed away from the centre — including a
    /// rotated case — so the rotation and per-axis width maths are checked against
    /// an external ground truth, not only at the centre where `exp(0) = 1` hides
    /// them.
    @Test
    func modelMatchesHandComputedOffCenterValues() throws
    {
        // θ = 0, off the centre on both axes: the exponent is
        // −( 2²/(2·2²) + 3²/(2·3²) ) = −1, so the value is background + amplitude·e⁻¹.
        let axisAligned = GaussianFit.Parameters( amplitude: 1000, x: 0, y: 0, sigmaX: 2, sigmaY: 3, theta: 0, background: 100 )

        #expect( abs( axisAligned.value( atX: 2, y: 3 ) - 467.87944117144235 ) < 1e-9 )

        // θ = π/2 swaps the axes, so the point (2, 0) lies along the now-vertical
        // σy = 1 axis: the exponent is −( 2²/(2·1²) ) = −2 and the value is
        // amplitude·e⁻². A round-off-tolerant bound absorbs cos(π/2)'s tiny residual.
        let rotated = GaussianFit.Parameters( amplitude: 1000, x: 0, y: 0, sigmaX: 2, sigmaY: 1, theta: .pi / 2, background: 0 )

        #expect( abs( rotated.value( atX: 2, y: 0 ) - 135.3352832366127 ) < 1e-6 )
    }

    /// A rotated, elliptical Gaussian (θ ≠ 0, σx ≠ σy) is recovered, exercising the
    /// θ and per-axis-width Jacobian columns that a round fit leaves unconstrained.
    @Test
    func recoversARotatedEllipticalGaussian() throws
    {
        let truth   = GaussianFit.Parameters( amplitude: 3000, x: 15.3, y: 14.7, sigmaX: 4, sigmaY: 2, theta: 0.6, background: 200 )
        let samples = self.samples( of: truth, radius: 12 )
        let guess   = GaussianFit.Parameters( amplitude: 2500, x: 15, y: 15, sigmaX: 3.5, sigmaY: 2.5, theta: 0.5, background: 180 )

        let fit = try #require( GaussianFit.fit( samples: samples, initialGuess: guess ) )

        #expect( abs( fit.x - truth.x ) < 0.05 )
        #expect( abs( fit.y - truth.y ) < 0.05 )
        #expect( abs( fit.amplitude - truth.amplitude ) < 0.02 * truth.amplitude )
        #expect( abs( fit.background - truth.background ) < 2 )

        // The widths pin the ellipse's orientation: with σx ≠ σy the θ + π/2 axis
        // swap would report the widths transposed, so asserting them (plus θ) rules
        // it out.
        #expect( abs( fit.sigmaX - truth.sigmaX ) < 0.1 )
        #expect( abs( fit.sigmaY - truth.sigmaY ) < 0.1 )

        // θ is only defined modulo π (the model is unchanged by θ → θ + π); sin of
        // the difference vanishes at both 0 and π, so it tests θ up to that
        // degeneracy.
        #expect( abs( Foundation.sin( fit.theta - truth.theta ) ) < 0.02 )
    }

    /// A Gaussian is recovered from fixed-seed noisy samples, backing the type's
    /// claim of noise robustness that every other (noiseless) test leaves untested.
    @Test
    func recoversAGaussianFromNoisyData() throws
    {
        let truth = GaussianFit.Parameters( amplitude: 3000, x: 15.3, y: 14.7, sigmaX: 3, sigmaY: 3, theta: 0, background: 200 )
        let clean = self.samples( of: truth, radius: 12 )

        var generator = SplitMix64( seed: 0x1234_5678_9ABC_DEF0 )
        let noisy     = clean.map { ( x: $0.x, y: $0.y, value: $0.value + self.gaussianNoise( using: &generator, sigma: 30 ) ) }

        let guess = GaussianFit.Parameters( amplitude: 2500, x: 15, y: 15, sigmaX: 2.5, sigmaY: 3.5, theta: 0, background: 180 )
        let fit   = try #require( GaussianFit.fit( samples: noisy, initialGuess: guess ) )

        // Looser bounds than the noiseless fit: the sub-pixel centre and the widths
        // must still land near the truth despite the added noise.
        #expect( abs( fit.x - truth.x ) < 0.2 )
        #expect( abs( fit.y - truth.y ) < 0.2 )
        #expect( abs( fit.amplitude - truth.amplitude ) < 0.05 * truth.amplitude )
        #expect( abs( fit.background - truth.background ) < 20 )
        #expect( abs( fit.sigmaX - truth.sigmaX ) < 0.3 )
        #expect( abs( fit.sigmaY - truth.sigmaY ) < 0.3 )
    }
}

/// A small, fast, seedable pseudo-random generator (SplitMix64) for reproducible
/// noisy-fit tests.
///
/// The system generator cannot be seeded, so a noisy recovery test would vary from
/// run to run; SplitMix64 gives a fixed, well-distributed sequence from a seed.
private struct SplitMix64: RandomNumberGenerator
{
    /// The running generator state, advanced by a fixed odd increment per draw.
    private var state: UInt64

    /// Creates a generator seeded with `seed`.
    ///
    /// - Parameter seed: The initial state; the same seed always yields the same
    ///                   sequence.
    init( seed: UInt64 )
    {
        self.state = seed
    }

    /// The next 64-bit value in the sequence (the SplitMix64 finalizer).
    mutating func next() -> UInt64
    {
        self.state = self.state &+ 0x9E37_79B9_7F4A_7C15

        var z = self.state

        z = ( z ^ ( z >> 30 ) ) &* 0xBF58_476D_1CE4_E5B9
        z = ( z ^ ( z >> 27 ) ) &* 0x94D0_49BB_1331_11EB

        return z ^ ( z >> 31 )
    }
}
