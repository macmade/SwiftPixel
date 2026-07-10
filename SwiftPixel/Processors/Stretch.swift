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
    /// Applies a non-linear tone stretch to a buffer, expanding faint detail.
    ///
    /// Requires a normalized buffer (samples in `[0, 1]`). Each algorithm rejects
    /// the parameter values that would produce a divide-by-zero or `NaN`.
    struct Stretch: PixelProcessor
    {
        /// The stretch curve and its tuning constant(s).
        public enum Algorithm: Sendable, Equatable, CustomStringConvertible
        {
            /// Logarithmic stretch `log(1 + n·x) / log(1 + n)`.
            ///
            /// The associated value `n` controls the curve's strength and must be
            /// `> 0`.
            case log( Double )

            /// Inverse-hyperbolic-sine stretch `asinh(n·x) / asinh(n)`.
            ///
            /// The associated value `n` controls the curve's strength and must be
            /// non-zero.
            case arcsinh( Double )

            /// Logistic (sigmoid) stretch `1 / (1 + exp(-n1·(x - n2)))`.
            ///
            /// The associated values are the slope `n1` and the midpoint `n2`.
            case sigmoid( Double, Double )

            /// Screen Transfer Function (STF): a per-channel midtones transfer
            /// function driven by explicit ``STFParameters``.
            ///
            /// The parameters can be filled by auto-deriving them from an image's
            /// statistics or by mapping a stored XISF display function; both flow
            /// through this single, editable case.
            case screenTransfer( STFParameters )

            /// A human-readable description of the algorithm and its constants.
            public var description: String
            {
                switch self
                {
                    case .log( let n ):              return String( format: "Logarithmic %.02f", n )
                    case .arcsinh( let n ):          return String( format: "Hyperbolic %.02f", n )
                    case .sigmoid( let n1, let n2 ): return String( format: "Sigmoid %.02f %.02f", n1, n2 )
                    case .screenTransfer( let p ):   return "Screen Transfer (\( p ))"
                }
            }
        }

        /// The stretch algorithm and its tuning constant(s).
        public let algorithm: Algorithm

        /// A human-readable name including the algorithm.
        public var name: String
        {
            "Stretch (\( self.algorithm ))"
        }

        /// Creates a stretch stage.
        ///
        /// - Parameter algorithm: The stretch curve and its tuning constant(s).
        public init( algorithm: Algorithm )
        {
            self.algorithm = algorithm
        }

        /// Applies the configured stretch to `buffer`, in place.
        ///
        /// - Parameter buffer: The normalized buffer to transform.
        ///
        /// - Throws: A `RuntimeError` if the buffer is not normalized or if the
        ///           algorithm's tuning constant is degenerate.
        public func process( buffer: inout PixelBuffer ) throws
        {
            guard buffer.isNormalized
            else
            {
                throw RuntimeError( message: "Buffer needs to be normalized" )
            }

            switch self.algorithm
            {
                case .log(     let n ):          try Self.logStretch(     buffer: &buffer, n: n )
                case .arcsinh( let n ):          try Self.arcsinhStretch( buffer: &buffer, n: n )
                case .sigmoid( let n1, let n2 ): try Self.sigmoidStretch( buffer: &buffer, n1: n1, n2: n2 )
                case .screenTransfer( let p ):   try Self.screenTransferStretch( buffer: &buffer, parameters: p )
            }
        }

        /// Applies a logarithmic stretch `log(1 + n·x) / log(1 + n)` in place.
        ///
        /// - Parameters:
        ///   - buffer: The buffer to transform.
        ///   - n:      The curve strength. Must be `> 0`.
        ///
        /// - Throws: A `RuntimeError` if `n <= 0` or the buffer cannot be accessed.
        private static func logStretch( buffer: inout PixelBuffer, n: Double ) throws
        {
            guard n > 0
            else
            {
                throw RuntimeError( message: "Logarithmic stretch requires n > 0: \( n )" )
            }

            var denominator = log( 1.0 + n )
            var one         = 1.0
            let count       = vDSP_Length( buffer.pixels.count )

            try buffer.withUnsafeMutablePixels
            {
                guard let baseAddress = $0.baseAddress
                else
                {
                    throw RuntimeError( message: "Failed to access data buffer" )
                }

                vDSP_vsmulD( baseAddress, 1, [ n ], baseAddress, 1, count )
                vDSP_vsaddD( baseAddress, 1, &one, baseAddress, 1, count )
                vvlog( baseAddress, baseAddress, [ Int32( count ) ] )
                vDSP_vsdivD( baseAddress, 1, &denominator, baseAddress, 1, count )
            }
        }

        /// Applies an inverse-hyperbolic-sine stretch `asinh(n·x) / asinh(n)` in
        /// place.
        ///
        /// - Parameters:
        ///   - buffer: The buffer to transform.
        ///   - n:      The curve strength. Must be non-zero.
        ///
        /// - Throws: A `RuntimeError` if `n == 0` or the buffer cannot be accessed.
        private static func arcsinhStretch( buffer: inout PixelBuffer, n: Double ) throws
        {
            guard n != 0
            else
            {
                throw RuntimeError( message: "Hyperbolic stretch requires n != 0: \( n )" )
            }

            var denominator = asinh( n )
            let count       = vDSP_Length( buffer.pixels.count )

            try buffer.withUnsafeMutablePixels
            {
                guard let baseAddress = $0.baseAddress
                else
                {
                    throw RuntimeError( message: "Failed to access data buffer" )
                }

                vDSP_vsmulD( baseAddress, 1, [ n ], baseAddress, 1, count )
                vvasinh( baseAddress, baseAddress, [ Int32( count ) ] )
                vDSP_vsdivD( baseAddress, 1, &denominator, baseAddress, 1, count )
            }
        }

        /// Applies a logistic (sigmoid) stretch `1 / (1 + exp(-n1·(x - n2)))` in
        /// place.
        ///
        /// - Parameters:
        ///   - buffer: The buffer to transform.
        ///   - n1:     The slope (steepness) of the curve.
        ///   - n2:     The midpoint (the input mapped to `0.5`).
        ///
        /// - Throws: A `RuntimeError` if the buffer cannot be accessed.
        private static func sigmoidStretch( buffer: inout PixelBuffer, n1: Double, n2: Double ) throws
        {
            let count    = vDSP_Length( buffer.pixels.count )
            var midpoint = -n2
            var slope    = n1
            var minusOne = -1.0
            var one      = 1.0

            try buffer.withUnsafeMutablePixels
            {
                guard let baseAddress = $0.baseAddress
                else
                {
                    throw RuntimeError( message: "Failed to access data buffer" )
                }

                vDSP_vsaddD( baseAddress, 1, &midpoint, baseAddress, 1, count )
                vDSP_vsmulD( baseAddress, 1, &slope, baseAddress, 1, count )
                vDSP_vsmulD( baseAddress, 1, &minusOne, baseAddress, 1, count )
                vvexp( baseAddress, baseAddress, [ Int32( count ) ] )
                vDSP_vsaddD( baseAddress, 1, &one, baseAddress, 1, count )
                vvrec( baseAddress, baseAddress, [ Int32( count ) ] )
            }
        }

        /// Applies a Screen Transfer Function (per-channel MTF) in place.
        ///
        /// - Parameters:
        ///   - buffer:     The normalized buffer to transform.
        ///   - parameters: The STF parameters, uniform or per-channel.
        ///
        /// - Throws: A `RuntimeError` if a channel's parameters are degenerate, or
        ///           if per-channel parameters are used with a buffer that is not
        ///           3-channel.
        private static func screenTransferStretch( buffer: inout PixelBuffer, parameters: STFParameters ) throws
        {
            switch parameters
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
                        throw RuntimeError( message: "Per-channel screen transfer requires a 3-channel buffer: \( buffer.channels )" )
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
                let pixels = UnsafeMutableSendable( UnsafeMutableBufferPointer( start: base, count: span ) )

                PixelUtilities.parallelOrSerial( iterations: count )
                {
                    let index = $0 * stride

                    pixels.value[ index ] = channel.map( pixels.value[ index ] )
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
