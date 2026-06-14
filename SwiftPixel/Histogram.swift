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

public struct Histogram
{
    public enum Mode
    {
        case rgb
        case luminance
    }

    public let bytes:    [ UInt8 ]
    public let channels: Int
    public let mode:     Mode
    public let data:     [ [ Int ] ]

    /*
     * Builds per-channel (or luminance) histograms from interleaved 8-bit
     * pixel data.
     *
     * `channels` is the number of interleaved samples per pixel and sets the
     * read stride: 1 (grayscale, replicated into R/G/B), 3 (RGB), or 4 (RGBA,
     * the alpha sample is ignored). Any trailing bytes that don't form a
     * complete pixel are skipped.
     */
    public init( bytes: [ UInt8 ], channels: Int, mode: Mode )
    {
        self.bytes    = bytes
        self.channels = channels
        self.mode     = mode

        let bins      = 256
        var red       = [ Int ]( repeating: 0, count: bins )
        var green     = [ Int ]( repeating: 0, count: bins )
        var blue      = [ Int ]( repeating: 0, count: bins )
        var luminance = [ Int ]( repeating: 0, count: bins )

        if channels >= 1
        {
            for i in stride( from: 0, to: bytes.count - channels + 1, by: channels )
            {
                let r: Int
                let g: Int
                let b: Int

                if channels >= 3
                {
                    r = Int( bytes[ i ] )
                    g = Int( bytes[ i + 1 ] )
                    b = Int( bytes[ i + 2 ] )
                }
                else
                {
                    let value = Int( bytes[ i ] )

                    r = value
                    g = value
                    b = value
                }

                red[   r ] += 1
                green[ g ] += 1
                blue[  b ] += 1

                let y = ( 2126 * r + 7152 * g + 722 * b ) / 10000

                luminance[ y ] += 1
            }
        }

        self.data = mode == .rgb ? [ red, green, blue ] : [ luminance ]
    }
}
