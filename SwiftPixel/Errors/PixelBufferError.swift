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

/// A failure originating from a ``PixelBuffer``'s geometry, normalization state,
/// or backing-memory access.
///
/// These are the buffer-level constraints the pixel pipeline and its processors
/// enforce at run time (as opposed to the config-time validation each processor
/// performs through its own nested `ValidationError`). CGImage-conversion
/// failures are reported separately through ``PixelImageError``.
public enum PixelBufferError: LocalizedError, Equatable, Sendable
{
    /// Identifies which buffer an access failure refers to.
    public enum Role: Sendable, Equatable
    {
        /// The generic working/data buffer.
        case data

        /// The input buffer of a two-buffer operation.
        case input

        /// The output buffer of a two-buffer operation.
        case output

        /// The human-readable fragment naming the buffer in a message.
        fileprivate var phrase: String
        {
            switch self
            {
                case .data:   return "data"
                case .input:  return "input data"
                case .output: return "output data"
            }
        }
    }

    /// The operation requires a normalized buffer (samples in `[0, 1]`), but the
    /// buffer is not normalized.
    case notNormalized

    /// The operation requires a non-normalized (raw) buffer, but the buffer is
    /// normalized.
    case mustNotBeNormalized

    /// A buffer's backing memory could not be accessed. `role` identifies which
    /// buffer.
    case bufferAccessFailed( role: Role )

    /// The backing data's length does not match the length the geometry implies.
    case dataSizeMismatch( expected: Int, actual: Int )

    /// The sample count does not match the `width × height × channels` geometry.
    case pixelCountMismatch( expected: Int, actual: Int )

    /// The requested channel count is below the minimum of one.
    case invalidChannelCount( Int )

    /// The width or height is negative.
    case negativeDimensions( width: Int, height: Int )

    /// The `width × height × channels` product overflows `Int`.
    case geometryOverflow( width: Int, height: Int, channels: Int )

    /// The byte size (`sampleCount × bytes-per-sample`) overflows `Int`.
    case sizeOverflow( sampleCount: Int )

    /// The buffer's channel count is not one the operation supports. `supported`
    /// lists the accepted channel counts.
    case unsupportedChannelCount( actual: Int, supported: [ Int ] )

    /// A human-readable description of the failure.
    public var errorDescription: String?
    {
        switch self
        {
            case .notNormalized:

                return "Buffer needs to be normalized"

            case .mustNotBeNormalized:

                return "Input buffer must not be normalized"

            case .bufferAccessFailed( let role ):

                return "Failed to access \( role.phrase ) buffer"

            case .dataSizeMismatch( let expected, let actual ):

                return "Data size does not match expected size: \( actual ) != \( expected )"

            case .pixelCountMismatch( let expected, let actual ):

                return "Pixel count does not match geometry: \( actual ) != \( expected )"

            case .invalidChannelCount( let channels ):

                return "Channel count must be at least 1: \( channels )"

            case .negativeDimensions( let width, let height ):

                return "Dimensions must not be negative: \( width )x\( height )"

            case .geometryOverflow( let width, let height, let channels ):

                return "Image geometry overflows Int: \( width ) x \( height ) x \( channels )"

            case .sizeOverflow( let sampleCount ):

                return "Byte size overflows Int for \( sampleCount ) samples"

            case .unsupportedChannelCount( let actual, let supported ):

                return "Requires \( Self.channelRequirement( for: supported ) ): \( actual )"
        }
    }

    /// Renders a list of supported channel counts as a readable buffer requirement.
    ///
    /// - Parameter supported: The accepted channel counts.
    /// - Returns: A phrase such as `"a single-channel buffer"`, `"a 3-channel
    ///            buffer"`, or `"a 1- or 3-channel buffer"`.
    private static func channelRequirement( for supported: [ Int ] ) -> String
    {
        let sorted = supported.sorted()

        if sorted == [ 1 ]
        {
            return "a single-channel buffer"
        }

        let list = sorted.map { String( $0 ) }.joined( separator: "- or " )

        return "a \( list )-channel buffer"
    }
}
