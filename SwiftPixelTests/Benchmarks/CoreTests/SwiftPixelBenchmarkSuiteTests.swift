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
import Testing

/// Smoke test for the benchmark matrix itself: it runs the whole suite once, at
/// a single iteration and with allocation measurement off, to confirm every case
/// executes over a compatible frame without throwing. This guards against a case
/// being wired to the wrong frame (e.g. a normalized-only processor over a raw
/// frame), which the opt-in ``Test_SwiftPixelBenchmarks`` would otherwise be the
/// first to hit.
struct Test_SwiftPixelBenchmarkSuite
{
    @Test
    func runsEveryCaseWithoutThrowing() async throws
    {
        let suite  = SwiftPixelBenchmarkSuite( frames: try BenchmarkFrames.tiny(), iterations: 1, warmup: 0, allocations: false )
        let report = try suite.report()

        #expect( report.metadata.module == "SwiftPixel" )
        #expect( report.measurements.isEmpty == false )
        #expect( report.measurements.allSatisfy { $0.timings.iterations == 1 } )
    }
}
