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

/// The per-pixel sample format of raw image data, following the FITS `BITPIX`
/// convention.
///
/// The cases mirror the values of the FITS `BITPIX` header keyword, which
/// encodes both the sample size and its numeric type as a signed integer:
///
/// | `BITPIX` | Case        | Sample type                  |
/// |---------:|-------------|------------------------------|
/// |        8 | `.uint8`    | 8-bit unsigned integer       |
/// |       16 | `.int16`    | 16-bit signed integer        |
/// |       32 | `.int32`    | 32-bit signed integer        |
/// |      -32 | `.float32`  | 32-bit IEEE 754 float        |
/// |      -64 | `.float64`  | 64-bit IEEE 754 float        |
///
/// Per the FITS convention, 8-bit samples are *unsigned* while the 16- and
/// 32-bit integer samples are *signed* — hence the `.uint8` versus
/// `.int16`/`.int32` naming. Multi-byte samples are stored big-endian.
///
/// > Note: `BZERO`/`BSCALE` linear rescaling is **not** applied; samples are
/// > decoded at their stored value.
public enum BitsPerPixel: Sendable, CustomStringConvertible
{
    /// 8-bit unsigned integer samples (`BITPIX` 8).
    case uint8

    /// 16-bit signed, big-endian integer samples (`BITPIX` 16).
    case int16

    /// 32-bit signed, big-endian integer samples (`BITPIX` 32).
    case int32

    /// 32-bit big-endian IEEE 754 floating-point samples (`BITPIX` -32).
    case float32

    /// 64-bit big-endian IEEE 754 floating-point samples (`BITPIX` -64).
    case float64

    /// Returns the case matching a raw FITS `BITPIX` value, or `nil` if the
    /// value is not a recognized format.
    ///
    /// - Parameter value: A FITS `BITPIX` value (`8`, `16`, `32`, `-32` or `-64`).
    ///
    /// - Returns: The matching `BitsPerPixel`, or `nil` for unsupported values.
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

    /// Returns the byte count needed to store `numberOfPixels` samples in this
    /// format.
    ///
    /// - Parameter numberOfPixels: The number of samples.
    ///
    /// - Returns: The total size in bytes (`numberOfPixels × bytes-per-sample`).
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

    /// A human-readable name for the sample format (e.g. `"UInt8"`, `"Int16"`).
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
