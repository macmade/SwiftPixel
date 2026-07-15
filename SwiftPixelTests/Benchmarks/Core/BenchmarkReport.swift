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

/// A complete benchmark run: a set of measurements plus the metadata needed to
/// interpret and reproduce them.
///
/// This is the top-level type serialized to the baseline JSON. Because real
/// timings vary from run to run, a baseline is a recorded *snapshot* — the
/// metadata records the conditions it was captured under, so a later run's
/// numbers can be compared in context rather than expected to match byte for
/// byte.
struct BenchmarkReport: Codable, Equatable, Sendable
{
    /// The conditions a benchmark run was captured under.
    struct Metadata: Codable, Equatable, Sendable
    {
        /// The module the run covers (e.g. `"SwiftPixel"`).
        let module: String

        /// When the run was captured, as an ISO-8601 timestamp.
        let capturedAt: String

        /// The host machine's model identifier, for context on the numbers.
        let host: String

        /// The operating-system version the run executed on.
        let operatingSystem: String

        /// The build configuration (`"debug"` or `"release"`). Optimized builds
        /// are the only ones whose timings are meaningful for comparison.
        let configuration: String

        /// The number of timed iterations each measurement summarizes.
        let iterations: Int
    }

    /// The conditions this run was captured under.
    let metadata: Metadata

    /// The individual measurements gathered in this run.
    let measurements: [ BenchmarkMeasurement ]
}
