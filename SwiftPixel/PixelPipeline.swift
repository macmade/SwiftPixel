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

public struct PixelPipeline
{
    public struct Config
    {
        public let scale:        ( scale: Double, offset: Double )?
        public let bayerPattern: Processors.Debayer.Pattern?
        public let normalize:    Processors.Normalize.Mode?
        public let stretch:      Processors.Stretch.Algorithm?
        public let correctGamma: Double?
        public let whiteBalance: ( r: Double, g: Double, b: Double )?
        public let bitsScale:    UInt?
    }

    public let config: Config

    public init( config: Config )
    {
        self.config = config
    }

    public func run( data: Data, width: Int, height: Int, bitsPerPixel: BitsPerPixel, config: Config ) throws -> PixelBuffer
    {
        let pixels     = try PixelUtilities.readRawPixels( data: data, width: width, height: height, bitsPerPixel: bitsPerPixel )
        var buffer     = PixelBuffer( width: width, height: height, channels: 1, pixels: pixels, isNormalized: false )
        var processors = [ PixelProcessor ]()

        if let scale = config.scale
        {
            processors.append( Processors.Scale( scale: scale.scale, offset: scale.offset ) )
        }

        if let pattern = config.bayerPattern
        {
            processors.append( Processors.Debayer( mode: .vng, pattern: pattern ) )
        }
        else
        {
            processors.append( Processors.MonoToRGB() )
        }

        if let normalize = config.normalize
        {
            processors.append( Processors.Normalize( mode: normalize ) )
        }

        if let stretch = config.stretch
        {
            processors.append( Processors.Stretch( algorithm: stretch ) )
        }

        if let correctGamma = config.correctGamma
        {
            processors.append( Processors.CorrectGamma( gamma: correctGamma ) )
        }

        if let whiteBalance = config.whiteBalance
        {
            processors.append( Processors.WhiteBalance( r: whiteBalance.r, g: whiteBalance.g, b: whiteBalance.b ) )
        }

        if let bitsScale = config.bitsScale
        {
            processors.append( Processors.BitsScale( bits: bitsScale ) )
        }

        try processors.forEach
        {
            try $0.process( buffer: &buffer )
        }

        return buffer
    }
}
