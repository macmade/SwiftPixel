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

struct Test_MarkdownReport
{
    @Test
    func formatsSubMicrosecondAsNanoseconds() async throws
    {
        #expect( MarkdownReport.formattedDuration( nanoseconds: 500 ) == "500 ns" )
    }

    @Test
    func formatsMicroseconds() async throws
    {
        #expect( MarkdownReport.formattedDuration( nanoseconds: 1_500 ) == "1.50 µs" )
    }

    @Test
    func formatsMilliseconds() async throws
    {
        #expect( MarkdownReport.formattedDuration( nanoseconds: 2_000_000 ) == "2.00 ms" )
    }

    @Test
    func formatsSeconds() async throws
    {
        #expect( MarkdownReport.formattedDuration( nanoseconds: 1_500_000_000 ) == "1.50 s" )
    }

    @Test
    func formatsBytesKilobytesMegabytes() async throws
    {
        #expect( MarkdownReport.formattedBytes( 512 )             == "512 B"   )
        #expect( MarkdownReport.formattedBytes( 2_048 )          == "2.00 KB" )
        #expect( MarkdownReport.formattedBytes( 2 * 1_048_576 )  == "2.00 MB" )
    }

    @Test
    func renderIncludesHeaderTableAndRows() async throws
    {
        let markdown = MarkdownReport.render( Self.report() )

        #expect( markdown.contains( "# SwiftPixel — Benchmark baseline" ) )
        #expect( markdown.contains( "| Category | Algorithm | Frame | Min | Median | Max | Peak alloc. |" ) )
        #expect( markdown.contains( "| Processor | Invert | mono-512 |" ) )
    }

    @Test
    func renderShowsDashForMissingPeak() async throws
    {
        let markdown = MarkdownReport.render( Self.report() )
        let dashRow  = markdown.split( separator: "\n" ).first { $0.contains( "| Bin | " ) }

        #expect( try #require( dashRow ).contains( "| — |" ) )
    }

    @Test
    func renderSortsRowsDeterministically() async throws
    {
        let markdown = MarkdownReport.render( Self.report() )
        let binIndex = try #require( markdown.range( of: "| Primitive | Bin |" ) )
        let invIndex = try #require( markdown.range( of: "| Processor | Invert |" ) )

        // "Primitive" sorts before "Processor" by category.
        #expect( binIndex.lowerBound < invIndex.lowerBound )
    }

    static func report() -> BenchmarkReport
    {
        let metadata = BenchmarkReport.Metadata(
            module:          "SwiftPixel",
            capturedAt:      "2026-07-15T12:00:00Z",
            host:            "Mac16,1",
            operatingSystem: "macOS 15.0",
            configuration:   "release",
            iterations:      20
        )

        let mono = BenchmarkFrameDescriptor( name: "mono-512", width: 512, height: 512, channels: 1, layout: "mono", isNormalized: true, notes: "n" )

        let invert = BenchmarkMeasurement(
            algorithm:           "Invert",
            category:            "Processor",
            frame:               mono,
            timings:             BenchmarkTimings( iterations: 20, minNanoseconds: 1_500, medianNanoseconds: 1_800, maxNanoseconds: 2_100 ),
            peakAllocationBytes: 4_096
        )

        let bin = BenchmarkMeasurement(
            algorithm:           "Bin",
            category:            "Primitive",
            frame:               mono,
            timings:             BenchmarkTimings( iterations: 20, minNanoseconds: 900, medianNanoseconds: 950, maxNanoseconds: 1_000 ),
            peakAllocationBytes: nil
        )

        return BenchmarkReport( metadata: metadata, measurements: [ invert, bin ] )
    }
}
