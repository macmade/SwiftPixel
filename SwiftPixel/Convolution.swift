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

import Accelerate
import Foundation

/// Accelerate-backed 2D convolution over `Double` sample grids.
///
/// The heavy pixel math runs on `vDSP`, with edge handling controlled here rather
/// than left to the framework: the input is padded by replicating its border
/// pixels, convolved, and cropped back to its original size. This gives a
/// well-defined edge-extension behaviour, so a flat region yields a clean
/// borderless result instead of edge artifacts.
public enum Convolution
{
    /// The zero-sum (high-pass / matched-filter) response of an image to a
    /// Gaussian kernel.
    ///
    /// Convolving with the kernel's zero-sum weights is, by linearity, exactly a
    /// Gaussian blur minus a box-mean blur over the same footprint: it peaks on
    /// blob-like features at the kernel's scale and vanishes on smooth content.
    ///
    /// - Parameters:
    ///   - image:  The single-channel image whose `pixels` are convolved.
    ///   - kernel: The Gaussian kernel providing the filter scale.
    /// - Returns: The response map, one value per pixel in row-major order (same
    ///   geometry as `image`), or an empty array if `image` is not single-channel.
    public static func zeroSumResponse( of image: PixelBuffer, kernel: GaussianKernel ) -> [ Double ]
    {
        guard image.channels == 1, image.width > 0, image.height > 0
        else
        {
            return []
        }

        let width  = image.width
        let height = image.height
        let size   = kernel.size

        // The separable path drives two degenerate 2D convolutions (a 1×size kernel
        // for the rows, a size×1 kernel for the columns). `vDSP.convolve` requires the
        // *non-convolved* signal dimension of each to clear a small fixed minimum —
        // at least 3 rows for the 1×size pass and 4 columns for the size×1 pass,
        // independent of the kernel size — below which it traps. An image that small
        // is not a real detection frame, and the dense path handles every geometry
        // correctly and negligibly cheaply, so fall back to it (covered by
        // `zeroSumResponseHandlesSmallImagesWithoutTrapping`).
        guard width >= 4, height >= 3
        else
        {
            return self.convolve( image.pixels, width: width, height: height, kernel: kernel.zeroSumValues, radius: kernel.radius )
        }

        // The zero-sum Gaussian kernel is `Gaussian − mean`, so by linearity its
        // response is a Gaussian blur minus a box-mean over the same footprint. Both
        // are separable — the 2D Gaussian `values` factor as the outer product of
        // `kernel.separableValues`, and the box factors into a 1D mean — so the
        // response is built from 1D passes along each axis instead of one dense 2D
        // convolution: `O(width·height·size)` rather than `O(width·height·size²)`. It
        // reproduces `convolve(_:kernel: kernel.zeroSumValues, …)` to floating-point
        // rounding, which `zeroSumResponseMatchesADenseConvolution` guards.
        let blur   = self.separableConvolveReplicating( image.pixels, width: width, height: height, kernel1D: kernel.separableValues, radius: kernel.radius )
        let boxSum = self.separableConvolveReplicating( image.pixels, width: width, height: height, kernel1D: [ Double ]( repeating: 1, count: size ), radius: kernel.radius )

        var response = [ Double ]( repeating: 0, count: width * height )

        // response = blur − boxSum / size²: the box-mean subtracts the constant the
        // zero-sum kernel removes, so a flat region maps to zero.
        vDSP.multiply( 1 / Double( size * size ), boxSum, result: &response )
        vDSP.subtract( blur, response, result: &response )

        return response
    }

    /// Convolves a row-major sample grid with a square, centred kernel, extending
    /// the image at its borders by replicating edge pixels.
    ///
    /// The kernel is symmetric in every Gaussian use here (Gaussian, zero-sum
    /// Gaussian, box), so convolution and correlation coincide and the kernel is
    /// applied as-is.
    ///
    /// - Parameters:
    ///   - values: The samples, in row-major order.
    ///   - width:  The grid width, in pixels.
    ///   - height: The grid height, in pixels.
    ///   - kernel: The kernel weights, row-major, of length `(2·radius + 1)²`.
    ///   - radius: The kernel radius, in pixels.
    /// - Returns: The convolved samples, same length and geometry as `values`; an
    ///   empty array for a degenerate grid (non-positive `width`/`height`, or
    ///   negative `radius`) or a precondition violation (`values.count` not
    ///   `width·height`, or `kernel.count` not `(2·radius + 1)²`).
    public static func convolve( _ values: [ Double ], width: Int, height: Int, kernel: [ Double ], radius: Int ) -> [ Double ]
    {
        guard width > 0, height > 0, radius >= 0
        else
        {
            return []
        }

        let size = ( 2 * radius ) + 1

        // Validate the caller's preconditions rather than trusting them: a short
        // `values` array would trap on an out-of-bounds read, and a wrong-sized
        // kernel would make vDSP.convolve over-read. A violated precondition
        // returns [], matching the degenerate-grid result.
        guard values.count == width * height, kernel.count == size * size
        else
        {
            return []
        }

        // `vDSP.convolve` requires the padded signal to clear a small fixed minimum —
        // at least 3 rows and 4 columns, independent of the kernel — or it traps: a
        // 1-pixel-wide image with a radius-1 kernel (padded width 3) would otherwise
        // abort. Pad each axis by the kernel radius (for the replicated border) and by
        // enough more to reach that minimum. Extra replicated padding does not change
        // the cropped central block — a border pixel replicates the same edge value
        // however wide the ring — so the result is identical for every larger image.
        let padX = Swift.max( radius, ( 4 - width  + 1 ) / 2 )
        let padY = Swift.max( radius, ( 3 - height + 1 ) / 2 )

        let paddedWidth  = width  + ( 2 * padX )
        let paddedHeight = height + ( 2 * padY )

        // Replicate the border pixels into the padding ring so the convolution
        // extends the image rather than reading zeros past its edges.
        let padded = ( 0 ..< ( paddedWidth * paddedHeight ) ).map
        {
            index -> Double in

            let x = Swift.min( Swift.max( ( index % paddedWidth ) - padX, 0 ), width  - 1 )
            let y = Swift.min( Swift.max( ( index / paddedWidth ) - padY, 0 ), height - 1 )

            return values[ ( y * width ) + x ]
        }

        let convolved = vDSP.convolve( padded, rowCount: paddedHeight, columnCount: paddedWidth, withKernel: kernel, kernelRowCount: size, kernelColumnCount: size )

        // Crop the central width×height block back out at offset (padX, padY). The
        // kernel overhangs the padded edge by its radius, so the valid, fully-
        // overlapped result sits in the central block — the ring replicated above.
        // Were that convention ever to shift, the edge and corner samples would stop
        // matching a replicated-border filter; `convolveExtendsBordersByReplication`
        // guards it.
        return ( 0 ..< ( width * height ) ).map
        {
            index in

            let x = index % width
            let y = index / width

            return convolved[ ( ( y + padY ) * paddedWidth ) + ( x + padX ) ]
        }
    }

    /// Convolves a row-major grid with a 1D kernel applied separably along both
    /// axes — horizontally, then vertically — extending the grid at its borders by
    /// replicating edge pixels, the same convention as
    /// ``convolve(_:width:height:kernel:radius:)``.
    ///
    /// For a separable 2D kernel `k ⊗ k`, this yields the same result as a full 2D
    /// convolution with that kernel (to floating-point rounding) at
    /// `O(width·height·kernel.count)` cost instead of `O(width·height·kernel.count²)`.
    /// Edge replication commutes with the separable decomposition — clamping the
    /// column index in the horizontal pass and then the row index in the vertical
    /// pass reproduces the 2D replicated-border result — so a border pixel is
    /// extended identically to the dense path.
    ///
    /// Each pass runs as a degenerate 2D `vDSP.convolve`: a `1×size` kernel for the
    /// rows and a `size×1` kernel for the columns, so neither pass mixes samples
    /// across the orthogonal axis.
    ///
    /// - Parameters:
    ///   - values:   The samples, in row-major order (`width·height` of them).
    ///   - width:    The grid width, in pixels.
    ///   - height:   The grid height, in pixels.
    ///   - kernel1D: The 1D kernel weights, of length `2·radius + 1`.
    ///   - radius:   The kernel radius, in pixels.
    /// - Returns: The convolved samples, same length and geometry as `values`.
    private static func separableConvolveReplicating( _ values: [ Double ], width: Int, height: Int, kernel1D: [ Double ], radius: Int ) -> [ Double ]
    {
        let size         = kernel1D.count
        let paddedWidth  = width  + ( 2 * radius )
        let paddedHeight = height + ( 2 * radius )

        // Horizontal pass: replicate each row's end pixels into a `radius`-wide ring,
        // convolve every row with the 1D kernel (a 1×size kernel touches no other
        // row), and crop the valid central columns back to `width`.
        let paddedRows = ( 0 ..< ( paddedWidth * height ) ).map
        {
            index -> Double in

            let x = Swift.min( Swift.max( ( index % paddedWidth ) - radius, 0 ), width - 1 )
            let y = index / paddedWidth

            return values[ ( y * width ) + x ]
        }

        let rowConvolved = vDSP.convolve( paddedRows, rowCount: height, columnCount: paddedWidth, withKernel: kernel1D, kernelRowCount: 1, kernelColumnCount: size )

        let horizontal = ( 0 ..< ( width * height ) ).map
        {
            index -> Double in

            let x = index % width
            let y = index / width

            return rowConvolved[ ( y * paddedWidth ) + ( x + radius ) ]
        }

        // Vertical pass: replicate each column's end pixels, convolve every column
        // (a size×1 kernel touches no other column), and crop the valid central rows.
        let paddedColumns = ( 0 ..< ( width * paddedHeight ) ).map
        {
            index -> Double in

            let x = index % width
            let y = Swift.min( Swift.max( ( index / width ) - radius, 0 ), height - 1 )

            return horizontal[ ( y * width ) + x ]
        }

        let columnConvolved = vDSP.convolve( paddedColumns, rowCount: paddedHeight, columnCount: width, withKernel: kernel1D, kernelRowCount: size, kernelColumnCount: 1 )

        return ( 0 ..< ( width * height ) ).map
        {
            index -> Double in

            let x = index % width
            let y = index / width

            return columnConvolved[ ( ( y + radius ) * width ) + x ]
        }
    }
}
