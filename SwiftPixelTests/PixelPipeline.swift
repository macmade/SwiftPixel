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
        whiteBalance:       Processors.WhiteBalance.Mode?                                              = nil,
        invert:             Bool                                                                       = false,
        brightnessContrast: ( brightness: Double, contrast: Double )?                                  = nil,
        levels:             Processors.Levels.Channels?                                                = nil,
        curves:             Processors.Curves.Channels?                                                = nil,
        colorBalance:       Processors.ColorBalance.Ranges?                                            = nil,
        hue:                Double?                                                                    = nil,
        saturation:         Double?                                                                    = nil,
        orient:             Processors.Orient.Orientation?                                             = nil,
        benchmark:          Bool                                                                       = false,
        benchmarkOutput:    ( @Sendable ( String ) -> Void )?                                          = nil
    ) -> PixelPipeline.Config
    {
        PixelPipeline.Config( scale: scale, debayer: debayer, normalize: normalize, stretch: stretch, correctGamma: correctGamma, whiteBalance: whiteBalance, invert: invert, brightnessContrast: brightnessContrast, levels: levels, curves: curves, colorBalance: colorBalance, hue: hue, saturation: saturation, orient: orient, benchmark: benchmark, benchmarkOutput: benchmarkOutput )
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
        let levels = Processors.Levels.Channels.uniform( Processors.Levels.Parameters( inputBlack: 0.1, inputWhite: 0.9 ) )
        let curves = Processors.Curves.Channels.uniform( Processors.Curves.Curve( points: [ .init( x: 0, y: 0 ), .init( x: 0.5, y: 0.7 ), .init( x: 1, y: 1 ) ] ) )

        let pipeline = PixelPipeline(
            config: Self.config(
                scale:              ( scale: 2.0, offset: 1.0 ),
                debayer:            ( .rggb, .bilinear ),
                normalize:          .minMax,
                stretch:            .log( 1.0 ),
                correctGamma:       2.0,
                whiteBalance:       .auto,
                invert:             true,
                brightnessContrast: ( brightness: 0.2, contrast: 1.5 ),
                levels:             levels,
                curves:             curves,
                colorBalance:       .init( midtones: .init( red: 0.1 ) ),
                hue:                30.0,
                saturation:         1.5,
                orient:             .init( rotation: .clockwise90, mirroredHorizontally: false )
            )
        )

        let names = pipeline.processors().map { $0.name }

        // The fixed order: raw scaling and demosaicing, then normalization, then
        // the linear-domain adjustments applied before the non-linear stretch
        // (white balance as colour calibration, then brightness/contrast), then
        // the stretch, then the display-referred stages applied on the stretched
        // image (gamma, levels, curves, colour balance, hue, saturation,
        // invert), with orientation — a pure geometry permutation — last.
        #expect( names.count == 14 )
        #expect( names[  0 ].hasPrefix( "Scale" ) )
        #expect( names[  1 ].hasPrefix( "Debayer" ) )
        #expect( names[  2 ].hasPrefix( "Normalize" ) )
        #expect( names[  3 ].hasPrefix( "White Balance" ) )
        #expect( names[  4 ].hasPrefix( "Brightness/Contrast" ) )
        #expect( names[  5 ].hasPrefix( "Stretch" ) )
        #expect( names[  6 ].hasPrefix( "Gamma Correction" ) )
        #expect( names[  7 ].hasPrefix( "Levels" ) )
        #expect( names[  8 ].hasPrefix( "Curves" ) )
        #expect( names[  9 ].hasPrefix( "Color Balance" ) )
        #expect( names[ 10 ].hasPrefix( "Hue" ) )
        #expect( names[ 11 ].hasPrefix( "Saturation" ) )
        #expect( names[ 12 ].hasPrefix( "Invert" ) )
        #expect( names[ 13 ].hasPrefix( "Orient" ) )
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
    func brightnessContrastAppendedAfterNormalizeBeforeStretch() async throws
    {
        let pipeline = PixelPipeline( config: Self.config( normalize: .minMax, stretch: .log( 1.0 ), brightnessContrast: ( brightness: 0.2, contrast: 1.5 ) ) )
        let names    = pipeline.processors().map { $0.name }

        let normalizeIndex = try #require( names.firstIndex { $0.hasPrefix( "Normalize" ) } )
        let brightIndex    = try #require( names.firstIndex { $0.hasPrefix( "Brightness/Contrast" ) } )
        let stretchIndex   = try #require( names.firstIndex { $0.hasPrefix( "Stretch" ) } )

        #expect( normalizeIndex < brightIndex )
        #expect( brightIndex < stretchIndex )
    }

    @Test
    func neutralBrightnessContrastNotAppended() async throws
    {
        let pipeline = PixelPipeline( config: Self.config( normalize: .minMax, brightnessContrast: ( brightness: 0.0, contrast: 1.0 ) ) )
        let names    = pipeline.processors().map { $0.name }

        #expect( names.contains { $0.hasPrefix( "Brightness/Contrast" ) } == false )
    }

    @Test
    func autoInsertsNormalizeForBrightnessContrast() async throws
    {
        let pipeline = PixelPipeline( config: Self.config( brightnessContrast: ( brightness: 0.2, contrast: 1.5 ) ) )
        let result   = try pipeline.run( pixels: [ 10, 20, 30, 40 ], width: 2, height: 2, bitsPerPixel: .uint8 )

        #expect( result.isNormalized == true )
        #expect( result.pixels.allSatisfy { $0 >= 0.0 && $0 <= 1.0 } )
    }

    @Test
    func levelsAppliedAfterStretch() async throws
    {
        let pipeline = PixelPipeline( config: Self.config( normalize: .minMax, stretch: .log( 1.0 ), brightnessContrast: ( brightness: 0.2, contrast: 1.5 ), levels: .uniform( Processors.Levels.Parameters( inputBlack: 0.1, inputWhite: 0.9 ) ) ) )
        let names    = pipeline.processors().map { $0.name }

        let brightIndex  = try #require( names.firstIndex { $0.hasPrefix( "Brightness/Contrast" ) } )
        let stretchIndex = try #require( names.firstIndex { $0.hasPrefix( "Stretch" ) } )
        let levelsIndex  = try #require( names.firstIndex { $0.hasPrefix( "Levels" ) } )

        // Brightness/contrast is a linear adjustment applied before the stretch;
        // levels is a display-referred tone remap applied after it.
        #expect( brightIndex  < stretchIndex )
        #expect( stretchIndex < levelsIndex )
    }

    @Test
    func identityLevelsNotAppended() async throws
    {
        let pipeline = PixelPipeline( config: Self.config( normalize: .minMax, levels: .uniform( .identity ) ) )
        let names    = pipeline.processors().map { $0.name }

        #expect( names.contains { $0.hasPrefix( "Levels" ) } == false )
    }

    @Test
    func autoInsertsNormalizeForLevels() async throws
    {
        let pipeline = PixelPipeline( config: Self.config( levels: .uniform( Processors.Levels.Parameters( inputBlack: 0.1, inputWhite: 0.9 ) ) ) )
        let result   = try pipeline.run( pixels: [ 10, 20, 30, 40 ], width: 2, height: 2, bitsPerPixel: .uint8 )

        #expect( result.isNormalized == true )
        #expect( result.pixels.allSatisfy { $0 >= 0.0 && $0 <= 1.0 } )
    }

    @Test
    func curvesAppliedAfterLevelsAndStretch() async throws
    {
        let levels = Processors.Levels.Channels.uniform( Processors.Levels.Parameters( inputBlack: 0.1, inputWhite: 0.9 ) )
        let curves = Processors.Curves.Channels.uniform( Processors.Curves.Curve( points: [ .init( x: 0, y: 0 ), .init( x: 0.5, y: 0.7 ), .init( x: 1, y: 1 ) ] ) )

        let pipeline = PixelPipeline( config: Self.config( normalize: .minMax, stretch: .log( 1.0 ), levels: levels, curves: curves ) )
        let names    = pipeline.processors().map { $0.name }

        let stretchIndex = try #require( names.firstIndex { $0.hasPrefix( "Stretch" ) } )
        let levelsIndex  = try #require( names.firstIndex { $0.hasPrefix( "Levels" ) } )
        let curvesIndex  = try #require( names.firstIndex { $0.hasPrefix( "Curves" ) } )

        // Levels and curves are display-referred tone remaps applied after the
        // stretch, in that order.
        #expect( stretchIndex < levelsIndex )
        #expect( levelsIndex  < curvesIndex )
    }

    @Test
    func identityCurvesNotAppended() async throws
    {
        let pipeline = PixelPipeline( config: Self.config( normalize: .minMax, curves: .uniform( .identity ) ) )
        let names    = pipeline.processors().map { $0.name }

        #expect( names.contains { $0.hasPrefix( "Curves" ) } == false )
    }

    @Test
    func autoInsertsNormalizeForCurves() async throws
    {
        let curves   = Processors.Curves.Channels.uniform( Processors.Curves.Curve( points: [ .init( x: 0, y: 0 ), .init( x: 0.5, y: 0.7 ), .init( x: 1, y: 1 ) ] ) )
        let pipeline = PixelPipeline( config: Self.config( curves: curves ) )
        let result   = try pipeline.run( pixels: [ 10, 20, 30, 40 ], width: 2, height: 2, bitsPerPixel: .uint8 )

        #expect( result.isNormalized == true )
        #expect( result.pixels.allSatisfy { $0 >= 0.0 && $0 <= 1.0 } )
    }

    @Test
    func saturationAppliedAfterStretchBeforeInvert() async throws
    {
        let pipeline = PixelPipeline( config: Self.config( normalize: .minMax, stretch: .log( 1.0 ), whiteBalance: .auto, invert: true, saturation: 1.5 ) )
        let names    = pipeline.processors().map { $0.name }

        let whiteBalanceIndex = try #require( names.firstIndex { $0.hasPrefix( "White Balance" ) } )
        let stretchIndex      = try #require( names.firstIndex { $0.hasPrefix( "Stretch" ) } )
        let saturationIndex   = try #require( names.firstIndex { $0.hasPrefix( "Saturation" ) } )
        let invertIndex       = try #require( names.firstIndex { $0.hasPrefix( "Invert" ) } )

        // White balance is a linear calibration applied before the stretch;
        // saturation is a display-referred colour adjustment applied after it,
        // ahead of the final invert.
        #expect( whiteBalanceIndex < stretchIndex )
        #expect( stretchIndex      < saturationIndex )
        #expect( saturationIndex   < invertIndex )
    }

    @Test
    func neutralSaturationNotAppended() async throws
    {
        let pipeline = PixelPipeline( config: Self.config( normalize: .minMax, saturation: 1.0 ) )
        let names    = pipeline.processors().map { $0.name }

        #expect( names.contains { $0.hasPrefix( "Saturation" ) } == false )
    }

    @Test
    func hueAppliedAfterCurvesBeforeSaturation() async throws
    {
        let curves   = Processors.Curves.Channels.uniform( Processors.Curves.Curve( points: [ .init( x: 0, y: 0 ), .init( x: 0.5, y: 0.7 ), .init( x: 1, y: 1 ) ] ) )
        let pipeline = PixelPipeline( config: Self.config( normalize: .minMax, stretch: .log( 1.0 ), curves: curves, hue: 30.0, saturation: 1.5 ) )
        let names    = pipeline.processors().map { $0.name }

        let curvesIndex     = try #require( names.firstIndex { $0.hasPrefix( "Curves" ) } )
        let hueIndex        = try #require( names.firstIndex { $0.hasPrefix( "Hue" ) } )
        let saturationIndex = try #require( names.firstIndex { $0.hasPrefix( "Saturation" ) } )

        // Hue is a display-referred colour rotation applied after the tone
        // stages, immediately ahead of saturation.
        #expect( curvesIndex < hueIndex )
        #expect( hueIndex    < saturationIndex )
    }

    @Test
    func neutralHueNotAppended() async throws
    {
        let pipeline = PixelPipeline( config: Self.config( normalize: .minMax, hue: 0.0 ) )
        let names    = pipeline.processors().map { $0.name }

        #expect( names.contains { $0.hasPrefix( "Hue" ) } == false )
    }

    @Test
    func autoInsertsNormalizeForHue() async throws
    {
        let pipeline = PixelPipeline( config: Self.config( hue: 30.0 ) )
        let result   = try pipeline.run( pixels: [ 10, 20, 30, 40 ], width: 2, height: 2, bitsPerPixel: .uint8 )

        #expect( result.isNormalized == true )
        #expect( result.pixels.allSatisfy { $0 >= 0.0 && $0 <= 1.0 } )
    }

    @Test
    func colorBalanceAppliedAfterCurvesBeforeHue() async throws
    {
        let curves   = Processors.Curves.Channels.uniform( Processors.Curves.Curve( points: [ .init( x: 0, y: 0 ), .init( x: 0.5, y: 0.7 ), .init( x: 1, y: 1 ) ] ) )
        let pipeline = PixelPipeline( config: Self.config( normalize: .minMax, stretch: .log( 1.0 ), curves: curves, colorBalance: .init( midtones: .init( red: 0.1 ) ), hue: 30.0 ) )
        let names    = pipeline.processors().map { $0.name }

        let curvesIndex       = try #require( names.firstIndex { $0.hasPrefix( "Curves" ) } )
        let colorBalanceIndex = try #require( names.firstIndex { $0.hasPrefix( "Color Balance" ) } )
        let hueIndex          = try #require( names.firstIndex { $0.hasPrefix( "Hue" ) } )

        // Colour balance is a display-referred grade applied after the tone
        // stages, ahead of hue and saturation.
        #expect( curvesIndex       < colorBalanceIndex )
        #expect( colorBalanceIndex < hueIndex )
    }

    @Test
    func neutralColorBalanceNotAppended() async throws
    {
        let pipeline = PixelPipeline( config: Self.config( normalize: .minMax, colorBalance: .identity ) )
        let names    = pipeline.processors().map { $0.name }

        #expect( names.contains { $0.hasPrefix( "Color Balance" ) } == false )
    }

    @Test
    func autoInsertsNormalizeForColorBalance() async throws
    {
        let pipeline = PixelPipeline( config: Self.config( colorBalance: .init( midtones: .init( red: 0.1 ) ) ) )
        let result   = try pipeline.run( pixels: [ 10, 20, 30, 40 ], width: 2, height: 2, bitsPerPixel: .uint8 )

        #expect( result.isNormalized == true )
        #expect( result.pixels.allSatisfy { $0 >= 0.0 && $0 <= 1.0 } )
    }

    @Test
    func autoInsertsNormalizeForSaturation() async throws
    {
        let pipeline = PixelPipeline( config: Self.config( saturation: 1.5 ) )
        let result   = try pipeline.run( pixels: [ 10, 20, 30, 40 ], width: 2, height: 2, bitsPerPixel: .uint8 )

        #expect( result.isNormalized == true )
        #expect( result.pixels.allSatisfy { $0 >= 0.0 && $0 <= 1.0 } )
    }

    @Test
    func orientAppendedLastWhenNonIdentity() async throws
    {
        let pipeline = PixelPipeline(
            config: Self.config(
                scale:        ( scale: 2.0, offset: 1.0 ),
                debayer:      ( .rggb, .bilinear ),
                normalize:    .minMax,
                stretch:      .log( 1.0 ),
                correctGamma: 2.0,
                whiteBalance: .auto,
                orient:       .init( rotation: .clockwise90, mirroredHorizontally: false )
            )
        )

        let names = pipeline.processors().map { $0.name }

        // Orientation is a pure geometry permutation, so it runs last — after
        // every value stage.
        #expect( names.last?.hasPrefix( "Orient" ) == true )
    }

    @Test
    func identityOrientIsNotAppended() async throws
    {
        let pipeline = PixelPipeline( config: Self.config( normalize: .minMax, orient: .identity ) )
        let names    = pipeline.processors().map { $0.name }

        #expect( names.contains { $0.hasPrefix( "Orient" ) } == false )
    }

    @Test
    func nilOrientIsNotAppended() async throws
    {
        let pipeline = PixelPipeline( config: Self.config( normalize: .minMax ) )
        let names    = pipeline.processors().map { $0.name }

        #expect( names.contains { $0.hasPrefix( "Orient" ) } == false )
    }

    @Test
    func orientRunSwapsDimensions() async throws
    {
        let pipeline = PixelPipeline( config: Self.config( normalize: .minMax, orient: .init( rotation: .clockwise90, mirroredHorizontally: false ) ) )

        // A 2x1 source rotated 90° becomes 1x2.
        let result = try pipeline.run( pixels: [ 10, 20 ], width: 2, height: 1, bitsPerPixel: .uint8 )

        #expect( result.width  == 1 )
        #expect( result.height == 2 )
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
