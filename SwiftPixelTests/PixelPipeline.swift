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

private final class OutputCollector: @unchecked
Sendable
{
    private let lock    = NSLock()
    private var storage = [ String ]()

    func append( _ line: String )
    {
        self.lock.lock()
        self.storage.append( line )
        self.lock.unlock()
    }

    var lines: [ String ]
    {
        self.lock.lock()

        defer
        {
            self.lock.unlock()
        }

        return self.storage
    }
}

struct Test_PixelPipeline
{
    private static func config(
        scale:           ( scale: Double, offset: Double )?                                           = nil,
        debayer:         ( pattern: Processors.Debayer.Pattern, mode: Processors.Debayer.Mode )?       = nil,
        normalize:       Processors.Normalize.Mode?                                                    = nil,
        stretch:         Processors.Stretch.Algorithm?                                                 = nil,
        correctGamma:    Double?                                                                       = nil,
        whiteBalance:    Processors.WhiteBalance.Mode?                                                 = nil,
        benchmark:       Bool                                                                          = false,
        benchmarkOutput: ( @Sendable ( String ) -> Void )?                                             = nil
    ) -> PixelPipeline.Config
    {
        PixelPipeline.Config( scale: scale, debayer: debayer, normalize: normalize, stretch: stretch, correctGamma: correctGamma, whiteBalance: whiteBalance, benchmark: benchmark, benchmarkOutput: benchmarkOutput )
    }

    @Test
    func runMono() async throws
    {
        let pipeline = PixelPipeline( config: Self.config( normalize: .minMax ) )
        let result   = try pipeline.run( pixels: [ 10, 20, 30, 40 ], width: 2, height: 2, bitsPerPixel: .uint8 )

        #expect( result.channels     == 3 )
        #expect( result.pixels.count == 12 )
        #expect( result.isNormalized == true )
        #expect( result.pixels.allSatisfy { $0 >= 0.0 && $0 <= 1.0 } )

        let bytes = try result.convertTo8Bits()

        #expect( bytes.count == 12 )
    }

    @Test
    func runRGBViaDebayer() async throws
    {
        let pipeline = PixelPipeline( config: Self.config( debayer: ( .rggb, .bilinear ), normalize: .minMax ) )
        let result   = try pipeline.run( pixels: [ 10, 20, 30, 40 ], width: 2, height: 2, bitsPerPixel: .uint8 )

        #expect( result.channels     == 3 )
        #expect( result.pixels.count == 12 )
        #expect( result.isNormalized == true )

        let bytes = try result.convertTo8Bits()

        #expect( bytes.count == 12 )
    }

    @Test
    func debayerModeSelectsBilinear() async throws
    {
        let pipeline = PixelPipeline( config: Self.config( debayer: ( .rggb, .bilinear ) ) )
        let names    = pipeline.processors().map { $0.name }

        #expect( names.contains { $0.hasPrefix( "Debayer" ) && $0.contains( "Bilinear" ) } )
    }

    @Test
    func debayerModeSelectsVNG() async throws
    {
        let pipeline = PixelPipeline( config: Self.config( debayer: ( .rggb, .vng ) ) )
        let names    = pipeline.processors().map { $0.name }

        #expect( names.contains { $0.hasPrefix( "Debayer" ) && $0.contains( "VNG" ) } )
    }

    @Test
    func autoInsertsNormalizeForStretch() async throws
    {
        let pipeline = PixelPipeline( config: Self.config( stretch: .log( 1.0 ) ) )
        let result   = try pipeline.run( pixels: [ 10, 20, 30, 40 ], width: 2, height: 2, bitsPerPixel: .uint8 )

        #expect( result.isNormalized == true )
        #expect( result.pixels.allSatisfy { $0 >= 0.0 && $0 <= 1.0 } )
    }

    @Test
    func stageOrder() async throws
    {
        let pipeline = PixelPipeline(
            config: Self.config(
                scale:        ( scale: 2.0, offset: 1.0 ),
                debayer:      ( .rggb, .bilinear ),
                normalize:    .minMax,
                stretch:      .log( 1.0 ),
                correctGamma: 2.0,
                whiteBalance: .auto
            )
        )

        let names = pipeline.processors().map { $0.name }

        #expect( names.count == 6 )
        #expect( names[ 0 ].hasPrefix( "Scale" ) )
        #expect( names[ 1 ].hasPrefix( "Debayer" ) )
        #expect( names[ 2 ].hasPrefix( "Normalize" ) )
        #expect( names[ 3 ].hasPrefix( "Stretch" ) )
        #expect( names[ 4 ].hasPrefix( "Gamma Correction" ) )
        #expect( names[ 5 ].hasPrefix( "White Balance" ) )
    }

    @Test
    func autoInsertedNormalizePrecedesStretch() async throws
    {
        let pipeline = PixelPipeline( config: Self.config( stretch: .log( 1.0 ) ) )
        let names    = pipeline.processors().map { $0.name }

        let normalizeIndex = names.firstIndex { $0.hasPrefix( "Normalize" ) }
        let stretchIndex   = names.firstIndex { $0.hasPrefix( "Stretch" ) }

        let normalize = try #require( normalizeIndex )
        let stretch   = try #require( stretchIndex )

        #expect( normalize < stretch )
    }

    @Test
    func noNormalizeInsertedWhenNotRequired() async throws
    {
        let pipeline = PixelPipeline( config: Self.config( scale: ( scale: 2.0, offset: 1.0 ) ) )
        let names    = pipeline.processors().map { $0.name }

        #expect( names.contains { $0.hasPrefix( "Normalize" ) } == false )
        #expect( names == [ "Scale (2.00 1.00)", "Mono to RGB" ] )
    }

    @Test
    func benchmarkSilentByDefault() async throws
    {
        let collector = OutputCollector()
        let pipeline  = PixelPipeline( config: Self.config( normalize: .minMax, benchmarkOutput: { collector.append( $0 ) } ) )

        _ = try pipeline.run( pixels: [ 10, 20, 30, 40 ], width: 2, height: 2, bitsPerPixel: .uint8 )

        #expect( collector.lines.isEmpty )
    }

    @Test
    func benchmarkEmitsOneLinePerStage() async throws
    {
        let collector = OutputCollector()
        let pipeline  = PixelPipeline( config: Self.config( normalize: .minMax, benchmark: true, benchmarkOutput: { collector.append( $0 ) } ) )

        _ = try pipeline.run( pixels: [ 10, 20, 30, 40 ], width: 2, height: 2, bitsPerPixel: .uint8 )

        #expect( collector.lines.count == 2 )
        #expect( collector.lines.allSatisfy { $0.hasPrefix( "Benchmarking - " ) } )
    }
}
