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

/// Tests for ``PixelUtilities`` median and median-absolute-deviation.
struct Test_PixelUtilities_Median
{
    /// The median of no values is `nil`.
    @Test
    func medianOfEmptyIsNil() throws
    {
        #expect( PixelUtilities.median( [ Double ]() ) == nil )
    }

    /// The median of an odd count is the middle value.
    @Test
    func medianOfOddCountIsTheMiddleValue() throws
    {
        #expect( PixelUtilities.median( [ 6, 2, 4 ] as [ Double ] ) == 4 )
    }

    /// The median of an even count averages the two middle values.
    @Test
    func medianOfEvenCountAveragesTheTwoMiddleValues() throws
    {
        #expect( PixelUtilities.median( [ 8, 2, 6, 4 ] as [ Double ] ) == 5 )
    }

    /// The median works for any `BinaryFloatingPoint`, e.g. `Float`.
    @Test
    func medianIsGenericOverFloatingPoint() throws
    {
        #expect( PixelUtilities.median( [ 8, 2, 6, 4 ] as [ Float ] ) == Float( 5 ) )
    }

    /// The median absolute deviation is measured about the given center.
    @Test
    func medianAbsoluteDeviationAboutACenter() throws
    {
        // |[2,4,6,8] − 5| = [3,1,1,3] → median = 2.
        #expect( PixelUtilities.medianAbsoluteDeviation( [ 2, 4, 6, 8 ] as [ Double ], around: 5 ) == 2 )
    }

    /// The median absolute deviation of no values is `nil`.
    @Test
    func medianAbsoluteDeviationOfEmptyIsNil() throws
    {
        #expect( PixelUtilities.medianAbsoluteDeviation( [ Double ](), around: 0 ) == nil )
    }

    /// The `Double` median ignores non-finite (NaN / ±Inf) samples, so a stray
    /// FITS blank cannot give the sort an undefined ordering.
    @Test
    func medianIgnoresNonFiniteSamples() throws
    {
        // NaN, +Inf and −Inf are all dropped before the median of the finite
        // remainder is taken.
        #expect( PixelUtilities.median( [ 1, 2, .nan, 3, 4 ] as [ Double ] )          == 2.5 )
        #expect( PixelUtilities.median( [ 1, 2, .infinity, 3, 4 ] as [ Double ] )     == 2.5 )
        #expect( PixelUtilities.median( [ -.infinity, 1, 2, 3 ] as [ Double ] )       == 2 )
    }

    /// A `Double` set with no finite samples has no median.
    @Test
    func medianOfAllNonFiniteIsNil() throws
    {
        #expect( PixelUtilities.median( [ .nan, .infinity, -.infinity ] as [ Double ] ) == nil )
    }

    /// The generic median ignores non-finite samples too, and yields `nil` when
    /// none are finite.
    @Test
    func genericMedianIgnoresNonFiniteSamples() throws
    {
        #expect( PixelUtilities.median( [ 1, 2, .nan, 3, 4 ] as [ Float ] ) == Float( 2.5 ) )
        #expect( PixelUtilities.median( [ .nan, .nan ] as [ Float ] )       == nil )
    }

    /// With non-finite samples present, the concrete `[Double]` overload and the
    /// generic overload agree on the finite median (they no longer diverge on the
    /// undefined NaN ordering).
    @Test
    func bothMedianOverloadsAgreeWithNonFiniteInput() throws
    {
        let concrete = PixelUtilities.median( [ 1, 2, .nan, 3, 4 ] as [ Double ] )
        let generic  = PixelUtilities.median( [ 1, 2, .nan, 3, 4 ] as [ Float ] )

        #expect( concrete == 2.5 )
        #expect( generic == Float( 2.5 ) )
    }

    /// The median absolute deviation ignores non-finite samples, since the
    /// deviation of a non-finite sample is itself non-finite and is dropped by the
    /// median.
    @Test
    func medianAbsoluteDeviationIgnoresNonFiniteSamples() throws
    {
        // |[1,2,3,4] − 2.5| = [1.5,0.5,0.5,1.5] → median = 1.0; the NaN is dropped.
        #expect( PixelUtilities.medianAbsoluteDeviation( [ 1, 2, .nan, 3, 4 ] as [ Double ], around: 2.5 ) == 1.0 )
    }
}
