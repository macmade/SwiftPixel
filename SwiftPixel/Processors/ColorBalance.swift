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

import Accelerate
import Foundation

public extension Processors
{
    /// Applies a tonal-range colour balance to a 3-channel normalized buffer,
    /// shifting the red, green and blue channels independently within the
    /// shadows, midtones and highlights.
    ///
    /// Each pixel's Rec. 709 luma selects how strongly it belongs to each
    /// tonal range, via smooth weights that peak at black (shadows), mid-gray
    /// (midtones) and white (highlights) and always sum to `1`. The matching
    /// per-channel shifts, scaled by those weights, are added to the channels and
    /// the result is clipped to `[0, 1]`:
    /// `out = channel + shadow·wShadow + midtone·wMid + highlight·wHigh`. A shift
    /// of `0` everywhere is an identity. Requires a normalized, 3-channel buffer.
    struct ColorBalance: PixelProcessor
    {
        /// An additive per-channel shift for one tonal range. A positive component
        /// pushes toward that primary (red/green/blue), a negative one toward its
        /// complement (cyan/magenta/yellow). All-zero is neutral.
        public struct Shift: Sendable, Equatable
        {
            /// The red-channel shift (`+` toward red, `−` toward cyan).
            public var red: Double

            /// The green-channel shift (`+` toward green, `−` toward magenta).
            public var green: Double

            /// The blue-channel shift (`+` toward blue, `−` toward yellow).
            public var blue: Double

            /// The neutral shift, which leaves the channels unchanged.
            public static let identity = Shift()

            /// Creates a per-channel shift.
            ///
            /// - Parameters:
            ///   - red:   The red-channel shift. Defaults to `0`.
            ///   - green: The green-channel shift. Defaults to `0`.
            ///   - blue:  The blue-channel shift. Defaults to `0`.
            public init( red: Double = 0, green: Double = 0, blue: Double = 0 )
            {
                self.red   = red
                self.green = green
                self.blue  = blue
            }

            /// Whether this shift is neutral (and so a no-op).
            public var isIdentity: Bool
            {
                self == .identity
            }
        }

        /// The per-channel shifts for the three tonal ranges.
        public struct Ranges: Sendable, Equatable
        {
            /// The shift applied most strongly to the darkest pixels.
            public var shadows: Shift

            /// The shift applied most strongly to the mid-gray pixels.
            public var midtones: Shift

            /// The shift applied most strongly to the brightest pixels.
            public var highlights: Shift

            /// The neutral balance, which leaves every pixel unchanged.
            public static let identity = Ranges()

            /// Creates a set of tonal-range shifts.
            ///
            /// - Parameters:
            ///   - shadows:    The shadows shift. Defaults to the identity.
            ///   - midtones:   The midtones shift. Defaults to the identity.
            ///   - highlights: The highlights shift. Defaults to the identity.
            public init( shadows: Shift = .identity, midtones: Shift = .identity, highlights: Shift = .identity )
            {
                self.shadows    = shadows
                self.midtones   = midtones
                self.highlights = highlights
            }

            /// Whether every range is neutral (and so the whole stage is a no-op).
            public var isIdentity: Bool
            {
                self == .identity
            }
        }

        /// The per-tonal-range shifts to apply.
        public let ranges: Ranges

        /// A human-readable name.
        public var name: String
        {
            "Color Balance"
        }

        /// Creates a colour-balance stage.
        ///
        /// - Parameter ranges: The per-tonal-range shifts to apply.
        public init( ranges: Ranges )
        {
            self.ranges = ranges
        }

        /// Applies the colour balance in place, clipping to `[0, 1]`.
        ///
        /// - Parameter buffer: The normalized, 3-channel buffer to transform.
        ///
        /// - Throws: A `PixelBufferError` if the buffer is not normalized or is not
        ///           3-channel.
        public func process( buffer: inout PixelBuffer ) throws
        {
            guard buffer.isNormalized
            else
            {
                throw PixelBufferError.notNormalized
            }

            guard buffer.channels == 3
            else
            {
                throw PixelBufferError.unsupportedChannelCount( actual: buffer.channels, supported: [ 3 ] )
            }

            let pixelCount = buffer.width * buffer.height

            guard pixelCount > 0
            else
            {
                return
            }

            // Build the per-pixel Rec. 709 luma plane, derive the three tonal-range
            // weight planes from it (the shadow, midtone and highlight smoothstep
            // weights, which sum to 1), then add the per-channel shifts scaled by
            // those weights and clip to [0, 1]. Every step is a whole-plane
            // vectorized operation, reproducing the scalar
            // `channel + shadow·wS + midtone·wM + highlight·wH` to within
            // floating-point rounding.
            let shadowShifts    = [ self.ranges.shadows.red,    self.ranges.shadows.green,    self.ranges.shadows.blue    ]
            let midtoneShifts   = [ self.ranges.midtones.red,   self.ranges.midtones.green,   self.ranges.midtones.blue   ]
            let highlightShifts = [ self.ranges.highlights.red, self.ranges.highlights.green, self.ranges.highlights.blue ]

            // Three working planes carved from a single contiguous store, sized
            // pixelCount·3 = pixels.count for a 3-channel buffer — so the allocation is
            // bounded by the same invariant PixelBuffer already enforces and cannot
            // overflow. The luma is computed into the midtone-weight plane (free until
            // the weights are combined) and read by both smoothsteps before that plane
            // is repurposed as scratch and then the midtone weight; the highlight plane
            // doubles as scratch for the shadow smoothstep's `(3 − 2t)` term.
            var planes = [ Double ]( repeating: 0.0, count: pixelCount * 3 )

            buffer.withUnsafeMutablePixels
            {
                pixels in

                planes.withUnsafeMutableBufferPointer
                {
                    store in

                    guard let rgb = pixels.baseAddress, let base = store.baseAddress
                    else
                    {
                        return
                    }

                    let n               = vDSP_Length( pixelCount )
                    let shadowWeight    = base
                    let midtoneWeight   = base + pixelCount
                    let highlightWeight = base + pixelCount * 2
                    let luma            = midtoneWeight // Occupies the midtone plane until the weights are combined.

                    // Rec. 709 luma, matching the Saturation stage's channel.
                    var weightRed   = 0.2126
                    var weightGreen = 0.7152
                    var weightBlue  = 0.0722

                    vDSP_vsmulD( rgb + 0, 3, &weightRed,   luma, 1, n )          // luma  = R · 0.2126
                    vDSP_vsmaD(  rgb + 1, 3, &weightGreen, luma, 1, luma, 1, n ) // luma += G · 0.7152
                    vDSP_vsmaD(  rgb + 2, 3, &weightBlue,  luma, 1, luma, 1, n ) // luma += B · 0.0722

                    var two    = 2.0
                    var negOne = -1.0
                    var negTwo = -2.0
                    var three  = 3.0
                    var zero   = 0.0
                    var one    = 1.0

                    // shadowWeight ← smoothstep(0, 0.5, luma): t = clip(2·luma, 0, 1),
                    // then t²·(3 − 2t), using the highlight plane as scratch for (3 − 2t).
                    vDSP_vsmulD( luma, 1, &two, shadowWeight, 1, n )
                    vDSP_vclipD( shadowWeight, 1, &zero, &one, shadowWeight, 1, n )
                    vDSP_vsmsaD( shadowWeight, 1, &negTwo, &three, highlightWeight, 1, n )
                    vDSP_vmulD(  shadowWeight, 1, shadowWeight, 1, shadowWeight, 1, n )
                    vDSP_vmulD(  shadowWeight, 1, highlightWeight, 1, shadowWeight, 1, n ) // smoothstep(0, 0.5)

                    // highlightWeight ← smoothstep(0.5, 1, luma): t = clip(2·luma − 1, 0, 1).
                    vDSP_vsmsaD( luma, 1, &two, &negOne, highlightWeight, 1, n )
                    vDSP_vclipD( highlightWeight, 1, &zero, &one, highlightWeight, 1, n )
                    vDSP_vsmsaD( highlightWeight, 1, &negTwo, &three, midtoneWeight, 1, n ) // luma now consumed; its plane is the (3 − 2t) scratch
                    vDSP_vmulD(  highlightWeight, 1, highlightWeight, 1, highlightWeight, 1, n )
                    vDSP_vmulD(  highlightWeight, 1, midtoneWeight, 1, highlightWeight, 1, n ) // smoothstep(0.5, 1)

                    // midtone = low − high (= 1 − shadow − highlight); shadow = 1 − low.
                    // `vDSP_vsubD` computes C = A − B with A and B passed swapped, so
                    // (highlight, shadow) yields shadow − highlight, i.e. low − high.
                    vDSP_vsubD(  highlightWeight, 1, shadowWeight, 1, midtoneWeight, 1, n )
                    vDSP_vsmsaD( shadowWeight, 1, &negOne, &one, shadowWeight, 1, n )

                    // channel ← channel + shadow·wS + midtone·wM + highlight·wH
                    ( 0 ..< 3 ).forEach
                    {
                        channel in

                        var shadowShift    = shadowShifts[ channel ]
                        var midtoneShift   = midtoneShifts[ channel ]
                        var highlightShift = highlightShifts[ channel ]

                        vDSP_vsmaD( shadowWeight,    1, &shadowShift,    rgb + channel, 3, rgb + channel, 3, n )
                        vDSP_vsmaD( midtoneWeight,   1, &midtoneShift,   rgb + channel, 3, rgb + channel, 3, n )
                        vDSP_vsmaD( highlightWeight, 1, &highlightShift, rgb + channel, 3, rgb + channel, 3, n )
                    }

                    vDSP_vclipD( rgb, 1, &zero, &one, rgb, 1, vDSP_Length( pixelCount * 3 ) )
                }
            }
        }
    }
}
