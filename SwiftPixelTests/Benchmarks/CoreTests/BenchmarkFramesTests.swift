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

struct Test_BenchmarkFrames
{
    @Test
    func everyFrameMatchesItsDescriptor() async throws
    {
        // The descriptor-derivation logic is size-independent, so the tiny set
        // exercises the same code path without building full-size frames.
        try BenchmarkFrames.tiny().all.forEach
        {
            #expect( $0.buffer.width        == $0.descriptor.width )
            #expect( $0.buffer.height       == $0.descriptor.height )
            #expect( $0.buffer.channels     == $0.descriptor.channels )
            #expect( $0.buffer.isNormalized == $0.descriptor.isNormalized )
            #expect( $0.buffer.pixels.count == $0.descriptor.sampleCount )
        }
    }

    @Test
    func frameNamesAreUnique() async throws
    {
        let names = try BenchmarkFrames.tiny().all.map { $0.descriptor.name }

        #expect( Set( names ).count == names.count )
    }

    @Test
    func generationIsDeterministic() async throws
    {
        let first  = try BenchmarkFrames.tiny().monoSmall
        let second = try BenchmarkFrames.tiny().monoSmall

        #expect( first.buffer.pixels == second.buffer.pixels )
    }

    @Test
    func normalizedFramesStayInUnitRange() async throws
    {
        let frame = try BenchmarkFrames.tiny().monoSmall

        #expect( frame.buffer.isNormalized )
        #expect( frame.buffer.pixels.allSatisfy { $0 >= 0.0 && $0 <= 1.0 } )
    }

    @Test
    func rawFramesSpanTheADURange() async throws
    {
        let frame = try BenchmarkFrames.tiny().rawMono

        #expect( frame.buffer.isNormalized == false )
        #expect( frame.buffer.pixels.allSatisfy { $0 >= 0.0 && $0 <= 65_535.0 } )
        #expect( frame.buffer.pixels.contains { $0 > 1.0 } )
    }

    @Test
    func frameContentIsNotConstant() async throws
    {
        let pixels = try BenchmarkFrames.tiny().monoSmall.buffer.pixels

        #expect( Set( pixels ).count > 1 )
    }

    @Test
    func tinyFramesShareLayoutsWithRepresentative() async throws
    {
        let representative = try BenchmarkFrames.representative()
        let tiny           = try BenchmarkFrames.tiny()

        #expect( tiny.all.count == representative.all.count )

        zip( tiny.all, representative.all ).forEach
        {
            #expect( $0.0.descriptor.channels     == $0.1.descriptor.channels )
            #expect( $0.0.descriptor.isNormalized == $0.1.descriptor.isNormalized )
            #expect( $0.0.descriptor.layout       == $0.1.descriptor.layout )
            #expect( $0.0.buffer.width < $0.1.buffer.width )
        }
    }
}
