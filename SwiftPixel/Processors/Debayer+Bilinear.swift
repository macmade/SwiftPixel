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

extension Processors.Debayer
{
    /// The four orthogonal neighbour offsets (left, right, up, down).
    private static let orthogonalOffsets: [ ( dx: Int, dy: Int ) ] = [ ( -1, 0 ), ( 1, 0 ), ( 0, -1 ), ( 0, 1 ) ]

    /// The four diagonal neighbour offsets.
    private static let diagonalOffsets: [ ( dx: Int, dy: Int ) ] = [ ( -1, -1 ), ( 1, -1 ), ( -1, 1 ), ( 1, 1 ) ]

    /// The two horizontal neighbour offsets (left, right).
    private static let horizontalOffsets: [ ( dx: Int, dy: Int ) ] = [ ( -1, 0 ), ( 1, 0 ) ]

    /// The two vertical neighbour offsets (up, down).
    private static let verticalOffsets: [ ( dx: Int, dy: Int ) ] = [ ( 0, -1 ), ( 0, 1 ) ]

    /// Reconstructs a 3-channel RGB image from a Bayer mosaic using bilinear
    /// interpolation.
    ///
    /// At each site the present color is taken directly and the two missing
    /// colors are the equal-weight average of their nearest same-color
    /// neighbors (a 4-neighbor cross or 4-corner set at red/blue sites, a
    /// 2-neighbor pair at green sites). At the border only the same-color
    /// neighbors that actually lie inside the image are averaged, so a border
    /// pixel never mixes in an edge-clamped wrong-color sample. Interpolation
    /// runs in parallel over rows.
    ///
    /// - Parameters:
    ///   - pixels:  The single-channel mosaic samples, row-major.
    ///   - pattern: The Bayer arrangement of `pixels`.
    ///   - width:   The image width in pixels.
    ///   - height:  The image height in pixels.
    ///
    /// - Returns: `width × height × 3` interleaved RGB samples.
    ///
    /// - Throws: A `PixelBufferError` if the sample buffers cannot be accessed.
    internal static func bilinear( pixels: [ Double ], pattern: Pattern, width: Int, height: Int ) throws -> [ Double ]
    {
        let colorMap = self.colorMap( width: width, height: height, pattern: pattern )
        var output   = [ Double ]( repeating: 0.0, count: width * height * 3 )

        try pixels.withUnsafeBufferPointer
        {
            guard let baseAddress = $0.baseAddress
            else
            {
                throw PixelBufferError.bufferAccessFailed( role: .input )
            }

            nonisolated( unsafe ) let input = baseAddress

            try output.withUnsafeMutableBufferPointer
            {
                guard let baseAddress = $0.baseAddress
                else
                {
                    throw PixelBufferError.bufferAccessFailed( role: .output )
                }

                nonisolated( unsafe ) let output = baseAddress

                PixelUtilities.parallelOrSerial( iterations: height, threshold: 64 )
                {
                    y in ( 0 ..< width ).forEach
                    {
                        x in

                        let i         = index( x: x, y: y, width: width )
                        let val       = input[ i ]
                        let colorType = colorMap[ i ]

                        var r = 0.0
                        var g = 0.0
                        var b = 0.0

                        switch colorType
                        {
                            case .red:

                                r = val
                                g = self.averageInBounds( offsets: Self.orthogonalOffsets, x: x, y: y, width: width, height: height, data: input, fallback: val )
                                b = self.averageInBounds( offsets: Self.diagonalOffsets,   x: x, y: y, width: width, height: height, data: input, fallback: val )

                            case .green:

                                let leftColor  = self.colorAt( x: x - 1, y: y, width: width, height: height, pattern: pattern )
                                let rightColor = self.colorAt( x: x + 1, y: y, width: width, height: height, pattern: pattern )

                                let horizontal = self.averageInBounds( offsets: Self.horizontalOffsets, x: x, y: y, width: width, height: height, data: input, fallback: val )
                                let vertical   = self.averageInBounds( offsets: Self.verticalOffsets,   x: x, y: y, width: width, height: height, data: input, fallback: val )

                                g = val

                                if leftColor == .red || rightColor == .red
                                {
                                    r = horizontal
                                    b = vertical
                                }
                                else
                                {
                                    r = vertical
                                    b = horizontal
                                }

                            case .blue:

                                r = self.averageInBounds( offsets: Self.diagonalOffsets,   x: x, y: y, width: width, height: height, data: input, fallback: val )
                                g = self.averageInBounds( offsets: Self.orthogonalOffsets, x: x, y: y, width: width, height: height, data: input, fallback: val )
                                b = val
                        }

                        let index           = i * 3
                        output[ index + 0 ] = r
                        output[ index + 1 ] = g
                        output[ index + 2 ] = b
                    }
                }
            }
        }

        return output
    }

    /// Averages `data` over the neighbour `offsets` that fall inside the image,
    /// so a border pixel never folds in an edge-clamped (wrong-color) sample.
    ///
    /// - Parameters:
    ///   - offsets:  The neighbour offsets to consider.
    ///   - x:        The column of the site.
    ///   - y:        The row of the site.
    ///   - width:    The image width in pixels.
    ///   - height:   The image height in pixels.
    ///   - data:     The single-channel sample buffer.
    ///   - fallback: The value to return if no offset is in bounds.
    ///
    /// - Returns: The mean of the in-bounds neighbours, or `fallback` if none is
    ///            in bounds.
    private static func averageInBounds( offsets: [ ( dx: Int, dy: Int ) ], x: Int, y: Int, width: Int, height: Int, data: UnsafePointer< Double >, fallback: Double ) -> Double
    {
        var sum   = 0.0
        var count = 0

        offsets.forEach
        {
            offset in

            let nx = x + offset.dx
            let ny = y + offset.dy

            guard nx >= 0, nx < width, ny >= 0, ny < height
            else
            {
                return
            }

            sum   += data[ self.index( x: nx, y: ny, width: width ) ]
            count += 1
        }

        return count == 0 ? fallback : sum / Double( count )
    }
}
