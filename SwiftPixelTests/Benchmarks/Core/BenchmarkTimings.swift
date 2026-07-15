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

/// Aggregated wall-clock statistics for a benchmarked operation, computed from a
/// set of per-iteration nanosecond samples.
///
/// The values are integer nanoseconds so they serialize losslessly into the
/// baseline JSON and stay comparable across machines. The minimum is the least
/// noisy estimate of an operation's intrinsic cost (it is the run least
/// disturbed by scheduling and thermal effects); the median resists outliers;
/// the maximum exposes worst-case variance.
struct BenchmarkTimings: Codable, Equatable, Sendable
{
    /// The number of timed iterations the statistics summarize.
    let iterations: Int

    /// The fastest iteration, in nanoseconds.
    let minNanoseconds: UInt64

    /// The median iteration, in nanoseconds.
    let medianNanoseconds: UInt64

    /// The slowest iteration, in nanoseconds.
    let maxNanoseconds: UInt64

    /// Builds timing statistics from raw per-iteration samples.
    ///
    /// The samples are sorted internally, so their input order is irrelevant.
    /// The median of an even number of samples is the integer mean of the two
    /// central values.
    ///
    /// - Parameter samples: The measured durations, in nanoseconds, one per
    ///                      iteration.
    /// - Returns: The aggregated statistics, or `nil` if `samples` is empty.
    static func from( samples: [ UInt64 ] ) -> BenchmarkTimings?
    {
        guard samples.isEmpty == false
        else
        {
            return nil
        }

        let sorted = samples.sorted()
        let count  = sorted.count
        let median: UInt64

        if count.isMultiple( of: 2 )
        {
            let low  = sorted[ ( count / 2 ) - 1 ]
            let high = sorted[ count / 2 ]
            median   = ( low / 2 ) + ( high / 2 ) + ( ( ( low % 2 ) + ( high % 2 ) ) / 2 )
        }
        else
        {
            median = sorted[ count / 2 ]
        }

        return BenchmarkTimings(
            iterations:        count,
            minNanoseconds:    sorted[ 0 ],
            medianNanoseconds: median,
            maxNanoseconds:    sorted[ count - 1 ]
        )
    }
}
