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

import Accelerate
import Foundation
import SwiftUtilities

public extension Processors
{
    /// Applies a Photoshop-style levels remap to a normalized buffer.
    ///
    /// Each sample is mapped by clamping it into the input black/white window,
    /// applying a midtone gamma, then rescaling into the output black/white
    /// range: `out = outputBlack + clip((v − inputBlack) / (inputWhite −
    /// inputBlack))^(1 / gamma) · (outputWhite − outputBlack)`, with the result
    /// clipped to `[0, 1]`. The same five parameters can be applied uniformly to
    /// every channel, or independently per RGB channel.
    struct Levels: PixelProcessor
    {
        /// One channel's level mapping.
        ///
        /// The input window (`inputBlack`, `inputWhite`) selects the tonal range
        /// to keep, `gamma` bends the midtones (matching ``CorrectGamma``: each
        /// value is raised to `1 / gamma`, so `> 1` brightens), and the output
        /// range (`outputBlack`, `outputWhite`) is the range the result is mapped
        /// into. The default values form an identity mapping.
        public struct Parameters: Sendable, Equatable
        {
            /// The input value mapped to black; samples at or below it clip to the
            /// output black.
            public let inputBlack: Double

            /// The input value mapped to white; samples at or above it clip to the
            /// output white. Must be greater than ``inputBlack``.
            public let inputWhite: Double

            /// The midtone gamma. Must be `> 0`; each value is raised to its
            /// reciprocal, so `1` is neutral and `> 1` brightens midtones.
            public let gamma: Double

            /// The darkest output value (lets the blacks be lifted to gray).
            public let outputBlack: Double

            /// The brightest output value (lets the highlights be capped).
            public let outputWhite: Double

            /// The identity mapping: the full input window, neutral gamma and the
            /// full output range, which leaves a sample unchanged.
            public static let identity = Parameters()

            /// Creates a level mapping.
            ///
            /// - Parameters:
            ///   - inputBlack:  The input value mapped to black. Defaults to `0`.
            ///   - inputWhite:  The input value mapped to white. Defaults to `1`.
            ///   - gamma:       The midtone gamma (`1` is neutral). Defaults to `1`.
            ///   - outputBlack: The darkest output value. Defaults to `0`.
            ///   - outputWhite: The brightest output value. Defaults to `1`.
            public init( inputBlack: Double = 0, inputWhite: Double = 1, gamma: Double = 1, outputBlack: Double = 0, outputWhite: Double = 1 )
            {
                self.inputBlack  = inputBlack
                self.inputWhite  = inputWhite
                self.gamma       = gamma
                self.outputBlack = outputBlack
                self.outputWhite = outputWhite
            }

            /// Whether these parameters are the identity mapping (and so a no-op).
            public var isIdentity: Bool
            {
                self == .identity
            }

            /// Validates that the parameters describe a usable mapping.
            ///
            /// - Throws: A `RuntimeError` if `gamma <= 0` or `inputWhite` is not
            ///           greater than `inputBlack`.
            func validate() throws
            {
                guard self.gamma > 0
                else
                {
                    throw RuntimeError( message: "Levels gamma must be greater than zero: \( self.gamma )" )
                }

                guard self.inputWhite > self.inputBlack
                else
                {
                    throw RuntimeError( message: "Levels input white must be greater than input black: \( self.inputWhite ) <= \( self.inputBlack )" )
                }
            }

            /// Maps a single sample through this level mapping, clipping the
            /// result to `[0, 1]`.
            ///
            /// - Parameter value: The normalized sample to map.
            /// - Returns: The remapped, clipped sample.
            func map( _ value: Double ) -> Double
            {
                let normalized = ( value - self.inputBlack ) / ( self.inputWhite - self.inputBlack )
                let clamped    = Swift.min( 1.0, Swift.max( 0.0, normalized ) )
                let curved     = self.gamma == 1 ? clamped : Foundation.pow( clamped, 1.0 / self.gamma )
                let output     = self.outputBlack + curved * ( self.outputWhite - self.outputBlack )

                return Swift.min( 1.0, Swift.max( 0.0, output ) )
            }
        }

        /// How the level parameters apply across the buffer's channels.
        public enum Channels: Sendable, Equatable
        {
            /// One mapping applied identically to every channel.
            case uniform( Parameters )

            /// A separate mapping for each of the red, green and blue channels;
            /// requires a 3-channel buffer.
            case perChannel( red: Parameters, green: Parameters, blue: Parameters )

            /// Whether every mapping is the identity (and so the whole stage is a
            /// no-op).
            public var isIdentity: Bool
            {
                switch self
                {
                    case .uniform( let p ):                  return p.isIdentity
                    case .perChannel( let r, let g, let b ): return r.isIdentity && g.isIdentity && b.isIdentity
                }
            }
        }

        /// How the level parameters apply across the buffer's channels.
        public let channels: Channels

        /// A human-readable name including the channel mode.
        public var name: String
        {
            switch self.channels
            {
                case .uniform( let p ):     return String( format: "Levels (%.02f-%.02f γ%.02f → %.02f-%.02f)", p.inputBlack, p.inputWhite, p.gamma, p.outputBlack, p.outputWhite )
                case .perChannel:           return "Levels (per-channel)"
            }
        }

        /// Creates a levels stage.
        ///
        /// - Parameter channels: How the level parameters apply across channels.
        public init( channels: Channels )
        {
            self.channels = channels
        }

        /// Applies the levels remap in place.
        ///
        /// - Parameter buffer: The normalized buffer to transform.
        ///
        /// - Throws: A `RuntimeError` if the buffer is not normalized, a
        ///           parameter set is degenerate (`gamma <= 0` or `inputWhite <=
        ///           inputBlack`), or per-channel parameters are used with a
        ///           buffer that is not 3-channel.
        public func process( buffer: inout PixelBuffer ) throws
        {
            guard buffer.isNormalized
            else
            {
                throw RuntimeError( message: "Buffer needs to be normalized" )
            }

            switch self.channels
            {
                case .uniform( let parameters ):

                    try parameters.validate()

                    let count = buffer.pixels.count

                    buffer.withUnsafeMutablePixels
                    {
                        guard let baseAddress = $0.baseAddress
                        else
                        {
                            return
                        }

                        Self.applyLevels( to: baseAddress, stride: 1, count: count, parameters: parameters )
                    }

                case .perChannel( let red, let green, let blue ):

                    try red.validate()
                    try green.validate()
                    try blue.validate()

                    guard buffer.channels == 3
                    else
                    {
                        throw RuntimeError( message: "Per-channel levels require a 3-channel buffer: \( buffer.channels )" )
                    }

                    let pixelCount = buffer.width * buffer.height

                    buffer.withUnsafeMutablePixels
                    {
                        guard let baseAddress = $0.baseAddress
                        else
                        {
                            return
                        }

                        Self.applyLevels( to: baseAddress + 0, stride: 3, count: pixelCount, parameters: red )
                        Self.applyLevels( to: baseAddress + 1, stride: 3, count: pixelCount, parameters: green )
                        Self.applyLevels( to: baseAddress + 2, stride: 3, count: pixelCount, parameters: blue )
                    }
            }
        }

        /// Applies one channel's level mapping to a strided view of the samples, in
        /// place, using Accelerate.
        ///
        /// The input window and the output range are affine clamps
        /// (``vDSP_vsmsaD`` + ``vDSP_vclipD``); the midtone gamma is a per-element
        /// power (`vvpows`, `c^(1/gamma)`) run on the contiguous samples — done in
        /// place for a single-channel buffer, or through a gather/scatter scratch
        /// for an interleaved one, since the vForce power has no strided form. A
        /// neutral gamma skips the power step entirely.
        ///
        /// - Parameters:
        ///   - base:       The address of the channel's first sample.
        ///   - stride:     The gap, in samples, between successive samples of the
        ///                 channel (`1` for a single-channel buffer, the channel
        ///                 count for an interleaved one).
        ///   - count:      The number of samples in the channel.
        ///   - parameters: The channel's level mapping, already validated.
        private static func applyLevels( to base: UnsafeMutablePointer< Double >, stride: Int, count: Int, parameters: Parameters )
        {
            guard count > 0
            else
            {
                return
            }

            let vCount    = vDSP_Length( count )
            let vStride   = vDSP_Stride( stride )
            let inScale   = 1.0 / ( parameters.inputWhite - parameters.inputBlack )
            let inOffset  = -parameters.inputBlack * inScale
            let outScale  = parameters.outputWhite - parameters.outputBlack
            let outOffset = parameters.outputBlack

            // Map into the input window and clip to [0, 1].
            vDSP_vsmsaD( base, vStride, [ inScale ], [ inOffset ], base, vStride, vCount )
            vDSP_vclipD( base, vStride, [ 0.0 ], [ 1.0 ], base, vStride, vCount )

            // Midtone gamma: raise each sample to 1 / gamma.
            if parameters.gamma != 1
            {
                var exponent = 1.0 / parameters.gamma
                var n        = Int32( count )

                if stride == 1
                {
                    vvpows( base, &exponent, base, &n )
                }
                else
                {
                    var scratch = [ Double ]( repeating: 0, count: count )

                    scratch.withUnsafeMutableBufferPointer
                    {
                        guard let contiguous = $0.baseAddress
                        else
                        {
                            return
                        }

                        // Gather the strided channel, raise to the power, scatter
                        // it back (multiplying by 1 is an exact strided copy).
                        vDSP_vsmulD( base, vStride, [ 1.0 ], contiguous, 1, vCount )
                        vvpows( contiguous, &exponent, contiguous, &n )
                        vDSP_vsmulD( contiguous, 1, [ 1.0 ], base, vStride, vCount )
                    }
                }
            }

            // Map into the output range and clip to [0, 1].
            vDSP_vsmsaD( base, vStride, [ outScale ], [ outOffset ], base, vStride, vCount )
            vDSP_vclipD( base, vStride, [ 0.0 ], [ 1.0 ], base, vStride, vCount )
        }
    }
}
