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
    /// Inverts a normalized buffer, mapping each sample to `1 - sample` to
    /// produce a photographic negative.
    ///
    /// Applies uniformly to every channel and leaves the samples normalized.
    /// Requires a normalized buffer (samples in `[0, 1]`).
    struct Invert: PixelProcessor
    {
        /// A human-readable name for the stage.
        public var name: String
        {
            "Invert"
        }

        /// Creates an invert stage.
        public init()
        {}

        /// Maps every sample to `1 - sample`, in place.
        ///
        /// - Parameter buffer: The normalized buffer to transform.
        ///
        /// - Throws: A `PixelBufferError` if the buffer is not normalized.
        public func process( buffer: inout PixelBuffer ) throws
        {
            guard buffer.isNormalized
            else
            {
                throw PixelBufferError.notNormalized
            }

            // 1 - x for each sample: a scalar multiply by -1 followed by a scalar
            // add of 1, computed in place over the whole interleaved buffer.
            var multiplier = -1.0
            var addend     =  1.0

            try buffer.withUnsafeMutablePixels
            {
                guard let baseAddress = $0.baseAddress
                else
                {
                    throw PixelBufferError.bufferAccessFailed( role: .data )
                }

                vDSP_vsmsaD( baseAddress, 1, &multiplier, &addend, baseAddress, 1, vDSP_Length( $0.count ) )
            }
        }
    }
}
