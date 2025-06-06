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

import Foundation
@testable import SwiftPixel
import Testing

struct Test_HistogramStatistics
{
    @Test
    func empty() async throws
    {
        let stats = HistogramStatistics( data: [ Int ]( repeating: 0, count: 256 ) )

        #expect( stats.count        == 0 )
        #expect( stats.mean         == 0 )
        #expect( stats.median       == 0 )
        #expect( stats.stdDev       == 0 )
        #expect( stats.min          == 0 )
        #expect( stats.max          == 0 )
        #expect( stats.percentile1  == 0 )
        #expect( stats.percentile99 == 0 )
    }

    @Test
    func singlePeak() async throws
    {
        var data   = [ Int ]( repeating: 0, count: 256 )
        data[ 42 ] = 100
        let stats  = HistogramStatistics( data: data )

        #expect( stats.count        == 100 )
        #expect( stats.mean         == 42 )
        #expect( stats.median       == 42 )
        #expect( stats.stdDev       == 0 )
        #expect( stats.min          == 42 )
        #expect( stats.max          == 42 )
        #expect( stats.percentile1  == 42 )
        #expect( stats.percentile99 == 42 )
    }

    @Test
    func linearSpread() async throws
    {
        var data   = [ Int ]( repeating: 0, count: 256 )
        data[ 10 ] = 50
        data[ 20 ] = 50
        let stats  = HistogramStatistics( data: data )

        #expect( stats.count        == 100 )
        #expect( stats.mean         == 15 )
        #expect( stats.median       == 10 )
        #expect( stats.stdDev      >= 4.9 )
        #expect( stats.stdDev      <= 5.1 )
        #expect( stats.min          == 10 )
        #expect( stats.max          == 20 )
        #expect( stats.percentile1  == 10 )
        #expect( stats.percentile99 == 20 )
    }
}
