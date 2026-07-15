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

/// Renders a ``BenchmarkReport`` as a human-readable Markdown document.
///
/// The output is deterministic — measurements are sorted by category, then
/// algorithm, then frame — so re-running the harness produces a clean,
/// reviewable diff in which only the numbers move.
enum MarkdownReport
{
    /// Renders the report to a Markdown string with a metadata header and a
    /// results table.
    ///
    /// - Parameter report: The report to render.
    /// - Returns: The Markdown document.
    static func render( _ report: BenchmarkReport ) -> String
    {
        var lines = [ String ]()

        lines.append( "# \( report.metadata.module ) — Benchmark baseline" )
        lines.append( "" )
        lines.append( "| Field | Value |" )
        lines.append( "| --- | --- |" )
        lines.append( "| Captured | \( report.metadata.capturedAt ) |" )
        lines.append( "| Host | \( report.metadata.host ) |" )
        lines.append( "| OS | \( report.metadata.operatingSystem ) |" )
        lines.append( "| Configuration | \( report.metadata.configuration ) |" )
        lines.append( "| Iterations | \( report.metadata.iterations ) |" )
        lines.append( "| Measurements | \( report.measurements.count ) |" )
        lines.append( "" )
        lines.append( "Timings are wall-clock per iteration; **min** is the least noisy estimate of intrinsic cost. Peak allocation is an approximate, best-effort figure (see the project README)." )
        lines.append( "" )
        lines.append( "| Category | Algorithm | Frame | Min | Median | Max | Peak alloc. |" )
        lines.append( "| --- | --- | --- | ---: | ---: | ---: | ---: |" )

        let sorted = report.measurements.sorted
        {
            ( $0.category, $0.algorithm, $0.frame.name ) < ( $1.category, $1.algorithm, $1.frame.name )
        }

        sorted.forEach
        {
            let peak = $0.peakAllocationBytes.map { Self.formattedBytes( $0 ) } ?? "—"

            lines.append(
                "| \( $0.category ) | \( $0.algorithm ) | \( $0.frame.name ) | \( Self.formattedDuration( nanoseconds: $0.timings.minNanoseconds ) ) | \( Self.formattedDuration( nanoseconds: $0.timings.medianNanoseconds ) ) | \( Self.formattedDuration( nanoseconds: $0.timings.maxNanoseconds ) ) | \( peak ) |"
            )
        }

        lines.append( "" )

        return lines.joined( separator: "\n" )
    }

    /// Formats a nanosecond duration into the most readable unit (ns, µs, ms, or
    /// s), with two decimal places above the nanosecond floor.
    ///
    /// - Parameter nanoseconds: The duration to format.
    /// - Returns: A human-readable duration string.
    static func formattedDuration( nanoseconds: UInt64 ) -> String
    {
        let value = Double( nanoseconds )

        if value < 1_000
        {
            return "\( nanoseconds ) ns"
        }
        else if value < 1_000_000
        {
            return Self.decimal( value / 1_000, unit: "µs" )
        }
        else if value < 1_000_000_000
        {
            return Self.decimal( value / 1_000_000, unit: "ms" )
        }
        else
        {
            return Self.decimal( value / 1_000_000_000, unit: "s" )
        }
    }

    /// Formats a byte count into the most readable binary unit (B, KB, MB, or
    /// GB).
    ///
    /// - Parameter bytes: The byte count to format.
    /// - Returns: A human-readable size string.
    static func formattedBytes( _ bytes: Int ) -> String
    {
        let value = Double( bytes )

        if value < 1_024
        {
            return "\( bytes ) B"
        }
        else if value < 1_048_576
        {
            return Self.decimal( value / 1_024, unit: "KB" )
        }
        else if value < 1_073_741_824
        {
            return Self.decimal( value / 1_048_576, unit: "MB" )
        }
        else
        {
            return Self.decimal( value / 1_073_741_824, unit: "GB" )
        }
    }

    /// Formats a value to two decimal places with a trailing unit, using a fixed
    /// POSIX locale so the decimal separator is always `.` — keeping the
    /// committed baseline reproducible regardless of the machine's locale.
    ///
    /// - Parameters:
    ///   - value: The value to format.
    ///   - unit:  The unit appended after the number.
    /// - Returns: The formatted `"<value> <unit>"` string.
    private static func decimal( _ value: Double, unit: String ) -> String
    {
        String( format: "%.2f \( unit )", locale: Self.posixLocale, value )
    }

    /// The fixed locale used for all numeric formatting in reports.
    private static let posixLocale = Locale( identifier: "en_US_POSIX" )
}
