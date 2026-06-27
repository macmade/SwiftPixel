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

/// A truncated, normalized 2D Gaussian convolution kernel, plus a zero-sum
/// (high-pass) variant.
///
/// The kernel is square with an odd footprint (`size = 2·radius + 1`) so it has a
/// well-defined centre. Its weights are sampled from an isotropic Gaussian of the
/// given standard deviation and normalized to sum to one — a smoothing (blur)
/// filter.
///
/// The ``zeroSumValues`` variant subtracts the mean weight from every tap, so the
/// kernel sums to zero and therefore produces no response to a constant region.
/// Convolving with it is a high-pass / band-pass filter: it responds to features
/// at the kernel's scale while rejecting smooth content (flat areas and slow
/// gradients). This is the standard form of a matched filter for blob-like
/// features the size of the kernel.
public struct GaussianKernel: Sendable
{
    /// The Gaussian standard deviation, in pixels.
    public let sigma: Double

    /// The kernel radius, in pixels: weights are sampled over `-radius ... radius`
    /// on each axis.
    public let radius: Int

    /// The kernel's side length, in pixels: `2·radius + 1`.
    public let size: Int

    /// The normalized Gaussian weights, in row-major order, summing to one.
    public let values: [ Double ]

    /// The zero-sum weights (``values`` with the mean weight subtracted), in
    /// row-major order, summing to approximately zero.
    public let zeroSumValues: [ Double ]

    /// Builds a Gaussian kernel for the given scale.
    ///
    /// - Parameters:
    ///   - sigma:          The Gaussian standard deviation, in pixels. Clamped to
    ///                     a small positive minimum so the footprint is always
    ///                     valid.
    ///   - radiusInSigmas: How many standard deviations the truncated footprint
    ///                     spans on each side. The default of `2` captures the
    ///                     bulk of the profile while keeping the kernel compact.
    public init( sigma: Double, radiusInSigmas: Double = 2 )
    {
        let safeSigma = Swift.max( sigma, 1e-6 )
        let radius    = Swift.max( 1, Int( ( safeSigma * radiusInSigmas ).rounded( .up ) ) )
        let size      = ( 2 * radius ) + 1

        // Sample the (unnormalized) Gaussian over the square footprint, then
        // divide by the total so the weights sum to one.
        let samples = ( 0 ..< ( size * size ) ).map
        {
            index -> Double in

            let x = ( index % size ) - radius
            let y = ( index / size ) - radius

            return Foundation.exp( -Double( ( x * x ) + ( y * y ) ) / ( 2 * safeSigma * safeSigma ) )
        }

        let total  = samples.reduce( 0, + )
        let values = samples.map { $0 / total }
        let mean   = values.reduce( 0, + ) / Double( values.count )

        self.sigma         = safeSigma
        self.radius        = radius
        self.size          = size
        self.values        = values
        self.zeroSumValues = values.map { $0 - mean }
    }
}
