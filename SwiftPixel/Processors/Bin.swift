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

public extension Processors
{
    /// Bins a single-channel image by an integer factor, treating it as a grid of
    /// 2×2 cells and averaging same-position sites — so a colour-filter-array mosaic
    /// stays phase-aligned and remains a valid, smaller mosaic.
    ///
    /// This runs on the raw mosaic *before* the demosaic (channel-forming) stage, so
    /// the expensive debayer then operates on a `factor²`-smaller mosaic — the point
    /// being to make a heavily downsampled preview cheap without degrading the
    /// debayer (which still does its normal interpolation, just on fewer samples).
    /// Averaging *same-colour* sites is what distinguishes this from a plain box
    /// average (``Resample`` in ``Resample/Mode/average``), which mixes adjacent
    /// colours and so may only run *after* channel-forming.
    ///
    /// Each output sample at within-cell position `(dx, dy)` is the mean of the
    /// `factor × factor` block of input cells' `(dx, dy)` samples. Any trailing
    /// partial cell along an edge is dropped. The stage requires a single-channel
    /// buffer and preserves the normalization flag. The factor must be at least one:
    /// a factor of one is the identity (a no-op), while a factor of zero or less — or
    /// one too large for the image to yield even a single output cell — throws a
    /// ``ValidationError``.
    struct Bin: PixelProcessor
    {
        /// The binning factor: the width/height of the square block of 2×2 cells
        /// combined into one output cell (also the per-axis size reduction). Must be
        /// at least one; one is the identity (no reduction), and values above one
        /// bin. A zero, negative, or too-large factor throws at ``process(buffer:)``.
        public let factor: Int

        /// A human-readable name including the factor.
        public var name: String
        {
            "Bin (\( self.factor )×\( self.factor ))"
        }

        /// Creates a binning stage.
        ///
        /// - Parameter factor: The binning factor. Defaults to one (the identity). A
        ///                     value below one, or too large for the image, throws
        ///                     when the stage runs.
        public init( factor: Int = 1 )
        {
            self.factor = factor
        }

        /// A validation failure for a binning stage's configuration.
        public enum ValidationError: LocalizedError, Equatable, Sendable
        {
            /// The binning factor is not strictly positive.
            case nonPositiveFactor( Int )

            /// The binning factor is larger than the image can bin — it would yield
            /// no output cells.
            case factorTooLarge( factor: Int, width: Int, height: Int )

            /// A human-readable description of the failure.
            public var errorDescription: String?
            {
                switch self
                {
                    case .nonPositiveFactor( let factor ):

                        return "Bin factor must be greater than zero: \( factor )"

                    case .factorTooLarge( let factor, let width, let height ):

                        return "Bin factor \( factor ) is too large for a \( width )×\( height ) image"
                }
            }
        }

        /// The output dimensions after binning by `factor`, in pixels — the cell grid
        /// (`width / 2 × height / 2`) reduced by `factor` and expanded back to pixels,
        /// dropping any partial edge cell.
        ///
        /// - Parameters:
        ///   - width:  The image width in pixels.
        ///   - height: The image height in pixels.
        ///   - factor: The binning factor.
        /// - Returns: The binned width and height.
        public static func outputSize( width: Int, height: Int, factor: Int ) -> ( width: Int, height: Int )
        {
            guard factor > 1
            else
            {
                return ( width, height )
            }

            let outputCellsX = ( width  / 2 ) / factor
            let outputCellsY = ( height / 2 ) / factor

            return ( outputCellsX * 2, outputCellsY * 2 )
        }

        /// Bins the buffer in place, rebuilding its geometry. A no-op when `factor`
        /// is one or less or the buffer is smaller than one output cell.
        ///
        /// - Parameter buffer: The single-channel buffer to bin.
        ///
        /// - Throws: A `PixelBufferError` if the buffer is not single-channel, or a
        ///           ``ValidationError`` if the factor is not strictly positive or is
        ///           too large for the image.
        public func process( buffer: inout PixelBuffer ) throws
        {
            guard buffer.channels == 1
            else
            {
                throw PixelBufferError.unsupportedChannelCount( actual: buffer.channels, supported: [ 1 ] )
            }

            let factor = self.factor

            guard factor > 0
            else
            {
                throw ValidationError.nonPositiveFactor( factor )
            }

            // A factor of one is the identity: nothing to bin.
            guard factor > 1
            else
            {
                return
            }

            let inputWidth   = buffer.width
            let inputHeight  = buffer.height
            let outputCellsX = ( inputWidth  / 2 ) / factor
            let outputCellsY = ( inputHeight / 2 ) / factor

            guard outputCellsX > 0, outputCellsY > 0
            else
            {
                throw ValidationError.factorTooLarge( factor: factor, width: inputWidth, height: inputHeight )
            }

            let outputWidth  = outputCellsX * 2
            let outputHeight = outputCellsY * 2
            let source       = buffer.pixels
            let count        = Double( factor * factor )

            var result = [ Double ]( repeating: 0.0, count: outputWidth * outputHeight )

            source.withUnsafeBufferPointer
            {
                sourcePointer in

                result.withUnsafeMutableBufferPointer
                {
                    resultPointer in

                    nonisolated( unsafe ) let sourceBuffer = sourcePointer
                    nonisolated( unsafe ) let resultBuffer = resultPointer

                    // One iteration per output cell row, writing only its own two
                    // output rows so parallel iterations never overlap. For each of
                    // the two cell rows, sum its `factor` source rows — spaced two
                    // apart, to stay on one colour parity — with vDSP (the dominant
                    // pass over the mosaic), then horizontally sum the `factor`
                    // same-colour columns (also spaced two apart) and divide.
                    PixelUtilities.parallelOrSerial( iterations: outputCellsY )
                    {
                        outputCellY in

                        guard let sourceBase = sourceBuffer.baseAddress,
                              let resultBase = resultBuffer.baseAddress
                        else
                        {
                            return
                        }

                        var rowSum = [ Double ]( repeating: 0.0, count: inputWidth )

                        rowSum.withUnsafeMutableBufferPointer
                        {
                            rowSumPointer in

                            guard let rowSumBase = rowSumPointer.baseAddress
                            else
                            {
                                return
                            }

                            for dy in 0 ..< 2
                            {
                                let firstRow = ( outputCellY * factor ) * 2 + dy

                                rowSumBase.update( from: sourceBase + firstRow * inputWidth, count: inputWidth )

                                for blockY in 1 ..< factor
                                {
                                    let inputRow = ( outputCellY * factor + blockY ) * 2 + dy

                                    vDSP_vaddD( rowSumBase, 1, sourceBase + inputRow * inputWidth, 1, rowSumBase, 1, vDSP_Length( inputWidth ) )
                                }

                                let outputY = outputCellY * 2 + dy

                                for outputCellX in 0 ..< outputCellsX
                                {
                                    for dx in 0 ..< 2
                                    {
                                        var sum = 0.0

                                        for blockX in 0 ..< factor
                                        {
                                            sum += rowSumBase[ ( outputCellX * factor + blockX ) * 2 + dx ]
                                        }

                                        resultBase[ outputY * outputWidth + ( outputCellX * 2 + dx ) ] = sum / count
                                    }
                                }
                            }
                        }
                    }
                }
            }

            buffer = try PixelBuffer( width: outputWidth, height: outputHeight, channels: 1, pixels: result, isNormalized: buffer.isNormalized )
        }
    }
}
