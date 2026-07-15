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

import Darwin
import Foundation

/// Captures the conditions a benchmark run executes under, so the baseline
/// records what its numbers should be read against.
enum BenchmarkEnvironment
{
    /// Builds the metadata block for a run.
    ///
    /// - Parameters:
    ///   - module:     The module being benchmarked (e.g. `"SwiftPixel"`).
    ///   - iterations: The number of timed iterations each measurement
    ///                 summarizes.
    /// - Returns: The populated metadata.
    static func metadata( module: String, iterations: Int ) -> BenchmarkReport.Metadata
    {
        BenchmarkReport.Metadata(
            module:          module,
            capturedAt:      Self.timestamp(),
            host:            Self.hardwareModel(),
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            configuration:   Self.configuration,
            iterations:      iterations
        )
    }

    /// The build configuration the harness was compiled with. Only `release`
    /// numbers are meaningful for comparison.
    static var configuration: String
    {
        #if DEBUG

            return "debug"

        #else

            return "release"

        #endif
    }

    /// The current time as an ISO-8601 timestamp.
    static func timestamp() -> String
    {
        ISO8601DateFormatter().string( from: Date() )
    }

    /// The host machine's model identifier (e.g. `"Mac16,1"`), or `"unknown"` if
    /// it cannot be read.
    static func hardwareModel() -> String
    {
        var size = 0

        guard sysctlbyname( "hw.model", nil, &size, nil, 0 ) == 0, size > 0
        else
        {
            return "unknown"
        }

        var bytes = [ UInt8 ]( repeating: 0, count: size )

        guard sysctlbyname( "hw.model", &bytes, &size, nil, 0 ) == 0
        else
        {
            return "unknown"
        }

        // `sysctlbyname` returns a null-terminated C string; drop the trailing
        // null (and any padding) before decoding.
        return String( decoding: bytes.prefix { $0 != 0 }, as: UTF8.self )
    }
}
