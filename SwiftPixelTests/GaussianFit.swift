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
}
