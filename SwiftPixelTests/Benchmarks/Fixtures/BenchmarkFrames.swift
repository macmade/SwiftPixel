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

/// The representative set of synthetic input frames the SwiftPixel harness runs
/// over.
///
/// SwiftPixel ships no fixture images — its tests build buffers inline — so the
/// harness synthesizes its own frames deterministically. Each frame's content is
/// a reproducible gradient-plus-noise pattern (never a constant, which would let
/// vectorized code take shortcuts that misrepresent real work), so two builds
/// produce byte-identical inputs and therefore comparable timings.
enum BenchmarkFrames
{
    /// A normalized sample in `[0, 1]` for the interleaved index `i`.
    ///
    /// The value mixes a low-frequency positional ramp with a deterministic
    /// high-frequency term so the data is neither constant nor trivially
    /// compressible.
    static func normalizedSample( _ i: Int ) -> Double
    {
        let noise = Double( ( i &* 1_103_515_245 &+ 12_345 ) & 0xFFFF ) / 65_535.0
        let ramp  = Double( i & 0x3FF ) / 1_023.0

        return ( ( 0.75 * ramp ) + ( 0.25 * noise ) ).clamped()
    }

    /// A raw, unnormalized sample in the 16-bit ADU range `[0, 65535]` for the
    /// interleaved index `i` — the domain of freshly decoded FITS data.
    static func rawSample( _ i: Int ) -> Double
    {
        ( self.normalizedSample( i ) * 65_535.0 ).rounded()
    }

    /// Builds a single frame with the given geometry and content domain.
    ///
    /// - Parameters:
    ///   - name:       The frame's stable identifier.
    ///   - width:      The frame width in pixels.
    ///   - height:     The frame height in pixels.
    ///   - channels:   The samples per pixel.
    ///   - normalized: Whether the samples are normalized to `[0, 1]` (otherwise
    ///                 they span the 16-bit ADU range).
    ///   - layout:     A human-readable description of the sample layout.
    ///   - notes:      What makes the frame representative.
    /// - Returns: The synthesized frame.
    /// - Throws: A `PixelBufferError` if the geometry is inconsistent.
    static func make( name: String, width: Int, height: Int, channels: Int, normalized: Bool, layout: String, notes: String ) throws -> BenchmarkFrame
    {
        let count  = width * height * channels
        let pixels = ( 0 ..< count ).map { normalized ? self.normalizedSample( $0 ) : self.rawSample( $0 ) }

        let buffer = try PixelBuffer(
            width:        width,
            height:       height,
            channels:     channels,
            pixels:       pixels,
            isNormalized: normalized
        )

        let descriptor = BenchmarkFrameDescriptor(
            name:         name,
            width:        width,
            height:       height,
            channels:     channels,
            layout:       layout,
            isNormalized: normalized,
            notes:        notes
        )

        return BenchmarkFrame( descriptor: descriptor, buffer: buffer )
    }

    // MARK: - Frame sets

    /// The full-size representative set — the sizes the committed baseline is
    /// captured at.
    ///
    /// - Returns: The representative frame set.
    /// - Throws: A `PixelBufferError` if any frame's geometry is inconsistent.
    static func representative() throws -> BenchmarkFrameSet
    {
        try self.set( monoSmall: 512, monoLarge: 2048, rgb: 1024, rawMono: 2048, cfa: 2048 )
    }

    /// A tiny set with the same layouts as ``representative()`` but small
    /// dimensions, so the suite's every case can be exercised in a fraction of a
    /// second — used by the smoke test, never committed.
    ///
    /// - Returns: The tiny frame set.
    /// - Throws: A `PixelBufferError` if any frame's geometry is inconsistent.
    static func tiny() throws -> BenchmarkFrameSet
    {
        try self.set( monoSmall: 16, monoLarge: 64, rgb: 32, rawMono: 64, cfa: 64 )
    }

    /// Builds a frame set from the square edge length of each member. Names are
    /// derived from the layout and edge length (e.g. `"mono-2048"`), so they are
    /// unique and self-documenting across sizes.
    private static func set( monoSmall: Int, monoLarge: Int, rgb: Int, rawMono: Int, cfa: Int ) throws -> BenchmarkFrameSet
    {
        BenchmarkFrameSet(
            monoSmall: try self.make( name: "mono-\( monoSmall )", width: monoSmall, height: monoSmall, channels: 1, normalized: true, layout: "mono", notes: "Synthetic mono gradient + noise in [0, 1]. Small frame for quick primitives and tone/level stages." ),
            monoLarge: try self.make( name: "mono-\( monoLarge )", width: monoLarge, height: monoLarge, channels: 1, normalized: true, layout: "mono", notes: "Synthetic mono gradient + noise in [0, 1]. Large frame that exposes per-pixel scaling." ),
            rgb:       try self.make( name: "rgb-\( rgb )", width: rgb, height: rgb, channels: 3, normalized: true, layout: "rgb", notes: "Synthetic interleaved RGB in [0, 1]. Exercises the colour processors (white balance, hue, saturation, colour balance)." ),
            rawMono:   try self.make( name: "raw-mono-\( rawMono )", width: rawMono, height: rawMono, channels: 1, normalized: false, layout: "mono (raw)", notes: "Synthetic mono in the 16-bit ADU range. Input to stages that operate on unnormalized data (Normalize, Scale, Bin, MonoToRGB)." ),
            cfa:       try self.make( name: "cfa-\( cfa )", width: cfa, height: cfa, channels: 1, normalized: false, layout: "cfa (RGGB mosaic)", notes: "Synthetic single-channel Bayer mosaic in the 16-bit ADU range. Input to the Debayer family." )
        )
    }
}

private extension Double
{
    /// Clamps the value to the `[0, 1]` range.
    func clamped() -> Double
    {
        Swift.min( 1.0, Swift.max( 0.0, self ) )
    }
}
