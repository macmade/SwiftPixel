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

struct Test_Processors_Debayer_VNG
{
    // The eight VNG gradients are zero over a flat window, for any center color.
    @Test
    func vngGradientsFlatAreZero() async throws
    {
        let flat = [ Double ]( repeating: 100.0, count: 5 * 5 )

        #expect( Processors.Debayer.vngGradients( flat, currentChannel: 0 ).allSatisfy { $0 == 0.0 } )
        #expect( Processors.Debayer.vngGradients( flat, currentChannel: 1 ).allSatisfy { $0 == 0.0 } )
    }

    // The gradient formulas and the keep threshold match the canonical VNG for a
    // vertical edge (columns 0-1 dark = 10, columns 2-4 bright = 90, center on
    // the bright side). Golden gradients are from an independent oracle running
    // PixInsight's verbatim formulas; the across-edge directions (W, NW, SW) must
    // exceed the threshold and be dropped, the along-edge/flat ones kept.
    @Test
    func vngGradientsAndThresholdForVerticalEdge() async throws
    {
        let patch = ( 0 ..< 5 ).flatMap { _ in [ 10.0, 10.0, 90.0, 90.0, 90.0 ] }

        // Order: N, E, S, W, NE, SE, NW, SW.
        let redCenter   = Processors.Debayer.vngGradients( patch, currentChannel: 0 )
        let greenCenter = Processors.Debayer.vngGradients( patch, currentChannel: 1 )

        #expect( redCenter   == [ 0, 160, 0, 320, 120, 120, 240, 240 ] )
        #expect( greenCenter == [ 0, 160, 0, 320, 160, 160, 320, 320 ] )

        let threshold = Processors.Debayer.vngThreshold( redCenter )

        #expect( threshold == 160 )      // 1.5·min + 0.5·(max − min) = 1.5·0 + 0.5·320
        #expect( redCenter[ 0 ] <= threshold ) // N  — flat, kept
        #expect( redCenter[ 1 ] <= threshold ) // E  — along the bright side, kept
        #expect( redCenter[ 3 ] >  threshold ) // W  — across the edge, dropped
        #expect( redCenter[ 6 ] >  threshold ) // NW — across the edge, dropped
        #expect( redCenter[ 7 ] >  threshold ) // SW — across the edge, dropped
    }

    // A flat mosaic reconstructs exactly (every channel equals the sample), for
    // every center color across the interior.
    @Test
    func vngFlatRegionIsExact() async throws
    {
        let value  = 123.0
        let pixels = [ Double ]( repeating: value, count: 8 * 8 )
        var buffer = try PixelBuffer( width: 8, height: 8, channels: 1, pixels: pixels, isNormalized: false )

        try Processors.Debayer( mode: .vng, pattern: .rggb ).process( buffer: &buffer )

        #expect( buffer.pixels.allSatisfy { $0 == value } )
    }

    // Golden for an 8x8 RGGB vertical step edge (columns 0-3 = 20, 4-7 = 200),
    // produced by an independent oracle: PixInsight's canonical VNG (verbatim
    // gradients / threshold / colour-difference sums) in raw sample space. The
    // interior [2,6) is VNG; the 2-pixel border replicates the nearest interior
    // pixel (as PixInsight does). All eight rows are identical because the input
    // is vertically uniform.
    @Test
    func vngInteriorGoldenStepEdgeRGGB() async throws
    {
        let pixels = ( 0 ..< 64 ).map { Double( ( $0 % 8 ) < 4 ? 20 : 200 ) }
        var buffer = try PixelBuffer( width: 8, height: 8, channels: 1, pixels: pixels, isNormalized: false )

        try Processors.Debayer( mode: .vng, pattern: .rggb ).process( buffer: &buffer )

        let row: [ Double ] =
            [
                20,  20,  20,   20,  20,  20,   20,  20,  20,   56,  20,  20,
                200, 200, 164,  200, 200, 200,  200, 200, 200,  200, 200, 200,
            ]
        let golden = ( 0 ..< 8 ).flatMap { _ in row }

        #expect( buffer.pixels == golden )
    }

    // Interior VNG for a non-RGGB pattern (GRBG): confirms the reconstruction is
    // driven by the channel map, not RGGB-specific. Same 8x8 step edge; the edge
    // artefacts land on different channels than RGGB because the Bayer phase
    // differs. Golden from the oracle.
    @Test
    func vngInteriorGoldenStepEdgeGRBG() async throws
    {
        let pixels = ( 0 ..< 64 ).map { Double( ( $0 % 8 ) < 4 ? 20 : 200 ) }
        var buffer = try PixelBuffer( width: 8, height: 8, channels: 1, pixels: pixels, isNormalized: false )

        try Processors.Debayer( mode: .vng, pattern: .grbg ).process( buffer: &buffer )

        let row: [ Double ] =
            [
                20,  20,  20,   20,  20,  20,   20,  20,  20,   20,  20,  56,
                164, 200, 200,  200, 200, 200,  200, 200, 200,  200, 200, 200,
            ]
        let golden = ( 0 ..< 8 ).flatMap { _ in row }

        #expect( buffer.pixels == golden )
    }

    // A tall image (height >= 68) drives parallelOrSerial's concurrentPerform
    // fan-out. The input is vertically uniform, so every row must reconstruct to
    // the same RGGB step-edge row — an exact check that the concurrent path is
    // correct and its disjoint per-row writes do not race.
    @Test
    func vngConcurrentPathIsCorrectForTallImage() async throws
    {
        let width  = 8
        let height = 80
        let pixels = ( 0 ..< width * height ).map { Double( ( $0 % width ) < 4 ? 20 : 200 ) }
        var buffer = try PixelBuffer( width: width, height: height, channels: 1, pixels: pixels, isNormalized: false )

        try Processors.Debayer( mode: .vng, pattern: .rggb ).process( buffer: &buffer )

        let row: [ Double ] =
            [
                20,  20,  20,   20,  20,  20,   20,  20,  20,   56,  20,  20,
                200, 200, 164,  200, 200, 200,  200, 200, 200,  200, 200, 200,
            ]
        let golden = ( 0 ..< height ).flatMap { _ in row }

        #expect( buffer.pixels == golden )
    }

    // The 2-pixel border must replicate the nearest fully-computed interior
    // pixel (PixInsight's border strategy), never edge-clamped wrong-colour
    // reads (CR-17). Uses the same 8x8 step edge.
    @Test
    func vngBorderReplicatesNearestInteriorPixel() async throws
    {
        let pixels = ( 0 ..< 64 ).map { Double( ( $0 % 8 ) < 4 ? 20 : 200 ) }
        var buffer = try PixelBuffer( width: 8, height: 8, channels: 1, pixels: pixels, isNormalized: false )

        try Processors.Debayer( mode: .vng, pattern: .rggb ).process( buffer: &buffer )

        func pixel( _ x: Int, _ y: Int ) -> [ Double ]
        {
            let i = ( y * 8 + x ) * 3

            return Array( buffer.pixels[ i ..< i + 3 ] )
        }

        ( 0 ..< 8 ).forEach
        {
            y in

            // Left two columns replicate column 2; right two replicate column 5.
            #expect( pixel( 0, y ) == pixel( 2, y ) )
            #expect( pixel( 1, y ) == pixel( 2, y ) )
            #expect( pixel( 7, y ) == pixel( 5, y ) )
            #expect( pixel( 6, y ) == pixel( 5, y ) )
        }

        ( 0 ..< 8 ).forEach
        {
            x in

            // Top two rows replicate row 2; bottom two replicate row 5.
            #expect( pixel( x, 0 ) == pixel( x, 2 ) )
            #expect( pixel( x, 1 ) == pixel( x, 2 ) )
            #expect( pixel( x, 7 ) == pixel( x, 5 ) )
            #expect( pixel( x, 6 ) == pixel( x, 5 ) )
        }
    }

    // A single bright red-site pixel (a star): its present red is preserved
    // exactly, green/blue reconstruct as the colour-difference average, and the
    // brightness spreads into the red plane along the good directions. Golden
    // values from the oracle.
    @Test
    func vngPointSourcePreservesStarAndSpreads() async throws
    {
        let pixels = ( 0 ..< 64 ).map { Double( $0 == ( 4 * 8 + 4 ) ? 1000 : 10 ) }
        var buffer = try PixelBuffer( width: 8, height: 8, channels: 1, pixels: pixels, isNormalized: false )

        try Processors.Debayer( mode: .vng, pattern: .rggb ).process( buffer: &buffer )

        func pixel( _ x: Int, _ y: Int ) -> [ Double ]
        {
            let i = ( y * 8 + x ) * 3

            return Array( buffer.pixels[ i ..< i + 3 ] )
        }

        #expect( pixel( 4, 4 ) == [ 1000, 505, 505 ] ) // star: red preserved, G=B=(1000+10)/2
        #expect( pixel( 3, 4 ) == [ 381.25, 10, 10 ] ) // spread west along the red plane
        #expect( pixel( 0, 0 ) == [ 10, 10, 10 ] )     // far background stays neutral
    }

    // Images smaller than 5x5 have no VNG interior (the 5x5 stencil needs a
    // 2-pixel inset), so VNG falls back to bilinear.
    @Test
    func vngTinyImageFallsBackToBilinear() async throws
    {
        try [ ( 2, 2 ), ( 4, 4 ), ( 4, 8 ), ( 8, 4 ) ].forEach
        {
            width, height in

            let pixels = ( 0 ..< width * height ).map { Double( $0 + 1 ) }

            var vng      = try PixelBuffer( width: width, height: height, channels: 1, pixels: pixels, isNormalized: false )
            var bilinear = try PixelBuffer( width: width, height: height, channels: 1, pixels: pixels, isNormalized: false )

            try Processors.Debayer( mode: .vng,      pattern: .rggb ).process( buffer: &vng )
            try Processors.Debayer( mode: .bilinear, pattern: .rggb ).process( buffer: &bilinear )

            #expect( vng.pixels == bilinear.pixels )
        }
    }

    // A 2x2 buffer is below the VNG interior size, so it falls back to bilinear;
    // the present colour at each RGGB site is still taken directly from the mosaic.
    @Test
    func vngRGGB_2x2() async throws
    {
        var buffer = try PixelBuffer( width: 2, height: 2, channels: 1, pixels: [ 10, 20, 30, 40 ], isNormalized: false )

        try Processors.Debayer( mode: .vng, pattern: .rggb ).process( buffer: &buffer )

        try #require( buffer.channels     == 3 )
        try #require( buffer.pixels.count == 12 )

        #expect( buffer.pixels.allSatisfy { $0.isFinite } )

        #expect( buffer.pixels[  0 ] == 10 ) // (0,0) red
        #expect( buffer.pixels[  4 ] == 20 ) // (1,0) green
        #expect( buffer.pixels[  7 ] == 30 ) // (0,1) green
        #expect( buffer.pixels[ 11 ] == 40 ) // (1,1) blue
    }

    // Same fallback for a BGGR 2x2: present colour preserved at each site.
    @Test
    func vngBGGR_2x2() async throws
    {
        var buffer = try PixelBuffer( width: 2, height: 2, channels: 1, pixels: [ 10, 20, 30, 40 ], isNormalized: false )

        try Processors.Debayer( mode: .vng, pattern: .bggr ).process( buffer: &buffer )

        try #require( buffer.channels     == 3 )
        try #require( buffer.pixels.count == 12 )

        #expect( buffer.pixels.allSatisfy { $0.isFinite } )

        #expect( buffer.pixels[  2 ] == 10 ) // (0,0) blue
        #expect( buffer.pixels[  4 ] == 20 ) // (1,0) green
        #expect( buffer.pixels[  7 ] == 30 ) // (0,1) green
        #expect( buffer.pixels[  9 ] == 40 ) // (1,1) red
    }

    @Test
    func vngAndBilinearBothSelectable() async throws
    {
        let pixels = ( 0 ..< 16 ).map { Double( $0 + 1 ) }

        for mode in [ Processors.Debayer.Mode.bilinear, .vng ]
        {
            var buffer = try PixelBuffer( width: 4, height: 4, channels: 1, pixels: pixels, isNormalized: false )

            try Processors.Debayer( mode: mode, pattern: .rggb ).process( buffer: &buffer )

            #expect( buffer.channels     == 3 )
            #expect( buffer.pixels.count == 48 )
            #expect( buffer.pixels.allSatisfy { $0.isFinite } )
        }
    }

    @Test
    func vngEdgeErrorNotWorseThanBilinear() async throws
    {
        // 8x8 luminance edge (every channel equal): columns 0-3 = 10, 4-7 = 90.
        // The true image is flat (v, v, v) per side, so reconstruction error
        // measures edge blurring. Sized so the VNG interior is exercised.
        let width  = 8
        let height = 8
        let row    = [ 10.0, 10.0, 10.0, 10.0, 90.0, 90.0, 90.0, 90.0 ]
        let mosaic = ( 0 ..< height ).flatMap { _ in row }

        func error( mode: Processors.Debayer.Mode ) throws -> Double
        {
            var buffer = try PixelBuffer( width: width, height: height, channels: 1, pixels: mosaic, isNormalized: false )

            try Processors.Debayer( mode: mode, pattern: .rggb ).process( buffer: &buffer )

            return ( 0 ..< width * height ).reduce( 0.0 )
            {
                let truth = row[ $1 % width ]

                return $0 + abs( buffer.pixels[ $1 * 3 + 0 ] - truth )
                    + abs( buffer.pixels[ $1 * 3 + 1 ] - truth )
                    + abs( buffer.pixels[ $1 * 3 + 2 ] - truth )
            }
        }

        let vngError      = try error( mode: .vng )
        let bilinearError = try error( mode: .bilinear )

        #expect( vngError <= bilinearError )
    }
}
