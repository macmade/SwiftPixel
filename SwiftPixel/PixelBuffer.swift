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

/// A geometrically consistent, channel-interleaved image buffer of `Double`
/// samples.
///
/// A buffer always satisfies `pixels.count == width × height × channels`; this
/// invariant is enforced at construction. Samples are stored interleaved in
/// row-major order (e.g. `R,G,B,R,G,B,…` for a 3-channel buffer).
///
/// `isNormalized` indicates whether the samples lie in the `[0, 1]` range.
/// Several processors (and `convertTo8Bits()` / `createCGImage()`) require a
/// normalized buffer.
public struct PixelBuffer: CustomStringConvertible
{
    /// The image width in pixels.
    public let width: Int

    /// The image height in pixels.
    public let height: Int

    /// The number of interleaved samples per pixel.
    public let channels: Int

    /// The interleaved samples, in row-major order.
    public var pixels: [ Double ]

    /// Whether the samples are normalized to the `[0, 1]` range.
    public var isNormalized: Bool

    /// Creates a buffer, validating that the geometry and sample count are
    /// consistent.
    ///
    /// - Parameters:
    ///   - width:        The image width in pixels. Must be `>= 0`.
    ///   - height:       The image height in pixels. Must be `>= 0`.
    ///   - channels:     The number of samples per pixel. Must be `>= 1`.
    ///   - pixels:       The interleaved samples. Their count must equal
    ///                   `width × height × channels`.
    ///   - isNormalized: Whether the samples are in the `[0, 1]` range.
    ///
    /// - Throws: A `RuntimeError` if `channels < 1`, if `width` or `height` is
    ///           negative, or if `pixels.count` does not match the geometry.
    public init( width: Int, height: Int, channels: Int, pixels: [ Double ], isNormalized: Bool ) throws
    {
        guard channels >= 1
        else
        {
            throw RuntimeError( message: "Channel count must be at least 1: \( channels )" )
        }

        guard width >= 0, height >= 0
        else
        {
            throw RuntimeError( message: "Dimensions must not be negative: \( width )x\( height )" )
        }

        guard pixels.count == width * height * channels
        else
        {
            throw RuntimeError( message: "Pixel count does not match geometry: \( pixels.count ) != \( width * height * channels )" )
        }

        self.width        = width
        self.height       = height
        self.channels     = channels
        self.pixels       = pixels
        self.isNormalized = isNormalized
    }

    /// A human-readable summary of the buffer's geometry and state.
    public var description: String
    {
        "PixelBuffer( width: \( self.width ), height: \( self.height ), channels: \( self.channels ), pixels: \( self.pixels.count ), isNormalized: \( self.isNormalized ) )"
    }

    /// Converts the normalized samples to 8-bit values.
    ///
    /// Each sample is scaled by `255`, clamped to `0...255`, and rounded to a
    /// `UInt8`. The buffer must be normalized.
    ///
    /// - Returns: The 8-bit samples, one per input sample, in the same order.
    ///
    /// - Throws: A `RuntimeError` if the buffer is not normalized.
    public func convertTo8Bits() throws -> [ UInt8 ]
    {
        guard self.isNormalized
        else
        {
            throw RuntimeError( message: "Buffer needs to be normalized" )
        }

        var scaledPixels = [ Double ]( repeating: 0.0, count: self.pixels.count )
        var result       = [ UInt8  ]( repeating: 0,   count: self.pixels.count )
        var scale        = 255.0

        vDSP_vsmulD( self.pixels, 1, &scale, &scaledPixels, 1, vDSP_Length( self.pixels.count ) )
        vDSP_vclipD( scaledPixels, 1, [ 0.0 ], [ 255.0 ], &scaledPixels, 1, vDSP_Length( self.pixels.count ) )
        vDSP_vfixru8D( scaledPixels, 1, &result, 1, vDSP_Length( self.pixels.count ) )

        return result
    }

    /// Renders the buffer to a `CGImage`.
    ///
    /// The buffer must be normalized (it is converted via `convertTo8Bits()`)
    /// and must have 1 (grayscale), 3 (RGB) or 4 (RGBA) channels.
    ///
    /// - Returns: A `CGImage` of the buffer's contents.
    ///
    /// - Throws: A `RuntimeError` if the channel count is unsupported, if the
    ///           buffer is not normalized, or if image creation fails.
    public func createCGImage() throws -> CGImage
    {
        guard self.channels == 1 || self.channels == 3 || self.channels == 4
        else
        {
            throw RuntimeError( message: "Unsupported number of channels: \( self.channels )" )
        }

        return try Self.createCGImage( bytes: try self.convertTo8Bits(), width: self.width, height: self.height, channels: self.channels )
    }

    /// Builds a `CGImage` from interleaved 8-bit samples.
    ///
    /// - Parameters:
    ///   - bytes:    The interleaved 8-bit samples, in row-major order.
    ///   - width:    The image width in pixels.
    ///   - height:   The image height in pixels.
    ///   - channels: The samples per pixel: 1 (grayscale), 3 (RGB) or 4 (RGBA,
    ///               premultiplied alpha).
    ///
    /// - Returns: A `CGImage` of the given samples.
    ///
    /// - Throws: A `RuntimeError` if the channel count is unsupported or if image
    ///           creation fails.
    public static func createCGImage( bytes: [ UInt8 ], width: Int, height: Int, channels: Int ) throws -> CGImage
    {
        let bitsPerComponent = 8
        let bitsPerPixel     = channels * bitsPerComponent
        let bytesPerRow      = width * channels

        let colorSpace: CGColorSpace
        let bitmapInfo: CGBitmapInfo

        switch channels
        {
            case 1:

                colorSpace = CGColorSpaceCreateDeviceGray()
                bitmapInfo = CGBitmapInfo( rawValue: CGImageAlphaInfo.none.rawValue )

            case 3:

                colorSpace = CGColorSpaceCreateDeviceRGB()
                bitmapInfo = CGBitmapInfo( rawValue: CGImageAlphaInfo.none.rawValue )

            case 4:

                colorSpace = CGColorSpaceCreateDeviceRGB()
                bitmapInfo = CGBitmapInfo( rawValue: CGImageAlphaInfo.premultipliedLast.rawValue )

            default:

                throw RuntimeError( message: "Unsupported channel configuration" )
        }

        guard let provider = CGDataProvider( data: Data( bytes ) as CFData )
        else
        {
            throw RuntimeError( message: "Failed to create CGDataProvider" )
        }

        guard let image = CGImage(
            width:             width,
            height:            height,
            bitsPerComponent:  bitsPerComponent,
            bitsPerPixel:      bitsPerPixel,
            bytesPerRow:       bytesPerRow,
            space:             colorSpace,
            bitmapInfo:        bitmapInfo,
            provider:          provider,
            decode:            nil,
            shouldInterpolate: true,
            intent:            .defaultIntent
        )
        else
        {
            throw RuntimeError( message: "Failed to create CGImage" )
        }

        return image
    }
}
