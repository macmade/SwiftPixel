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

import Accelerate
import Foundation
import SwiftUtilities

public extension Processors
{
    /// Applies a power-law gamma curve, raising each sample to `1 / gamma`.
    ///
    /// Requires a normalized buffer (samples in `[0, 1]`). `gamma` must be
    /// greater than zero.
    struct CorrectGamma: PixelProcessor
    {
        /// The gamma exponent. Must be `> 0`; each sample is raised to its
        /// reciprocal (`pow(sample, 1 / gamma)`).
        public let gamma: Double

        /// A human-readable name including the gamma value.
        public var name: String
        {
            String( format: "Gamma Correction (%.02f)", self.gamma )
        }

        /// Raises every sample to `1 / gamma`, in place.
        ///
        /// - Parameter buffer: The normalized buffer to transform.
        ///
        /// - Throws: A `RuntimeError` if the buffer is not normalized or if
        ///           `gamma <= 0`.
        public func process( buffer: inout PixelBuffer ) throws
        {
            guard buffer.isNormalized
            else
            {
                throw RuntimeError( message: "Buffer needs to be normalized" )
            }

            guard self.gamma > 0
            else
            {
                throw RuntimeError( message: "Gamma must be greater than zero: \( self.gamma )" )
            }

            var count        = Int32( buffer.pixels.count )
            let inverseGamma = 1.0 / self.gamma
            let exponents    = [ Double ]( repeating: inverseGamma, count: buffer.pixels.count )

            try buffer.withUnsafeMutablePixels
            {
                guard let baseAddress = $0.baseAddress
                else
                {
                    throw RuntimeError( message: "Failed to access data buffer" )
                }

                vvpow( baseAddress, exponents, baseAddress, &count )
            }
        }
    }
}
