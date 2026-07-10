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
    /// Applies an editable tone curve to a normalized buffer, interpolating the
    /// user's control points with a monotone cubic spline.
    ///
    /// The curve is sampled into a lookup table and applied per sample. The same
    /// curve can be applied uniformly to every channel, or independently per RGB
    /// channel. Monotone cubic (Fritsch–Carlson) interpolation is used so the
    /// curve never overshoots or introduces a non-monotonic dip between control
    /// points; the result is clipped to `[0, 1]`.
    struct Curves: PixelProcessor
    {
        /// A single control point of a tone curve, with both coordinates in
        /// `[0, 1]` (input `x` mapped to output `y`).
        public struct Point: Sendable, Equatable
        {
            /// The input coordinate (`0...1`).
            public let x: Double

            /// The output coordinate (`0...1`).
            public let y: Double

            /// Creates a control point.
            ///
            /// - Parameters:
            ///   - x: The input coordinate.
            ///   - y: The output coordinate.
            public init( x: Double, y: Double )
            {
                self.x = x
                self.y = y
            }
        }

        /// One channel's tone curve: an ordered set of control points.
        public struct Curve: Sendable, Equatable
        {
            /// The number of entries in the sampled lookup table. One more than a
            /// power of two, so the LUT nodes land exactly on tidy fractions (e.g.
            /// `0.5` → index `512`), which keeps control points at those inputs
            /// exact.
            static let lookupTableSize = 1025

            /// The control points, ordered by strictly increasing `x`, each
            /// coordinate in `[0, 1]`.
            public let points: [ Point ]

            /// The identity curve (a straight line from `(0, 0)` to `(1, 1)`),
            /// which leaves a sample unchanged.
            public static let identity = Curve( points: [ Point( x: 0, y: 0 ), Point( x: 1, y: 1 ) ] )

            /// Creates a curve from its control points.
            ///
            /// - Parameter points: The control points, ordered by increasing `x`.
            public init( points: [ Point ] )
            {
                self.points = points
            }

            /// Whether this curve is the identity (and so a no-op).
            public var isIdentity: Bool
            {
                self == .identity
            }

            /// Validates that the curve is usable.
            ///
            /// - Throws: A `RuntimeError` if there are fewer than two points, the
            ///           `x` coordinates are not strictly increasing, or any
            ///           coordinate is outside `[0, 1]`.
            func validate() throws
            {
                guard self.points.count >= 2
                else
                {
                    throw RuntimeError( message: "Curves needs at least two control points" )
                }

                for ( index, point ) in self.points.enumerated()
                {
                    guard point.x >= 0, point.x <= 1, point.y >= 0, point.y <= 1
                    else
                    {
                        throw RuntimeError( message: "Curves control point out of range: (\( point.x ), \( point.y ))" )
                    }

                    if index > 0, point.x <= self.points[ index - 1 ].x
                    {
                        throw RuntimeError( message: "Curves control points must have strictly increasing x" )
                    }
                }
            }

            /// Evaluates the curve at `x`, clipped to `[0, 1]`.
            ///
            /// - Parameter x: The input coordinate.
            /// - Returns: The interpolated output.
            public func value( at x: Double ) -> Double
            {
                self.value( at: x, tangents: self.tangents() )
            }

            /// Evaluates the curve at `x` using precomputed tangents.
            ///
            /// Flat outside the first and last control points; Hermite-interpolated
            /// within, then clipped to `[0, 1]`.
            ///
            /// - Parameters:
            ///   - x:        The input coordinate.
            ///   - tangents: The per-point tangents from ``tangents()``.
            /// - Returns: The interpolated output.
            func value( at x: Double, tangents: [ Double ] ) -> Double
            {
                guard let first = self.points.first, let last = self.points.last
                else
                {
                    return x
                }

                if x <= first.x
                {
                    return first.y
                }

                if x >= last.x
                {
                    return last.y
                }

                var index = 0

                while index < self.points.count - 1, x > self.points[ index + 1 ].x
                {
                    index += 1
                }

                let p0 = self.points[ index ]
                let p1 = self.points[ index + 1 ]
                let h  = p1.x - p0.x
                let t  = ( x - p0.x ) / h
                let t2 = t * t
                let t3 = t2 * t

                // Cubic Hermite basis functions.
                let h00 =  2 * t3 - 3 * t2 + 1
                let h10 =      t3 - 2 * t2 + t
                let h01 = -2 * t3 + 3 * t2
                let h11 =      t3 -     t2

                let y = h00 * p0.y + h10 * h * tangents[ index ] + h01 * p1.y + h11 * h * tangents[ index + 1 ]

                return Swift.min( 1.0, Swift.max( 0.0, y ) )
            }

            /// Computes monotonicity-preserving (Fritsch–Carlson) tangents at each
            /// control point.
            ///
            /// - Returns: One tangent per control point.
            func tangents() -> [ Double ]
            {
                let count = self.points.count

                guard count >= 2
                else
                {
                    return [ Double ]( repeating: 0, count: count )
                }

                var secants = [ Double ]( repeating: 0, count: count - 1 )

                for i in 0 ..< count - 1
                {
                    secants[ i ] = ( self.points[ i + 1 ].y - self.points[ i ].y ) / ( self.points[ i + 1 ].x - self.points[ i ].x )
                }

                var tangents = [ Double ]( repeating: 0, count: count )

                tangents[ 0 ]         = secants[ 0 ]
                tangents[ count - 1 ] = secants[ count - 2 ]

                for i in 1 ..< count - 1
                {
                    tangents[ i ] = ( secants[ i - 1 ] + secants[ i ] ) / 2.0
                }

                // Clamp the tangents so each segment stays monotonic and cannot
                // overshoot (Fritsch–Carlson).
                for i in 0 ..< count - 1
                {
                    if secants[ i ] == 0
                    {
                        tangents[ i ]     = 0
                        tangents[ i + 1 ] = 0
                    }
                    else
                    {
                        let alpha = tangents[ i ]     / secants[ i ]
                        let beta  = tangents[ i + 1 ] / secants[ i ]
                        let sum   = alpha * alpha + beta * beta

                        if sum > 9.0
                        {
                            let tau = 3.0 / sum.squareRoot()

                            tangents[ i ]     = tau * alpha * secants[ i ]
                            tangents[ i + 1 ] = tau * beta  * secants[ i ]
                        }
                    }
                }

                return tangents
            }

            /// Samples the curve into a lookup table spanning `[0, 1]`.
            ///
            /// - Returns: ``lookupTableSize`` evenly spaced output values.
            func lookupTable() -> [ Double ]
            {
                let tangents = self.tangents()
                let size     = Self.lookupTableSize

                return ( 0 ..< size ).map
                {
                    self.value( at: Double( $0 ) / Double( size - 1 ), tangents: tangents )
                }
            }
        }

        /// How the curve applies across the buffer's channels.
        public enum Channels: Sendable, Equatable
        {
            /// One curve applied identically to every channel.
            case uniform( Curve )

            /// A separate curve for each of the red, green and blue channels;
            /// requires a 3-channel buffer.
            case perChannel( red: Curve, green: Curve, blue: Curve )

            /// Whether every curve is the identity (and so the whole stage is a
            /// no-op).
            public var isIdentity: Bool
            {
                switch self
                {
                    case .uniform( let c ):                  return c.isIdentity
                    case .perChannel( let r, let g, let b ): return r.isIdentity && g.isIdentity && b.isIdentity
                }
            }
        }

        /// How the curve applies across the buffer's channels.
        public let channels: Channels

        /// A human-readable name including the channel mode.
        public var name: String
        {
            switch self.channels
            {
                case .uniform( let c ): return "Curves (\( c.points.count ) points)"
                case .perChannel:       return "Curves (per-channel)"
            }
        }

        /// Creates a curves stage.
        ///
        /// - Parameter channels: How the curve applies across channels.
        public init( channels: Channels )
        {
            self.channels = channels
        }

        /// Applies the tone curve in place.
        ///
        /// - Parameter buffer: The normalized buffer to transform.
        ///
        /// - Throws: A `RuntimeError` if the buffer is not normalized, a curve is
        ///           invalid, or per-channel curves are used with a buffer that is
        ///           not 3-channel.
        public func process( buffer: inout PixelBuffer ) throws
        {
            guard buffer.isNormalized
            else
            {
                throw RuntimeError( message: "Buffer needs to be normalized" )
            }

            switch self.channels
            {
                case .uniform( let curve ):

                    try curve.validate()

                    let lut   = curve.lookupTable()
                    let count = buffer.pixels.count

                    buffer.withUnsafeMutablePixels
                    {
                        guard let baseAddress = $0.baseAddress
                        else
                        {
                            return
                        }

                        Self.applyCurve( to: baseAddress, stride: 1, count: count, lut: lut )
                    }

                case .perChannel( let red, let green, let blue ):

                    try red.validate()
                    try green.validate()
                    try blue.validate()

                    guard buffer.channels == 3
                    else
                    {
                        throw RuntimeError( message: "Per-channel curves require a 3-channel buffer: \( buffer.channels )" )
                    }

                    let redLUT     = red.lookupTable()
                    let greenLUT   = green.lookupTable()
                    let blueLUT    = blue.lookupTable()
                    let pixelCount = buffer.width * buffer.height

                    buffer.withUnsafeMutablePixels
                    {
                        guard let baseAddress = $0.baseAddress
                        else
                        {
                            return
                        }

                        Self.applyCurve( to: baseAddress + 0, stride: 3, count: pixelCount, lut: redLUT )
                        Self.applyCurve( to: baseAddress + 1, stride: 3, count: pixelCount, lut: greenLUT )
                        Self.applyCurve( to: baseAddress + 2, stride: 3, count: pixelCount, lut: blueLUT )
                    }
            }
        }

        /// Applies a lookup table to a strided view of the samples, in place, using
        /// Accelerate's vectorized table interpolation.
        ///
        /// Each sample is clipped to `[0, 1]`, scaled to the table's index domain,
        /// then mapped through ``vDSP_vlintD``, which does the table lookup and the
        /// linear interpolation between the two nearest nodes in one pass. The
        /// table is padded with one sentinel entry (a copy of its last value) so the
        /// interpolation's `A[b + 1]` read stays in bounds at the top of the range,
        /// where the interpolation weight is zero.
        ///
        /// - Parameters:
        ///   - base:   The address of the channel's first sample.
        ///   - stride: The gap, in samples, between successive samples of the
        ///             channel (`1` for a single-channel buffer, the channel count
        ///             for an interleaved one).
        ///   - count:  The number of samples in the channel.
        ///   - lut:    The lookup table from ``Curve/lookupTable()``.
        private static func applyCurve( to base: UnsafeMutablePointer< Double >, stride: Int, count: Int, lut: [ Double ] )
        {
            guard count > 0, lut.isEmpty == false
            else
            {
                return
            }

            let vCount   = vDSP_Length( count )
            let vStride  = vDSP_Stride( stride )
            let maxIndex = Double( lut.count - 1 )

            // Clip into range, then scale to the table's [0, count - 1] index domain.
            vDSP_vclipD( base, vStride, [ 0.0 ], [ 1.0 ], base, vStride, vCount )
            vDSP_vsmulD( base, vStride, [ maxIndex ], base, vStride, vCount )

            var padded = lut

            padded.append( lut[ lut.count - 1 ] )

            padded.withUnsafeBufferPointer
            {
                guard let table = $0.baseAddress
                else
                {
                    return
                }

                vDSP_vlintD( table, base, vStride, base, vStride, vCount, vDSP_Length( $0.count ) )
            }
        }

        /// Maps a sample through a lookup table with linear interpolation between
        /// the two nearest nodes.
        ///
        /// The scalar reference for the vectorized ``applyCurve(to:stride:count:lut:)``.
        ///
        /// - Parameters:
        ///   - value: The normalized sample to map.
        ///   - lut:   The lookup table from ``Curve/lookupTable()``.
        /// - Returns: The mapped sample.
        static func sample( _ value: Double, lut: [ Double ] ) -> Double
        {
            let count   = lut.count
            let clamped = Swift.min( 1.0, Swift.max( 0.0, value ) )
            let position = clamped * Double( count - 1 )
            let lower    = Int( position )

            guard lower < count - 1
            else
            {
                return lut[ count - 1 ]
            }

            let fraction = position - Double( lower )

            return lut[ lower ] + fraction * ( lut[ lower + 1 ] - lut[ lower ] )
        }
    }
}
