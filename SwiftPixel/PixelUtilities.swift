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
import SwiftUtilities

public enum PixelUtilities
{
    public static func readRawPixels( data: Data, width: Int, height: Int, bitsPerPixel: BitsPerPixel ) throws -> [ Double ]
    {
        let count = width * height
        let size  = bitsPerPixel.size( numberOfPixels: count )

        guard data.count == size
        else
        {
            throw RuntimeError( message: "Data size does not match expected size: \( data.count ) != \( size )" )
        }

        let result = UnsafeMutableSendable( [ Double ]( repeating: 0.0, count: count ) )

        try data.withUnsafeBytes
        {
            guard let baseAddress = $0.baseAddress
            else
            {
                throw RuntimeError( message: "Failed to access data buffer" )
            }

            switch bitsPerPixel
            {
                case .uint8:

                    let buffer = UnsafeSendable( baseAddress.assumingMemoryBound( to: UInt8.self ) )

                    DispatchQueue.concurrentPerform( iterations: count )
                    {
                        result.value[ $0 ] = Double( buffer.value[ $0 ] )
                    }

                case .int16:

                    let buffer = UnsafeSendable( baseAddress.assumingMemoryBound( to: Int16.self ) )

                    DispatchQueue.concurrentPerform( iterations: count )
                    {
                        result.value[ $0 ] = Double( Int16( bigEndian: buffer.value[ $0 ] ) )
                    }

                case .int32:

                    let buffer = UnsafeSendable( baseAddress.assumingMemoryBound( to: Int32.self ) )

                    DispatchQueue.concurrentPerform( iterations: count )
                    {
                        result.value[ $0 ] = Double( Int32( bigEndian: buffer.value[ $0 ] ) )
                    }

                case .float32:

                    let buffer = UnsafeSendable( baseAddress.assumingMemoryBound( to: UInt32.self ) )

                    DispatchQueue.concurrentPerform( iterations: count )
                    {
                        result.value[ $0 ] = Double( Float32( bitPattern: UInt32( bigEndian: buffer.value[ $0 ] ) ) )
                    }

                case .float64:

                    let buffer = UnsafeSendable( baseAddress.assumingMemoryBound( to: UInt64.self ) )

                    DispatchQueue.concurrentPerform( iterations: count )
                    {
                        result.value[ $0 ] = Double( bitPattern: UInt64( bigEndian: buffer.value[ $0 ] ) )
                    }
            }
        }

        return result.value
    }
}
