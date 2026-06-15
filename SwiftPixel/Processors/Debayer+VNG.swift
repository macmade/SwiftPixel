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

extension Processors.Debayer
{
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
        let center = self.sample( pixels: pixels, x: x, y: y, width: width, height: height )

        return self.gradientDirections.map
        {
            let one = self.sample( pixels: pixels, x: x + $0.dx,     y: y + $0.dy,     width: width, height: height )
            let two = self.sample( pixels: pixels, x: x + 2 * $0.dx, y: y + 2 * $0.dy, width: width, height: height )

            return abs( center - one ) + abs( center - two )
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
        let good = self.goodGradients( self.gradients( pixels: pixels, x: x, y: y, width: width, height: height ) )

        // Indices of the orthogonal directions (N, E, S, W) in gradientDirections.
        let orthogonal = [ 0, 2, 4, 6 ]
        var retained   = orthogonal.filter { good[ $0 ] }

        if retained.isEmpty
        {
            retained = orthogonal
        }

        let values = retained.map
        {
            self.sample( pixels: pixels, x: x + self.gradientDirections[ $0 ].dx, y: y + self.gradientDirections[ $0 ].dy, width: width, height: height )
        }

        return values.reduce( 0.0, + ) / Double( values.count )
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
