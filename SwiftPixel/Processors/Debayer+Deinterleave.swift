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

public extension Processors.Debayer
{
    /// Splits a Bayer mosaic into its three per-channel sample sets, by
    /// color-filter position — *without* demosaicing.
    ///
    /// Unlike ``process(buffer:)``, which interpolates the mosaic into a
    /// co-located 3-channel image, this collects each site's raw sample into the
    /// channel its filter samples, using the same tile geometry as the demosaic
    /// (``colorMap(width:height:pattern:)``). The green set holds both green sites
    /// of every 2×2 tile, so it is roughly twice the size of the red and blue
    /// sets; the sets are intentionally left at their natural, unequal sizes and
    /// not co-located, because the caller only needs each channel's own robust
    /// statistics (median / MAD) — no interpolation, and so no cross-channel
    /// blending of one channel's samples into another.
    ///
    /// - Parameters:
    ///   - pixels:  The row-major mosaic samples, one per pixel.
    ///   - width:   The mosaic width in pixels. Must be positive.
    ///   - height:  The mosaic height in pixels. Must be positive.
    ///   - pattern: The Bayer color-filter arrangement of the mosaic.
    /// - Returns: The red, green and blue sample sets, each in row-major order.
    ///
    /// - Throws: A `PixelBufferError` if the sample count does not match `width ×
    ///           height`, or the geometry is invalid.
    static func deinterleave( mosaic pixels: [ Double ], width: Int, height: Int, pattern: Pattern ) throws -> ( red: [ Double ], green: [ Double ], blue: [ Double ] )
    {
        let expected = try PixelUtilities.checkedSampleCount( width: width, height: height, channels: 1 )

        guard pixels.count == expected
        else
        {
            throw PixelBufferError.dataSizeMismatch( expected: expected, actual: pixels.count )
        }

        let colors = Self.colorMap( width: width, height: height, pattern: pattern )

        var red   = [ Double ]()
        var green = [ Double ]()
        var blue  = [ Double ]()

        // Reserve the natural per-tile proportions (¼ red, ½ green, ¼ blue) to
        // avoid repeated reallocation while partitioning.
        red.reserveCapacity(   pixels.count / 4 )
        green.reserveCapacity( pixels.count / 2 )
        blue.reserveCapacity(  pixels.count / 4 )

        colors.enumerated().forEach
        {
            index, color in switch color
            {
                case .red:   red.append(   pixels[ index ] )
                case .green: green.append( pixels[ index ] )
                case .blue:  blue.append(  pixels[ index ] )
            }
        }

        return ( red: red, green: green, blue: blue )
    }
}
