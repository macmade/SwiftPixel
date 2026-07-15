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

struct Test_BenchmarkClock
{
    @Test
    func runsWarmupThenTimedIterations() async throws
    {
        var calls   = 0
        let samples = BenchmarkClock.sample( iterations: 5, warmup: 2 ) { calls += 1 }

        #expect( calls == 7 )
        #expect( samples.count == 5 )
    }

    @Test
    func zeroIterationsStillRunsWarmup() async throws
    {
        var calls   = 0
        let samples = BenchmarkClock.sample( iterations: 0, warmup: 3 ) { calls += 1 }

        #expect( calls == 3 )
        #expect( samples.isEmpty )
    }

    @Test
    func negativeWarmupIsTreatedAsZero() async throws
    {
        var calls = 0

        _ = BenchmarkClock.sample( iterations: 1, warmup: -5 ) { calls += 1 }

        #expect( calls == 1 )
    }

    @Test
    func rethrowsErrorFromBody() async throws
    {
        struct BodyError: Error {}

        #expect( throws: BodyError.self )
        {
            _ = try BenchmarkClock.sample( iterations: 3 ) { throw BodyError() }
        }
    }
}
