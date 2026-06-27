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

public extension Processors
{
    /// Demosaics a single-channel Bayer-mosaic buffer into 3-channel RGB.
    ///
    /// Requires a non-normalized, 1-channel buffer; the result has 3 channels.
    /// The interpolation algorithms live in mode-specific extensions
    /// (`Debayer+Bilinear`, `Debayer+VNG`); this file holds the shared mosaic
    /// geometry and color-layout helpers.
    struct Debayer: PixelProcessor
    {
        /// The arrangement of color filters in the 2×2 Bayer tile, identified by
        /// the colors of the top-left, top-right, bottom-left and bottom-right
        /// samples.
        public enum Pattern: Sendable, Equatable, CustomStringConvertible
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
        public enum Mode: Sendable, Equatable, CustomStringConvertible
        {
            /// Bilinear interpolation: each missing color is the equal-weight
            /// average of its nearest same-color neighbors.
            case bilinear

            /// Variable Number of Gradients: the green channel is interpolated
            /// along low-variation directions selected per pixel, and red/blue
            /// follow as a color difference against the reconstructed green.
            case vng

            /// A human-readable name for the algorithm.
            public var description: String
            {
                switch self
                {
                    case .bilinear: return "Bilinear"
                    case .vng:      return "VNG"
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

        /// Creates a demosaicing stage.
        ///
        /// - Parameters:
        ///   - mode:    The demosaicing algorithm.
        ///   - pattern: The Bayer color-filter arrangement of the input mosaic.
        public init( mode: Mode, pattern: Pattern )
        {
            self.mode    = mode
            self.pattern = pattern
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
            let expected = try PixelUtilities.checkedSampleCount( width: buffer.width, height: buffer.height, channels: 1 )

            guard buffer.pixels.count == expected
            else
            {
                throw RuntimeError( message: "Data size does not match expected size: \( buffer.pixels.count ) != \( expected )" )
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

            let pixels: [ Double ]

            switch self.mode
            {
                case .bilinear: pixels = try Self.bilinear( pixels: buffer.pixels, pattern: self.pattern, width: buffer.width, height: buffer.height )
                case .vng:      pixels = try Self.vng(      pixels: buffer.pixels, pattern: self.pattern, width: buffer.width, height: buffer.height )
            }

            buffer = try PixelBuffer( width: buffer.width, height: buffer.height, channels: 3, pixels: pixels, isNormalized: buffer.isNormalized )
        }

        /// The color a given mosaic site samples.
        internal enum ColorType: Sendable
        {
            /// A red sample site.
            case red

            /// A green sample site.
            case green

            /// A blue sample site.
            case blue
        }

        /// Returns the row-major buffer index of pixel `(x, y)`.
        ///
        /// - Parameters:
        ///   - x:     The column.
        ///   - y:     The row.
        ///   - width: The image width in pixels.
        ///
        /// - Returns: `y × width + x`.
        internal static func index( x: Int, y: Int, width: Int ) -> Int
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
        internal static func colorMap( width: Int, height: Int, pattern: Pattern ) -> [ ColorType ]
        {
            var map = [ ColorType ]( repeating: .red, count: width * height )

            ( 0 ..< height ).forEach
            {
                y in ( 0 ..< width ).forEach
                {
                    x in map[ self.index( x: x, y: y, width: width ) ] = self.colorAt( x: x, y: y, width: width, height: height, pattern: pattern )
                }
            }

            return map
        }

        /// Returns the color sampled at site `(x, y)` for a Bayer pattern, based
        /// on the parity of the row and column within the 2×2 tile.
        ///
        /// Coordinates are clamped to the image bounds before classification, so
        /// a neighbour one step off an edge resolves to the same color as the
        /// edge pixel that edge-clamped reads return — and the parity is computed
        /// on a non-negative coordinate.
        ///
        /// - Parameters:
        ///   - x:       The column (may be out of range).
        ///   - y:       The row (may be out of range).
        ///   - width:   The image width in pixels.
        ///   - height:  The image height in pixels.
        ///   - pattern: The Bayer arrangement.
        ///
        /// - Returns: The `ColorType` sampled at that site.
        internal static func colorAt( x: Int, y: Int, width: Int, height: Int, pattern: Pattern ) -> ColorType
        {
            let clampedX = Swift.min( Swift.max( x, 0 ), width  - 1 )
            let clampedY = Swift.min( Swift.max( y, 0 ), height - 1 )
            let evenCol  = clampedX % 2 == 0
            let evenRow  = clampedY % 2 == 0

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
    }
}
