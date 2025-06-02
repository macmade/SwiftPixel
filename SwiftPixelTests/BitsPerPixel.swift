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
import Testing

struct Test_BitsPerPixel
{
    @Test
    func from() async throws
    {
        #expect( BitsPerPixel.from( value: 8 )   == .uint8 )
        #expect( BitsPerPixel.from( value: 16 )  == .int16 )
        #expect( BitsPerPixel.from( value: 32 )  == .int32 )
        #expect( BitsPerPixel.from( value: -32 ) == .float32 )
        #expect( BitsPerPixel.from( value: -64 ) == .float64 )

        #expect( BitsPerPixel.from( value: 0 )    == nil )
        #expect( BitsPerPixel.from( value: 1 )    == nil )
        #expect( BitsPerPixel.from( value: -1 )   == nil )
        #expect( BitsPerPixel.from( value: 128 )  == nil )
        #expect( BitsPerPixel.from( value: -128 ) == nil )
    }

    @Test
    func size() async throws
    {
        #expect( BitsPerPixel.uint8.size(   numberOfPixels: 10 ) == 10 * 1 )
        #expect( BitsPerPixel.int16.size(   numberOfPixels: 10 ) == 10 * 2 )
        #expect( BitsPerPixel.int32.size(   numberOfPixels: 10 ) == 10 * 4 )
        #expect( BitsPerPixel.float32.size( numberOfPixels: 10 ) == 10 * 4 )
        #expect( BitsPerPixel.float64.size( numberOfPixels: 10 ) == 10 * 8 )
    }

    @Test
    func description() async throws
    {
        #expect( BitsPerPixel.uint8.description   == "UInt8" )
        #expect( BitsPerPixel.int16.description   == "Int16" )
        #expect( BitsPerPixel.int32.description   == "Int32" )
        #expect( BitsPerPixel.float32.description == "Float32" )
        #expect( BitsPerPixel.float64.description == "Float64" )
    }
}
