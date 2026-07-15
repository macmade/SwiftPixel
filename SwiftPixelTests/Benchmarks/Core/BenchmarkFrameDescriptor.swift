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

/// A self-describing record of a benchmark input frame's characteristics.
///
/// It is embedded in every ``BenchmarkMeasurement`` and serialized into the
/// baseline, so the committed results document exactly what each number was
/// measured on — geometry, channel layout, and normalization state — without a
/// reader needing the harness source.
struct BenchmarkFrameDescriptor: Codable, Equatable, Sendable
{
    /// A short, stable identifier for the frame (e.g. `"mono-2048"`), used as the
    /// frame column in reports and to match frames across baselines.
    let name: String

    /// The frame width in pixels.
    let width: Int

    /// The frame height in pixels.
    let height: Int

    /// The number of interleaved samples per pixel.
    let channels: Int

    /// A human-readable description of the sample layout (e.g. `"mono"`,
    /// `"rgb"`, `"cfa (RGGB mosaic)"`).
    let layout: String

    /// Whether the samples are normalized to the `[0, 1]` range.
    let isNormalized: Bool

    /// A note describing how the frame is synthesized or sourced, and what makes
    /// it representative.
    let notes: String

    /// The total number of samples in the frame — `width × height × channels`.
    var sampleCount: Int
    {
        self.width * self.height * self.channels
    }

    /// The number of pixels in the frame — `width × height`.
    var pixelCount: Int
    {
        self.width * self.height
    }
}
