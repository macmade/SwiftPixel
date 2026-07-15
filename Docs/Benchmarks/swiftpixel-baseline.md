# SwiftPixel — Benchmark baseline

| Field | Value |
| --- | --- |
| Captured | 2026-07-15T19:24:10Z |
| Host | Mac16,12 |
| OS | Version 26.5.1 (Build 25F80) |
| Configuration | release |
| Iterations | 20 |
| Measurements | 29 |

Timings are wall-clock per iteration; **min** is the least noisy estimate of intrinsic cost. Peak allocation is an approximate, best-effort figure (see the harness README).

| Category | Algorithm | Frame | Min | Median | Max | Peak alloc. |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Primitive | Convolution.zeroSumResponse | mono-2048 | 86.11 ms | 86.32 ms | 89.32 ms | 64.53 MB |
| Primitive | GaussianFit.fit | mono-512 | 38.88 µs | 39.00 µs | 41.12 µs | 7.22 KB |
| Primitive | GaussianKernel(sigma:) | mono-512 | 750 ns | 792 ns | 1.12 µs | 320 B |
| Primitive | Histogram | mono-2048 | 4.15 ms | 4.17 ms | 4.20 ms | 12.88 KB |
| Primitive | HistogramStatistics | mono-2048 | 541 ns | 583 ns | 625 ns | 384 B |
| Primitive | PixelUtilities.interleave | mono-2048 | 26.17 ms | 26.34 ms | 116.00 ms | 96.02 MB |
| Primitive | PixelUtilities.median | mono-2048 | 243.83 ms | 245.04 ms | 262.18 ms | 32.02 MB |
| Primitive | PixelUtilities.medianAbsoluteDeviation | mono-2048 | 249.65 ms | 250.47 ms | 291.26 ms | 64.03 MB |
| Primitive | PixelUtilities.percentileBounds | mono-2048 | 244.38 ms | 245.26 ms | 268.13 ms | 32.02 MB |
| Primitive | PixelUtilities.readRawPixels | mono-2048 | 171.24 ms | 178.61 ms | 188.84 ms | 32.02 MB |
| Processor | Bin | raw-mono-2048 | 1.82 ms | 1.84 ms | 1.94 ms | 8.04 MB |
| Processor | BrightnessContrast | mono-2048 | 1.91 ms | 2.01 ms | 2.30 ms | 32.02 MB |
| Processor | ColorBalance | rgb-1024 | 48.37 ms | 55.16 ms | 55.41 ms | 32.02 MB |
| Processor | CorrectGamma | mono-2048 | 11.91 ms | 11.96 ms | 12.13 ms | 32.06 MB |
| Processor | CosmeticCorrection | raw-mono-2048 | 204.55 ms | 206.45 ms | 387.77 ms | 32.02 MB |
| Processor | Curves | mono-2048 | 3.55 ms | 3.61 ms | 3.84 ms | 32.04 MB |
| Processor | Debayer (Bilinear) | cfa-2048 | 7.09 ms | 7.45 ms | 81.41 ms | 104.03 MB |
| Processor | Debayer (VNG) | cfa-2048 | 20.85 ms | 23.46 ms | 29.18 ms | 136.05 MB |
| Processor | Hue | rgb-1024 | 54.53 ms | 56.72 ms | 57.31 ms | 32.02 MB |
| Processor | Invert | mono-2048 | 1.31 ms | 1.38 ms | 1.49 ms | 32.02 MB |
| Processor | Levels | mono-2048 | 14.30 ms | 14.43 ms | 14.78 ms | 32.02 MB |
| Processor | MonoToRGB | raw-mono-2048 | 168.71 ms | 196.07 ms | 200.61 ms | 96.02 MB |
| Processor | Normalize | raw-mono-2048 | 3.01 ms | 3.04 ms | 3.21 ms | 32.02 MB |
| Processor | Orient | mono-2048 | 177.79 ms | 186.32 ms | 195.30 ms | 32.02 MB |
| Processor | Resample | mono-2048 | 1.47 ms | 1.47 ms | 1.53 ms | 2.04 MB |
| Processor | Saturation | rgb-1024 | 50.93 ms | 52.82 ms | 54.41 ms | 32.02 MB |
| Processor | Scale | raw-mono-2048 | 1.89 ms | 1.92 ms | 2.06 ms | 32.02 MB |
| Processor | Stretch | mono-2048 | 6.04 ms | 6.30 ms | 9.79 ms | 64.03 MB |
| Processor | WhiteBalance | rgb-1024 | 3.38 ms | 3.45 ms | 5.53 ms | 32.02 MB |
