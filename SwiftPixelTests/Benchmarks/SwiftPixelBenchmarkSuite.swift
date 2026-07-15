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
@testable import SwiftPixel

/// Assembles and runs the SwiftPixel benchmark matrix — every processor and core
/// primitive over the representative frame set — into a single report.
///
/// Each case runs a repeatable unit of work: processors are applied to a fresh
/// copy of their input frame (a `PixelBuffer` is a value type, so a mutating
/// stage copies on write), and pure primitives are called with precomputed
/// inputs. Every result is passed through ``keep(_:)`` so an optimized build
/// cannot elide the work as dead code.
struct SwiftPixelBenchmarkSuite
{
    private let runner: BenchmarkRunner
    private let frames: BenchmarkFrameSet
    private let allocations: Bool

    /// The number of timed iterations each measurement summarizes.
    var iterations: Int
    {
        self.runner.iterations
    }

    /// Creates a suite.
    ///
    /// - Parameters:
    ///   - frames:      The frame set the cases run over.
    ///   - iterations:  The number of timed iterations per case. Defaults to
    ///                  `20`.
    ///   - warmup:      The number of untimed warmup iterations. Defaults to `3`.
    ///   - allocations: Whether to measure peak allocation. Defaults to `true`;
    ///                  the smoke test disables it to stay fast.
    init( frames: BenchmarkFrameSet, iterations: Int = 20, warmup: Int = 3, allocations: Bool = true )
    {
        self.frames      = frames
        self.runner      = BenchmarkRunner( iterations: iterations, warmup: warmup )
        self.allocations = allocations
    }

    /// Runs the full matrix and packages it with run metadata.
    ///
    /// - Returns: The complete report.
    /// - Throws: Any error raised while building a frame or running a case.
    func report() throws -> BenchmarkReport
    {
        BenchmarkReport(
            metadata:     BenchmarkEnvironment.metadata( module: "SwiftPixel", iterations: self.iterations ),
            measurements: try self.measurements()
        )
    }

    /// Extends the lifetime of a benchmarked result so the optimizer cannot
    /// discard the computation that produced it.
    private func keep< T >( _ value: T )
    {
        withExtendedLifetime( value ) {}
    }

    /// Builds every measurement in the matrix.
    private func measurements() throws -> [ BenchmarkMeasurement ]
    {
        let monoSmall = self.frames.monoSmall
        let monoLarge = self.frames.monoLarge
        let rgb       = self.frames.rgb
        let rawMono   = self.frames.rawMono
        let cfa       = self.frames.cfa

        var results = [ BenchmarkMeasurement ]()

        func record( _ algorithm: String, category: String, frame: BenchmarkFrame, _ body: () throws -> Void ) throws
        {
            if let measurement = try self.runner.measure( algorithm: algorithm, category: category, frame: frame.descriptor, allocations: self.allocations, body )
            {
                results.append( measurement )
            }
        }

        // MARK: Processors

        try record( "Invert", category: "Processor", frame: monoLarge )
        {
            var buffer = monoLarge.buffer

            try Processors.Invert().process( buffer: &buffer )

            self.keep( buffer )
        }

        try record( "BrightnessContrast", category: "Processor", frame: monoLarge )
        {
            var buffer = monoLarge.buffer

            try Processors.BrightnessContrast( brightness: 0.1, contrast: 0.2 ).process( buffer: &buffer )

            self.keep( buffer )
        }

        try record( "CorrectGamma", category: "Processor", frame: monoLarge )
        {
            var buffer = monoLarge.buffer

            try Processors.CorrectGamma( gamma: 2.2 ).process( buffer: &buffer )

            self.keep( buffer )
        }

        try record( "Levels", category: "Processor", frame: monoLarge )
        {
            var buffer     = monoLarge.buffer
            let parameters = Processors.Levels.Parameters( inputBlack: 0.05, inputWhite: 0.95, gamma: 1.1, outputBlack: 0, outputWhite: 1 )

            try Processors.Levels( channels: .uniform( parameters ) ).process( buffer: &buffer )

            self.keep( buffer )
        }

        try record( "Curves", category: "Processor", frame: monoLarge )
        {
            var buffer = monoLarge.buffer
            let curve  = Processors.Curves.Curve( points: [ .init( x: 0, y: 0 ), .init( x: 0.5, y: 0.6 ), .init( x: 1, y: 1 ) ] )

            try Processors.Curves( channels: .uniform( curve ) ).process( buffer: &buffer )

            self.keep( buffer )
        }

        try record( "Stretch", category: "Processor", frame: monoLarge )
        {
            var buffer  = monoLarge.buffer
            let channel = Processors.Stretch.STFParameters.Channel( shadows: 0.1, midtones: 0.4, highlights: 0.9, low: 0, high: 1 )

            try Processors.Stretch( parameters: .uniform( channel ) ).process( buffer: &buffer )

            self.keep( buffer )
        }

        try record( "Normalize", category: "Processor", frame: rawMono )
        {
            var buffer = rawMono.buffer

            try Processors.Normalize( mode: .minMax ).process( buffer: &buffer )

            self.keep( buffer )
        }

        try record( "Scale", category: "Processor", frame: rawMono )
        {
            var buffer = rawMono.buffer

            try Processors.Scale( scale: 1.0 / 65_535.0, offset: 0 ).process( buffer: &buffer )

            self.keep( buffer )
        }

        try record( "MonoToRGB", category: "Processor", frame: rawMono )
        {
            var buffer = rawMono.buffer

            try Processors.MonoToRGB().process( buffer: &buffer )

            self.keep( buffer )
        }

        try record( "Orient", category: "Processor", frame: monoLarge )
        {
            var buffer = monoLarge.buffer

            try Processors.Orient( orientation: .init( rotation: .clockwise90, mirroredHorizontally: false ) ).process( buffer: &buffer )

            self.keep( buffer )
        }

        try record( "Resample", category: "Processor", frame: monoLarge )
        {
            var buffer = monoLarge.buffer

            try Processors.Resample( maxDimension: 512, mode: .average ).process( buffer: &buffer )

            self.keep( buffer )
        }

        try record( "Bin", category: "Processor", frame: rawMono )
        {
            var buffer = rawMono.buffer

            try Processors.Bin( factor: 2 ).process( buffer: &buffer )

            self.keep( buffer )
        }

        try record( "CosmeticCorrection", category: "Processor", frame: rawMono )
        {
            var buffer = rawMono.buffer

            try Processors.CosmeticCorrection( layout: .mono, parameters: .default ).process( buffer: &buffer )

            self.keep( buffer )
        }

        try record( "WhiteBalance", category: "Processor", frame: rgb )
        {
            var buffer = rgb.buffer

            try Processors.WhiteBalance( mode: .auto ).process( buffer: &buffer )

            self.keep( buffer )
        }

        try record( "Hue", category: "Processor", frame: rgb )
        {
            var buffer = rgb.buffer

            try Processors.Hue( angle: 30 ).process( buffer: &buffer )

            self.keep( buffer )
        }

        try record( "Saturation", category: "Processor", frame: rgb )
        {
            var buffer = rgb.buffer

            try Processors.Saturation( saturation: 1.2 ).process( buffer: &buffer )

            self.keep( buffer )
        }

        try record( "ColorBalance", category: "Processor", frame: rgb )
        {
            var buffer = rgb.buffer
            let ranges = Processors.ColorBalance.Ranges(
                shadows:    .init( red: 0.1, green: 0, blue: 0 ),
                midtones:   .init( red: 0, green: 0.05, blue: 0 ),
                highlights: .init( red: 0, green: 0, blue: -0.05 )
            )

            try Processors.ColorBalance( ranges: ranges ).process( buffer: &buffer )

            self.keep( buffer )
        }

        try record( "Debayer (Bilinear)", category: "Processor", frame: cfa )
        {
            var buffer = cfa.buffer

            try Processors.Debayer( mode: .bilinear, pattern: .rggb ).process( buffer: &buffer )

            self.keep( buffer )
        }

        try record( "Debayer (VNG)", category: "Processor", frame: cfa )
        {
            var buffer = cfa.buffer

            try Processors.Debayer( mode: .vng, pattern: .rggb ).process( buffer: &buffer )

            self.keep( buffer )
        }

        // MARK: Core primitives

        let kernel = GaussianKernel( sigma: 2 )

        try record( "Convolution.zeroSumResponse", category: "Primitive", frame: monoLarge )
        {
            self.keep( Convolution.zeroSumResponse( of: monoLarge.buffer, kernel: kernel ) )
        }

        let histogramBytes = try monoLarge.buffer.convertTo8Bits()

        try record( "Histogram", category: "Primitive", frame: monoLarge )
        {
            self.keep( Histogram( bytes: histogramBytes, channels: 1, mode: .mono ) )
        }

        let histogramData = Histogram( bytes: histogramBytes, channels: 1, mode: .mono ).data[ 0 ]

        try record( "HistogramStatistics", category: "Primitive", frame: monoLarge )
        {
            self.keep( HistogramStatistics( data: histogramData ) )
        }

        try record( "PixelUtilities.median", category: "Primitive", frame: monoLarge )
        {
            self.keep( PixelUtilities.median( monoLarge.buffer.pixels ) )
        }

        let median = PixelUtilities.median( monoLarge.buffer.pixels ) ?? 0

        try record( "PixelUtilities.medianAbsoluteDeviation", category: "Primitive", frame: monoLarge )
        {
            self.keep( PixelUtilities.medianAbsoluteDeviation( monoLarge.buffer.pixels, around: median ) )
        }

        try record( "PixelUtilities.percentileBounds", category: "Primitive", frame: monoLarge )
        {
            self.keep( PixelUtilities.percentileBounds( in: monoLarge.buffer.pixels, lower: 0.25, upper: 0.99 ) )
        }

        let plane = monoLarge.buffer.pixels

        try record( "PixelUtilities.interleave", category: "Primitive", frame: monoLarge )
        {
            self.keep( try PixelUtilities.interleave( planes: [ plane, plane, plane ] ) )
        }

        let rawData = Data( count: monoLarge.descriptor.pixelCount * 2 )

        try record( "PixelUtilities.readRawPixels", category: "Primitive", frame: monoLarge )
        {
            self.keep( try PixelUtilities.readRawPixels( data: rawData, width: monoLarge.descriptor.width, height: monoLarge.descriptor.height, bitsPerPixel: .int16 ) )
        }

        try record( "GaussianKernel(sigma:)", category: "Primitive", frame: monoSmall )
        {
            self.keep( GaussianKernel( sigma: 3 ) )
        }

        let fitSamples = Self.gaussianSamples()
        let fitGuess   = GaussianFit.Parameters( amplitude: 3_000, x: 0, y: 0, sigmaX: 2, sigmaY: 2, theta: 0, background: 200 )

        try record( "GaussianFit.fit", category: "Primitive", frame: monoSmall )
        {
            self.keep( GaussianFit.fit( samples: fitSamples, initialGuess: fitGuess ) )
        }

        return results
    }

    /// Builds a synthetic 15×15 Gaussian star patch for the ``GaussianFit.fit``
    /// benchmark: a peak of 3000 over a background of 200 with σ = 2.
    private static func gaussianSamples() -> [ ( x: Double, y: Double, value: Double ) ]
    {
        let radius = 7

        return ( -radius ... radius ).flatMap
        {
            dy in

            ( -radius ... radius ).map
            {
                dx -> ( x: Double, y: Double, value: Double ) in

                let squared = Double( ( dx * dx ) + ( dy * dy ) )
                let value   = 200.0 + ( 3_000.0 * exp( -squared / ( 2.0 * 4.0 ) ) )

                return ( x: Double( dx ), y: Double( dy ), value: value )
            }
        }
    }
}
