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
import SwiftUtilities

/// A configurable image-processing pipeline that decodes raw pixels and applies
/// an ordered chain of processors.
///
/// The stage order is fixed and enforces each processor's preconditions: scale,
/// then demosaic to RGB, then normalize, then the normalization-dependent stages
/// (stretch, gamma, white balance, invert). A default normalization is inserted
/// automatically when a normalization-dependent stage is requested without one.
public struct PixelPipeline: Sendable
{
    /// Declarative description of which stages to run and how.
    ///
    /// Each optional property enables the corresponding stage when non-`nil`.
    /// The pipeline applies them in a fixed order regardless of declaration
    /// order; see `PixelPipeline`.
    public struct Config: Sendable
    {
        /// Affine scaling applied to the raw samples (`scale`, `offset`).
        public let scale: ( scale: Double, offset: Double )?

        /// The Bayer pattern to demosaic and the demosaicing mode to use; when
        /// `nil`, mono is expanded to RGB.
        public let debayer: ( pattern: Processors.Debayer.Pattern, mode: Processors.Debayer.Mode )?

        /// The normalization mode. May be inserted automatically (as `.minMax`)
        /// when a normalization-dependent stage is requested without one.
        public let normalize: Processors.Normalize.Mode?

        /// The tone-stretch algorithm. Requires normalization.
        public let stretch: Processors.Stretch.Algorithm?

        /// The gamma exponent for gamma correction. Requires normalization.
        public let correctGamma: Double?

        /// The white-balance mode. Requires normalization.
        public let whiteBalance: Processors.WhiteBalance.Mode?

        /// Whether to invert the image (photographic negative). Requires
        /// normalization.
        public let invert: Bool

        /// The net orientation (rotation + optional mirror) to apply, or `nil`
        /// to leave the image as captured. Applied last, as a pure geometry
        /// permutation.
        public let orient: Processors.Orient.Orientation?

        /// Whether to emit per-stage timing measurements. Off by default.
        public let benchmark: Bool

        /// The sink for benchmarking output when `benchmark` is `true`; falls
        /// back to printing to standard output when `nil`.
        public let benchmarkOutput: ( @Sendable ( String ) -> Void )?

        /// Creates a pipeline configuration.
        ///
        /// - Parameters:
        ///   - scale:           Optional affine scaling of the raw samples. Defaults to `nil`.
        ///   - debayer:         Optional Bayer pattern and demosaicing mode; `nil` expands mono to RGB. Defaults to `nil`.
        ///   - normalize:       Optional normalization mode. Defaults to `nil`.
        ///   - stretch:         Optional tone-stretch algorithm. Defaults to `nil`.
        ///   - correctGamma:    Optional gamma exponent. Defaults to `nil`.
        ///   - whiteBalance:    Optional white-balance mode. Defaults to `nil`.
        ///   - invert:          Whether to invert the image. Defaults to `false`.
        ///   - orient:          Optional net orientation to apply last. Defaults to `nil`.
        ///   - benchmark:       Whether to emit per-stage timings. Defaults to `false`.
        ///   - benchmarkOutput: Optional sink for timing output. Defaults to `nil` (prints).
        public init( scale: ( scale: Double, offset: Double )? = nil, debayer: ( pattern: Processors.Debayer.Pattern, mode: Processors.Debayer.Mode )? = nil, normalize: Processors.Normalize.Mode? = nil, stretch: Processors.Stretch.Algorithm? = nil, correctGamma: Double? = nil, whiteBalance: Processors.WhiteBalance.Mode? = nil, invert: Bool = false, orient: Processors.Orient.Orientation? = nil, benchmark: Bool = false, benchmarkOutput: ( @Sendable ( String ) -> Void )? = nil )
        {
            self.scale           = scale
            self.debayer         = debayer
            self.normalize       = normalize
            self.stretch         = stretch
            self.correctGamma    = correctGamma
            self.whiteBalance    = whiteBalance
            self.invert          = invert
            self.orient          = orient
            self.benchmark       = benchmark
            self.benchmarkOutput = benchmarkOutput
        }
    }

    /// The configuration driving this pipeline.
    public let config: Config

    /// Creates a pipeline with the given configuration.
    ///
    /// - Parameter config: The stages to run and how.
    public init( config: Config )
    {
        self.config = config
    }

    /// Decodes raw bytes and runs the pipeline over them.
    ///
    /// - Parameters:
    ///   - data:         The raw, single-channel sample bytes.
    ///   - width:        The image width in pixels.
    ///   - height:       The image height in pixels.
    ///   - bitsPerPixel: The sample format of `data`.
    ///
    /// - Returns: The processed buffer.
    ///
    /// - Throws: A `RuntimeError` if decoding fails or any stage fails.
    public func run( data: Data, width: Int, height: Int, bitsPerPixel: BitsPerPixel ) throws -> PixelBuffer
    {
        let pixels = try PixelUtilities.readRawPixels( data: data, width: width, height: height, bitsPerPixel: bitsPerPixel )

        return try self.run( pixels: pixels, width: width, height: height, bitsPerPixel: bitsPerPixel )
    }

    /// Runs the pipeline over already-decoded single-channel samples.
    ///
    /// - Parameters:
    ///   - pixels:       The single-channel samples, in row-major order.
    ///   - width:        The image width in pixels.
    ///   - height:       The image height in pixels.
    ///   - bitsPerPixel: The original sample format (informational).
    ///
    /// - Returns: The processed buffer.
    ///
    /// - Throws: A `RuntimeError` if the geometry is inconsistent or any stage
    ///           fails.
    public func run( pixels: [ Double ], width: Int, height: Int, bitsPerPixel: BitsPerPixel ) throws -> PixelBuffer
    {
        var buffer = try PixelBuffer( width: width, height: height, channels: 1, pixels: pixels, isNormalized: false )

        let output: ( String ) -> Void

        if self.config.benchmark
        {
            output = self.config.benchmarkOutput ?? { print( $0 ) }
        }
        else
        {
            output = { _ in }
        }

        try self.processors().forEach
        {
            processor in try Benchmark.run( label: processor.description, output: output )
            {
                try processor.process( buffer: &buffer )
            }
        }

        return buffer
    }

    /// Builds the ordered processor chain for the configuration.
    ///
    /// The order is fixed and enforces the processors' preconditions: raw
    /// scaling, then demosaicing to RGB, then normalization, then the stages
    /// that require a normalized buffer (stretch, gamma, white balance, invert).
    ///
    /// Stretch, gamma correction, white balance and invert all require a
    /// normalized buffer. If any of them is requested without an explicit
    /// normalization mode, a default min/max Normalize is inserted automatically
    /// so the configuration cannot produce a "buffer needs to be normalized"
    /// failure.
    ///
    /// - Returns: The processors to apply, in execution order.
    func processors() -> [ PixelProcessor ]
    {
        var processors = [ PixelProcessor ]()

        if let scale = self.config.scale
        {
            processors.append( Processors.Scale( scale: scale.scale, offset: scale.offset ) )
        }

        if let debayer = self.config.debayer
        {
            processors.append( Processors.Debayer( mode: debayer.mode, pattern: debayer.pattern ) )
        }
        else
        {
            processors.append( Processors.MonoToRGB() )
        }

        let requiresNormalization = self.config.stretch != nil || self.config.correctGamma != nil || self.config.whiteBalance != nil || self.config.invert
        let normalizeMode: Processors.Normalize.Mode?

        if let configured = self.config.normalize
        {
            normalizeMode = configured
        }
        else if requiresNormalization
        {
            normalizeMode = .minMax
        }
        else
        {
            normalizeMode = nil
        }

        if let normalizeMode
        {
            processors.append( Processors.Normalize( mode: normalizeMode ) )
        }

        if let stretch = self.config.stretch
        {
            processors.append( Processors.Stretch( algorithm: stretch ) )
        }

        if let correctGamma = self.config.correctGamma
        {
            processors.append( Processors.CorrectGamma( gamma: correctGamma ) )
        }

        if let whiteBalance = self.config.whiteBalance
        {
            processors.append( Processors.WhiteBalance( mode: whiteBalance ) )
        }

        if self.config.invert
        {
            processors.append( Processors.Invert() )
        }

        // Orientation is a pure geometry permutation independent of the value
        // stages, so it runs last. An identity orientation is skipped.
        if let orient = self.config.orient, orient.isIdentity == false
        {
            processors.append( Processors.Orient( orientation: orient ) )
        }

        return processors
    }
}
