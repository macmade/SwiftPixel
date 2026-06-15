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

struct Test_Processors_Debayer_VNG
{
    @Test
    func gradientsFlatRegionAreZero() async throws
    {
        let pixels = [ Double ]( repeating: 100.0, count: 5 * 5 )

        let gradients = Processors.Debayer.gradients( pixels: pixels, x: 2, y: 2, width: 5, height: 5 )

        #expect( gradients.count == 8 )
        #expect( gradients.allSatisfy { $0 == 0.0 } )
    }

    @Test
    func gradientThresholdExcludesAcrossEdgeDirections() async throws
    {
        // Vertical edge: columns 0-1 are dark, columns 2-4 are bright.
        let row    = [ 0.0, 0.0, 100.0, 100.0, 100.0 ]
        let pixels = ( 0 ..< 5 ).flatMap { _ in row }

        // Centre at (2,2), on the bright side adjacent to the edge.
        let gradients = Processors.Debayer.gradients( pixels: pixels, x: 2, y: 2, width: 5, height: 5 )
        let good      = Processors.Debayer.goodGradients( gradients )

        // Index order: N, NE, E, SE, S, SW, W, NW.
        #expect( good[ 2 ] == true )  // east, along the flat bright region -> retained
        #expect( good[ 6 ] == false ) // west, across the edge into the dark region -> excluded
    }
}
