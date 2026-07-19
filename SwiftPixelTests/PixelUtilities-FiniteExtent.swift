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

struct Test_PixelUtilities_FiniteExtent
{
    @Test
    func emptyArrayHasNoExtent() async throws
    {
        #expect( PixelUtilities.finiteExtent( [] ) == nil )
    }

    @Test
    func singleElementIsBothExtremes() async throws
    {
        let extent = try #require( PixelUtilities.finiteExtent( [ 42 ] ) )

        #expect( extent.minimum == 42 )
        #expect( extent.maximum == 42 )
    }

    @Test
    func returnsMinimumAndMaximumRegardlessOfOrder() async throws
    {
        let extent = try #require( PixelUtilities.finiteExtent( [ 3, -2, 7, 0, 5 ].shuffled() ) )

        #expect( extent.minimum == -2 )
        #expect( extent.maximum == 7 )
    }

    /// A leading `NaN` must not poison the extremes. The standard-library
    /// `min()` / `max()` return `NaN` for `[ .nan, … ]`, so a raw scan would; the
    /// finite-aware extent drops it and returns the finite bounds.
    @Test
    func leadingNaNIsIgnored() async throws
    {
        let extent = try #require( PixelUtilities.finiteExtent( [ .nan, 0, 1, 2, 3 ] ) )

        #expect( extent.minimum == 0 )
        #expect( extent.maximum == 3 )
        #expect( extent.minimum.isFinite )
        #expect( extent.maximum.isFinite )
    }

    /// A `+Inf` anywhere must not leak into the maximum.
    @Test
    func positiveInfinityDoesNotLeakIntoMaximum() async throws
    {
        let extent = try #require( PixelUtilities.finiteExtent( [ 0, 1, .infinity, 2, 3 ] ) )

        #expect( extent.maximum == 3 )
        #expect( extent.maximum.isFinite )
    }

    /// A `−Inf` anywhere must not leak into the minimum.
    @Test
    func negativeInfinityDoesNotLeakIntoMinimum() async throws
    {
        let extent = try #require( PixelUtilities.finiteExtent( [ 0, -.infinity, 1, 2, 3 ] ) )

        #expect( extent.minimum == 0 )
        #expect( extent.minimum.isFinite )
    }

    /// An array with no finite samples has no extent, matching the `nil` contract
    /// of the sibling robust helpers.
    @Test
    func allNonFiniteHasNoExtent() async throws
    {
        #expect( PixelUtilities.finiteExtent( [ .nan, .infinity, -.infinity, .nan ] ) == nil )
    }
}
