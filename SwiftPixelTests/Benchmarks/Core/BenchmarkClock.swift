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

/// A monotonic wall-clock sampler for micro-benchmarks.
enum BenchmarkClock
{
    /// Runs `body` repeatedly, returning one elapsed-nanosecond sample per timed
    /// iteration.
    ///
    /// A number of untimed `warmup` iterations run first, so one-off costs (lazy
    /// initialization, first-touch page faults, instruction-cache warmup) do not
    /// skew the samples. Timing uses `DispatchTime`'s monotonic clock, which is
    /// unaffected by wall-clock adjustments.
    ///
    /// - Parameters:
    ///   - iterations: The number of timed iterations. Values `< 1` yield no
    ///                 samples (though the warmup iterations still run).
    ///   - warmup:     The number of untimed warmup iterations. Negative values
    ///                 are treated as `0`.
    ///   - body:       The operation to measure.
    /// - Returns: The elapsed nanoseconds for each timed iteration, in order.
    /// - Throws: Rethrows the first error thrown by `body`.
    static func sample( iterations: Int, warmup: Int = 0, _ body: () throws -> Void ) rethrows -> [ UInt64 ]
    {
        try ( 0 ..< max( 0, warmup ) ).forEach { _ in try body() }

        guard iterations >= 1
        else
        {
            return []
        }

        return try ( 0 ..< iterations ).map
        {
            _ -> UInt64 in

            let start = DispatchTime.now()

            try body()

            let end = DispatchTime.now()

            return end.uptimeNanoseconds - start.uptimeNanoseconds
        }
    }
}
