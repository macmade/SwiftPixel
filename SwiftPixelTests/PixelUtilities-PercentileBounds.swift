/*******************************************************************************
 * The MIT License (MIT)
 *
 * Copyright (c) 2025, Jean-David Gadina - www.xs-labs.com
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

import Accelerate
import Foundation
@testable import SwiftPixel
import Testing

struct Test_PixelUtilities_PercentileBounds
{
    @Test
    func emptyArray() async throws
    {
        let result = PixelUtilities.percentileBounds( in: [], lower: 25, upper: 75 )

        #expect( result.lower == 0 )
        #expect( result.upper == 0 )
    }

    @Test
    func singleElement() async throws
    {
        let result = PixelUtilities.percentileBounds( in: [ 42 ], lower: 25, upper: 75 )

        #expect( result.lower == 42 )
        #expect( result.upper == 42 )
    }

    @Test
    func twoElements() async throws
    {
        let result = PixelUtilities.percentileBounds( in: [ 10, 20 ].shuffled(), lower: 0, upper: 100 )

        #expect( result.lower == 10 )
        #expect( result.upper == 20 )
    }

    @Test
    func twoElementsInterpolated() async throws
    {
        let result = PixelUtilities.percentileBounds( in: [ 10, 20 ].shuffled(), lower: 25, upper: 75 )

        #expect( result.lower == 12.5 )
        #expect( result.upper == 17.5 )
    }

    @Test
    func multipleElements25to75() async throws
    {
        let result = PixelUtilities.percentileBounds( in: [ 10, 20, 30, 40, 50 ].shuffled(), lower: 25, upper: 75 )

        #expect( result.lower == 20 )
        #expect( result.upper == 40 )
    }

    @Test
    func multipleElements0to100() async throws
    {
        let result = PixelUtilities.percentileBounds( in: [ 10, 20, 30, 40, 50 ].shuffled(), lower: 0, upper: 100 )

        #expect( result.lower == 10 )
        #expect( result.upper == 50 )
    }

    @Test
    func multipleElementsInterpolated() async throws
    {
        let result = PixelUtilities.percentileBounds( in: [ 10, 20, 30, 40 ].shuffled(), lower: 37.5, upper: 87.5 )

        #expect( result.lower == 21.25 )
        #expect( result.upper == 36.25 )
    }
}
