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

/// Memory accounting is sampled and best-effort, so these tests only assert the
/// meter's contract — non-negative, non-crashing, error-propagating — never
/// exact byte counts.
struct Test_AllocationMeter
{
    @Test
    func currentAllocatedBytesIsPositive() async throws
    {
        #expect( AllocationMeter.currentAllocatedBytes() > 0 )
    }

    @Test
    func peakBytesIsNonNegative() async throws
    {
        let peak = AllocationMeter.peakBytes
        {
            var buffer = [ Int ]( repeating: 0, count: 2_000_000 )

            buffer[ buffer.count - 1 ] = 1

            _ = buffer.reduce( 0, + )
        }

        #expect( peak >= 0 )
    }

    @Test
    func peakBytesRethrowsErrorFromBody() async throws
    {
        struct BodyError: Error {}

        #expect( throws: BodyError.self )
        {
            _ = try AllocationMeter.peakBytes { throw BodyError() }
        }
    }
}
