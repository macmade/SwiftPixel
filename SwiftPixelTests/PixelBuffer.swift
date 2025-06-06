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
@testable import SwiftPixel
import SwiftUtilities
import Testing

struct Test_PixelBuffer
{
    @Test
    func initialize()
    {
        let width      = 4
        let height     = 3
        let channels   = 2
        let pixelData  = Array( stride( from: 0.0, to: Double( width * height * channels ), by: 1.0 ))
        let normalized = true

        let buffer = PixelBuffer(
            width: width,
            height: height,
            channels: channels,
            pixels: pixelData,
            isNormalized: normalized
        )

        #expect( buffer.width        == width )
        #expect( buffer.height       == height )
        #expect( buffer.channels     == channels )
        #expect( buffer.pixels       == pixelData )
        #expect( buffer.pixels.count == width * height * channels )
        #expect( buffer.pixels.first == 0.0 )
        #expect( buffer.pixels.last  == Double( pixelData.count - 1 ) )
        #expect( buffer.isNormalized == normalized )
    }

    @Test
    func description()
    {
        let buffer = PixelBuffer(
            width:        10,
            height:       20,
            channels:     1,
            pixels:       [ 0.0, 0.5, 1.0, 0.75 ],
            isNormalized: true
        )

        #expect( buffer.description == "PixelBuffer( width: 10, height: 20, channels: 1, pixels: 4, isNormalized: true )" )
    }

    @Test
    func convert() async throws
    {
        let buffer = PixelBuffer(
            width:        2,
            height:       2,
            channels:     1,
            pixels:       [ 0.0, 0.5, 1.0, 0.25 ],
            isNormalized: true
        )

        let result = try buffer.convertTo8Bits()

        #expect( result == [ 0, 128, 255, 64 ] )
    }

    @Test
    func comvertClamp() async throws
    {
        let buffer = PixelBuffer(
            width:        2,
            height:       2,
            channels:     1,
            pixels:       [ -0.1, 0.0, 1.0, 1.1 ],
            isNormalized: true
        )

        let result = try buffer.convertTo8Bits()

        #expect( result == [ 0, 0, 255, 255 ] )
    }

    @Test
    func convertNotNormalized() async throws
    {
        let buffer = PixelBuffer(
            width:        2,
            height:       2,
            channels:     1,
            pixels:       [ 0.0, 0.5, 1.0, 0.25 ],
            isNormalized: false
        )

        #expect( throws: RuntimeError.self )
        {
            try buffer.convertTo8Bits()
        }
    }

    @Test
    func convertEmpty() async throws
    {
        let buffer = PixelBuffer(
            width:        0,
            height:       0,
            channels:     0,
            pixels:       [ ],
            isNormalized: true
        )

        let result = try buffer.convertTo8Bits()

        #expect( result == [] )
    }

    @Test
    func createCGImageWith1Channel() async throws
    {
        let buffer = PixelBuffer(
            width:        2,
            height:       2,
            channels:     1,
            pixels:       [ 0.0, 0.5, 0.5, 1.0 ],
            isNormalized: true
        )

        let image1 = try buffer.createCGImage()
        let image2 = try PixelBuffer.createCGImage( bytes: try buffer.convertTo8Bits(), width: buffer.width, height: buffer.height, channels: buffer.channels )

        #expect( image1.width            == 2 )
        #expect( image1.height           == 2 )
        #expect( image1.bitsPerComponent == 8 )
        #expect( image1.bitsPerPixel     == 8 )
        #expect( image1.bytesPerRow      == 2 )

        #expect( image2.width            == 2 )
        #expect( image2.height           == 2 )
        #expect( image2.bitsPerComponent == 8 )
        #expect( image2.bitsPerPixel     == 8 )
        #expect( image2.bytesPerRow      == 2 )
    }

    @Test
    func createCGImageWith3Channels() async throws
    {
        let buffer = PixelBuffer(
            width:        1,
            height:       1,
            channels:     3,
            pixels:       [ 1.0, 0.0, 0.5 ],
            isNormalized: true
        )

        let image1 = try buffer.createCGImage()
        let image2 = try PixelBuffer.createCGImage( bytes: try buffer.convertTo8Bits(), width: buffer.width, height: buffer.height, channels: buffer.channels )

        #expect( image1.width            == 1 )
        #expect( image1.height           == 1 )
        #expect( image1.bitsPerComponent == 8 )
        #expect( image1.bitsPerPixel     == 24 )
        #expect( image1.bytesPerRow      == 3 )

        #expect( image2.width            == 1 )
        #expect( image2.height           == 1 )
        #expect( image2.bitsPerComponent == 8 )
        #expect( image2.bitsPerPixel     == 24 )
        #expect( image2.bytesPerRow      == 3 )
    }

    @Test
    func createCGImageWith4Channels() async throws
    {
        let buffer = PixelBuffer(
            width:        1,
            height:       1,
            channels:     4,
            pixels:       [ 1.0, 0.0, 0.5, 1.0 ],
            isNormalized: true
        )

        let image1 = try buffer.createCGImage()
        let image2 = try PixelBuffer.createCGImage( bytes: try buffer.convertTo8Bits(), width: buffer.width, height: buffer.height, channels: buffer.channels )

        #expect( image1.width            == 1 )
        #expect( image1.height           == 1 )
        #expect( image1.bitsPerComponent == 8 )
        #expect( image1.bitsPerPixel     == 32 )
        #expect( image1.bytesPerRow      == 4 )

        #expect( image2.width            == 1 )
        #expect( image2.height           == 1 )
        #expect( image2.bitsPerComponent == 8 )
        #expect( image2.bitsPerPixel     == 32 )
        #expect( image2.bytesPerRow      == 4 )
    }

    @Test
    func createCGImageUnsupportedChannels() async throws
    {
        let buffer = PixelBuffer(
            width:        1,
            height:       1,
            channels:     2,
            pixels:       [ 0.0, 1.0 ],
            isNormalized: true
        )

        #expect( throws: RuntimeError.self )
        {
            try buffer.createCGImage()
        }

        #expect( throws: RuntimeError.self )
        {
            try PixelBuffer.createCGImage( bytes: try buffer.convertTo8Bits(), width: buffer.width, height: buffer.height, channels: buffer.channels )
        }
    }

    @Test
    func createCGImageIncorrectPixelCount() async throws
    {
        let buffer = PixelBuffer(
            width:        2,
            height:       2,
            channels:     3,
            pixels:       [ 1.0, 0.0, 0.5 ],
            isNormalized: true
        )

        #expect( throws: RuntimeError.self )
        {
            try buffer.createCGImage()
        }

        #expect( throws: RuntimeError.self )
        {
            try PixelBuffer.createCGImage( bytes: try buffer.convertTo8Bits(), width: buffer.width, height: buffer.height, channels: buffer.channels )
        }
    }

    @Test
    func createCGImageNotNormalized() async throws
    {
        let buffer = PixelBuffer(
            width:        1,
            height:       1,
            channels:     3,
            pixels:       [ 1.0, 0.0, 0.5 ],
            isNormalized: false
        )

        #expect( throws: RuntimeError.self )
        {
            try buffer.createCGImage()
        }

        #expect( throws: RuntimeError.self )
        {
            try PixelBuffer.createCGImage( bytes: try buffer.convertTo8Bits(), width: buffer.width, height: buffer.height, channels: buffer.channels )
        }
    }
}
