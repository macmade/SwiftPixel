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

public struct PixelBuffer: CustomStringConvertible
{
    public let width:        Int
    public let height:       Int
    public var channels:     Int
    public var pixels:       [ Double ]
    public var isNormalized: Bool

    public var description: String
    {
        "PixelBuffer( width: \( self.width ), height: \( self.height ), channels: \( self.channels ), pixels: \( self.pixels.count ), isNormalized: \( self.isNormalized ) )"
    }

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

    public func createCGImage() throws -> CGImage
    {
        guard self.channels == 1 || self.channels == 3 || self.channels == 4
        else
        {
            throw RuntimeError( message: "Unsupported number of channels: \( self.channels )" )
        }

        let count = self.width * self.height * self.channels

        guard self.pixels.count >= count
        else
        {
            throw RuntimeError( message: "Data size does not match expected size: \( self.pixels.count ) != \( count )" )
        }

        let bytes            = try self.convertTo8Bits()
        let bitsPerComponent = 8
        let bitsPerPixel     = self.channels * bitsPerComponent
        let bytesPerRow      = self.width * self.channels

        let colorSpace: CGColorSpace
        let bitmapInfo: CGBitmapInfo

        switch self.channels
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
            width:             self.width,
            height:            self.height,
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
