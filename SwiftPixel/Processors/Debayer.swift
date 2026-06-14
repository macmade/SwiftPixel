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
    /// Demosaics a single-channel Bayer-mosaic buffer into 3-channel RGB.
    ///
    /// Requires a non-normalized, 1-channel buffer; the result has 3 channels.
    struct Debayer: PixelProcessor
    {
        /// The arrangement of color filters in the 2×2 Bayer tile, identified by
        /// the colors of the top-left, top-right, bottom-left and bottom-right
        /// samples.
        public enum Pattern: Sendable, CustomStringConvertible
        {
            /// Blue, Green / Green, Red.
            case bggr

            /// Red, Green / Blue, Green.
            case rgbg

            /// Green, Red / Blue, Green.
            case grbg

            /// Red, Green / Green, Blue.
            case rggb

            /// The four-letter pattern code (e.g. `"RGGB"`).
            public var description: String
            {
                switch self
                {
                    case .bggr: return "BGGR"
                    case .rgbg: return "RGBG"
                    case .grbg: return "GRBG"
                    case .rggb: return "RGGB"
                }
            }
        }

        /// The demosaicing algorithm.
        public enum Mode: Sendable, CustomStringConvertible
        {
            /// Bilinear interpolation: each missing color is the equal-weight
            /// average of its nearest same-color neighbors.
            case bilinear

            /// A human-readable name for the algorithm.
            public var description: String
            {
                switch self
                {
                    case .bilinear: return "Bilinear"
                }
            }
        }

        /// The demosaicing algorithm.
        public let mode: Mode

        /// The Bayer color-filter arrangement of the input mosaic.
        public let pattern: Pattern

        /// A human-readable name including the mode and pattern.
        public var name: String
        {
            "Debayer (\( self.mode ) \( self.pattern ))"
        }

        /// Demosaics `buffer` from a Bayer mosaic into 3-channel RGB, in place.
        ///
        /// - Parameter buffer: A non-normalized, 1-channel mosaic buffer.
        ///
        /// - Throws: A `RuntimeError` if the buffer is normalized, is not
        ///           single-channel, or its sample count does not match its
        ///           geometry.
        public func process( buffer: inout PixelBuffer ) throws
        {
            guard buffer.pixels.count == buffer.width * buffer.height
            else
            {
                throw RuntimeError( message: "Data size does not match expected size: \( buffer.pixels.count ) != \( buffer.width * buffer.height )" )
            }

            guard buffer.channels == 1
            else
            {
                throw RuntimeError( message: "Unsupported channel count: \( buffer.channels )" )
            }

            guard buffer.isNormalized == false
            else
            {
                throw RuntimeError( message: "Input buffer must not be normalized" )
            }

            switch self.mode
            {
                case .bilinear:

                    let pixels = try Self.bilinear( pixels: buffer.pixels, pattern: self.pattern, width: buffer.width, height: buffer.height )

                    buffer = try PixelBuffer( width: buffer.width, height: buffer.height, channels: 3, pixels: pixels, isNormalized: buffer.isNormalized )
            }
        }

        /// The color a given mosaic site samples.
        private enum ColorType: Sendable
        {
            /// A red sample site.
            case red

            /// A green sample site.
            case green

            /// A blue sample site.
            case blue
        }

        /// Reconstructs a 3-channel RGB image from a Bayer mosaic using bilinear
        /// interpolation.
        ///
        /// At each site the present color is taken directly and the two missing
        /// colors are the equal-weight average of their nearest same-color
        /// neighbors (a 4-neighbor cross or 4-corner set at red/blue sites, a
        /// 2-neighbor pair at green sites). Interpolation runs in parallel over
        /// rows. Out-of-bounds neighbors are clamped to the image edge.
        ///
        /// - Parameters:
        ///   - pixels:  The single-channel mosaic samples, row-major.
        ///   - pattern: The Bayer arrangement of `pixels`.
        ///   - width:   The image width in pixels.
        ///   - height:  The image height in pixels.
        ///
        /// - Returns: `width × height × 3` interleaved RGB samples.
        ///
        /// - Throws: A `RuntimeError` if the sample buffers cannot be accessed.
        private static func bilinear( pixels: [ Double ], pattern: Pattern, width: Int, height: Int ) throws -> [ Double ]
        {
            let colorMap = self.colorMap( width: width, height: height, pattern: pattern )
            var output   = [ Double ]( repeating: 0.0, count: width * height * 3 )

            try pixels.withUnsafeBufferPointer
            {
                guard let baseAddress = $0.baseAddress
                else
                {
                    throw RuntimeError( message: "Failed to access input data buffer" )
                }

                let input = UnsafeSendable( baseAddress )

                try output.withUnsafeMutableBufferPointer
                {
                    guard let baseAddress = $0.baseAddress
                    else
                    {
                        throw RuntimeError( message: "Failed to access output data buffer" )
                    }

                    let output = UnsafeSendable( baseAddress )

                    DispatchQueue.concurrentPerform( iterations: height )
                    {
                        y in ( 0 ..< width ).forEach
                        {
                            x in

                            let i         = index( x: x, y: y, width: width )
                            let val       = input.value[ i ]
                            let colorType = colorMap[ i ]

                            var r = 0.0
                            var g = 0.0
                            var b = 0.0

                            switch colorType
                            {
                                case .red:

                                    r = val
                                    g = self.averageSIMD( values:
                                        [
                                            self.safeRead( x: x - 1, y: y,     width: width, height: height, data: input.value ),
                                            self.safeRead( x: x + 1, y: y,     width: width, height: height, data: input.value ),
                                            self.safeRead( x: x,     y: y - 1, width: width, height: height, data: input.value ),
                                            self.safeRead( x: x,     y: y + 1, width: width, height: height, data: input.value ),
                                        ]
                                    )
                                    b = self.averageSIMD( values:
                                        [
                                            self.safeRead( x: x - 1, y: y - 1, width: width, height: height, data: input.value ),
                                            self.safeRead( x: x + 1, y: y - 1, width: width, height: height, data: input.value ),
                                            self.safeRead( x: x - 1, y: y + 1, width: width, height: height, data: input.value ),
                                            self.safeRead( x: x + 1, y: y + 1, width: width, height: height, data: input.value ),
                                        ]
                                    )

                                case .green:

                                    let left  = self.colorAt( x: x - 1, y: y, pattern: pattern )
                                    let right = self.colorAt( x: x + 1, y: y, pattern: pattern )

                                    if left == .red || right == .red
                                    {
                                        r = self.averageSIMD( values:
                                            [
                                                self.safeRead( x: x - 1, y: y, width: width, height: height, data: input.value ),
                                                self.safeRead( x: x + 1, y: y, width: width, height: height, data: input.value ),
                                            ]
                                        )
                                        g = val
                                        b = self.averageSIMD( values:
                                            [
                                                self.safeRead( x: x, y: y - 1, width: width, height: height, data: input.value ),
                                                self.safeRead( x: x, y: y + 1, width: width, height: height, data: input.value ),
                                            ]
                                        )
                                    }
                                    else
                                    {
                                        r = self.averageSIMD( values:
                                            [
                                                self.safeRead( x: x, y: y - 1, width: width, height: height, data: input.value ),
                                                self.safeRead( x: x, y: y + 1, width: width, height: height, data: input.value ),
                                            ]
                                        )
                                        g = val
                                        b = self.averageSIMD( values:
                                            [
                                                self.safeRead( x: x - 1, y: y, width: width, height: height, data: input.value ),
                                                self.safeRead( x: x + 1, y: y, width: width, height: height, data: input.value ),
                                            ]
                                        )
                                    }

                                case .blue:

                                    r = self.averageSIMD( values:
                                        [
                                            self.safeRead( x: x - 1, y: y - 1, width: width, height: height, data: input.value ),
                                            self.safeRead( x: x + 1, y: y - 1, width: width, height: height, data: input.value ),
                                            self.safeRead( x: x - 1, y: y + 1, width: width, height: height, data: input.value ),
                                            self.safeRead( x: x + 1, y: y + 1, width: width, height: height, data: input.value ),
                                        ]
                                    )
                                    g = self.averageSIMD( values:
                                        [
                                            self.safeRead( x: x - 1, y: y,     width: width, height: height, data: input.value ),
                                            self.safeRead( x: x + 1, y: y,     width: width, height: height, data: input.value ),
                                            self.safeRead( x: x,     y: y - 1, width: width, height: height, data: input.value ),
                                            self.safeRead( x: x,     y: y + 1, width: width, height: height, data: input.value ),
                                        ]
                                    )
                                    b = val
                            }

                            let index                 = i * 3
                            output.value[ index + 0 ] = r
                            output.value[ index + 1 ] = g
                            output.value[ index + 2 ] = b
                        }
                    }
                }
            }

            return output
        }

        /// Returns the row-major buffer index of pixel `(x, y)`.
        ///
        /// - Parameters:
        ///   - x:     The column.
        ///   - y:     The row.
        ///   - width: The image width in pixels.
        ///
        /// - Returns: `y × width + x`.
        private static func index( x: Int, y: Int, width: Int ) -> Int
        {
            return y * width + x
        }

        /// Precomputes the color type of every site for a pattern, so the inner
        /// loop avoids recomputing it per pixel.
        ///
        /// - Parameters:
        ///   - width:   The image width in pixels.
        ///   - height:  The image height in pixels.
        ///   - pattern: The Bayer arrangement.
        ///
        /// - Returns: A row-major map of `ColorType` per site.
        private static func colorMap( width: Int, height: Int, pattern: Pattern ) -> [ ColorType ]
        {
            var map = [ ColorType ]( repeating: .red, count: width * height )

            ( 0 ..< height ).forEach
            {
                y in ( 0 ..< width ).forEach
                {
                    x in map[ self.index( x: x, y: y, width: width ) ] = self.colorAt( x: x, y: y, pattern: pattern )
                }
            }

            return map
        }

        /// Returns the color sampled at site `(x, y)` for a Bayer pattern, based
        /// on the parity of the row and column within the 2×2 tile.
        ///
        /// - Parameters:
        ///   - x:       The column.
        ///   - y:       The row.
        ///   - pattern: The Bayer arrangement.
        ///
        /// - Returns: The `ColorType` sampled at that site.
        private static func colorAt( x: Int, y: Int, pattern: Pattern ) -> ColorType
        {
            let evenCol = x % 2 == 0
            let evenRow = y % 2 == 0

            switch pattern
            {
                case .bggr:

                    switch ( evenRow, evenCol )
                    {
                        case ( true,  true  ): return .blue
                        case ( true,  false ): return .green
                        case ( false, true  ): return .green
                        case ( false, false ): return .red
                    }

                case .rgbg:

                    switch ( evenRow, evenCol )
                    {
                        case ( true,  true  ): return .red
                        case ( true,  false ): return .green
                        case ( false, true  ): return .blue
                        case ( false, false ): return .green
                    }

                case .grbg:

                    switch ( evenRow, evenCol )
                    {
                        case ( true,  false ): return .red
                        case ( true,  true  ): return .green
                        case ( false, false ): return .green
                        case ( false, true  ): return .blue
                    }

                case .rggb:

                    switch ( evenRow, evenCol )
                    {
                        case ( true,  true  ): return .red
                        case ( true,  false ): return .green
                        case ( false, true  ): return .green
                        case ( false, false ): return .blue
                    }
            }
        }

        /// Reads sample `(x, y)`, clamping coordinates to the image edge so
        /// neighbor reads near the border stay in bounds.
        ///
        /// - Parameters:
        ///   - x:      The column (may be out of range).
        ///   - y:      The row (may be out of range).
        ///   - width:  The image width in pixels.
        ///   - height: The image height in pixels.
        ///   - data:   The single-channel sample buffer.
        ///
        /// - Returns: The sample at the clamped coordinate.
        private static func safeRead( x: Int, y: Int, width: Int, height: Int, data: UnsafePointer< Double > ) -> Double
        {
            let clampedX = min( max( x, 0 ), width  - 1 )
            let clampedY = min( max( y, 0 ), height - 1 )

            return data[ self.index( x: clampedX, y: clampedY, width: width ) ]
        }

        /// Returns the arithmetic mean of `values` using vDSP.
        ///
        /// - Parameter values: The values to average.
        ///
        /// - Returns: Their mean.
        private static func averageSIMD( values: [ Double ] ) -> Double
        {
            var result = 0.0

            vDSP_meanvD( values, 1, &result, vDSP_Length( values.count ) )

            return result
        }
    }
}
