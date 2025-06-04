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

public extension Processors
{
    struct Normalize: PixelProcessor
    {
        public enum Mode: Sendable, CustomStringConvertible
        {
            case minMax
            case percentile( Double, Double )

            public var description: String
            {
                switch self
                {
                    case .minMax:                       return "Min/Max"
                    case .percentile( let p1, let p2 ): return String( format: "Percentile - %.02f %.02f", p1, p2 )
                }
            }
        }

        public let mode: Mode

        public var name: String
        {
            "Normalize (\( self.mode ))"
        }

        public func process( buffer: inout PixelBuffer ) throws
        {
            guard buffer.pixels.isEmpty == false
            else
            {
                buffer.isNormalized = true

                return
            }

            let count = vDSP_Length( buffer.pixels.count )

            switch self.mode
            {
                case .minMax:

                    var minValue: Double = 0
                    var maxValue: Double = 0

                    vDSP_minvD( buffer.pixels, 1, &minValue, count )
                    vDSP_maxvD( buffer.pixels, 1, &maxValue, count )

                    guard minValue != maxValue
                    else
                    {
                        return
                    }

                    let range  = maxValue - minValue
                    let scale  = 1.0 / range
                    let offset = -minValue / range

                    vDSP_vsmsaD( buffer.pixels, 1, [ scale ], [ offset ], &buffer.pixels, 1, count )

                case .percentile( let lowerPercentile, let upperPercentile ):

                    let bounds = PixelUtilities.percentileBounds( in: buffer.pixels, lower: lowerPercentile, upper: upperPercentile )

                    guard bounds.lower != bounds.upper
                    else
                    {
                        return
                    }

                    vDSP_vclipD( buffer.pixels, 1, [ bounds.lower ], [ bounds.upper ], &buffer.pixels, 1, count )

                    let range  = bounds.upper - bounds.lower
                    let scale  = 1.0 / range
                    let offset = -bounds.lower / range

                    vDSP_vsmsaD( buffer.pixels, 1, [ scale ], [ offset ], &buffer.pixels, 1, count )
            }

            vDSP_vclipD( buffer.pixels, 1, [ 0.0 ], [ 1.0 ], &buffer.pixels, 1, count )

            buffer.isNormalized = true
        }
    }
}
