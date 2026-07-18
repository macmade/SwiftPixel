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
@testable import SwiftPixel
import Testing

struct Test_PixelBuffer
{
    @Test
    func initialize() throws
    {
        let width      = 4
        let height     = 3
        let channels   = 2
        let pixelData  = Array( stride( from: 0.0, to: Double( width * height * channels ), by: 1.0 ))
        let normalized = true

        let buffer = try PixelBuffer(
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
    func initializeThrowsOnPixelCountMismatch()
    {
        #expect( throws: PixelBufferError.self )
        {
            _ = try PixelBuffer( width: 2, height: 2, channels: 1, pixels: [ 0.0, 0.5, 1.0 ], isNormalized: true )
        }
    }

    @Test
    func initializeThrowsOnGeometryOverflow()
    {
        #expect( throws: PixelBufferError.self )
        {
            _ = try PixelBuffer( width: Int.max, height: 2, channels: 1, pixels: [], isNormalized: false )
        }
    }

    @Test
    func withUnsafeMutablePixelsMutatesInPlaceAndSetsFlag() throws
    {
        var buffer = try PixelBuffer( width: 2, height: 1, channels: 1, pixels: [ 1.0, 2.0 ], isNormalized: false )

        buffer.withUnsafeMutablePixels( isNormalized: true )
        {
            for index in $0.indices
            {
                $0[ index ] *= 10.0
            }
        }

        #expect( buffer.pixels       == [ 10.0, 20.0 ] )
        #expect( buffer.isNormalized == true )
    }

    @Test
    func equatable() throws
    {
        let a = try PixelBuffer( width: 2, height: 1, channels: 1, pixels: [ 1.0, 2.0 ], isNormalized: false )
        let b = try PixelBuffer( width: 2, height: 1, channels: 1, pixels: [ 1.0, 2.0 ], isNormalized: false )
        let c = try PixelBuffer( width: 2, height: 1, channels: 1, pixels: [ 1.0, 3.0 ], isNormalized: false )

        #expect( a == b )
        #expect( a != c )
    }

    @Test
    func equatableDistinguishesTheFlagAndGeometry() throws
    {
        let base = try PixelBuffer( width: 2, height: 1, channels: 1, pixels: [ 1.0, 2.0 ], isNormalized: false )

        // isNormalized participates in the synthesized ==, so two buffers identical
        // in every other respect but for the flag are not equal.
        let flagged = try PixelBuffer( width: 2, height: 1, channels: 1, pixels: [ 1.0, 2.0 ], isNormalized: true )

        #expect( base != flagged )

        // The same samples under a different geometry — reshaped, or a different
        // channel count — are likewise unequal.
        let reshaped   = try PixelBuffer( width: 1, height: 2, channels: 1, pixels: [ 1.0, 2.0 ], isNormalized: false )
        let threeChans = try PixelBuffer( width: 2, height: 1, channels: 3, pixels: [ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0 ], isNormalized: false )

        #expect( base != reshaped )
        #expect( base != threeChans )
    }

    @Test
    func sendableHandoff() async throws
    {
        let buffer = try PixelBuffer( width: 2, height: 1, channels: 1, pixels: [ 1.0, 2.0 ], isNormalized: true )
        let sum    = await Task { buffer.pixels.reduce( 0.0, + ) }.value

        #expect( sum == 3.0 )
    }

    @Test
    func withUnsafeMutablePixelsPreservesFlag() throws
    {
        var buffer = try PixelBuffer( width: 2, height: 1, channels: 1, pixels: [ 1.0, 2.0 ], isNormalized: true )

        buffer.withUnsafeMutablePixels
        {
            for index in $0.indices
            {
                $0[ index ] += 1.0
            }
        }

        #expect( buffer.pixels       == [ 2.0, 3.0 ] )
        #expect( buffer.isNormalized == true )
    }

    @Test
    func withUnsafeMutablePixelsReturnsBodyResult() throws
    {
        var buffer = try PixelBuffer( width: 2, height: 1, channels: 1, pixels: [ 3.0, 4.0 ], isNormalized: true )

        let sum = buffer.withUnsafeMutablePixels( isNormalized: false )
        {
            $0.reduce( 0.0, + )
        }

        #expect( sum                 == 7.0 )
        #expect( buffer.isNormalized == false )
    }

    @Test
    func withUnsafeMutablePixelsLeavesFlagUnchangedWhenBodyThrows() throws
    {
        struct SampleError: Error {}

        var buffer = try PixelBuffer( width: 2, height: 1, channels: 1, pixels: [ 1.0, 2.0 ], isNormalized: false )

        // The flag is applied only on a non-throwing return: when the body throws
        // after a partial write, the flag stays false, the write persists (the
        // pointer aliases the array's own storage, so nothing is rolled back), and
        // the original error is rethrown.
        #expect( throws: SampleError.self )
        {
            try buffer.withUnsafeMutablePixels( isNormalized: true )
            {
                $0[ 0 ] = 99.0

                throw SampleError()
            }
        }

        #expect( buffer.isNormalized == false )
        #expect( buffer.pixels       == [ 99.0, 2.0 ] )
    }

    @Test
    func pixelBufferErrorDescriptions() throws
    {
        #expect( PixelBufferError.notNormalized.errorDescription == "Buffer needs to be normalized" )
        #expect( PixelBufferError.mustNotBeNormalized.errorDescription == "Input buffer must not be normalized" )
        #expect( PixelBufferError.bufferAccessFailed( role: .data ).errorDescription == "Failed to access data buffer" )
        #expect( PixelBufferError.bufferAccessFailed( role: .input ).errorDescription == "Failed to access input data buffer" )
        #expect( PixelBufferError.bufferAccessFailed( role: .output ).errorDescription == "Failed to access output data buffer" )
        #expect( PixelBufferError.dataSizeMismatch( expected: 8, actual: 6 ).errorDescription == "Data size does not match expected size: 6 != 8" )
        #expect( PixelBufferError.pixelCountMismatch( expected: 4, actual: 3 ).errorDescription == "Pixel count does not match geometry: 3 != 4" )
        #expect( PixelBufferError.invalidChannelCount( 0 ).errorDescription == "Channel count must be at least 1: 0" )
        #expect( PixelBufferError.negativeDimensions( width: -1, height: 2 ).errorDescription == "Dimensions must not be negative: -1x2" )
        #expect( PixelBufferError.geometryOverflow( width: 9, height: 9, channels: 3 ).errorDescription == "Image geometry overflows Int: 9 x 9 x 3" )
        #expect( PixelBufferError.sizeOverflow( sampleCount: 42 ).errorDescription == "Byte size overflows Int for 42 samples" )

        // `supported` is sorted before rendering: [ 1 ] collapses to the single-
        // channel phrasing, and a multi-element list is joined as "1- or 3-channel".
        #expect( PixelBufferError.unsupportedChannelCount( actual: 3, supported: [ 1 ] ).errorDescription == "Requires a single-channel buffer: 3" )
        #expect( PixelBufferError.unsupportedChannelCount( actual: 2, supported: [ 3, 1 ] ).errorDescription == "Requires a 1- or 3-channel buffer: 2" )
    }

    @Test
    func pixelImageErrorDescriptions() throws
    {
        #expect( PixelImageError.unsupportedChannelConfiguration( 2 ).errorDescription == "Unsupported channel configuration: 2" )
        #expect( PixelImageError.dataProviderCreationFailed.errorDescription == "Failed to create CGDataProvider" )
        #expect( PixelImageError.imageCreationFailed.errorDescription == "Failed to create CGImage" )
    }

    @Test
    func initializeThrowsOnChannelsBelowOne()
    {
        #expect( throws: PixelBufferError.self )
        {
            _ = try PixelBuffer( width: 0, height: 0, channels: 0, pixels: [], isNormalized: true )
        }
    }

    @Test
    func initializeThrowsOnNegativeDimensions()
    {
        #expect( throws: PixelBufferError.self )
        {
            _ = try PixelBuffer( width: -1, height: 1, channels: 1, pixels: [ 0.5 ], isNormalized: true )
        }
    }

    @Test
    func description() throws
    {
        let buffer = try PixelBuffer(
            width:        4,
            height:       1,
            channels:     1,
            pixels:       [ 0.0, 0.5, 1.0, 0.75 ],
            isNormalized: true
        )

        #expect( buffer.description == "PixelBuffer( width: 4, height: 1, channels: 1, pixels: 4, isNormalized: true )" )
    }

    @Test
    func convert() async throws
    {
        let buffer = try PixelBuffer(
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
        let buffer = try PixelBuffer(
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
        let buffer = try PixelBuffer(
            width:        2,
            height:       2,
            channels:     1,
            pixels:       [ 0.0, 0.5, 1.0, 0.25 ],
            isNormalized: false
        )

        #expect( throws: PixelBufferError.self )
        {
            try buffer.convertTo8Bits()
        }
    }

    @Test
    func convertEmpty() async throws
    {
        let buffer = try PixelBuffer(
            width:        0,
            height:       0,
            channels:     1,
            pixels:       [ ],
            isNormalized: true
        )

        let result = try buffer.convertTo8Bits()

        #expect( result == [] )
    }

    @Test
    func createCGImageWith1Channel() async throws
    {
        let buffer = try PixelBuffer(
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
        let buffer = try PixelBuffer(
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
        let buffer = try PixelBuffer(
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
    func createCGImageFourChannelUsesPremultipliedAlpha() async throws
    {
        // Pin the 4-channel contract: CoreGraphics reads the RGB samples as already
        // multiplied by alpha (premultipliedLast). The alpha < 1 sample is what
        // makes premultiplied versus straight alpha observable — a straight-alpha
        // caller would get wrong colours through this path.
        let buffer = try PixelBuffer(
            width:        1,
            height:       1,
            channels:     4,
            pixels:       [ 0.25, 0.0, 0.0, 0.5 ], // premultiplied red at half alpha
            isNormalized: true
        )

        let image = try buffer.createCGImage()

        #expect( image.alphaInfo == .premultipliedLast )
    }

    @Test
    func createCGImageUnsupportedChannels() async throws
    {
        let buffer = try PixelBuffer(
            width:        1,
            height:       1,
            channels:     2,
            pixels:       [ 0.0, 1.0 ],
            isNormalized: true
        )

        #expect( throws: PixelImageError.self )
        {
            try buffer.createCGImage()
        }

        #expect( throws: PixelImageError.self )
        {
            try PixelBuffer.createCGImage( bytes: try buffer.convertTo8Bits(), width: buffer.width, height: buffer.height, channels: buffer.channels )
        }
    }

    @Test
    func createCGImageNotNormalized() async throws
    {
        let buffer = try PixelBuffer(
            width:        1,
            height:       1,
            channels:     3,
            pixels:       [ 1.0, 0.0, 0.5 ],
            isNormalized: false
        )

        #expect( throws: PixelBufferError.self )
        {
            try buffer.createCGImage()
        }

        #expect( throws: PixelBufferError.self )
        {
            try PixelBuffer.createCGImage( bytes: try buffer.convertTo8Bits(), width: buffer.width, height: buffer.height, channels: buffer.channels )
        }
    }
}
