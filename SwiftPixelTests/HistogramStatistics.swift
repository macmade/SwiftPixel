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

struct Test_HistogramStatistics
{
    @Test
    func standardDeviationClampsNegativeVarianceToZero() async throws
    {
        // sumSq/total - mean*mean is slightly negative here (floating-point
        // cancellation); without the clamp, sqrt would yield NaN.
        let result = HistogramStatistics.standardDeviation( sumSq: 1.0, total: 1.0, mean: 1.000_000_000_1 )

        #expect( result.isFinite )
        #expect( result == 0.0 )
    }

    @Test
    func standardDeviationComputesPositiveValue() async throws
    {
        // Two equally weighted bins at 0 and 2: variance = 2.0 - 1.0 = 1.0.
        let result = HistogramStatistics.standardDeviation( sumSq: 4.0, total: 2.0, mean: 1.0 )

        #expect( result == 1.0 )
    }

    @Test
    func equatableAndHashable() async throws
    {
        let a = HistogramStatistics( data: ( 0 ..< 256 ).map { $0 } )
        let b = HistogramStatistics( data: ( 0 ..< 256 ).map { $0 } )
        let c = HistogramStatistics( data: [ Int ]( repeating: 0, count: 256 ) )

        #expect( a == b )
        #expect( a != c )
        #expect( Set( [ a, b, c ] ).count == 2 )
    }

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
    func emptyArray() async throws
    {
        let stats = HistogramStatistics( data: [] )

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

    @Test
    func smallTotalPercentilesDoNotCollapseToBinZero() async throws
    {
        // Total < 100: Int( total · 0.01 ) truncates to 0, so the pre-fix scan
        // matched bin 0 immediately (cumulative >= 0 is always true) and reported
        // the 1st percentile as bin 0 regardless of where the data lie. Clamping
        // the threshold to >= 1 resolves it to a real, occupied bin.
        var data    = [ Int ]( repeating: 0, count: 256 )
        data[ 100 ] = 25
        data[ 150 ] = 25
        let stats   = HistogramStatistics( data: data )

        #expect( stats.count        == 50 )
        #expect( stats.min          == 100 )
        #expect( stats.max          == 150 )
        #expect( stats.median       == 100 ) // lower-median convention (D4)
        #expect( stats.percentile1  == 100 ) // was 0 before the clamp
        #expect( stats.percentile99 == 150 )
    }

    @Test
    func singleSampleIsInternallyConsistent() async throws
    {
        // total == 1: total / 2 and Int( 1 · 0.99 ) both truncate to 0, so the
        // pre-fix median and percentile99 collapsed to bin 0 while min == max were
        // the real bin — an internally inconsistent result. Clamping the crossings
        // to >= 1 makes every index-valued statistic agree on the single bin.
        var data    = [ Int ]( repeating: 0, count: 256 )
        data[ 200 ] = 1
        let stats   = HistogramStatistics( data: data )

        #expect( stats.count        == 1 )
        #expect( stats.min          == 200 )
        #expect( stats.max          == 200 )
        #expect( stats.median       == 200 )
        #expect( stats.percentile1  == 200 )
        #expect( stats.percentile99 == 200 )
    }
}
