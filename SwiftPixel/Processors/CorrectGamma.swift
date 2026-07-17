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
    /// Applies a power-law gamma curve, raising each sample to `1 / gamma`.
    ///
    /// Requires a normalized buffer (samples in `[0, 1]`). `gamma` must be
    /// greater than zero. The alpha channel of a 4-channel (premultiplied RGBA)
    /// buffer is left unchanged.
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

        /// Creates a gamma-correction stage.
        ///
        /// - Parameter gamma: The gamma exponent. Must be `> 0`; each sample is
        ///                    raised to its reciprocal (`pow(sample, 1 / gamma)`).
        public init( gamma: Double )
        {
            self.gamma = gamma
        }

        /// A validation failure for a gamma-correction stage's configuration.
        public enum ValidationError: LocalizedError, Equatable, Sendable
        {
            /// The gamma exponent is not strictly positive.
            case nonPositiveGamma( Double )

            /// A human-readable description of the failure.
            public var errorDescription: String?
            {
                switch self
                {
                    case .nonPositiveGamma( let gamma ):

                        return "Gamma must be greater than zero: \( gamma )"
                }
            }
        }

        /// Raises every colour sample to `1 / gamma`, in place, leaving a 4-channel
        /// buffer's alpha unchanged.
        ///
        /// - Parameter buffer: The normalized buffer to transform.
        ///
        /// - Throws: A `PixelBufferError` or `CorrectGamma.ValidationError` if the buffer is not normalized or if
        ///           `gamma <= 0`.
        public func process( buffer: inout PixelBuffer ) throws
        {
            guard buffer.isNormalized
            else
            {
                throw PixelBufferError.notNormalized
            }

            guard self.gamma > 0
            else
            {
                throw ValidationError.nonPositiveGamma( self.gamma )
            }

            let chunkSize    = 4096
            let total        = buffer.pixels.count
            let inverseGamma = 1.0 / self.gamma
            let exponents    = [ Double ]( repeating: inverseGamma, count: Swift.min( chunkSize, total ) )

            // The power is raised over the whole interleaved buffer; a 4-channel
            // buffer's alpha is restored afterwards, so only the colours are gamma-
            // corrected.
            try buffer.withUnsafeMutablePixelsPreservingAlpha
            {
                guard let baseAddress = $0.baseAddress
                else
                {
                    throw PixelBufferError.bufferAccessFailed( role: .data )
                }

                var offset = 0

                while offset < total
                {
                    var n = Int32( Swift.min( chunkSize, total - offset ) )

                    vvpow( baseAddress + offset, exponents, baseAddress + offset, &n )

                    offset += Int( n )
                }
            }
        }
    }
}
