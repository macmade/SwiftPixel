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

import Accelerate
import Foundation
import SwiftUtilities

public extension Processors
{
    struct WhiteBalance: PixelProcessor
    {
        public enum Mode: Sendable, CustomStringConvertible
        {
            case auto
            case manual( red: Double, green: Double, blue: Double )

            public var description: String
            {
                switch self
                {
                    case .auto:                          return "Auto"
                    case .manual( let r, let g, let b ): return String( format: "Manual - R: %.02f, G: %.02f, B: %.02f", r, g, b )
                }
            }
        }

        public let mode: Mode

        public var name: String
        {
            String( format: "White Balance (\( self.mode )" )
        }

        public func process( buffer: inout PixelBuffer ) throws
        {
            guard buffer.isNormalized
            else
            {
                throw RuntimeError( message: "Buffer needs to be normalized" )
            }

            guard buffer.channels == 3
            else
            {
                throw RuntimeError( message: "Unsupported channel count: \( buffer.channels )" )
            }

            switch ( self.mode )
            {
                case .auto:

                    let rgb = try Self.computeGains( buffer: buffer )

                    try Self.whiteBalance( buffer: &buffer, r: rgb.r, g: rgb.g, b: rgb.b )

                case .manual( let r, let g, let b ):

                    try Self.whiteBalance( buffer: &buffer, r: r, g: g, b: b )
            }
        }

        private static func whiteBalance( buffer: inout PixelBuffer, r: Double, g: Double, b: Double ) throws
        {
            let count = vDSP_Length( buffer.width * buffer.height )

            try buffer.pixels.withUnsafeMutableBufferPointer
            {
                guard let baseAddress = $0.baseAddress
                else
                {
                    throw RuntimeError( message: "Failed to access data buffer" )
                }

                var r = r
                var g = g
                var b = b

                vDSP_vsmulD( baseAddress, 3, &r, baseAddress, 3, count )
                vDSP_vsmulD( baseAddress.advanced( by: 1 ), 3, &g, baseAddress.advanced( by: 1 ), 3, count )
                vDSP_vsmulD( baseAddress.advanced( by: 2 ), 3, &b, baseAddress.advanced( by: 2 ), 3, count )
            }
        }

        private static func computeGains( buffer: PixelBuffer ) throws -> ( r: Double, g: Double, b: Double )
        {
            let count = vDSP_Length( buffer.width * buffer.height )

            return try buffer.pixels.withUnsafeBufferPointer
            {
                guard let baseAddress = $0.baseAddress
                else
                {
                    throw RuntimeError( message: "Failed to access data buffer" )
                }

                var sumR = 0.0
                var sumG = 0.0
                var sumB = 0.0

                vDSP_sveD( baseAddress, 3, &sumR, count )
                vDSP_sveD( baseAddress.advanced( by: 1 ), 3, &sumG, count )
                vDSP_sveD( baseAddress.advanced( by: 2 ), 3, &sumB, count )

                let avgR  = sumR / Double( count )
                let avgG  = sumG / Double( count )
                let avgB  = sumB / Double( count )
                let gray  = ( avgR + avgG + avgB ) / 3.0
                let gainR = gray > 0 ? gray / avgR : 1.0
                let gainG = gray > 0 ? gray / avgG : 1.0
                let gainB = gray > 0 ? gray / avgB : 1.0

                return ( gainR, gainG, gainB )
            }
        }
    }
}
