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

struct Test_PixelUtilities_ReadRawPixels
{
    @Test
    func readRawPixels_UInt8() async throws
    {
        let values: [ UInt8 ] = [ 0x0A, 0x14, 0x1E, 0x28 ]
        let data              = Data( values )
        let result            = try PixelUtilities.readRawPixels( data: data, width: 2, height: 2, bitsPerPixel: .uint8 )

        #expect( result == [ 10.0, 20.0, 30.0, 40.0 ] )
    }

    @Test
    func readRawPixels_UInt16() async throws
    {
        let values: [ UInt8 ] = [ 0x00, 0x0A, 0x00, 0x14, 0x00, 0x1E, 0x00, 0x28 ]
        let data              = Data( values )
        let result            = try PixelUtilities.readRawPixels( data: data, width: 2, height: 2, bitsPerPixel: .int16 )

        #expect( result == [ 10.0, 20.0, 30.0, 40.0 ] )
    }

    @Test
    func readRawPixels_UInt32() async throws
    {
        let values: [ UInt8 ] = [ 0x00, 0x00, 0x00, 0x0A, 0x00, 0x00, 0x00, 0x14, 0x00, 0x00, 0x00, 0x1E, 0x00, 0x00, 0x00, 0x28 ]
        let data              = Data( values )
        let result            = try PixelUtilities.readRawPixels( data: data, width: 2, height: 2, bitsPerPixel: .int32 )

        #expect( result == [ 10.0, 20.0, 30.0, 40.0 ] )
    }

    @Test
    func readRawPixels_Float32() async throws
    {
        let values: [ Float32 ] = [ 10.0, 20.0, 30.0, 40.0 ]
        let data                = Data( values.flatMap { withUnsafeBytes( of: $0.bitPattern.bigEndian, Array.init ) } )
        let result              = try PixelUtilities.readRawPixels( data: data, width: 2, height: 2, bitsPerPixel: .float32 )

        #expect( result == [ 10.0, 20.0, 30.0, 40.0 ] )
    }

    @Test
    func readRawPixels_Float64() async throws
    {
        let values: [ Float64 ] = [ 10.0, 20.0, 30.0, 40.0 ]
        let data                = Data( values.flatMap { withUnsafeBytes( of: $0.bitPattern.bigEndian, Array.init ) } )
        let result              = try PixelUtilities.readRawPixels( data: data, width: 2, height: 2, bitsPerPixel: .float64 )

        #expect( result == [ 10.0, 20.0, 30.0, 40.0 ] )
    }

    @Test
    func incorrectSize() async throws
    {
        #expect( throws: RuntimeError.self )
        {
            _ = try PixelUtilities.readRawPixels( data: Data( [ 0x00, 0x01 ] ), width: 2, height: 2, bitsPerPixel: .int16 )
        }
    }
}
