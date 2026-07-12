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

public extension Processors
{
    /// Applies a Screen Transfer Function (STF) to a buffer, expanding faint
    /// detail with a per-channel midtones transfer function.
    ///
    /// Requires a normalized buffer (samples in `[0, 1]`). The parameters can be
    /// filled by auto-deriving them from an image's statistics or by mapping a
    /// stored XISF display function; both flow through the same editable
    /// ``STFParameters``. Degenerate parameters (an empty clip window or expansion
    /// range, or out-of-range midtones) are rejected.
    struct Stretch: PixelProcessor
    {
        /// The Screen Transfer parameters, uniform or per-channel.
        public let parameters: STFParameters

        /// A human-readable name including the parameters.
        public var name: String
        {
            "Stretch (\( self.parameters ))"
        }

        /// Creates a stretch stage.
        ///
        /// - Parameter parameters: The Screen Transfer parameters to apply.
        public init( parameters: STFParameters )
        {
            self.parameters = parameters
        }

        /// Applies the configured Screen Transfer to `buffer`, in place.
        ///
        /// - Parameter buffer: The normalized buffer to transform.
        ///
        /// - Throws: A `PixelBufferError` or `STFParameters.ValidationError` if the buffer is not normalized, if a
        ///           channel's parameters are degenerate, or if per-channel
        ///           parameters are used with a buffer that is not 3-channel.
        public func process( buffer: inout PixelBuffer ) throws
        {
            guard buffer.isNormalized
            else
            {
                throw PixelBufferError.notNormalized
            }

            switch self.parameters
            {
                case .uniform( let channel ):

                    try channel.validate()

                    let count = buffer.pixels.count

                    buffer.withUnsafeMutablePixels
                    {
                        guard let baseAddress = $0.baseAddress
                        else
                        {
                            return
                        }

                        Self.applyScreenTransfer( to: baseAddress, stride: 1, count: count, channel: channel )
                    }

                case .perChannel( let red, let green, let blue ):

                    try red.validate()
                    try green.validate()
                    try blue.validate()

                    guard buffer.channels == 3
                    else
                    {
                        throw PixelBufferError.unsupportedChannelCount( actual: buffer.channels, supported: [ 3 ] )
                    }

                    let pixelCount = buffer.width * buffer.height

                    buffer.withUnsafeMutablePixels
                    {
                        guard let baseAddress = $0.baseAddress
                        else
                        {
                            return
                        }

                        Self.applyScreenTransfer( to: baseAddress + 0, stride: 3, count: pixelCount, channel: red )
                        Self.applyScreenTransfer( to: baseAddress + 1, stride: 3, count: pixelCount, channel: green )
                        Self.applyScreenTransfer( to: baseAddress + 2, stride: 3, count: pixelCount, channel: blue )
                    }
            }
        }

        /// Applies one channel's STF to a strided view of the samples, in place.
        ///
        /// For the usual midtones range `(0, 1)` this is a vectorized Accelerate
        /// pipeline — clip into the `[shadows, highlights]` window, the midtones
        /// transfer `((m − 1)·c) / ((2m − 1)·c − m)`, then the `[low, high]`
        /// expansion — where the denominator is provably non-zero over the clipped
        /// `[0, 1]` range. The degenerate midtones (`m ≤ 0` or `m ≥ 1`) are
        /// step-shaped limits that do not vectorize cleanly, so they fall back to
        /// the scalar ``STFParameters/Channel/map(_:)`` reference.
        ///
        /// - Parameters:
        ///   - base:    The address of the channel's first sample.
        ///   - stride:  The gap, in samples, between successive samples of the
        ///              channel (`1` for a single-channel buffer, the channel count
        ///              for an interleaved one).
        ///   - count:   The number of samples in the channel.
        ///   - channel: The channel's STF parameters, already validated.
        private static func applyScreenTransfer( to base: UnsafeMutablePointer< Double >, stride: Int, count: Int, channel: STFParameters.Channel )
        {
            guard count > 0
            else
            {
                return
            }

            let midtones = channel.midtones

            guard midtones > 0, midtones < 1
            else
            {
                let span   = ( count - 1 ) * stride + 1
                nonisolated( unsafe ) let pixels = UnsafeMutableBufferPointer( start: base, count: span )

                PixelUtilities.parallelOrSerial( iterations: count )
                {
                    let index = $0 * stride

                    pixels[ index ] = channel.map( pixels[ index ] )
                }

                return
            }

            let vCount     = vDSP_Length( count )
            let vStride    = vDSP_Stride( stride )
            let clipScale  = 1.0 / ( channel.highlights - channel.shadows )
            let clipOffset = -channel.shadows * clipScale
            let numScale   = midtones - 1.0
            let denScale   = 2.0 * midtones - 1.0
            let denOffset  = -midtones
            let expScale   = 1.0 / ( channel.high - channel.low )
            let expOffset  = -channel.low * expScale

            var scratch = [ Double ]( repeating: 0, count: count )

            scratch.withUnsafeMutableBufferPointer
            {
                guard let denominator = $0.baseAddress
                else
                {
                    return
                }

                // Clip into the [shadows, highlights] window, then to [0, 1].
                vDSP_vsmsaD( base, vStride, [ clipScale ], [ clipOffset ], base, vStride, vCount )
                vDSP_vclipD( base, vStride, [ 0.0 ], [ 1.0 ], base, vStride, vCount )

                // Midtones transfer: ((m − 1)·c) / ((2m − 1)·c − m). The
                // denominator is computed into the scratch buffer before the
                // numerator overwrites the clipped samples in place.
                vDSP_vsmsaD( base, vStride, [ denScale ], [ denOffset ], denominator, 1, vCount )
                vDSP_vsmulD( base, vStride, [ numScale ], base, vStride, vCount )
                vDSP_vdivD( denominator, 1, base, vStride, base, vStride, vCount )

                // Map into the [low, high] expansion range, then to [0, 1].
                vDSP_vsmsaD( base, vStride, [ expScale ], [ expOffset ], base, vStride, vCount )
                vDSP_vclipD( base, vStride, [ 0.0 ], [ 1.0 ], base, vStride, vCount )
            }
        }
    }
}
