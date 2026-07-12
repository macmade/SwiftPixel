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
import SwiftPixel
import Testing

struct Test_PixelPipeline_Config
{
    @Test
    func initNil() async throws
    {
        let config = PixelPipeline.Config(
            scale:        nil,
            inputFormat:  .mono,
            normalize:    nil,
            stretch:      nil,
            correctGamma: nil,
            whiteBalance: nil
        )

        #expect( config.scale        == nil )
        #expect( config.inputFormat  == .mono )
        #expect( config.normalize    == nil )
        #expect( config.stretch      == nil )
        #expect( config.correctGamma == nil )
        #expect( config.whiteBalance == nil )
    }

    @Test
    func initComplete() async throws
    {
        let config = PixelPipeline.Config(
            scale:        ( scale: 1.5, offset: 0.2 ),
            inputFormat:  .cfa( pattern: .rggb, mode: .vng ),
            normalize:    .percentile( 0.1, 0.9 ),
            stretch:      .uniform( .init( midtones: 0.3 ) ),
            correctGamma: 2.2,
            whiteBalance: .manual( red: 1, green: 2, blue: 3 )
        )

        #expect( config.scale?.scale   == 1.5 )
        #expect( config.scale?.offset  == 0.2 )
        #expect( config.inputFormat    == .cfa( pattern: .rggb, mode: .vng ) )
        #expect( config.correctGamma   == 2.2 )

        if case .percentile( let lower, let upper ) = config.normalize
        {
            #expect( lower == 0.1 )
            #expect( upper == 0.9 )
        }
        else
        {
            #expect( Bool( false ) )
        }

        if case .uniform( let channel ) = config.stretch
        {
            #expect( channel.midtones == 0.3 )
        }
        else
        {
            #expect( Bool( false ) )
        }

        if case .manual( let r, let g, let b ) = config.whiteBalance
        {
            #expect( r == 1 )
            #expect( g == 2 )
            #expect( b == 3 )
        }
        else
        {
            #expect( Bool( false ) )
        }
    }

    @Test
    func initDefaultsCosmeticCorrectionToNil() async throws
    {
        let config = PixelPipeline.Config( inputFormat: .mono )

        #expect( config.cosmeticCorrection == nil )
    }

    @Test
    func initCarriesCosmeticCorrection() async throws
    {
        let parameters = Processors.CosmeticCorrection.Parameters( isEnabled: true, correctHot: true, hotThreshold: 5.0, correctCold: false, coldThreshold: 8.0 )
        let config     = PixelPipeline.Config( inputFormat: .cfa( pattern: .rggb, mode: .vng ), cosmeticCorrection: parameters )

        #expect( config.cosmeticCorrection == parameters )
    }

    @Test
    func initOnlySpecifiedStage() async throws
    {
        let config = PixelPipeline.Config( stretch: .uniform( .init( midtones: 0.3 ) ) )

        #expect( config.scale        == nil )
        #expect( config.inputFormat  == .mono )
        #expect( config.normalize    == nil )
        #expect( config.correctGamma == nil )
        #expect( config.whiteBalance == nil )

        if case .uniform( let channel ) = config.stretch
        {
            #expect( channel.midtones == 0.3 )
        }
        else
        {
            #expect( Bool( false ) )
        }
    }
}
