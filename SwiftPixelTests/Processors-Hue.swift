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
@testable import SwiftPixel
import Testing

struct Test_Processors_Hue
{
    /// The tolerance for comparing round-tripped floating-point channels.
    private let tolerance = 1e-9

    @Test
    func zeroAngleIsIdentity() async throws
    {
        let input  = [ 0.2, 0.5, 0.9 ]
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: input, isNormalized: true )

        try Processors.Hue( angle: 0.0 ).process( buffer: &buffer )

        #expect( zip( buffer.pixels, input ).allSatisfy { abs( $0 - $1 ) < self.tolerance }, "got \( buffer.pixels ), expected \( input )" )
    }

    @Test
    func fullRotationIsIdentity() async throws
    {
        let input  = [ 0.2, 0.5, 0.9 ]
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: input, isNormalized: true )

        // A full turn wraps back onto itself, so the image is unchanged.
        try Processors.Hue( angle: 360.0 ).process( buffer: &buffer )

        #expect( zip( buffer.pixels, input ).allSatisfy { abs( $0 - $1 ) < self.tolerance }, "got \( buffer.pixels ), expected \( input )" )
    }

    @Test
    func rotatesRedToGreenAtPlus120() async throws
    {
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: [ 1.0, 0.0, 0.0 ], isNormalized: true )

        try Processors.Hue( angle: 120.0 ).process( buffer: &buffer )

        let expected = [ 0.0, 1.0, 0.0 ]

        #expect( zip( buffer.pixels, expected ).allSatisfy { abs( $0 - $1 ) < self.tolerance }, "got \( buffer.pixels ), expected \( expected )" )
    }

    @Test
    func rotatesGreenToBlueAtPlus120() async throws
    {
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: [ 0.0, 1.0, 0.0 ], isNormalized: true )

        try Processors.Hue( angle: 120.0 ).process( buffer: &buffer )

        let expected = [ 0.0, 0.0, 1.0 ]

        #expect( zip( buffer.pixels, expected ).allSatisfy { abs( $0 - $1 ) < self.tolerance }, "got \( buffer.pixels ), expected \( expected )" )
    }

    @Test
    func rotatesBlueToRedAtPlus120() async throws
    {
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: [ 0.0, 0.0, 1.0 ], isNormalized: true )

        try Processors.Hue( angle: 120.0 ).process( buffer: &buffer )

        let expected = [ 1.0, 0.0, 0.0 ]

        #expect( zip( buffer.pixels, expected ).allSatisfy { abs( $0 - $1 ) < self.tolerance }, "got \( buffer.pixels ), expected \( expected )" )
    }

    @Test
    func negativeAngleWrapsRedToBlue() async throws
    {
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: [ 1.0, 0.0, 0.0 ], isNormalized: true )

        // −120° is equivalent to +240°, taking red round to blue.
        try Processors.Hue( angle: -120.0 ).process( buffer: &buffer )

        let expected = [ 0.0, 0.0, 1.0 ]

        #expect( zip( buffer.pixels, expected ).allSatisfy { abs( $0 - $1 ) < self.tolerance }, "got \( buffer.pixels ), expected \( expected )" )
    }

    @Test
    func grayIsUnchanged() async throws
    {
        let input  = [ 0.5, 0.5, 0.5 ]
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: input, isNormalized: true )

        // A neutral pixel has no hue to rotate, so any angle leaves it untouched.
        try Processors.Hue( angle: 90.0 ).process( buffer: &buffer )

        #expect( zip( buffer.pixels, input ).allSatisfy { abs( $0 - $1 ) < self.tolerance }, "got \( buffer.pixels ), expected \( input )" )
    }

    @Test
    func appliesPerPixel() async throws
    {
        // Two distinct primaries, each rotated 120° onto the next primary.
        var buffer = try PixelBuffer( width: 2, height: 1, channels: 3, pixels: [ 1.0, 0.0, 0.0, 0.0, 1.0, 0.0 ], isNormalized: true )

        try Processors.Hue( angle: 120.0 ).process( buffer: &buffer )

        let expected = [ 0.0, 1.0, 0.0, 0.0, 0.0, 1.0 ]

        #expect( zip( buffer.pixels, expected ).allSatisfy { abs( $0 - $1 ) < self.tolerance }, "got \( buffer.pixels ), expected \( expected )" )
    }

    @Test
    func arbitraryAngleRoundTrips() async throws
    {
        // Rotating a chromatic, non-primary pixel by +37° then −37° returns the
        // original: for a normalized pixel the intermediate RGB never clips (its
        // channels stay within [match, v] ⊆ [0, 1]), so no information is lost and
        // wrap(wrap(h + 37) − 37) = h. This is the full HSV round trip at an angle
        // that is not a multiple of 60/120°, which the primary-only tests skip.
        let input  = [ 0.8, 0.4, 0.2 ]
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: input, isNormalized: true )

        try Processors.Hue( angle:  37.0 ).process( buffer: &buffer )
        try Processors.Hue( angle: -37.0 ).process( buffer: &buffer )

        #expect( zip( buffer.pixels, input ).allSatisfy { abs( $0 - $1 ) < self.tolerance }, "got \( buffer.pixels ), expected \( input )" )
    }

    @Test
    func eightFortyFiveDegreeStepsReturnToStart() async throws
    {
        // Eight successive 45° rotations sum to a full turn, returning the pixel to
        // where it started — a stronger check of the 45° step than the flag-only
        // `remainsNormalized` test.
        let input  = [ 0.8, 0.4, 0.2 ]
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: input, isNormalized: true )

        try ( 0 ..< 8 ).forEach { _ in try Processors.Hue( angle: 45.0 ).process( buffer: &buffer ) }

        #expect( zip( buffer.pixels, input ).allSatisfy { abs( $0 - $1 ) < self.tolerance }, "got \( buffer.pixels ), expected \( input )" )
    }

    @Test
    func remainsNormalized() async throws
    {
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: [ 0.2, 0.5, 0.9 ], isNormalized: true )

        try Processors.Hue( angle: 45.0 ).process( buffer: &buffer )

        #expect( buffer.isNormalized )
    }

    @Test
    func nonThreeChannelThrows() async throws
    {
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 1, pixels: [ 0.5 ], isNormalized: true )

        #expect( throws: PixelBufferError.self )
        {
            try Processors.Hue( angle: 45.0 ).process( buffer: &buffer )
        }
    }

    @Test
    func notNormalizedThrows() async throws
    {
        var buffer = try PixelBuffer( width: 1, height: 1, channels: 3, pixels: [ 0.2, 0.5, 0.9 ], isNormalized: false )

        #expect( throws: PixelBufferError.self )
        {
            try Processors.Hue( angle: 45.0 ).process( buffer: &buffer )
        }
    }

    @Test
    func name() async throws
    {
        #expect( Processors.Hue( angle: 45.0 ).name.isEmpty == false )
    }
}
