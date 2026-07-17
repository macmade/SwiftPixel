SwiftPixel
==========

[![Build Status](https://img.shields.io/github/actions/workflow/status/macmade/SwiftPixel/ci-mac.yaml?label=macOS&logo=apple)](https://github.com/macmade/SwiftPixel/actions/workflows/ci-mac.yaml)
[![Issues](http://img.shields.io/github/issues/macmade/SwiftPixel.svg?logo=github)](https://github.com/macmade/SwiftPixel/issues)
![Status](https://img.shields.io/badge/status-active-brightgreen.svg?logo=git)
![License](https://img.shields.io/badge/license-mit-brightgreen.svg?logo=open-source-initiative)  
[![Contact](https://img.shields.io/badge/follow-@macmade-blue.svg?logo=twitter&style=social)](https://twitter.com/macmade)
[![Sponsor](https://img.shields.io/badge/sponsor-macmade-pink.svg?logo=github-sponsors&style=social)](https://github.com/sponsors/macmade)

### About

Pixel Processing Library for Swift.

SwiftPixel decodes raw, single-channel image samples (following the FITS
`BITPIX` convention) and runs them through a configurable, fixed-order pipeline
of processing stages, producing a normalized `PixelBuffer` that can be rendered
to a `CGImage`.

### Features

- **`PixelPipeline`** — a declarative, config-driven pipeline. You enable the
  stages you want through `PixelPipeline.Config`; the pipeline applies them in a
  fixed order that satisfies each stage's preconditions and inserts a default
  normalization when a normalization-dependent stage needs one. Optional
  per-stage benchmarking is built in.
- **`PixelBuffer`** — a geometrically consistent, channel-interleaved buffer of
  `Double` samples, with `convertTo8Bits()` and `createCGImage()` for output
  (1-channel grayscale, 3-channel RGB or 4-channel RGBA).
- **`BitsPerPixel`** — raw sample formats following the FITS `BITPIX`
  convention: `.uint8`, `.int16`, `.int32`, `.float32`, `.float64`.
- **`Histogram` / `HistogramStatistics`** — per-channel, luminance or mono
  histograms from 8-bit data, plus statistics (mean, median, standard
  deviation, min/max, 1st/99th percentiles).
- **`GaussianKernel` / `Convolution`** — a truncated, normalized 2D Gaussian
  kernel with a zero-sum (high-pass) variant, and an Accelerate-backed (`vDSP`)
  2D convolution over `Double` sample grids. Edge handling extends the image by
  replicating border pixels, and a `zeroSumResponse` helper gives the
  matched-filter response (a Gaussian blur minus a box-mean blur) that peaks on
  blob-like features and vanishes on smooth content.
- **`GaussianFit`** — a least-squares fit of a 2D elliptical Gaussian (amplitude,
  centre, the two axis widths, orientation and background) to `(x, y, value)`
  samples, by Levenberg–Marquardt. Recovers an accurate sub-pixel centre and
  shape for a blob-like feature, and reports `nil` for a non-physical or
  no-better-than-flat fit.
- **Built-in processors** (the `Processors` namespace, all conforming to
  `PixelProcessor`):
  - `Scale` — affine scaling of raw samples.
  - `Debayer` — demosaicing of `BGGR`/`GRBG`/`RGGB`/`GBRG` Bayer patterns,
    `Bilinear` or `VNG`.
  - `MonoToRGB` — expand single-channel data to RGB.
  - `Normalize` — min/max or percentile normalization to `[0, 1]`.
  - `BrightnessContrast` — linear brightness offset and contrast factor.
  - `Levels` — per-channel levels remap.
  - `Curves` — per-channel tone curves.
  - `Stretch` — logarithmic, hyperbolic-sine or sigmoid tone stretching.
  - `CorrectGamma` — gamma correction.
  - `WhiteBalance` — automatic or manual white balance.
  - `Saturation` — luminance-preserving saturation adjustment.
  - `Invert` — photographic-negative inversion.
  - `Orient` — rotation (0°/90°/180°/270°) with optional horizontal mirror.

### Usage

Build a `PixelPipeline.Config` enabling the stages you need, then run it over
your raw sample data. The pipeline applies the stages in a fixed order, so the
declaration order of the configuration does not matter:

```swift
import SwiftPixel

let config = PixelPipeline.Config(
    debayer:      ( pattern: .rggb, mode: .vng ),
    normalize:    .percentile( 0.25, 99.75 ),
    stretch:      .arcsinh( 0.5 ),
    whiteBalance: .auto
)

let pipeline = PixelPipeline( config: config )

// Decode raw, single-channel sample bytes and run the pipeline.
let buffer = try pipeline.run(
    data:         rawData,
    width:        4096,
    height:       4096,
    bitsPerPixel: .int16
)

// The pipeline leaves the buffer normalized, so it can be rendered directly.
let image = try buffer.createCGImage()

// Histograms are built from the buffer's 8-bit samples.
let histogram = Histogram( bytes: try buffer.convertTo8Bits(), channels: buffer.channels, mode: .rgb )
```

### Installation

Add the package to your `Package.swift` dependencies:

```swift
.package( url: "https://github.com/macmade/SwiftPixel.git", branch: "main" )
```

Then add `SwiftPixel` to your target's dependencies. The library can also be
used directly through its Xcode project.

### Cloning

This project uses submodules.  
To clone it, use the following command:

```bash
git clone --recursive https://github.com/macmade/SwiftPixel.git
```

### Benchmarks

The test target includes an opt-in **benchmark & profiling harness** (under
`SwiftPixelTests/Benchmarks/`) that measures the runtime — and approximate peak
memory — of every processor and core primitive over a fixed set of deterministic
synthetic frames (mono, RGB, raw, and RGGB mosaic at a few sizes), and writes a
committed baseline for before/after comparison.

It is **excluded from ordinary test runs** — only the harness's own fast unit
tests run there — and executes only when the `RUN_BENCHMARKS` environment
variable is set. Because `xcodebuild test` does not forward the environment to
the test-host process, capture a baseline through SwiftPM, in an optimized build:

```bash
RUN_BENCHMARKS=1 swift test -c release --filter Test_SwiftPixelBenchmarks
```

Two files are written to `Docs/Benchmarks/` (override the directory with the
`FITSCOPE_BENCH_OUT` environment variable): `swiftpixel-baseline.json` — the
machine-diffable source of truth — and `swiftpixel-baseline.md` — a
human-readable table generated from it. Each measurement records min / median /
max wall-clock timing (the **min** is the least noisy estimate of intrinsic cost)
and a best-effort, approximate peak allocation. A baseline is a snapshot, not a
target: real timings vary between runs, so compare like for like — same host,
same Release build.

License
-------

Project is released under the terms of the MIT License.

Repository Infos
----------------

    Owner:          Jean-David Gadina - XS-Labs
    Web:            www.xs-labs.com
    Blog:           www.noxeos.com
    Twitter:        @macmade
    GitHub:         github.com/macmade
    LinkedIn:       ch.linkedin.com/in/macmade/
    StackOverflow:  stackoverflow.com/users/182676/macmade
