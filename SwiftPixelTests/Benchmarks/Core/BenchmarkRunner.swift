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

/// Drives a single benchmark: it warms up and times an operation, then measures
/// its approximate peak allocation in a separate pass, and packages the result.
///
/// Timing and allocation are measured in separate passes on purpose: the
/// background footprint sampler used for allocations perturbs timing, so it must
/// not run while the wall-clock samples are being gathered.
struct BenchmarkRunner
{
    /// The number of timed iterations gathered per measurement.
    let iterations: Int

    /// The number of untimed warmup iterations run before timing.
    let warmup: Int

    /// Creates a runner.
    ///
    /// - Parameters:
    ///   - iterations: The number of timed iterations. Defaults to `20`.
    ///   - warmup:     The number of untimed warmup iterations. Defaults to `3`.
    init( iterations: Int = 20, warmup: Int = 3 )
    {
        self.iterations = iterations
        self.warmup     = warmup
    }

    /// Measures `body` and returns the packaged result.
    ///
    /// - Parameters:
    ///   - algorithm:   The measured algorithm's display name.
    ///   - category:    The group the algorithm belongs to.
    ///   - frame:       The frame the algorithm is measured on.
    ///   - allocations: Whether to run the extra allocation-measurement pass.
    ///                  Defaults to `true`.
    ///   - body:        The operation to measure. It must be repeatable — the
    ///                  runner invokes it many times.
    /// - Returns: The measurement, or `nil` if no timing samples were gathered
    ///            (only when `iterations < 1`).
    /// - Throws: Rethrows the first error thrown by `body`.
    func measure( algorithm: String, category: String, frame: BenchmarkFrameDescriptor, allocations: Bool = true, _ body: () throws -> Void ) rethrows -> BenchmarkMeasurement?
    {
        let samples = try BenchmarkClock.sample( iterations: self.iterations, warmup: self.warmup, body )

        guard let timings = BenchmarkTimings.from( samples: samples )
        else
        {
            return nil
        }

        let peak = try allocations ? AllocationMeter.peakBytes( during: body ) : nil

        return BenchmarkMeasurement(
            algorithm:           algorithm,
            category:            category,
            frame:               frame,
            timings:             timings,
            peakAllocationBytes: peak
        )
    }
}
