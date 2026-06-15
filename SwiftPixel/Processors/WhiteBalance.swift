/*******************************************************************************
 * The MIT License (MIT)
 *
 * Copyright (c) 2025, Jean-David Gadina - www.xs-labs.com
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
    /// Adjusts the per-channel balance of a 3-channel (RGB) buffer.
    ///
    /// Requires a normalized, 3-channel buffer. After applying the gains the
    /// samples are re-clipped to `[0, 1]`.
    struct WhiteBalance: PixelProcessor
    {
        /// How the per-channel gains are determined.
        public enum Mode: Sendable, Equatable, CustomStringConvertible
        {
            /// Computes gains automatically using the gray-world assumption (each
            /// channel is scaled so its average matches the overall gray average).
            case auto

            /// Applies the given per-channel multiplicative gains directly.
            case manual( red: Double, green: Double, blue: Double )

            /// A human-readable description of the mode and any gains.
            public var description: String
            {
                switch self
                {
                    case .auto:                          return "Auto"
                    case .manual( let r, let g, let b ): return String( format: "Manual - R: %.02f, G: %.02f, B: %.02f", r, g, b )
                }
            }
        }

        /// How the per-channel gains are determined.
        public let mode: Mode

        /// A human-readable name including the mode.
        public var name: String
        {
            "White Balance (\( self.mode ))"
        }

        /// Applies white-balance gains to `buffer`, in place.
        ///
        /// - Parameter buffer: A normalized, 3-channel buffer.
        ///
        /// - Throws: A `RuntimeError` if the buffer is not normalized, is not
        ///           3-channel, or its sample count does not match its geometry.
        public func process( buffer: inout PixelBuffer ) throws
        {
            guard buffer.isNormalized
            else
            {
                throw RuntimeError( message: "Buffer needs to be normalized" )
            }

            guard buffer.channels == 3
            else
            {
                throw RuntimeError( message: "Unsupported channel count: \( buffer.channels )" )
            }

            let expected = try PixelUtilities.checkedSampleCount( width: buffer.width, height: buffer.height, channels: buffer.channels )

            guard buffer.pixels.count == expected
            else
            {
                throw RuntimeError( message: "Data size does not match expected size: \( buffer.pixels.count ) != \( expected )" )
            }

            switch ( self.mode )
            {
                case .auto:

                    let rgb = try Self.computeGains( buffer: buffer )

                    try Self.whiteBalance( buffer: &buffer, r: rgb.r, g: rgb.g, b: rgb.b )

                case .manual( let r, let g, let b ):

                    try Self.whiteBalance( buffer: &buffer, r: r, g: g, b: b )
            }
        }

        /// Multiplies each channel by its gain and re-clips the result to
        /// `[0, 1]`, in place.
        ///
        /// - Parameters:
        ///   - buffer: A 3-channel buffer.
        ///   - r:      The gain for the red channel.
        ///   - g:      The gain for the green channel.
        ///   - b:      The gain for the blue channel.
        ///
        /// - Throws: A `RuntimeError` if the sample buffer cannot be accessed.
        private static func whiteBalance( buffer: inout PixelBuffer, r: Double, g: Double, b: Double ) throws
        {
            let count = vDSP_Length( buffer.width * buffer.height )

            try buffer.withUnsafeMutablePixels
            {
                guard let baseAddress = $0.baseAddress
                else
                {
                    throw RuntimeError( message: "Failed to access data buffer" )
                }

                var r = r
                var g = g
                var b = b

                vDSP_vsmulD( baseAddress, 3, &r, baseAddress, 3, count )
                vDSP_vsmulD( baseAddress.advanced( by: 1 ), 3, &g, baseAddress.advanced( by: 1 ), 3, count )
                vDSP_vsmulD( baseAddress.advanced( by: 2 ), 3, &b, baseAddress.advanced( by: 2 ), 3, count )

                vDSP_vclipD( baseAddress, 1, [ 0.0 ], [ 1.0 ], baseAddress, 1, count * 3 )
            }
        }

        /// Computes gray-world white-balance gains for a 3-channel buffer.
        ///
        /// Each gain scales a channel's average toward the overall gray average.
        /// A channel whose average is zero gets a gain of `1.0`, avoiding a
        /// division by zero.
        ///
        /// - Parameter buffer: A 3-channel buffer.
        ///
        /// - Returns: The per-channel gains.
        ///
        /// - Throws: A `RuntimeError` if the sample buffer cannot be accessed.
        private static func computeGains( buffer: PixelBuffer ) throws -> ( r: Double, g: Double, b: Double )
        {
            let count = vDSP_Length( buffer.width * buffer.height )

            return try buffer.pixels.withUnsafeBufferPointer
            {
                guard let baseAddress = $0.baseAddress
                else
                {
                    throw RuntimeError( message: "Failed to access data buffer" )
                }

                var sumR = 0.0
                var sumG = 0.0
                var sumB = 0.0

                vDSP_sveD( baseAddress, 3, &sumR, count )
                vDSP_sveD( baseAddress.advanced( by: 1 ), 3, &sumG, count )
                vDSP_sveD( baseAddress.advanced( by: 2 ), 3, &sumB, count )

                let avgR  = sumR / Double( count )
                let avgG  = sumG / Double( count )
                let avgB  = sumB / Double( count )
                let gray  = ( avgR + avgG + avgB ) / 3.0
                let gainR = avgR > 0 ? gray / avgR : 1.0
                let gainG = avgG > 0 ? gray / avgG : 1.0
                let gainB = avgB > 0 ? gray / avgB : 1.0

                return ( gainR, gainG, gainB )
            }
        }
    }
}
