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
import SwiftUtilities
import Testing

struct Test_PixelUtilities_Interleave
{
    @Test
    func interleavesThreeChannels() throws
    {
        let result = try PixelUtilities.interleave( planes: [ [ 10, 40 ], [ 20, 50 ], [ 30, 60 ] ] )

        // [ r0 g0 b0 r1 g1 b1 ]
        #expect( result == [ 10, 20, 30, 40, 50, 60 ] )
    }

    @Test
    func interleavesArbitraryChannelCount() throws
    {
        // Two channels, three samples each -> [ c0s0 c1s0 c0s1 c1s1 c0s2 c1s2 ].
        let result = try PixelUtilities.interleave( planes: [ [ 1, 2, 3 ], [ 4, 5, 6 ] ] )

        #expect( result == [ 1, 4, 2, 5, 3, 6 ] )
    }

    @Test
    func rejectsUnequalPlaneLengths() throws
    {
        #expect( throws: ( any Error ).self )
        {
            _ = try PixelUtilities.interleave( planes: [ [ 1, 2, 3 ], [ 4, 5 ] ] )
        }
    }

    @Test
    func rejectsEmptyInput() throws
    {
        #expect( throws: ( any Error ).self )
        {
            _ = try PixelUtilities.interleave( planes: [] )
        }

        #expect( throws: ( any Error ).self )
        {
            _ = try PixelUtilities.interleave( planes: [ [], [] ] )
        }
    }
}
