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

public extension Processors.Stretch
{
    /// The parameters of a Screen Transfer Function (STF) — a midtones transfer
    /// function (MTF) applied per channel, matching the PixInsight / XISF display
    /// function model.
    ///
    /// The same five parameters can be applied uniformly to every channel, or
    /// independently per RGB channel, mirroring ``Processors/Levels/Channels``.
    /// Both an auto-derived STF (``computed(from:shadowClipFactor:targetBackground:)``)
    /// and a stored XISF display function converge on this single, editable
    /// representation.
    enum STFParameters: Sendable, Equatable, CustomStringConvertible
    {
        /// One mapping applied identically to every channel.
        case uniform( Channel )

        /// A separate mapping for each of the red, green and blue channels;
        /// requires a 3-channel buffer.
        case perChannel( red: Channel, green: Channel, blue: Channel )

        /// A validation failure for an STF's configuration or auto-derivation.
        public enum ValidationError: LocalizedError, Equatable, Sendable
        {
            /// The highlights clip point is not strictly greater than the shadows.
            case highlightsNotAboveShadows( highlights: Double, shadows: Double )

            /// The high expansion bound is not strictly greater than the low bound.
            case highNotAboveLow( high: Double, low: Double )

            /// The midtones balance is outside `[0, 1]`.
            case midtonesOutOfRange( Double )

            /// An STF cannot be derived from an empty buffer.
            case emptyBuffer

            /// An STF cannot be derived from an empty channel.
            case emptyChannel

            /// A human-readable description of the failure.
            public var errorDescription: String?
            {
                switch self
                {
                    case .highlightsNotAboveShadows( let highlights, let shadows ):

                        return "STF highlights must be greater than shadows: \( highlights ) <= \( shadows )"

                    case .highNotAboveLow( let high, let low ):

                        return "STF high expansion must be greater than low: \( high ) <= \( low )"

                    case .midtonesOutOfRange( let midtones ):

                        return "STF midtones balance must be within [0, 1]: \( midtones )"

                    case .emptyBuffer:

                        return "Cannot derive an STF from an empty buffer"

                    case .emptyChannel:

                        return "Cannot derive an STF from an empty channel"
                }
            }
        }

        /// One channel's STF mapping.
        ///
        /// A sample is clipped into the `[shadows, highlights]` window, curved by
        /// the midtones balance, then remapped into the `[low, high]` expansion
        /// range, clipping the result to `[0, 1]`:
        /// `expanded = clip((mtf(midtones, clip((x − shadows) / (highlights −
        /// shadows))) − low) / (high − low))`. The default values form an identity
        /// mapping.
        public struct Channel: Sendable, Equatable, CustomStringConvertible
        {
            /// The shadows clip point; samples at or below it map to black.
            public let shadows: Double

            /// The midtones balance driving the MTF curve, in `[0, 1]` (`0.5` is
            /// neutral, `< 0.5` brightens, `> 0.5` darkens).
            public let midtones: Double

            /// The highlights clip point; samples at or above it map to white.
            /// Must be greater than ``shadows``.
            public let highlights: Double

            /// The low end of the dynamic-range expansion; the curved black point
            /// is remapped to it.
            public let low: Double

            /// The high end of the dynamic-range expansion; the curved white point
            /// is remapped to it. Must be greater than ``low``.
            public let high: Double

            /// The identity mapping: the full input window, neutral midtones and no
            /// range expansion, which leaves a sample unchanged.
            public static let identity = Channel()

            /// Creates a channel mapping.
            ///
            /// - Parameters:
            ///   - shadows:    The shadows clip point. Defaults to `0`.
            ///   - midtones:   The midtones balance (`0.5` is neutral). Defaults to
            ///                 `0.5`.
            ///   - highlights: The highlights clip point. Defaults to `1`.
            ///   - low:        The low range-expansion bound. Defaults to `0`.
            ///   - high:       The high range-expansion bound. Defaults to `1`.
            public init( shadows: Double = 0, midtones: Double = 0.5, highlights: Double = 1, low: Double = 0, high: Double = 1 )
            {
                self.shadows    = shadows
                self.midtones   = midtones
                self.highlights = highlights
                self.low        = low
                self.high       = high
            }

            /// Whether this mapping is the identity (and so a no-op).
            public var isIdentity: Bool
            {
                self == .identity
            }

            /// A human-readable description of the channel's parameters.
            public var description: String
            {
                String( format: "s%.3f m%.3f h%.3f l%.3f r%.3f", self.shadows, self.midtones, self.highlights, self.low, self.high )
            }

            /// Validates that the parameters describe a usable mapping.
            ///
            /// - Throws: A `STFParameters.ValidationError` if `highlights <= shadows`, `high <= low`,
            ///           or `midtones` is outside `[0, 1]`.
            func validate() throws
            {
                guard self.highlights > self.shadows
                else
                {
                    throw STFParameters.ValidationError.highlightsNotAboveShadows( highlights: self.highlights, shadows: self.shadows )
                }

                guard self.high > self.low
                else
                {
                    throw STFParameters.ValidationError.highNotAboveLow( high: self.high, low: self.low )
                }

                guard self.midtones >= 0, self.midtones <= 1
                else
                {
                    throw STFParameters.ValidationError.midtonesOutOfRange( self.midtones )
                }
            }

            /// Maps a single sample through this STF, clipping the result to
            /// `[0, 1]`.
            ///
            /// The parameters are assumed valid (see ``validate()``), which the
            /// apply path checks once before mapping every sample.
            ///
            /// - Parameter value: The normalized sample to map.
            /// - Returns: The transferred, clipped sample.
            func map( _ value: Double ) -> Double
            {
                let clipped  = Swift.min( 1.0, Swift.max( 0.0, ( value - self.shadows ) / ( self.highlights - self.shadows ) ) )
                let curved   = PixelUtilities.mtf( self.midtones, clipped )
                let expanded = ( curved - self.low ) / ( self.high - self.low )

                return Swift.min( 1.0, Swift.max( 0.0, expanded ) )
            }

            /// Derives an auto-STF channel mapping from a channel's robust
            /// statistics.
            ///
            /// The shadows are clipped a few median-absolute-deviations below the
            /// median, and the midtones balance is solved so the clipped median
            /// lands on `targetBackground`. Because the MTF satisfies
            /// `mtf(m, x0) = t  ⇔  m = mtf(t, x0)`, the balance is simply
            /// `mtf(targetBackground, m0)`, where `m0` is the median renormalized
            /// into the post-clip window. A channel with no spread (`mad <= 0`) or
            /// no post-clip range yields the identity, since it cannot be
            /// meaningfully stretched.
            ///
            /// - Parameters:
            ///   - median:           The channel's median (normalized).
            ///   - mad:              The channel's median absolute deviation about
            ///                       the median.
            ///   - shadowClipFactor: How many MADs below the median to clip the
            ///                       shadows (typically `2.8`).
            ///   - targetBackground: The value the median should map to (typically
            ///                       `0.25`).
            /// - Returns: The derived channel mapping, or the identity when the
            ///            channel has no usable dynamic range.
            public static func computed( median: Double, mad: Double, shadowClipFactor: Double, targetBackground: Double ) -> Channel
            {
                guard mad > 0
                else
                {
                    return .identity
                }

                let shadows = Swift.min( 1.0, Swift.max( 0.0, median - shadowClipFactor * mad ) )
                let range   = 1.0 - shadows

                guard range > 0
                else
                {
                    return .identity
                }

                let m0       = ( median - shadows ) / range
                let midtones = PixelUtilities.mtf( targetBackground, m0 )

                return Channel( shadows: shadows, midtones: midtones, highlights: 1.0, low: 0.0, high: 1.0 )
            }
        }

        /// The identity STF (a uniform identity channel), which is a no-op.
        public static let identity = STFParameters.uniform( .identity )

        /// Whether every channel mapping is the identity (and so the whole stage
        /// is a no-op).
        public var isIdentity: Bool
        {
            switch self
            {
                case .uniform( let channel ):            return channel.isIdentity
                case .perChannel( let r, let g, let b ): return r.isIdentity && g.isIdentity && b.isIdentity
            }
        }

        /// A human-readable description of the STF parameters.
        public var description: String
        {
            switch self
            {
                case .uniform( let channel ): return "STF \( channel )"
                case .perChannel:             return "STF (per-channel)"
            }
        }

        /// Derives an auto-STF from a normalized buffer's own statistics.
        ///
        /// A single-channel buffer yields a ``uniform(_:)`` result; a three-channel
        /// buffer yields a ``perChannel(red:green:blue:)`` result, each channel
        /// derived from its own median and median absolute deviation.
        ///
        /// - Parameters:
        ///   - buffer:           The normalized buffer to analyze.
        ///   - shadowClipFactor: How many MADs below the median to clip the
        ///                       shadows. Defaults to `2.8`.
        ///   - targetBackground: The value the median should map to. Defaults to
        ///                       `0.25`.
        /// - Returns: The derived STF parameters.
        ///
        /// - Throws: A `PixelBufferError` or `STFParameters.ValidationError` if the buffer is not normalized, is empty, or
        ///           has an unsupported channel count (only 1 and 3 are supported).
        public static func computed( from buffer: PixelBuffer, shadowClipFactor: Double = 2.8, targetBackground: Double = 0.25 ) throws -> STFParameters
        {
            guard buffer.isNormalized
            else
            {
                throw PixelBufferError.notNormalized
            }

            guard buffer.pixels.isEmpty == false
            else
            {
                throw STFParameters.ValidationError.emptyBuffer
            }

            switch buffer.channels
            {
                case 1:

                    return .uniform( try Self.channel( from: buffer.pixels, shadowClipFactor: shadowClipFactor, targetBackground: targetBackground ) )

                case 3:

                    let red   = try Self.channel( from: Self.samples( of: 0, in: buffer ), shadowClipFactor: shadowClipFactor, targetBackground: targetBackground )
                    let green = try Self.channel( from: Self.samples( of: 1, in: buffer ), shadowClipFactor: shadowClipFactor, targetBackground: targetBackground )
                    let blue  = try Self.channel( from: Self.samples( of: 2, in: buffer ), shadowClipFactor: shadowClipFactor, targetBackground: targetBackground )

                    return .perChannel( red: red, green: green, blue: blue )

                default:

                    throw PixelBufferError.unsupportedChannelCount( actual: buffer.channels, supported: [ 1, 3 ] )
            }
        }

        /// Derives an auto-STF from a buffer, normalizing a copy first when the
        /// buffer is not already normalized.
        ///
        /// This is the one-shot "normalize → parameters" helper the image loaders
        /// and preview extensions use to materialize editable auto-STF parameters
        /// without duplicating the pipeline: it never mutates `buffer`.
        ///
        /// - Parameters:
        ///   - buffer:           The buffer to analyze (normalized or not).
        ///   - mode:             The normalization mode to apply when the buffer is
        ///                       not yet normalized. Defaults to ``Processors/Normalize/Mode/minMax``.
        ///   - shadowClipFactor: How many MADs below the median to clip the
        ///                       shadows. Defaults to `2.8`.
        ///   - targetBackground: The value the median should map to. Defaults to
        ///                       `0.25`.
        /// - Returns: The derived STF parameters.
        ///
        /// - Throws: A `PixelBufferError` or `STFParameters.ValidationError` if normalization or derivation fails.
        public static func computed( normalizing buffer: PixelBuffer, using mode: Processors.Normalize.Mode = .minMax, shadowClipFactor: Double = 2.8, targetBackground: Double = 0.25 ) throws -> STFParameters
        {
            var normalized = buffer

            if normalized.isNormalized == false
            {
                try Processors.Normalize( mode: mode ).process( buffer: &normalized )
            }

            return try Self.computed( from: normalized, shadowClipFactor: shadowClipFactor, targetBackground: targetBackground )
        }

        /// Derives an unlinked, per-channel auto-STF from a single-channel Bayer
        /// mosaic, by deinterleaving it into its three color-filter sample sets.
        ///
        /// This is the colour-filter-array counterpart of ``computed(from:shadowClipFactor:targetBackground:)``:
        /// where that reduces a *co-located* 3-channel buffer, this derives each
        /// channel's mapping straight from the mosaic's own red, green and blue
        /// sites (see ``Processors/Debayer/deinterleave(mosaic:width:height:pattern:)``),
        /// so each channel clips only its own darkest tail and no demosaic
        /// interpolation blends the channels' statistics together. It always yields
        /// a ``perChannel(red:green:blue:)`` result. A channel with no sampled sites
        /// (a degenerate mosaic too small to contain that colour) or no spread
        /// falls back to the identity for that channel.
        ///
        /// - Parameters:
        ///   - buffer:           The normalized, single-channel mosaic buffer.
        ///   - pattern:          The Bayer color-filter arrangement of the mosaic.
        ///   - shadowClipFactor: How many MADs below the median to clip the
        ///                       shadows. Defaults to `2.8`.
        ///   - targetBackground: The value the median should map to. Defaults to
        ///                       `0.25`.
        /// - Returns: The derived per-channel STF parameters.
        ///
        /// - Throws: A `PixelBufferError` or `STFParameters.ValidationError` if the buffer is not normalized, is empty, is
        ///           not single-channel, or its sample count does not match its
        ///           geometry.
        public static func computed( fromMosaic buffer: PixelBuffer, pattern: Processors.Debayer.Pattern, shadowClipFactor: Double = 2.8, targetBackground: Double = 0.25 ) throws -> STFParameters
        {
            guard buffer.isNormalized
            else
            {
                throw PixelBufferError.notNormalized
            }

            guard buffer.pixels.isEmpty == false
            else
            {
                throw STFParameters.ValidationError.emptyBuffer
            }

            guard buffer.channels == 1
            else
            {
                throw PixelBufferError.unsupportedChannelCount( actual: buffer.channels, supported: [ 1 ] )
            }

            let samples = try Processors.Debayer.deinterleave( mosaic: buffer.pixels, width: buffer.width, height: buffer.height, pattern: pattern )
            let red     = Self.channelOrIdentity( from: samples.red,   shadowClipFactor: shadowClipFactor, targetBackground: targetBackground )
            let green   = Self.channelOrIdentity( from: samples.green, shadowClipFactor: shadowClipFactor, targetBackground: targetBackground )
            let blue    = Self.channelOrIdentity( from: samples.blue,  shadowClipFactor: shadowClipFactor, targetBackground: targetBackground )

            return .perChannel( red: red, green: green, blue: blue )
        }

        /// Derives a single channel mapping from a channel's samples.
        ///
        /// - Parameters:
        ///   - samples:          The channel's samples.
        ///   - shadowClipFactor: How many MADs below the median to clip the shadows.
        ///   - targetBackground: The value the median should map to.
        /// - Returns: The derived channel mapping.
        ///
        /// - Throws: A `STFParameters.ValidationError` if the samples are empty.
        private static func channel( from samples: [ Double ], shadowClipFactor: Double, targetBackground: Double ) throws -> Channel
        {
            guard let median = PixelUtilities.median( samples ), let mad = PixelUtilities.medianAbsoluteDeviation( samples, around: median )
            else
            {
                throw STFParameters.ValidationError.emptyChannel
            }

            return Channel.computed( median: median, mad: mad, shadowClipFactor: shadowClipFactor, targetBackground: targetBackground )
        }

        /// Derives a single channel mapping from a channel's samples, degrading to
        /// the identity rather than throwing when the channel has no samples.
        ///
        /// Used by the mosaic derivation, where a degenerate mosaic can leave one
        /// colour with no sampled sites: an absent colour cannot be stretched, so it
        /// is left unchanged instead of failing the whole derivation.
        ///
        /// - Parameters:
        ///   - samples:          The channel's samples (possibly empty).
        ///   - shadowClipFactor: How many MADs below the median to clip the shadows.
        ///   - targetBackground: The value the median should map to.
        /// - Returns: The derived channel mapping, or the identity for an empty
        ///            channel.
        private static func channelOrIdentity( from samples: [ Double ], shadowClipFactor: Double, targetBackground: Double ) -> Channel
        {
            guard let median = PixelUtilities.median( samples ), let mad = PixelUtilities.medianAbsoluteDeviation( samples, around: median )
            else
            {
                return .identity
            }

            return Channel.computed( median: median, mad: mad, shadowClipFactor: shadowClipFactor, targetBackground: targetBackground )
        }

        /// Extracts one channel's samples from an interleaved buffer.
        ///
        /// - Parameters:
        ///   - channel: The zero-based channel index.
        ///   - buffer:  The interleaved buffer.
        /// - Returns: The samples of the requested channel, in row-major order.
        private static func samples( of channel: Int, in buffer: PixelBuffer ) -> [ Double ]
        {
            stride( from: channel, to: buffer.pixels.count, by: buffer.channels ).map { buffer.pixels[ $0 ] }
        }
    }
}
