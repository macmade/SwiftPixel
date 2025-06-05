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

public struct PixelPipeline: Sendable
{
    public struct Config: Sendable
    {
        public let scale:        ( scale: Double, offset: Double )?
        public let bayerPattern: Processors.Debayer.Pattern?
        public let normalize:    Processors.Normalize.Mode?
        public let stretch:      Processors.Stretch.Algorithm?
        public let correctGamma: Double?
        public let whiteBalance: Processors.WhiteBalance.Mode?

        public init( scale: ( scale: Double, offset: Double )?, bayerPattern: Processors.Debayer.Pattern?, normalize: Processors.Normalize.Mode?, stretch: Processors.Stretch.Algorithm?, correctGamma: Double?, whiteBalance: Processors.WhiteBalance.Mode? )
        {
            self.scale        = scale
            self.bayerPattern = bayerPattern
            self.normalize    = normalize
            self.stretch      = stretch
            self.correctGamma = correctGamma
            self.whiteBalance = whiteBalance
        }
    }

    public let config: Config

    public init( config: Config )
    {
        self.config = config
    }

    public func run( data: Data, width: Int, height: Int, bitsPerPixel: BitsPerPixel ) throws -> PixelBuffer
    {
        let pixels     = try PixelUtilities.readRawPixels( data: data, width: width, height: height, bitsPerPixel: bitsPerPixel )
        var buffer     = PixelBuffer( width: width, height: height, channels: 1, pixels: pixels, isNormalized: false )
        var processors = [ PixelProcessor ]()

        if let scale = self.config.scale
        {
            processors.append( Processors.Scale( scale: scale.scale, offset: scale.offset ) )
        }

        if let pattern = self.config.bayerPattern
        {
            processors.append( Processors.Debayer( mode: .vng, pattern: pattern ) )
        }
        else
        {
            processors.append( Processors.MonoToRGB() )
        }

        if let normalize = self.config.normalize
        {
            processors.append( Processors.Normalize( mode: normalize ) )
        }

        if let stretch = self.config.stretch
        {
            processors.append( Processors.Stretch( algorithm: stretch ) )
        }

        if let correctGamma = self.config.correctGamma
        {
            processors.append( Processors.CorrectGamma( gamma: correctGamma ) )
        }

        if let whiteBalance = self.config.whiteBalance
        {
            processors.append( Processors.WhiteBalance( mode: whiteBalance ) )
        }

        try processors.forEach
        {
            processor in try Benchmark.run( label: processor.description )
            {
                try processor.process( buffer: &buffer )
            }
        }

        return buffer
    }
}
