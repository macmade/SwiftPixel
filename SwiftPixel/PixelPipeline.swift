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

/// A configurable image-processing pipeline that decodes raw pixels and applies
/// an ordered chain of processors.
///
/// The stage order is fixed and enforces each processor's preconditions: scale,
/// then demosaic to RGB, then normalize, then the normalization-dependent
/// stages. Those run in two groups around the non-linear stretch: white balance
/// as a linear colour calibration before the stretch, then the stretch, then the
/// display-referred stages on the stretched image (brightness/contrast, gamma,
/// levels, curves, colour balance, hue, saturation, invert), with orientation
/// last. A default normalization is inserted automatically when a
/// normalization-dependent stage is requested without one.
public struct PixelPipeline: Sendable
{
    /// Declarative description of which stages to run and how.
    ///
    /// Each optional property enables the corresponding stage when non-`nil`.
    /// The pipeline applies them in a fixed order regardless of declaration
    /// order; see `PixelPipeline`.
    public struct Config: Sendable
    {
        /// How the pipeline's input samples are laid out, which determines the
        /// channel-forming stage: a single-channel monochrome frame is expanded
        /// to RGB, a single-channel colour-filter-array frame is demosaiced, and
        /// an already-interleaved RGB frame is passed through untouched.
        public enum InputFormat: Sendable, Equatable
        {
            /// A single-channel monochrome frame, expanded to RGB.
            case mono

            /// A single-channel colour-filter-array frame, demosaiced to RGB with
            /// the given Bayer pattern and demosaicing mode.
            case cfa( pattern: Processors.Debayer.Pattern, mode: Processors.Debayer.Mode )

            /// An already-interleaved three-channel RGB frame, passed through with
            /// no channel-forming stage.
            case rgb

            /// The number of interleaved channels the input samples carry: one for
            /// ``mono`` and ``cfa`` (a single mosaic/luminance channel), three for
            /// ``rgb``.
            public var channels: Int
            {
                switch self
                {
                    case .mono: return 1
                    case .cfa:  return 1
                    case .rgb:  return 3
                }
            }
        }

        /// Affine scaling applied to the raw samples (`scale`, `offset`).
        public let scale: ( scale: Double, offset: Double )?

        /// How the input samples are laid out, selecting the channel-forming
        /// stage: mono is expanded to RGB, a colour-filter array is demosaiced,
        /// and an already-interleaved RGB frame is passed through untouched.
        public let inputFormat: InputFormat

        /// The largest dimension the rendered image may take, or `nil` to render at
        /// full resolution. When set, a box-averaging downsample runs immediately
        /// after the channel-forming stage (on co-located RGB, so it is safe for a
        /// colour-filter-array source too), shrinking the image before the
        /// per-pixel stages so a small preview costs a fraction of a full render.
        /// The full-resolution app render leaves this `nil`.
        public let maxDimension: Int?

        /// The factor by which to bin the raw single-channel mosaic *before* the
        /// demosaic; one (the default) skips binning. A ``Processors/Bin`` stage runs
        /// before channel-forming (only for a single-channel input), averaging
        /// same-colour sites so a colour-filter-array frame stays phase-aligned, so
        /// the expensive debayer then runs on a `factor²`-smaller mosaic. Set above
        /// one only when heavily downsampling a mosaic preview; the full-resolution
        /// app render leaves it at one.
        public let binFactor: Int

        /// The cosmetic-correction (hot/cold pixel repair) parameters, or `nil` to
        /// skip the stage. Applied to the raw samples, before the channel-forming
        /// stage, so a defect is repaired before demosaicing can smear it across
        /// its neighbours; its ``Processors/CosmeticCorrection/Layout`` is derived
        /// from ``inputFormat``. Operates on raw samples and never forces
        /// normalization.
        public let cosmeticCorrection: Processors.CosmeticCorrection.Parameters?

        /// The normalization mode. May be inserted automatically (as `.minMax`)
        /// when a normalization-dependent stage is requested without one.
        public let normalize: Processors.Normalize.Mode?

        /// The Screen Transfer parameters, or `nil` for no stretch. Requires
        /// normalization.
        public let stretch: Processors.Stretch.STFParameters?

        /// The gamma exponent for gamma correction. Requires normalization.
        public let correctGamma: Double?

        /// The white-balance mode. Requires normalization; applied before the
        /// stretch, as a linear per-channel colour calibration.
        public let whiteBalance: Processors.WhiteBalance.Mode?

        /// The brightness offset and contrast factor, or `nil` to leave both at
        /// their neutral values. Requires normalization; a display-referred
        /// adjustment applied after the stretch, before gamma.
        public let brightnessContrast: ( brightness: Double, contrast: Double )?

        /// The levels remap to apply, or `nil` to leave the tones untouched.
        /// Requires normalization; a parametric tone remap applied after the
        /// stretch, on the display-referred image.
        public let levels: Processors.Levels.Channels?

        /// The tone curve to apply, or `nil` to leave the tones untouched.
        /// Requires normalization; applied right after levels, on the
        /// display-referred image.
        public let curves: Processors.Curves.Channels?

        /// The tonal-range colour balance to apply, or `nil` to leave the
        /// channels untouched. Requires normalization; a display-referred colour
        /// grade applied after the tone stages, before hue and saturation.
        public let colorBalance: Processors.ColorBalance.Ranges?

        /// The hue-rotation angle in degrees, or `nil` to leave the hue
        /// untouched. Requires normalization; a display-referred colour
        /// adjustment applied just before saturation.
        public let hue: Double?

        /// The colour-saturation factor, or `nil` to leave saturation untouched.
        /// Requires normalization; a colour adjustment applied after the tone
        /// stages, on the display-referred image.
        public let saturation: Double?

        /// Whether to invert the image (photographic negative). Requires
        /// normalization.
        public let invert: Bool

        /// The net orientation (rotation + optional mirror) to apply, or `nil`
        /// to leave the image as captured. Applied last, as a pure geometry
        /// permutation.
        public let orient: Processors.Orient.Orientation?

        /// An optional per-stage timing hook.
        ///
        /// When non-`nil`, the pipeline wraps each processor stage in this closure,
        /// passing the stage's label and the work to run; when `nil`, stages run
        /// directly with no measurement. The pipeline performs no timing or
        /// formatting itself — a consumer that wants per-stage measurements supplies
        /// the timing (for example by forwarding to its own benchmarking helper), so
        /// the pipeline stays free of any benchmarking dependency.
        public let measure: ( @Sendable ( String, () throws -> Void ) throws -> Void )?

        /// Creates a pipeline configuration.
        ///
        /// - Parameters:
        ///   - scale:           Optional affine scaling of the raw samples. Defaults to `nil`.
        ///   - inputFormat:     How the input samples are laid out — mono (expanded to RGB), a colour-filter array (demosaiced), or already-RGB (passed through). Defaults to `.mono`.
        ///   - maxDimension:    Optional cap on the rendered image's largest dimension; a box-averaging downsample runs after channel-forming when set. Defaults to `nil` (full resolution).
        ///   - binFactor:       Factor to bin a single-channel mosaic before channel-forming, so the debayer runs on a smaller mosaic. Defaults to one (no binning); a value below one, or too large for the image, throws when the stage runs.
        ///   - cosmeticCorrection: Optional hot/cold pixel repair applied to the raw samples before the channel-forming stage. Defaults to `nil`.
        ///   - normalize:       Optional normalization mode. Defaults to `nil`.
        ///   - stretch:         Optional Screen Transfer parameters. Defaults to `nil`.
        ///   - correctGamma:    Optional gamma exponent. Defaults to `nil`.
        ///   - whiteBalance:       Optional white-balance mode. Defaults to `nil`.
        ///   - invert:             Whether to invert the image. Defaults to `false`.
        ///   - brightnessContrast: Optional brightness offset and contrast factor. Defaults to `nil`.
        ///   - levels:             Optional levels remap. Defaults to `nil`.
        ///   - curves:             Optional tone curve. Defaults to `nil`.
        ///   - colorBalance:       Optional tonal-range colour balance. Defaults to `nil`.
        ///   - hue:                Optional hue-rotation angle in degrees. Defaults to `nil`.
        ///   - saturation:         Optional colour-saturation factor. Defaults to `nil`.
        ///   - orient:             Optional net orientation to apply last. Defaults to `nil`.
        ///   - measure:            Optional per-stage timing hook. Defaults to `nil` (stages run un-measured).
        public init( scale: ( scale: Double, offset: Double )? = nil, inputFormat: InputFormat = .mono, maxDimension: Int? = nil, binFactor: Int = 1, cosmeticCorrection: Processors.CosmeticCorrection.Parameters? = nil, normalize: Processors.Normalize.Mode? = nil, stretch: Processors.Stretch.STFParameters? = nil, correctGamma: Double? = nil, whiteBalance: Processors.WhiteBalance.Mode? = nil, invert: Bool = false, brightnessContrast: ( brightness: Double, contrast: Double )? = nil, levels: Processors.Levels.Channels? = nil, curves: Processors.Curves.Channels? = nil, colorBalance: Processors.ColorBalance.Ranges? = nil, hue: Double? = nil, saturation: Double? = nil, orient: Processors.Orient.Orientation? = nil, measure: ( @Sendable ( String, () throws -> Void ) throws -> Void )? = nil )
        {
            self.scale              = scale
            self.inputFormat        = inputFormat
            self.maxDimension       = maxDimension
            self.binFactor          = binFactor
            self.cosmeticCorrection = cosmeticCorrection
            self.normalize          = normalize
            self.stretch            = stretch
            self.correctGamma       = correctGamma
            self.whiteBalance       = whiteBalance
            self.invert             = invert
            self.brightnessContrast = brightnessContrast
            self.levels             = levels
            self.curves             = curves
            self.colorBalance       = colorBalance
            self.hue                = hue
            self.saturation         = saturation
            self.orient             = orient
            self.measure            = measure
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
    /// - Throws: An error if decoding fails or any stage fails.
    public func run( data: Data, width: Int, height: Int, bitsPerPixel: BitsPerPixel ) throws -> PixelBuffer
    {
        let pixels = try PixelUtilities.readRawPixels( data: data, width: width, height: height, bitsPerPixel: bitsPerPixel )

        return try self.run( pixels: pixels, width: width, height: height, bitsPerPixel: bitsPerPixel )
    }

    /// Runs the pipeline over already-decoded samples, interpreted per the
    /// configuration's ``Config/inputFormat``: a single mono or colour-filter-array
    /// channel, or interleaved RGB samples.
    ///
    /// - Parameters:
    ///   - pixels:       The samples in row-major order — one channel for a mono or
    ///                   CFA input, or interleaved RGB for a three-channel input.
    ///                   Their count must equal `width * height * inputFormat.channels`.
    ///   - width:        The image width in pixels.
    ///   - height:       The image height in pixels.
    ///   - bitsPerPixel: The original sample format (informational).
    ///
    /// - Returns: The processed buffer.
    ///
    /// - Throws: An error if the geometry is inconsistent or any stage
    ///           fails.
    public func run( pixels: [ Double ], width: Int, height: Int, bitsPerPixel: BitsPerPixel ) throws -> PixelBuffer
    {
        var buffer = try PixelBuffer( width: width, height: height, channels: self.config.inputFormat.channels, pixels: pixels, isNormalized: false )

        try self.processors().forEach
        {
            processor in

            let stage = { try processor.process( buffer: &buffer ) }

            if let measure = self.config.measure
            {
                try measure( processor.description, stage )
            }
            else
            {
                try stage()
            }
        }

        return buffer
    }

    /// Runs the pipeline over separate channel planes, interleaving them first.
    ///
    /// A convenience over ``run(pixels:width:height:bitsPerPixel:)`` for formats
    /// that decode their channels into separate planes (e.g. a band-sequential RGB
    /// image): the planes are interleaved via ``PixelUtilities/interleave(planes:)``
    /// into the layout the pipeline expects, then processed. The plane count must
    /// match the configuration's ``Config/inputFormat`` channel count.
    ///
    /// - Parameters:
    ///   - planes:       The channel planes, in channel order, all the same length.
    ///   - width:        The image width in pixels.
    ///   - height:       The image height in pixels.
    ///   - bitsPerPixel: The original sample format (informational).
    ///
    /// - Returns: The processed buffer.
    ///
    /// - Throws: An error if the plane count does not match the input
    ///           format's channel count, the planes are empty or unequal in length,
    ///           or any stage fails.
    public func run( planes: [ [ Double ] ], width: Int, height: Int, bitsPerPixel: BitsPerPixel ) throws -> PixelBuffer
    {
        guard planes.count == self.config.inputFormat.channels
        else
        {
            throw PixelPipelineError.planeCountMismatch( expected: self.config.inputFormat.channels, actual: planes.count )
        }

        let pixels = try PixelUtilities.interleave( planes: planes )

        return try self.run( pixels: pixels, width: width, height: height, bitsPerPixel: bitsPerPixel )
    }

    /// Builds the ordered processor chain for the configuration.
    ///
    /// The order is fixed and enforces the processors' preconditions: raw
    /// scaling, then demosaicing to RGB, then normalization, then the stages
    /// that require a normalized buffer. Those normalization-dependent stages
    /// run in two groups around the non-linear stretch: white balance as a
    /// linear colour calibration before the stretch, then the stretch, then the
    /// display-referred stages on the stretched image (brightness/contrast,
    /// gamma, levels, curves, colour balance, hue, saturation, invert).
    /// Orientation, a pure geometry permutation, runs last.
    ///
    /// All of these stages require a normalized buffer. If any is requested
    /// without an explicit normalization mode, a default min/max Normalize is
    /// inserted automatically so the configuration cannot produce a "buffer
    /// needs to be normalized" failure.
    ///
    /// - Returns: The processors to apply, in execution order.
    func processors() -> [ PixelProcessor ]
    {
        var processors = [ PixelProcessor ]()

        if let scale = self.config.scale
        {
            processors.append( Processors.Scale( scale: scale.scale, offset: scale.offset ) )
        }

        // Cosmetic correction repairs hot/cold pixels on the raw samples, before
        // the channel-forming stage, so a defect is fixed before demosaicing can
        // smear it across its neighbours. Its neighbour lattice is derived from the
        // input layout; the concrete Bayer pattern is not needed. It runs on raw
        // samples and is intentionally absent from the normalization predicate
        // below, so requesting it never forces a normalization.
        if let cosmeticCorrection = self.config.cosmeticCorrection
        {
            let layout: Processors.CosmeticCorrection.Layout

            switch self.config.inputFormat
            {
                case .mono: layout = .mono
                case .cfa:  layout = .cfa
                case .rgb:  layout = .rgb
            }

            processors.append( Processors.CosmeticCorrection( layout: layout, parameters: cosmeticCorrection ) )
        }

        // Binning reduces a raw single-channel mosaic before the demosaic, averaging
        // same-colour sites so the pattern survives, so the expensive debayer runs on
        // a smaller mosaic. It applies only to a single-channel input (a mono or CFA
        // frame); an already-RGB frame has no mosaic to bin.
        if self.config.binFactor != 1, self.config.inputFormat.channels == 1
        {
            processors.append( Processors.Bin( factor: self.config.binFactor ) )
        }

        // The channel-forming stage brings the input to RGB according to its
        // layout: a monochrome frame is expanded, a colour-filter array is
        // demosaiced, and an already-RGB frame needs no forming stage.
        switch self.config.inputFormat
        {
            case .mono:

                processors.append( Processors.MonoToRGB() )

            case .cfa( let pattern, let mode ):

                processors.append( Processors.Debayer( mode: mode, pattern: pattern ) )

            case .rgb:

                break
        }

        // Downsampling runs right after channel-forming: the buffer is now
        // co-located RGB, so box averaging is safe (a raw colour-filter-array
        // mosaic must never be averaged across its colour sites), and shrinking
        // here spares every per-pixel stage below the full-resolution cost — the
        // point of a small preview render. A no-op when the image already fits.
        if let maxDimension = self.config.maxDimension
        {
            processors.append( Processors.Resample( maxDimension: maxDimension ) )
        }

        // A neutral brightness/contrast (no offset, unit factor) is a no-op and
        // is dropped here, so it neither runs nor forces a normalization.
        let brightnessContrast: ( brightness: Double, contrast: Double )?

        if let configured = self.config.brightnessContrast, configured.brightness != 0.0 || configured.contrast != 1.0
        {
            brightnessContrast = configured
        }
        else
        {
            brightnessContrast = nil
        }

        // An identity levels remap is a no-op and is dropped here, so it neither
        // runs nor forces a normalization.
        let levels: Processors.Levels.Channels?

        if let configured = self.config.levels, configured.isIdentity == false
        {
            levels = configured
        }
        else
        {
            levels = nil
        }

        // An identity tone curve is a no-op and is dropped here, so it neither
        // runs nor forces a normalization.
        let curves: Processors.Curves.Channels?

        if let configured = self.config.curves, configured.isIdentity == false
        {
            curves = configured
        }
        else
        {
            curves = nil
        }

        // A neutral saturation (factor 1) is a no-op and is dropped here.
        let saturation: Double?

        if let configured = self.config.saturation, configured != 1.0
        {
            saturation = configured
        }
        else
        {
            saturation = nil
        }

        // A neutral hue rotation (0°) is a no-op and is dropped here.
        let hue: Double?

        if let configured = self.config.hue, configured != 0.0
        {
            hue = configured
        }
        else
        {
            hue = nil
        }

        // A neutral colour balance is a no-op and is dropped here.
        let colorBalance: Processors.ColorBalance.Ranges?

        if let configured = self.config.colorBalance, configured.isIdentity == false
        {
            colorBalance = configured
        }
        else
        {
            colorBalance = nil
        }

        let requiresNormalization = self.config.stretch != nil || self.config.correctGamma != nil || self.config.whiteBalance != nil || self.config.invert || brightnessContrast != nil || levels != nil || curves != nil || colorBalance != nil || hue != nil || saturation != nil
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

        // White balance is a linear, per-channel colour calibration on the
        // normalized data, applied before the non-linear stretch so the gains
        // act on the linear signal.
        if let whiteBalance = self.config.whiteBalance
        {
            processors.append( Processors.WhiteBalance( mode: whiteBalance ) )
        }

        if let stretch = self.config.stretch
        {
            processors.append( Processors.Stretch( parameters: stretch ) )
        }

        // Brightness/contrast is a display-referred adjustment applied on the
        // stretched image, immediately after the stretch — where the tones are
        // spread across the display range, so a midpoint-centred contrast and an
        // additive brightness respond gently and predictably (on the linear
        // pre-stretch signal, which sits near black, the same adjustment is wildly
        // over-sensitive).
        if let brightnessContrast
        {
            processors.append( Processors.BrightnessContrast( brightness: brightnessContrast.brightness, contrast: brightnessContrast.contrast ) )
        }

        if let correctGamma = self.config.correctGamma
        {
            processors.append( Processors.CorrectGamma( gamma: correctGamma ) )
        }

        // Levels is a parametric tone remap applied after the stretch, on the
        // display-referred (stretched) image.
        if let levels
        {
            processors.append( Processors.Levels( channels: levels ) )
        }

        // Curves is another tone remap, applied right after levels.
        if let curves
        {
            processors.append( Processors.Curves( channels: curves ) )
        }

        // Colour balance is a display-referred colour grade applied after the
        // tone stages, before hue and saturation.
        if let colorBalance
        {
            processors.append( Processors.ColorBalance( ranges: colorBalance ) )
        }

        // Hue is a colour rotation on the display-referred image, applied just
        // before saturation.
        if let hue
        {
            processors.append( Processors.Hue( angle: hue ) )
        }

        // Saturation is a colour adjustment on the display-referred image,
        // applied after the tone stages.
        if let saturation
        {
            processors.append( Processors.Saturation( saturation: saturation ) )
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

/// A failure originating from the pixel pipeline's own input handling.
public enum PixelPipelineError: LocalizedError, Equatable, Sendable
{
    /// The number of supplied channel planes does not match the input format's
    /// channel count.
    case planeCountMismatch( expected: Int, actual: Int )

    /// A human-readable description of the failure.
    public var errorDescription: String?
    {
        switch self
        {
            case .planeCountMismatch( let expected, let actual ):

                return "Plane count \( actual ) does not match the input format's channel count \( expected )."
        }
    }
}
