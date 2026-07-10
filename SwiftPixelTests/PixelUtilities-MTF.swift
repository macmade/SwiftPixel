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

struct Test_PixelUtilities_MTF
{
    @Test
    func midtonesOfHalfIsTheIdentity() async throws
    {
        let inputs = [ 0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0 ]

        #expect( inputs.allSatisfy { abs( PixelUtilities.mtf( 0.5, $0 ) - $0 ) < 1e-12 } )
    }

    @Test
    func midtonesOfZeroLiftsInteriorToOne() async throws
    {
        #expect( abs( PixelUtilities.mtf( 0.0, 0.25 ) - 1.0 ) < 1e-12 )
        #expect( abs( PixelUtilities.mtf( 0.0, 0.75 ) - 1.0 ) < 1e-12 )
    }

    @Test
    func midtonesOfOnePushesInteriorToZero() async throws
    {
        #expect( abs( PixelUtilities.mtf( 1.0, 0.25 ) - 0.0 ) < 1e-12 )
        #expect( abs( PixelUtilities.mtf( 1.0, 0.75 ) - 0.0 ) < 1e-12 )
    }

    @Test
    func boundaryInputsAreFixedPoints() async throws
    {
        let midtones = [ 0.0, 0.2, 0.5, 0.8, 1.0 ]

        #expect( midtones.allSatisfy { PixelUtilities.mtf( $0, 0.0 ) == 0.0 } )
        #expect( midtones.allSatisfy { PixelUtilities.mtf( $0, 1.0 ) == 1.0 } )
    }

    @Test
    func matchesTheClosedFormOnAKnownPoint() async throws
    {
        let m        = 0.25
        let x        = 0.1
        let expected = ( ( m - 1.0 ) * x ) / ( ( 2.0 * m - 1.0 ) * x - m )

        #expect( abs( PixelUtilities.mtf( m, x ) - expected ) < 1e-12 )
    }

    @Test
    func isMonotonicIncreasingInX() async throws
    {
        let m       = 0.2
        let samples = stride( from: 0.0, through: 1.0, by: 0.01 ).map { PixelUtilities.mtf( m, $0 ) }
        let pairs   = zip( samples, samples.dropFirst() )

        #expect( pairs.allSatisfy { $0 <= $1 + 1e-12 } )
        #expect( samples.allSatisfy { $0 >= -1e-12 && $0 <= 1.0 + 1e-12 } )
    }

    @Test
    func brightensWhenMidtonesBelowHalf() async throws
    {
        #expect( PixelUtilities.mtf( 0.2, 0.1 ) > 0.1 )
    }

    @Test
    func darkensWhenMidtonesAboveHalf() async throws
    {
        #expect( PixelUtilities.mtf( 0.8, 0.9 ) < 0.9 )
    }
}
