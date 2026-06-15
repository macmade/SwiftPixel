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

import Foundation
import SwiftUtilities

extension Processors.Debayer
{
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
    internal static func bilinear( pixels: [ Double ], pattern: Pattern, width: Int, height: Int ) throws -> [ Double ]
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

                PixelUtilities.parallelOrSerial( iterations: height, threshold: 64 )
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

                                let left  = self.safeRead( x: x - 1, y: y,     width: width, height: height, data: input.value )
                                let right = self.safeRead( x: x + 1, y: y,     width: width, height: height, data: input.value )
                                let up    = self.safeRead( x: x,     y: y - 1, width: width, height: height, data: input.value )
                                let down  = self.safeRead( x: x,     y: y + 1, width: width, height: height, data: input.value )
                                let ul    = self.safeRead( x: x - 1, y: y - 1, width: width, height: height, data: input.value )
                                let ur    = self.safeRead( x: x + 1, y: y - 1, width: width, height: height, data: input.value )
                                let ll    = self.safeRead( x: x - 1, y: y + 1, width: width, height: height, data: input.value )
                                let lr    = self.safeRead( x: x + 1, y: y + 1, width: width, height: height, data: input.value )

                                r = val
                                g = ( left + right + up + down ) * 0.25
                                b = ( ul + ur + ll + lr ) * 0.25

                            case .green:

                                let left  = self.colorAt( x: x - 1, y: y, width: width, height: height, pattern: pattern )
                                let right = self.colorAt( x: x + 1, y: y, width: width, height: height, pattern: pattern )

                                let horizontal = (
                                    self.safeRead( x: x - 1, y: y, width: width, height: height, data: input.value )
                                  + self.safeRead( x: x + 1, y: y, width: width, height: height, data: input.value )
                                ) * 0.5
                                let vertical = (
                                    self.safeRead( x: x, y: y - 1, width: width, height: height, data: input.value )
                                  + self.safeRead( x: x, y: y + 1, width: width, height: height, data: input.value )
                                ) * 0.5

                                g = val

                                if left == .red || right == .red
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

                                let left  = self.safeRead( x: x - 1, y: y,     width: width, height: height, data: input.value )
                                let right = self.safeRead( x: x + 1, y: y,     width: width, height: height, data: input.value )
                                let up    = self.safeRead( x: x,     y: y - 1, width: width, height: height, data: input.value )
                                let down  = self.safeRead( x: x,     y: y + 1, width: width, height: height, data: input.value )
                                let ul    = self.safeRead( x: x - 1, y: y - 1, width: width, height: height, data: input.value )
                                let ur    = self.safeRead( x: x + 1, y: y - 1, width: width, height: height, data: input.value )
                                let ll    = self.safeRead( x: x - 1, y: y + 1, width: width, height: height, data: input.value )
                                let lr    = self.safeRead( x: x + 1, y: y + 1, width: width, height: height, data: input.value )

                                r = ( ul + ur + ll + lr ) * 0.25
                                g = ( left + right + up + down ) * 0.25
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
}
