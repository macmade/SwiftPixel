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

struct Test_BenchmarkOutput
{
    @Test
    func usesOverrideDirectoryWhenSet() async throws
    {
        let resolved = BenchmarkOutput.outputDirectory(
            environment: [ BenchmarkOutput.environmentKey: "/tmp/benchmarks" ],
            default:      URL( fileURLWithPath: "/default", isDirectory: true )
        )

        #expect( resolved.path == "/tmp/benchmarks" )
    }

    @Test
    func usesDefaultWhenOverrideAbsent() async throws
    {
        let fallback = URL( fileURLWithPath: "/default", isDirectory: true )
        let resolved = BenchmarkOutput.outputDirectory( environment: [ : ], default: fallback )

        #expect( resolved == fallback )
    }

    @Test
    func usesDefaultWhenOverrideEmpty() async throws
    {
        let fallback = URL( fileURLWithPath: "/default", isDirectory: true )
        let resolved = BenchmarkOutput.outputDirectory( environment: [ BenchmarkOutput.environmentKey: "" ], default: fallback )

        #expect( resolved == fallback )
    }

    @Test
    func writesJSONAndMarkdownThatDecodeBack() async throws
    {
        let directory = URL( fileURLWithPath: NSTemporaryDirectory() ).appendingPathComponent( "swiftpixel-bench-\( UUID().uuidString )", isDirectory: true )

        defer
        {
            try? FileManager.default.removeItem( at: directory )
        }

        let report = Test_MarkdownReport.report()
        let urls   = try BenchmarkOutput.write( report: report, baseName: "swiftpixel-baseline", to: directory )

        #expect( FileManager.default.fileExists( atPath: urls.json.path ) )
        #expect( FileManager.default.fileExists( atPath: urls.markdown.path ) )

        let decoded = try JSONDecoder().decode( BenchmarkReport.self, from: try Data( contentsOf: urls.json ) )

        #expect( decoded == report )

        let markdown = try String( contentsOf: urls.markdown, encoding: .utf8 )

        #expect( markdown.contains( "Benchmark baseline" ) )
    }
}
