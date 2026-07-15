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

/// The named input frames the SwiftPixel benchmark suite runs over.
///
/// Grouping the frames lets the suite's case wiring stay independent of their
/// sizes: the opt-in capture uses full-size ``BenchmarkFrames/representative()``
/// frames, while the fast smoke test uses ``BenchmarkFrames/tiny()`` frames — the
/// same cases, exercised at a size that runs in a fraction of a second.
struct BenchmarkFrameSet
{
    /// A small normalized single-channel frame.
    let monoSmall: BenchmarkFrame

    /// A large normalized single-channel frame.
    let monoLarge: BenchmarkFrame

    /// A normalized three-channel interleaved frame.
    let rgb: BenchmarkFrame

    /// A raw (unnormalized) single-channel frame.
    let rawMono: BenchmarkFrame

    /// A raw (unnormalized) single-channel Bayer mosaic.
    let cfa: BenchmarkFrame

    /// Every frame in the set, in a stable order.
    var all: [ BenchmarkFrame ]
    {
        [ self.monoSmall, self.monoLarge, self.rgb, self.rawMono, self.cfa ]
    }
}
