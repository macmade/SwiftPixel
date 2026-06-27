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
}
