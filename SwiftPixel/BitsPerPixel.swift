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

public enum BitsPerPixel: CustomStringConvertible
{
    case uint8
    case int16
    case int32
    case float32
    case float64

    public static func from< T: BinaryInteger >( value: T ) -> BitsPerPixel?
    {
        switch value
        {
            case   8: return .uint8
            case  16: return .int16
            case  32: return .int32
            case -32: return .float32
            case -64: return .float64
            default:  return nil
        }
    }

    public func size( numberOfPixels: Int ) -> Int
    {
        switch self
        {
            case .uint8:   return numberOfPixels * 1
            case .int16:   return numberOfPixels * 2
            case .int32:   return numberOfPixels * 4
            case .float32: return numberOfPixels * 4
            case .float64: return numberOfPixels * 8
        }
    }

    public var description: String
    {
        switch self
        {
            case .uint8:   return "UInt8"
            case .int16:   return "Int16"
            case .int32:   return "Int32"
            case .float32: return "Float32"
            case .float64: return "Float64"
        }
    }
}
