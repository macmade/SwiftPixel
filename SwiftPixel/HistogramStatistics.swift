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

/// Summary statistics computed from a single histogram channel.
///
/// All index-valued statistics (`median`, `min`, `max`, percentiles) are bin
/// indices, i.e. intensity values in `0...255`. For empty input (no samples),
/// every field is `0`.
public struct HistogramStatistics: Equatable, Hashable
{
    /// The total number of samples across all bins.
    public let count: Int

    /// The intensity-weighted mean.
    public let mean: Double

    /// The bin index at which the cumulative count reaches half the total.
    public let median: Int

    /// The standard deviation of the intensities.
    public let stdDev: Double

    /// The lowest bin index with a non-zero count.
    public let min: Int

    /// The highest bin index with a non-zero count.
    public let max: Int

    /// The bin index at the 1st percentile.
    public let percentile1: Int

    /// The bin index at the 99th percentile.
    public let percentile99: Int

    /// Computes summary statistics from a histogram channel.
    ///
    /// - Parameter data: The per-bin counts (typically 256 entries). If the
    ///                   counts sum to zero, every statistic is `0`.
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
        let stdDev      = Self.standardDeviation( sumSq: sumSq, total: Double( total ), mean: mean )
        let percentiles = Self.percentiles( data: data, total: total, p1: 0.01, p2: 0.99 )

        // minVal/maxVal are always set once total > 0 (there is at least one
        // non-zero bin), so these fallbacks are defensive and unreachable here;
        // 0 is used consistently to match the empty-input convention above.
        self.count        = total
        self.mean         = mean
        self.median       = median
        self.stdDev       = stdDev
        self.min          = minVal ?? 0
        self.max          = maxVal ?? 0
        self.percentile1  = percentiles.p1
        self.percentile99 = percentiles.p2
    }

    /// Returns the standard deviation from the running sums, clamping the
    /// variance at zero before the square root.
    ///
    /// The sum-of-squares variance `(sumSq / total) − mean²` can land slightly
    /// below zero through floating-point cancellation when the distribution has
    /// almost no spread; clamping keeps `sqrt` from producing `NaN`.
    ///
    /// - Parameters:
    ///   - sumSq: The frequency-weighted sum of squared bin indices.
    ///   - total: The total count.
    ///   - mean:  The distribution mean.
    ///
    /// - Returns: The standard deviation, always finite and `>= 0`.
    public static func standardDeviation( sumSq: Double, total: Double, mean: Double ) -> Double
    {
        let variance = ( sumSq / total ) - ( mean * mean )

        return sqrt( Swift.max( 0.0, variance ) )
    }

    /// Returns the bin indices at two cumulative-fraction thresholds.
    ///
    /// - Parameters:
    ///   - data:  The per-bin counts.
    ///   - total: The sum of all counts.
    ///   - p1:    The lower cumulative fraction (e.g. `0.01` for the 1st percentile).
    ///   - p2:    The upper cumulative fraction (e.g. `0.99` for the 99th percentile).
    ///
    /// - Returns: The bin indices at which the cumulative count first reaches
    ///            `p1·total` and `p2·total`.
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

        // r1/r2 are always set when total > 0; the 0 fallback is defensive and
        // matches the empty-input convention.
        return ( r1 ?? 0, r2 ?? 0 )
    }
}
