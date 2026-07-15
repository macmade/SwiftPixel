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

/// Resolves where a baseline is written and serializes it there as JSON and
/// Markdown.
enum BenchmarkOutput
{
    /// The environment variable that overrides the output directory.
    ///
    /// When set to a non-empty path, the baseline is written there instead of the
    /// default location — the mechanism used to capture the baseline into a
    /// plan's folder without coupling the submodule to any superproject layout.
    static let environmentKey = "FITSCOPE_BENCH_OUT"

    /// Resolves the output directory: the `FITSCOPE_BENCH_OUT` override if it is
    /// set and non-empty, otherwise `defaultDirectory`.
    ///
    /// A tilde in the override is expanded, so `~/…` works from a shell.
    ///
    /// - Parameters:
    ///   - environment:      The environment to read the override from.
    ///   - defaultDirectory: The directory used when no override is set.
    /// - Returns: The directory the baseline should be written to.
    static func outputDirectory( environment: [ String: String ], default defaultDirectory: URL ) -> URL
    {
        guard let override = environment[ self.environmentKey ], override.isEmpty == false
        else
        {
            return defaultDirectory
        }

        return URL( fileURLWithPath: ( override as NSString ).expandingTildeInPath, isDirectory: true )
    }

    /// Writes the report to `directory` as `<baseName>.json` and
    /// `<baseName>.md`, creating the directory if needed.
    ///
    /// The JSON is pretty-printed with sorted keys so it stays diff-friendly, and
    /// both files are written atomically.
    ///
    /// - Parameters:
    ///   - report:    The report to serialize.
    ///   - baseName:  The base file name shared by both outputs.
    ///   - directory: The destination directory.
    /// - Returns: The URLs of the written JSON and Markdown files.
    /// - Throws: Any error raised while creating the directory or writing a file.
    @discardableResult
    static func write( report: BenchmarkReport, baseName: String, to directory: URL ) throws -> ( json: URL, markdown: URL )
    {
        try FileManager.default.createDirectory( at: directory, withIntermediateDirectories: true )

        let encoder = JSONEncoder()

        encoder.outputFormatting = [ .prettyPrinted, .sortedKeys ]

        let jsonURL = directory.appendingPathComponent( "\( baseName ).json" )
        let mdURL   = directory.appendingPathComponent( "\( baseName ).md"   )

        try encoder.encode( report ).write( to: jsonURL, options: .atomic )
        try Data( MarkdownReport.render( report ).utf8 ).write( to: mdURL, options: .atomic )

        return ( json: jsonURL, markdown: mdURL )
    }
}
