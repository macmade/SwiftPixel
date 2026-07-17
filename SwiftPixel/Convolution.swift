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
        guard image.channels == 1
        else
        {
            return []
        }

        return self.convolve( image.pixels, width: image.width, height: image.height, kernel: kernel.zeroSumValues, radius: kernel.radius )
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

        let paddedWidth  = width  + ( 2 * radius )
        let paddedHeight = height + ( 2 * radius )

        // Replicate the border pixels into the padding ring so the convolution
        // extends the image rather than reading zeros past its edges.
        let padded = ( 0 ..< ( paddedWidth * paddedHeight ) ).map
        {
            index -> Double in

            let x = Swift.min( Swift.max( ( index % paddedWidth ) - radius, 0 ), width  - 1 )
            let y = Swift.min( Swift.max( ( index / paddedWidth ) - radius, 0 ), height - 1 )

            return values[ ( y * width ) + x ]
        }

        let convolved = vDSP.convolve( padded, rowCount: paddedHeight, columnCount: paddedWidth, withKernel: kernel, kernelRowCount: size, kernelColumnCount: size )

        // Crop the central region back to the original geometry; the padded
        // border, where the kernel reached into the padding, is discarded.
        return ( 0 ..< ( width * height ) ).map
        {
            index in

            let x = index % width
            let y = index / width

            return convolved[ ( ( y + radius ) * paddedWidth ) + ( x + radius ) ]
        }
    }
}
