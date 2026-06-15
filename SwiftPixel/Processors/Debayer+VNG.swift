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
    /// The four orthogonal neighbour offsets (left, right, up, down).
    private static let orthogonalOffsets: [ ( dx: Int, dy: Int ) ] = [ ( -1, 0 ), ( 1, 0 ), ( 0, -1 ), ( 0, 1 ) ]

    /// The four diagonal neighbour offsets.
    private static let diagonalOffsets: [ ( dx: Int, dy: Int ) ] = [ ( -1, -1 ), ( 1, -1 ), ( -1, 1 ), ( 1, 1 ) ]

    /// Reconstructs a 3-channel RGB image from a Bayer mosaic using Variable
    /// Number of Gradients (VNG) demosaicing.
    ///
    /// The green channel is reconstructed first — directly at green sites and
    /// via `interpolateGreen` (gradient-weighted) at red/blue sites — then red
    /// and blue follow as a color difference against that green plane. The
    /// present color at each site is preserved exactly. Both passes run in
    /// parallel over rows; out-of-bounds neighbors are clamped to the edge.
    ///
    /// - Parameters:
    ///   - pixels:  The single-channel mosaic samples, row-major.
    ///   - pattern: The Bayer arrangement of `pixels`.
    ///   - width:   The image width in pixels.
    ///   - height:  The image height in pixels.
    ///
    /// - Returns: `width × height × 3` interleaved RGB samples.
    ///
    /// - Throws: A `RuntimeError` if the output buffer cannot be accessed.
    internal static func vng( pixels: [ Double ], pattern: Pattern, width: Int, height: Int ) throws -> [ Double ]
    {
        let colorMap = self.colorMap( width: width, height: height, pattern: pattern )
        let green    = self.greenPlane( pixels: pixels, colorMap: colorMap, width: width, height: height )
        var output   = [ Double ]( repeating: 0.0, count: width * height * 3 )

        try output.withUnsafeMutableBufferPointer
        {
            guard let baseAddress = $0.baseAddress
            else
            {
                throw RuntimeError( message: "Failed to access output data buffer" )
            }

            let output = UnsafeMutableSendable( baseAddress )

            DispatchQueue.concurrentPerform( iterations: height )
            {
                y in ( 0 ..< width ).forEach
                {
                    x in

                    let i   = self.index( x: x, y: y, width: width )
                    let rgb = self.interpolateColor( pixels: pixels, green: green, colorMap: colorMap, pattern: pattern, x: x, y: y, width: width, height: height )

                    output.value[ i * 3 + 0 ] = rgb.r
                    output.value[ i * 3 + 1 ] = rgb.g
                    output.value[ i * 3 + 2 ] = rgb.b
                }
            }
        }

        return output
    }

    /// Reconstructs the full green plane: green sites keep their value, red/blue
    /// sites use the gradient-weighted `interpolateGreen`.
    ///
    /// - Parameters:
    ///   - pixels:   The single-channel mosaic samples, row-major.
    ///   - colorMap: The per-site color map.
    ///   - width:    The image width in pixels.
    ///   - height:   The image height in pixels.
    ///
    /// - Returns: A row-major green value per site.
    private static func greenPlane( pixels: [ Double ], colorMap: [ ColorType ], width: Int, height: Int ) -> [ Double ]
    {
        var green = [ Double ]( repeating: 0.0, count: width * height )

        green.withUnsafeMutableBufferPointer
        {
            let buffer = UnsafeMutableSendable( $0 )

            DispatchQueue.concurrentPerform( iterations: height )
            {
                y in ( 0 ..< width ).forEach
                {
                    x in

                    let i = self.index( x: x, y: y, width: width )

                    buffer.value[ i ] = colorMap[ i ] == .green ? pixels[ i ] : self.interpolateGreen( pixels: pixels, x: x, y: y, width: width, height: height )
                }
            }
        }

        return green
    }

    /// Computes the red, green and blue values at site `(x, y)`.
    ///
    /// Green comes from the reconstructed plane. Red and blue are a color
    /// difference (chroma) against green, averaged over the same-color
    /// neighbours: diagonal neighbours at a red/blue site, and the orthogonal
    /// neighbours of the matching color at a green site.
    ///
    /// - Parameters:
    ///   - pixels:   The single-channel mosaic samples, row-major.
    ///   - green:    The reconstructed green plane.
    ///   - colorMap: The per-site color map.
    ///   - pattern:  The Bayer arrangement.
    ///   - x:        The column of the site.
    ///   - y:        The row of the site.
    ///   - width:    The image width in pixels.
    ///   - height:   The image height in pixels.
    ///
    /// - Returns: The interpolated `(r, g, b)` at the site.
    private static func interpolateColor( pixels: [ Double ], green: [ Double ], colorMap: [ ColorType ], pattern: Pattern, x: Int, y: Int, width: Int, height: Int ) -> ( r: Double, g: Double, b: Double )
    {
        let i = self.index( x: x, y: y, width: width )
        let g = green[ i ]

        switch colorMap[ i ]
        {
            case .red:

                let b = g + self.chromaDifference( pixels: pixels, green: green, offsets: Self.diagonalOffsets, x: x, y: y, width: width, height: height )

                return ( r: pixels[ i ], g: g, b: b )

            case .blue:

                let r = g + self.chromaDifference( pixels: pixels, green: green, offsets: Self.diagonalOffsets, x: x, y: y, width: width, height: height )

                return ( r: r, g: g, b: pixels[ i ] )

            case .green:

                let r = g + self.chromaDifference( for: .red,  pixels: pixels, green: green, pattern: pattern, x: x, y: y, width: width, height: height )
                let b = g + self.chromaDifference( for: .blue, pixels: pixels, green: green, pattern: pattern, x: x, y: y, width: width, height: height )

                return ( r: r, g: g, b: b )
        }
    }

    /// Averages the color difference `sample − green` over the given neighbour
    /// offsets, using edge-clamped reads.
    ///
    /// - Parameters:
    ///   - pixels:  The single-channel mosaic samples, row-major.
    ///   - green:   The reconstructed green plane.
    ///   - offsets: The neighbour offsets to average over.
    ///   - x:       The column of the site.
    ///   - y:       The row of the site.
    ///   - width:   The image width in pixels.
    ///   - height:  The image height in pixels.
    ///
    /// - Returns: The mean neighbour color difference, or `0` if `offsets` is empty.
    private static func chromaDifference( pixels: [ Double ], green: [ Double ], offsets: [ ( dx: Int, dy: Int ) ], x: Int, y: Int, width: Int, height: Int ) -> Double
    {
        guard offsets.isEmpty == false
        else
        {
            return 0
        }

        var sum = 0.0

        for offset in offsets
        {
            sum += self.sample( pixels: pixels, x: x + offset.dx, y: y + offset.dy, width: width, height: height )
                 - self.sample( pixels: green,  x: x + offset.dx, y: y + offset.dy, width: width, height: height )
        }

        return sum / Double( offsets.count )
    }

    /// Averages the color difference `sample − green` over the orthogonal
    /// neighbours whose Bayer site is `color`, using edge-clamped reads. This is
    /// the green-site equivalent of `chromaDifference` without materializing a
    /// filtered offset array per pixel.
    ///
    /// - Parameters:
    ///   - color:   The neighbour color to average over (`.red` or `.blue`).
    ///   - pixels:  The single-channel mosaic samples, row-major.
    ///   - green:   The reconstructed green plane.
    ///   - pattern: The Bayer arrangement.
    ///   - x:       The column of the green site.
    ///   - y:       The row of the green site.
    ///   - width:   The image width in pixels.
    ///   - height:  The image height in pixels.
    ///
    /// - Returns: The mean neighbour color difference, or `0` if no orthogonal
    ///            neighbour has the requested color.
    private static func chromaDifference( for color: ColorType, pixels: [ Double ], green: [ Double ], pattern: Pattern, x: Int, y: Int, width: Int, height: Int ) -> Double
    {
        var sum   = 0.0
        var count = 0

        for offset in Self.orthogonalOffsets
        {
            guard self.colorAt( x: x + offset.dx, y: y + offset.dy, width: width, height: height, pattern: pattern ) == color
            else
            {
                continue
            }

            sum += self.sample( pixels: pixels, x: x + offset.dx, y: y + offset.dy, width: width, height: height )
                 - self.sample( pixels: green,  x: x + offset.dx, y: y + offset.dy, width: width, height: height )
            count += 1
        }

        return count == 0 ? 0 : sum / Double( count )
    }

    /// The eight neighbour directions used for VNG gradient analysis, ordered
    /// clockwise from north: N, NE, E, SE, S, SW, W, NW.
    ///
    /// Arrays returned by `gradients(pixels:x:y:width:height:)` and
    /// `goodGradients(_:k1:k2:)` are aligned with this order.
    internal static let gradientDirections: [ ( dx: Int, dy: Int ) ] =
    [
        (  0, -1 ), (  1, -1 ), (  1, 0 ), (  1, 1 ),
        (  0,  1 ), ( -1,  1 ), ( -1, 0 ), ( -1, -1 ),
    ]

    /// Computes the eight directional gradients at site `(x, y)` over the
    /// mosaic.
    ///
    /// Each gradient sums the one-step and two-step absolute differences along
    /// its direction (see `gradientDirections`), so it is zero in a flat region
    /// and grows across an edge. Coordinates are clamped to the image edge.
    ///
    /// - Parameters:
    ///   - pixels: The single-channel mosaic samples, row-major.
    ///   - x:      The column of the site.
    ///   - y:      The row of the site.
    ///   - width:  The image width in pixels.
    ///   - height: The image height in pixels.
    ///
    /// - Returns: Eight gradient magnitudes, aligned with `gradientDirections`.
    internal static func gradients( pixels: [ Double ], x: Int, y: Int, width: Int, height: Int ) -> [ Double ]
    {
        var result = [ Double ]( repeating: 0.0, count: self.gradientDirections.count )

        result.withUnsafeMutableBufferPointer
        {
            self.fillGradients( pixels: pixels, x: x, y: y, width: width, height: height, into: $0 )
        }

        return result
    }

    /// Computes the eight directional gradients at site `(x, y)` into `buffer`,
    /// avoiding a per-call heap allocation in the green-plane hot loop.
    ///
    /// - Parameters:
    ///   - pixels: The single-channel mosaic samples, row-major.
    ///   - x:      The column of the site.
    ///   - y:      The row of the site.
    ///   - width:  The image width in pixels.
    ///   - height: The image height in pixels.
    ///   - buffer: A destination of at least `gradientDirections.count` elements,
    ///             filled in `gradientDirections` order.
    private static func fillGradients( pixels: [ Double ], x: Int, y: Int, width: Int, height: Int, into buffer: UnsafeMutableBufferPointer< Double > )
    {
        let center = self.sample( pixels: pixels, x: x, y: y, width: width, height: height )

        for index in self.gradientDirections.indices
        {
            let direction = self.gradientDirections[ index ]
            let one       = self.sample( pixels: pixels, x: x + direction.dx,     y: y + direction.dy,     width: width, height: height )
            let two       = self.sample( pixels: pixels, x: x + 2 * direction.dx, y: y + 2 * direction.dy, width: width, height: height )

            buffer[ index ] = abs( center - one ) + abs( center - two )
        }
    }

    /// Interpolates the green value at a red or blue site, using the
    /// gradient-selected directions.
    ///
    /// The orthogonal neighbours of a red/blue site are green. Only those lying
    /// in a retained (low-variation) direction are averaged, so green neighbours
    /// across an edge are dropped — reducing zippering. In a flat region all
    /// four are retained, matching the bilinear green. If the gradient selection
    /// retains no orthogonal direction, all four green neighbours are averaged
    /// as a fallback.
    ///
    /// - Parameters:
    ///   - pixels: The single-channel mosaic samples, row-major.
    ///   - x:      The column of the red/blue site.
    ///   - y:      The row of the red/blue site.
    ///   - width:  The image width in pixels.
    ///   - height: The image height in pixels.
    ///
    /// - Returns: The interpolated green value at `(x, y)`.
    internal static func interpolateGreen( pixels: [ Double ], x: Int, y: Int, width: Int, height: Int ) -> Double
    {
        // The orthogonal directions (N, E, S, W) are the even indices of
        // gradientDirections.
        let orthogonal = stride( from: 0, to: self.gradientDirections.count, by: 2 )

        return withUnsafeTemporaryAllocation( of: Double.self, capacity: self.gradientDirections.count )
        {
            gradients in

            self.fillGradients( pixels: pixels, x: x, y: y, width: width, height: height, into: gradients )

            let threshold = self.gradientThreshold( UnsafeBufferPointer( gradients ) )
            var sum       = 0.0
            var count     = 0

            for index in orthogonal where gradients[ index ] <= threshold
            {
                let direction = self.gradientDirections[ index ]

                sum   += self.sample( pixels: pixels, x: x + direction.dx, y: y + direction.dy, width: width, height: height )
                count += 1
            }

            if count == 0
            {
                for index in orthogonal
                {
                    let direction = self.gradientDirections[ index ]

                    sum   += self.sample( pixels: pixels, x: x + direction.dx, y: y + direction.dy, width: width, height: height )
                    count += 1
                }
            }

            return sum / Double( count )
        }
    }

    /// Reads sample `(x, y)`, clamping coordinates to the image edge.
    ///
    /// - Parameters:
    ///   - pixels: The single-channel mosaic samples, row-major.
    ///   - x:      The column (may be out of range).
    ///   - y:      The row (may be out of range).
    ///   - width:  The image width in pixels.
    ///   - height: The image height in pixels.
    ///
    /// - Returns: The sample at the clamped coordinate.
    private static func sample( pixels: [ Double ], x: Int, y: Int, width: Int, height: Int ) -> Double
    {
        let clampedX = Swift.min( Swift.max( x, 0 ), width  - 1 )
        let clampedY = Swift.min( Swift.max( y, 0 ), height - 1 )

        return pixels[ self.index( x: clampedX, y: clampedY, width: width ) ]
    }

    /// Computes the VNG gradient threshold `k1·min + k2·(max − min)`.
    ///
    /// Gradients at or below the threshold identify the low-variation directions
    /// that are good to interpolate along.
    ///
    /// - Parameters:
    ///   - gradients: The directional gradients (see `gradients(...)`).
    ///   - k1:        The weight on the minimum gradient.
    ///   - k2:        The weight on the gradient range.
    ///
    /// - Returns: The threshold value, or `0` for an empty input.
    internal static func gradientThreshold( _ gradients: [ Double ], k1: Double = 1.5, k2: Double = 0.5 ) -> Double
    {
        return gradients.withUnsafeBufferPointer { self.gradientThreshold( $0, k1: k1, k2: k2 ) }
    }

    /// Computes the VNG gradient threshold over a buffer of gradients, avoiding
    /// an intermediate array in the green-plane hot loop. See
    /// `gradientThreshold(_:k1:k2:)`.
    ///
    /// - Parameters:
    ///   - gradients: The directional gradients.
    ///   - k1:        The weight on the minimum gradient.
    ///   - k2:        The weight on the gradient range.
    ///
    /// - Returns: The threshold value, or `0` for an empty input.
    private static func gradientThreshold( _ gradients: UnsafeBufferPointer< Double >, k1: Double = 1.5, k2: Double = 0.5 ) -> Double
    {
        guard let minimum = gradients.min(), let maximum = gradients.max()
        else
        {
            return 0
        }

        return k1 * minimum + k2 * ( maximum - minimum )
    }

    /// Selects the "good" (low-variation) directions whose gradient is at or
    /// below the VNG threshold.
    ///
    /// - Parameters:
    ///   - gradients: The directional gradients (see `gradients(...)`).
    ///   - k1:        The weight on the minimum gradient.
    ///   - k2:        The weight on the gradient range.
    ///
    /// - Returns: Booleans aligned with `gradientDirections`; `true` marks a
    ///            retained direction.
    internal static func goodGradients( _ gradients: [ Double ], k1: Double = 1.5, k2: Double = 0.5 ) -> [ Bool ]
    {
        let threshold = self.gradientThreshold( gradients, k1: k1, k2: k2 )

        return gradients.map { $0 <= threshold }
    }
}
