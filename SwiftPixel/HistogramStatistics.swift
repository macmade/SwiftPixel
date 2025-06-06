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

public struct HistogramStatistics
{
    public let count:        Int
    public let mean:         Double
    public let median:       Int
    public let stdDev:       Double
    public let min:          Int
    public let max:          Int
    public let percentile1:  Int
    public let percentile99: Int

    public init( data: [ Int ] )
    {
        let total = data.reduce( 0, + )

        guard total > 0
        else
        {
            self.count        = 0
            self.mean         = 0
            self.median       = 0
            self.stdDev       = 0
            self.min          = 0
            self.max          = 0
            self.percentile1  = 0
            self.percentile99 = 0

            return
        }

        var sum         = 0.0
        var sumSq       = 0.0
        var cumulative  = 0
        var medianFound = false
        var median      = 0
        var minVal:       Int?
        var maxVal:       Int?

        data.enumerated().forEach
        {
            index, value in

            if value > 0
            {
                if minVal == nil
                {
                    minVal = index
                }

                maxVal = index
            }

            let freq   = Double( value )
            let dIndex = Double( index )

            sum   += dIndex * freq
            sumSq += dIndex * dIndex * freq

            if medianFound == false
            {
                cumulative += value

                if cumulative >= total / 2
                {
                    median      = index
                    medianFound = true
                }
            }
        }

        let mean        = sum / Double( total )
        let stdDev      = sqrt( ( sumSq / Double( total ) ) - ( mean * mean ) )
        let percentiles = Self.percentiles( data: data, total: total, p1: 0.01, p2: 0.99 )

        self.count        = total
        self.mean         = mean
        self.median       = median
        self.stdDev       = stdDev
        self.min          = minVal ?? 0
        self.max          = maxVal ?? 255
        self.percentile1  = percentiles.p1
        self.percentile99 = percentiles.p2
    }

    public static func percentiles( data: [ Int ], total: Int, p1: Double, p2: Double ) -> ( p1: Int, p2: Int )
    {
        let t1         = Int( Double( total ) * p1 )
        let t2         = Int( Double( total ) * p2 )
        var cumulative = 0
        var r1:          Int?
        var r2:          Int?

        for i in 0 ..< data.count
        {
            cumulative += data[ i ]

            if r1 == nil && cumulative >= t1
            {
                r1 = i
            }

            if r2 == nil && cumulative >= t2
            {
                r2 = i
            }

            if r1 != nil && r2 != nil
            {
                break
            }
        }

        return ( r1 ?? 255, r2 ?? 255 )
    }
}
