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
        func read( _ px: Int, _ py: Int ) -> Double
        {
            let clampedX = Swift.min( Swift.max( px, 0 ), width  - 1 )
            let clampedY = Swift.min( Swift.max( py, 0 ), height - 1 )

            return pixels[ self.index( x: clampedX, y: clampedY, width: width ) ]
        }

        let center = read( x, y )

        return self.gradientDirections.map
        {
            direction in

            let one = read( x + direction.dx,     y + direction.dy )
            let two = read( x + 2 * direction.dx, y + 2 * direction.dy )

            return abs( center - one ) + abs( center - two )
        }
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
