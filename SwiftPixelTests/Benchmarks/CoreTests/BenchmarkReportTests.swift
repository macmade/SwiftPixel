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

struct Test_BenchmarkReport
{
    static func frame() -> BenchmarkFrameDescriptor
    {
        BenchmarkFrameDescriptor( name: "mono-2", width: 2, height: 2, channels: 1, layout: "mono", isNormalized: true, notes: "sample" )
    }

    static func measurement( peak: Int? ) throws -> BenchmarkMeasurement
    {
        BenchmarkMeasurement(
            algorithm:           "Invert",
            category:            "Processor",
            frame:               Self.frame(),
            timings:             try #require( BenchmarkTimings.from( samples: [ 10, 20, 30 ] ) ),
            peakAllocationBytes: peak
        )
    }

    @Test
    func measurementRoundTripsThroughJSON() async throws
    {
        let original = try Self.measurement( peak: 4_096 )
        let data     = try JSONEncoder().encode( original )
        let decoded  = try JSONDecoder().decode( BenchmarkMeasurement.self, from: data )

        #expect( decoded == original )
    }

    @Test
    func measurementWithoutPeakRoundTripsThroughJSON() async throws
    {
        let original = try Self.measurement( peak: nil )
        let data     = try JSONEncoder().encode( original )
        let decoded  = try JSONDecoder().decode( BenchmarkMeasurement.self, from: data )

        #expect( decoded == original )
        #expect( decoded.peakAllocationBytes == nil )
    }

    @Test
    func reportRoundTripsThroughJSON() async throws
    {
        let metadata = BenchmarkReport.Metadata(
            module:          "SwiftPixel",
            capturedAt:      "2026-07-15T12:00:00Z",
            host:            "Mac16,1",
            operatingSystem: "macOS 15.0",
            configuration:   "release",
            iterations:      20
        )
        let original = BenchmarkReport( metadata: metadata, measurements: [ try Self.measurement( peak: 1_024 ), try Self.measurement( peak: nil ) ] )
        let data     = try JSONEncoder().encode( original )
        let decoded  = try JSONDecoder().decode( BenchmarkReport.self, from: data )

        #expect( decoded == original )
    }

    @Test
    func descriptorDerivesCounts() async throws
    {
        let descriptor = BenchmarkFrameDescriptor( name: "rgb", width: 4, height: 3, channels: 3, layout: "rgb", isNormalized: true, notes: "n" )

        #expect( descriptor.pixelCount  == 12 )
        #expect( descriptor.sampleCount == 36 )
    }
}
