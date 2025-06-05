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
    struct Stretch: PixelProcessor
    {
        public enum Algorithm: Sendable, CustomStringConvertible
        {
            case log( Double )
            case arcsinh( Double )
            case sigmoid( Double, Double )

            public var description: String
            {
                switch self
                {
                    case .log( let n ):              return String( format: "Logarithmic %.02f", n )
                    case .arcsinh( let n ):          return String( format: "Hyperbolic %.02f", n )
                    case .sigmoid( let n1, let n2 ): return String( format: "Sigmoid %.02f %.02f", n1, n2 )
                }
            }
        }

        public let algorithm: Algorithm

        public var name: String
        {
            "Stretch (\( self.algorithm ))"
        }

        public func process( buffer: inout PixelBuffer ) throws
        {
            guard buffer.isNormalized
            else
            {
                throw RuntimeError( message: "Buffer needs to be normalized" )
            }

            switch self.algorithm
            {
                case .log(     let n ):          try Self.logStretch(     buffer: &buffer, n: n )
                case .arcsinh( let n ):          try Self.arcsinhStretch( buffer: &buffer, n: n )
                case .sigmoid( let n1, let n2 ): try Self.sigmoidStretch( buffer: &buffer, n1: n1, n2: n2 )
            }
        }

        private static func logStretch( buffer: inout PixelBuffer, n: Double ) throws
        {
            var denominator = log( 1.0 + n )
            var one         = 1.0
            let count       = vDSP_Length( buffer.pixels.count )

            try buffer.pixels.withUnsafeMutableBufferPointer
            {
                guard let baseAddress = $0.baseAddress
                else
                {
                    throw RuntimeError( message: "Failed to access data buffer" )
                }

                vDSP_vsmulD( baseAddress, 1, [ n ], baseAddress, 1, count )
                vDSP_vsaddD( baseAddress, 1, &one, baseAddress, 1, count )
                vvlog( baseAddress, baseAddress, [ Int32( count ) ] )
                vDSP_vsdivD( baseAddress, 1, &denominator, baseAddress, 1, count )
            }
        }

        private static func arcsinhStretch( buffer: inout PixelBuffer, n: Double ) throws
        {
            var denominator = asinh( n )
            let count       = vDSP_Length( buffer.pixels.count )

            try buffer.pixels.withUnsafeMutableBufferPointer
            {
                guard let baseAddress = $0.baseAddress
                else
                {
                    throw RuntimeError( message: "Failed to access data buffer" )
                }

                vDSP_vsmulD( baseAddress, 1, [ n ], baseAddress, 1, count )
                vvasinh( baseAddress, baseAddress, [ Int32( count ) ] )
                vDSP_vsdivD( baseAddress, 1, &denominator, baseAddress, 1, count )
            }
        }

        private static func sigmoidStretch( buffer: inout PixelBuffer, n1: Double, n2: Double ) throws
        {
            let count    = vDSP_Length( buffer.pixels.count )
            var midpoint = -n2
            var slope    = n1
            var minusOne = -1.0
            var one      = 1.0

            try buffer.pixels.withUnsafeMutableBufferPointer
            {
                guard let baseAddress = $0.baseAddress
                else
                {
                    throw RuntimeError( message: "Failed to access data buffer" )
                }

                vDSP_vsaddD( baseAddress, 1, &midpoint, baseAddress, 1, count )
                vDSP_vsmulD( baseAddress, 1, &slope, baseAddress, 1, count )
                vDSP_vsmulD( baseAddress, 1, &minusOne, baseAddress, 1, count )
                vvexp( baseAddress, baseAddress, [ Int32( count ) ] )
                vDSP_vsaddD( baseAddress, 1, &one, baseAddress, 1, count )
                vvrec( baseAddress, baseAddress, [ Int32( count ) ] )
            }
        }
    }
}
