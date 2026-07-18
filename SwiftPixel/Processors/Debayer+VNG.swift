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
    /// The channel index (`R = 0`, `G = 1`, `B = 2`) of a mosaic color. The VNG
    /// gradient formulas and color-difference tables assume this ordering.
    ///
    /// - Parameter color: The color sampled at a site.
    ///
    /// - Returns: `0` for red, `1` for green, `2` for blue.
    private static func channelIndex( _ color: ColorType ) -> Int
    {
        switch color
        {
            case .red:   return 0
            case .green: return 1
            case .blue:  return 2
        }
    }

    /// Reconstructs a 3-channel RGB image from a Bayer mosaic using canonical
    /// Variable Number of Gradients (VNG) demosaicing.
    ///
    /// This is a faithful port of the Chang–Cheng–Cok VNG algorithm as
    /// implemented in PixInsight's `Debayer` process (the reference used by most
    /// astronomy software). For each interior pixel it computes eight
    /// like-colored directional gradients over the surrounding 5×5 window,
    /// keeps the directions whose gradient is at or below
    /// `k1·min + k2·(max − min)` (with `k1 = 1.5`, `k2 = 0.5`), and reconstructs
    /// the two missing colors as color differences averaged over those kept
    /// directions. The present color at each site is preserved exactly.
    ///
    /// The 5×5 stencil needs a two-pixel inset, so VNG only refines the interior
    /// (sites at least two pixels from every edge); the two-pixel border
    /// replicates the nearest interior pixel, exactly as PixInsight does, so no
    /// edge-clamped wrong-color sample is ever mixed in. An image smaller than
    /// 5×5 has no interior and falls back to bilinear (which handles the border
    /// with same-color-only averaging).
    ///
    /// Unlike PixInsight — which normalizes to `[0, 1]` and clamps — this runs in
    /// raw sample space and does not clamp, matching the non-normalized Debayer
    /// contract and the downstream pipeline's own normalization.
    ///
    /// - Parameters:
    ///   - pixels:  The single-channel mosaic samples, row-major.
    ///   - pattern: The Bayer arrangement of `pixels`.
    ///   - width:   The image width in pixels.
    ///   - height:  The image height in pixels.
    ///
    /// - Returns: `width × height × 3` interleaved RGB samples.
    ///
    /// - Throws: A `PixelBufferError` if the output buffer cannot be accessed.
    internal static func vng( pixels: [ Double ], pattern: Pattern, width: Int, height: Int ) throws -> [ Double ]
    {
        guard width >= 5, height >= 5
        else
        {
            return try self.bilinear( pixels: pixels, pattern: pattern, width: width, height: height )
        }

        let channelMap = self.colorMap( width: width, height: height, pattern: pattern ).map { self.channelIndex( $0 ) }
        var output     = [ Double ]( repeating: 0.0, count: width * height * 3 )

        try output.withUnsafeMutableBufferPointer
        {
            guard let outputBase = $0.baseAddress
            else
            {
                throw PixelBufferError.bufferAccessFailed( role: .output )
            }

            nonisolated( unsafe ) let output = outputBase

            PixelUtilities.parallelOrSerial( iterations: height - 4, threshold: 64 )
            {
                row in self.interpolateRow( y: row + 2, input: pixels, channels: channelMap, output: output, width: width )
            }

            self.replicateBorder( output: output, width: width, height: height )
        }

        return output
    }

    /// Reconstructs every interior pixel of row `y` (columns `2 ..< width − 2`),
    /// writing the interleaved RGB result into `output`.
    ///
    /// The 5×5 sample and channel windows and the eight-gradient buffer are
    /// allocated once for the whole row and reused across columns, so the
    /// per-pixel work does no allocation.
    ///
    /// - Parameters:
    ///   - y:        The interior row (`2 ..< height − 2`).
    ///   - input:    The single-channel mosaic samples, row-major.
    ///   - channels: The per-site channel index (`0/1/2`), row-major.
    ///   - output:   The interleaved RGB destination.
    ///   - width:    The image width in pixels.
    private static func interpolateRow( y: Int, input: [ Double ], channels: [ Int ], output: UnsafeMutablePointer< Double >, width: Int )
    {
        var v             = [ Double ]( repeating: 0.0, count: 25 )
        var channelWindow = [ Int ]( repeating: 0, count: 25 )
        var gradients     = [ Double ]( repeating: 0.0, count: 8 )

        ( 2 ..< width - 2 ).forEach
        {
            x in

            // Cache the 5×5 sample and channel windows centered on (x, y).
            ( 0 ..< 5 ).forEach
            {
                wy in

                let sourceRow = ( y + wy - 2 ) * width + ( x - 2 )
                let target    = wy * 5

                ( 0 ..< 5 ).forEach
                {
                    wx in

                    v[ target + wx ]             = input[ sourceRow + wx ]
                    channelWindow[ target + wx ] = channels[ sourceRow + wx ]
                }
            }

            let currentChannel = channelWindow[ 12 ]

            self.computeGradients( v: v, currentChannel: currentChannel, into: &gradients )

            let keep               = self.threshold( gradients )
            let sums               = self.colorSums( v: v, channels: channelWindow, gradients: gradients, threshold: keep )
            let center             = v[ 12 ]
            let currentSum         = sums.value( currentChannel )
            let ( other1, other2 ) = self.otherChannels( currentChannel )
            let base               = ( y * width + x ) * 3

            output[ base + currentChannel ] = center
            output[ base + other1 ]         = center + ( sums.value( other1 ) - currentSum ) / Double( sums.count )
            output[ base + other2 ]         = center + ( sums.value( other2 ) - currentSum ) / Double( sums.count )
        }
    }

    /// The two channel indices other than `channel`, in ascending (R, G, B)
    /// order.
    ///
    /// - Parameter channel: The present channel (`0`, `1`, or `2`).
    ///
    /// - Returns: The other two channel indices.
    private static func otherChannels( _ channel: Int ) -> ( Int, Int )
    {
        switch channel
        {
            case 0:  return ( 1, 2 )
            case 1:  return ( 0, 2 )
            default: return ( 0, 1 )
        }
    }

    /// Replicates the two-pixel border of the RGB `output` from the nearest
    /// fully-computed interior pixel, mirroring PixInsight's border handling.
    ///
    /// The two outer columns of every interior row copy column 2 (left) and
    /// column `width − 3` (right); the two outer rows then copy row 2 (top) and
    /// row `height − 3` (bottom) across the full width, which also fills the four
    /// corners.
    ///
    /// - Parameters:
    ///   - output: The interleaved RGB buffer to patch in place.
    ///   - width:  The image width in pixels.
    ///   - height: The image height in pixels.
    private static func replicateBorder( output: UnsafeMutablePointer< Double >, width: Int, height: Int )
    {
        func copyPixel( from source: Int, to destination: Int )
        {
            output[ destination * 3 + 0 ] = output[ source * 3 + 0 ]
            output[ destination * 3 + 1 ] = output[ source * 3 + 1 ]
            output[ destination * 3 + 2 ] = output[ source * 3 + 2 ]
        }

        ( 2 ..< height - 2 ).forEach
        {
            y in

            let left  = y * width + 2
            let right = y * width + ( width - 3 )

            copyPixel( from: left,  to: y * width )
            copyPixel( from: left,  to: y * width + 1 )
            copyPixel( from: right, to: y * width + ( width - 1 ) )
            copyPixel( from: right, to: y * width + ( width - 2 ) )
        }

        ( 0 ..< width ).forEach
        {
            x in

            let top    = 2 * width + x
            let bottom = ( height - 3 ) * width + x

            copyPixel( from: top,    to: x )
            copyPixel( from: top,    to: width + x )
            copyPixel( from: bottom, to: ( height - 1 ) * width + x )
            copyPixel( from: bottom, to: ( height - 2 ) * width + x )
        }
    }

    /// Computes the eight like-colored directional gradients over a 5×5 window,
    /// in the order N, E, S, W, NE, SE, NW, SW.
    ///
    /// Each gradient sums the absolute differences of *same-color* sample pairs
    /// along its direction (with the diagonal terms weighted a half), following
    /// the VNG paper. The diagonal gradients use a different pair set for a green
    /// center than for a red/blue center. This mirrors PixInsight's
    /// `ComputeGradients` exactly — including the two full-weight south-diagonal
    /// terms (`v19 − v13`, `v15 − v11`) that read asymmetrically against their
    /// north counterparts in the reference source.
    ///
    /// - Parameters:
    ///   - v:              The 5×5 sample window (row-major, center at index 12).
    ///   - currentChannel: The center's channel (`1` = green, else red/blue).
    ///   - gradients:      The eight-element destination.
    private static func computeGradients( v: [ Double ], currentChannel: Int, into gradients: inout [ Double ] )
    {
        // Absolute difference of two like-colored window samples, by index.
        func d( _ a: Int, _ b: Int ) -> Double { return abs( v[ a ] - v[ b ] ) }

        gradients[ 0 ] = d( 7, 17 )  + d( 2, 12 )  + d( 6, 16 ) * 0.5 + d( 8, 18 ) * 0.5 + d( 1, 11 ) * 0.5 + d( 3, 13 ) * 0.5
        gradients[ 1 ] = d( 13, 11 ) + d( 14, 12 ) + d( 8, 6 ) * 0.5 + d( 18, 16 ) * 0.5 + d( 9, 7 ) * 0.5 + d( 19, 17 ) * 0.5
        gradients[ 2 ] = d( 17, 7 )  + d( 22, 12 ) + d( 16, 6 ) * 0.5 + d( 18, 8 ) * 0.5 + d( 21, 11 ) * 0.5 + d( 23, 13 ) * 0.5
        gradients[ 3 ] = d( 11, 13 ) + d( 10, 12 ) + d( 6, 8 ) * 0.5 + d( 16, 18 ) * 0.5 + d( 5, 7 ) * 0.5 + d( 15, 17 ) * 0.5

        if currentChannel == 1
        {
            gradients[ 4 ] = d( 8, 16 )  + d( 4, 12 )  + d( 3, 11 )  + d( 9, 17 )
            gradients[ 5 ] = d( 18, 6 )  + d( 24, 12 ) + d( 23, 11 ) + d( 19, 7 )
            gradients[ 6 ] = d( 6, 18 )  + d( 0, 12 )  + d( 1, 13 )  + d( 5, 17 )
            gradients[ 7 ] = d( 16, 8 )  + d( 20, 12 ) + d( 21, 13 ) + d( 15, 7 )
        }
        else
        {
            gradients[ 4 ] = d( 8, 16 )  + d( 4, 12 )  + d( 7, 11 ) * 0.5 + d( 13, 17 ) * 0.5 + d( 3, 7 ) * 0.5 + d( 9, 13 ) * 0.5
            gradients[ 5 ] = d( 18, 6 )  + d( 24, 12 ) + d( 13, 7 ) * 0.5 + d( 17, 11 ) * 0.5 + d( 19, 13 )     + d( 23, 17 ) * 0.5
            gradients[ 6 ] = d( 6, 18 )  + d( 0, 12 )  + d( 7, 13 ) * 0.5 + d( 11, 17 ) * 0.5 + d( 1, 7 ) * 0.5 + d( 5, 11 ) * 0.5
            gradients[ 7 ] = d( 16, 8 )  + d( 20, 12 ) + d( 11, 7 ) * 0.5 + d( 17, 13 ) * 0.5 + d( 15, 11 )     + d( 21, 17 ) * 0.5
        }
    }

    /// The VNG threshold below which a direction is kept: `k1·min + k2·(max − min)`
    /// over the eight gradients, with `k1 = 1.5`, `k2 = 0.5` (the paper's
    /// empirically-tuned constants, matching PixInsight and the value used
    /// throughout SwiftPixel).
    ///
    /// - Parameter gradients: The eight directional gradients.
    ///
    /// - Returns: The keep threshold.
    private static func threshold( _ gradients: [ Double ] ) -> Double
    {
        let minimum = gradients.min() ?? 0
        let maximum = gradients.max() ?? 0

        return 1.5 * minimum + 0.5 * ( maximum - minimum )
    }

    /// The per-channel color-coefficient sums over the kept directions, plus the
    /// number of directions kept.
    private struct ColorSums
    {
        /// The summed red coefficient.
        let red: Double

        /// The summed green coefficient.
        let green: Double

        /// The summed blue coefficient.
        let blue: Double

        /// The number of kept directions (always at least one).
        let count: Int

        /// The summed coefficient for a channel index (`0` red, `1` green, else
        /// blue).
        ///
        /// - Parameter channel: The channel index.
        ///
        /// - Returns: The matching per-channel sum.
        func value( _ channel: Int ) -> Double
        {
            switch channel
            {
                case 0:  return self.red
                case 1:  return self.green
                default: return self.blue
            }
        }
    }

    /// The 5×5 window indices whose samples feed each direction's color sum, for
    /// a green center. Aligned with the N, E, S, W, NE, SE, NW, SW gradient
    /// order; copied verbatim from PixInsight.
    private static let greenCenterSumIndices: [ [ Int ] ] =
        [
            [  1,  2,  3,  7, 11, 12, 13 ],
            [  7,  9, 12, 13, 14, 17, 19 ],
            [ 11, 12, 13, 17, 21, 22, 23 ],
            [  5,  7, 10, 11, 12, 15, 17 ],
            [  3,  7,  8,  9, 13 ],
            [ 13, 17, 18, 19, 23 ],
            [  1,  5,  6,  7, 11 ],
            [ 11, 15, 16, 17, 21 ],
        ]

    /// The 5×5 window indices whose samples feed each direction's color sum, for
    /// a red or blue center. Aligned with the N, E, S, W, NE, SE, NW, SW gradient
    /// order; copied verbatim from PixInsight.
    private static let otherCenterSumIndices: [ [ Int ] ] =
        [
            [  2,  6,  7,  8, 12 ],
            [  8, 12, 13, 14, 18 ],
            [ 12, 16, 17, 18, 22 ],
            [  6, 10, 11, 12, 16 ],
            [  3,  4,  7,  8,  9, 12, 13 ],
            [ 12, 13, 17, 18, 19, 23, 24 ],
            [  0,  1,  5,  6,  7, 11, 12 ],
            [ 11, 12, 15, 16, 17, 20, 21 ],
        ]

    /// Accumulates, over the directions kept by the threshold, the per-channel
    /// average of the same-direction 5×5 samples — the color coefficients the
    /// reconstruction differences against.
    ///
    /// For each kept direction the samples in its footprint are grouped by
    /// channel and averaged, and those per-channel averages are summed across
    /// directions. Mirrors PixInsight's `ComputeSums`, with the keep test folded
    /// in. At least the minimum-gradient direction always qualifies, so `count`
    /// is never zero. A small tolerance keeps exact ties (notably flat regions).
    ///
    /// - Parameters:
    ///   - v:         The 5×5 sample window.
    ///   - channels:  The 5×5 channel-index window.
    ///   - gradients: The eight directional gradients.
    ///   - threshold: The keep threshold.
    ///
    /// - Returns: The per-channel coefficient sums and the kept-direction count.
    private static func colorSums( v: [ Double ], channels: [ Int ], gradients: [ Double ], threshold: Double ) -> ColorSums
    {
        let indexTable = channels[ 12 ] == 1 ? self.greenCenterSumIndices : self.otherCenterSumIndices
        let keep       = threshold + 1e-10

        var sumRed   = 0.0
        var sumGreen = 0.0
        var sumBlue  = 0.0
        var count    = 0

        for direction in 0 ..< 8 where gradients[ direction ] <= keep
        {
            var partialRed   = 0.0
            var partialGreen = 0.0
            var partialBlue  = 0.0
            var countRed     = 0
            var countGreen   = 0
            var countBlue    = 0

            indexTable[ direction ].forEach
            {
                index in

                switch channels[ index ]
                {
                    case 0:  partialRed   += v[ index ]
                        countRed   += 1
                    case 1:  partialGreen += v[ index ]
                        countGreen += 1
                    default: partialBlue  += v[ index ]
                        countBlue  += 1
                }
            }

            if countRed   > 0 { sumRed   += partialRed   / Double( countRed ) }
            if countGreen > 0 { sumGreen += partialGreen / Double( countGreen ) }
            if countBlue  > 0 { sumBlue  += partialBlue  / Double( countBlue ) }

            count += 1
        }

        return ColorSums( red: sumRed, green: sumGreen, blue: sumBlue, count: count )
    }

    /// Computes the eight VNG directional gradients for a 5×5 window — the
    /// testable entry point over the private implementation.
    ///
    /// - Parameters:
    ///   - v:              The 5×5 sample window (row-major, center at index 12);
    ///                     must hold at least 25 samples.
    ///   - currentChannel: The center's channel (`0` red, `1` green, `2` blue).
    ///
    /// - Returns: The eight gradients in N, E, S, W, NE, SE, NW, SW order.
    internal static func vngGradients( _ v: [ Double ], currentChannel: Int ) -> [ Double ]
    {
        var gradients = [ Double ]( repeating: 0.0, count: 8 )

        self.computeGradients( v: v, currentChannel: currentChannel, into: &gradients )

        return gradients
    }

    /// The VNG keep threshold `k1·min + k2·(max − min)` for a set of gradients —
    /// the testable entry point over the private implementation.
    ///
    /// - Parameter gradients: The eight directional gradients.
    ///
    /// - Returns: The keep threshold.
    internal static func vngThreshold( _ gradients: [ Double ] ) -> Double
    {
        return self.threshold( gradients )
    }
}
