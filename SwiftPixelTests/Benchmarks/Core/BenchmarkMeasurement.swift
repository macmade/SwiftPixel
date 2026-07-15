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

/// A single benchmark result: one algorithm measured over one input frame.
struct BenchmarkMeasurement: Codable, Equatable, Sendable
{
    /// The measured algorithm's display name (e.g. a processor's `name`, or a
    /// primitive's label such as `"Convolution.zeroSumResponse"`).
    let algorithm: String

    /// The group the algorithm belongs to (e.g. `"Processor"`, `"Primitive"`),
    /// used to organize the report.
    let category: String

    /// The frame the algorithm was measured on.
    let frame: BenchmarkFrameDescriptor

    /// The wall-clock statistics gathered over the timed iterations.
    let timings: BenchmarkTimings

    /// The approximate peak memory increase during the operation, in bytes, or
    /// `nil` if allocation measurement was skipped for this run.
    let peakAllocationBytes: Int?
}
