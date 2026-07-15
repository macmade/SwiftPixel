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

/// The opt-in benchmark entry point.
///
/// This measurement is intentionally excluded from ordinary test runs — it is
/// slow and its numbers are only meaningful in an optimized build — so it runs
/// only when the `RUN_BENCHMARKS` environment variable is set. Because
/// `xcodebuild` does not forward the parent environment to the test host, capture
/// a baseline through SwiftPM:
///
/// ```
/// RUN_BENCHMARKS=1 swift test -c release --filter Test_SwiftPixelBenchmarks
/// ```
///
/// The baseline is written to `SwiftPixel/Docs/Benchmarks` by default, or to the
/// directory named by `FITSCOPE_BENCH_OUT` when that variable is set. See the
/// "Benchmarks" section of the SwiftPixel README for details.
struct Test_SwiftPixelBenchmarks
{
    @Test( .enabled( if: ProcessInfo.processInfo.environment[ "RUN_BENCHMARKS" ] != nil ) )
    func captureBaseline() async throws
    {
        let suite     = SwiftPixelBenchmarkSuite( frames: try BenchmarkFrames.representative() )
        let report    = try suite.report()
        let directory = BenchmarkOutput.outputDirectory(
            environment: ProcessInfo.processInfo.environment,
            default:     Self.defaultOutputDirectory()
        )
        let urls = try BenchmarkOutput.write( report: report, baseName: "swiftpixel-baseline", to: directory )

        print( "SwiftPixel benchmark baseline written to:" )
        print( "  \( urls.json.path )" )
        print( "  \( urls.markdown.path )" )
    }

    /// The default baseline directory: `SwiftPixel/Docs/Benchmarks`, resolved
    /// relative to this source file so it works under both `swift test` and the
    /// Xcode test target, and in a standalone checkout of the submodule.
    static func defaultOutputDirectory() -> URL
    {
        URL( fileURLWithPath: #filePath )
            .deletingLastPathComponent() // Benchmarks/
            .deletingLastPathComponent() // SwiftPixelTests/
            .deletingLastPathComponent() // repository root
            .appendingPathComponent( "Docs/Benchmarks", isDirectory: true )
    }
}
