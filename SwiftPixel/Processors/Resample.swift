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
    /// Downsamples a buffer to fit within a maximum dimension, by a single integer
    /// factor on both axes (so the aspect ratio is preserved to within rounding).
    /// The factor is the smallest that brings the larger side to at most
    /// `maxDimension`; when the buffer already fits, the stage is a no-op.
    ///
    /// The ``Mode`` selects the anti-aliasing filter — the two ends of the classic
    /// trade-off:
    ///
    /// - ``Mode/average`` box-averages each `factor × factor` block into one sample.
    ///   It produces a smooth, downscaled *image*, and must run on co-located
    ///   channels — after the channel-forming stage, never on a raw colour-filter-
    ///   array mosaic, where averaging neighbouring sites would blend colours.
    /// - ``Mode/nearest(blockSize:)`` decimates: it keeps whole `blockSize × blockSize`
    ///   cells and discards the rest, leaving the survivors unchanged. It preserves
    ///   the value *distribution* (so statistics such as the median and MAD are not
    ///   biased the way averaging biases them), and a `blockSize` of `2` keeps whole
    ///   2×2 cells so a Bayer mosaic stays phase-aligned.
    ///
    /// Values are combined (or copied) linearly and the normalization flag is
    /// preserved, so the stage can sit before or after normalization.
    struct Resample: PixelProcessor
    {
        /// The anti-aliasing filter used while downsampling.
        public enum Mode: Sendable, Equatable
        {
            /// Box-average each `factor × factor` block — a smooth downscaled image.
            /// Requires co-located channels (never a raw mosaic).
            case average

            /// Decimate, keeping whole `blockSize × blockSize` cells and discarding
            /// the rest. `blockSize` `1` is a per-sample nearest decimation of a
            /// co-located buffer; `2` keeps whole 2×2 cells, preserving a Bayer
            /// mosaic's colour phase.
            case nearest( blockSize: Int )
        }

        /// The largest dimension (width or height, in samples) the output may take.
        /// A value of zero or less disables the stage.
        public let maxDimension: Int

        /// The anti-aliasing filter used while downsampling.
        public let mode: Mode

        /// A human-readable name including the target maximum dimension and mode.
        public var name: String
        {
            switch self.mode
            {
                case .average:                  return "Resample (max \( self.maxDimension ) px, average)"
                case .nearest( let blockSize ): return "Resample (max \( self.maxDimension ) px, nearest \( blockSize )×\( blockSize ))"
            }
        }

        /// Creates a resample stage.
        ///
        /// - Parameters:
        ///   - maxDimension: The largest dimension the output may take. A value of
        ///                   zero or less makes the stage a no-op.
        ///   - mode:         The anti-aliasing filter. Defaults to ``Mode/average``.
        public init( maxDimension: Int, mode: Mode = .average )
        {
            self.maxDimension = maxDimension
            self.mode         = mode
        }

        /// The integer downsampling factor for an image of the given size, so the
        /// larger side ends up at most `maxDimension`.
        ///
        /// Returns `1` (no downsampling) when `maxDimension` is not positive or the
        /// image already fits; otherwise the smallest factor `f` such that
        /// `ceil( maxSide / f ) <= maxDimension`.
        ///
        /// - Parameters:
        ///   - width:        The image width in pixels.
        ///   - height:       The image height in pixels.
        ///   - maxDimension: The largest dimension the output may take.
        /// - Returns: The downsampling factor (at least `1`).
        public static func factor( width: Int, height: Int, maxDimension: Int ) -> Int
        {
            let maxSide = Swift.max( width, height )

            guard maxDimension > 0, maxSide > maxDimension
            else
            {
                return 1
            }

            return ( maxSide + maxDimension - 1 ) / maxDimension
        }

        /// The output dimensions after box-averaging by `factor` (each axis rounded
        /// up so no edge samples are dropped, and never below `1`).
        ///
        /// - Parameters:
        ///   - width:  The image width in pixels.
        ///   - height: The image height in pixels.
        ///   - factor: The downsampling factor.
        /// - Returns: The downsampled width and height.
        public static func outputSize( width: Int, height: Int, factor: Int ) -> ( width: Int, height: Int )
        {
            guard factor > 1
            else
            {
                return ( width, height )
            }

            let outputWidth  = Swift.max( 1, ( width  + factor - 1 ) / factor )
            let outputHeight = Swift.max( 1, ( height + factor - 1 ) / factor )

            return ( outputWidth, outputHeight )
        }

        /// Downsamples the buffer in place per the configured ``mode``, rebuilding
        /// its geometry. A no-op when the buffer already fits within `maxDimension`.
        ///
        /// - Parameter buffer: The buffer to downsample.
        ///
        /// - Throws: A `PixelBufferError` if the downsampled geometry is inconsistent.
        public func process( buffer: inout PixelBuffer ) throws
        {
            switch self.mode
            {
                case .average:

                    try self.averaged( buffer: &buffer )

                case .nearest( let blockSize ):

                    try self.decimated( buffer: &buffer, blockSize: blockSize )
            }
        }

        /// Box-averages the buffer in place: each output sample is the mean of the
        /// `factor × factor` input block it covers.
        ///
        /// The box average is separable, so each output row is produced in two steps:
        /// its `factor` input rows are summed with `vDSP_vaddD` — the dominant,
        /// `O(sampleCount)` pass over the source, run vectorized like the codebase's
        /// other per-sample processors (e.g. ``Scale``) — then the resulting row is
        /// horizontally box-summed and divided by each block's sample count. The
        /// horizontal step touches only the already-reduced row (`factor×` fewer
        /// samples), so it stays a simple scalar pass that also handles the partial
        /// edge blocks. Output rows are processed in parallel; each reads only its
        /// own input rows and writes only its own output row.
        ///
        /// - Parameter buffer: The buffer to downsample.
        ///
        /// - Throws: A `PixelBufferError` if the downsampled geometry is inconsistent.
        private func averaged( buffer: inout PixelBuffer ) throws
        {
            let factor = Self.factor( width: buffer.width, height: buffer.height, maxDimension: self.maxDimension )

            guard factor > 1
            else
            {
                return
            }

            let inputWidth  = buffer.width
            let inputHeight = buffer.height
            let channels    = buffer.channels
            let output      = Self.outputSize( width: inputWidth, height: inputHeight, factor: factor )
            let rowLength   = inputWidth * channels
            let source      = buffer.pixels

            var result = [ Double ]( repeating: 0.0, count: output.width * output.height * channels )

            source.withUnsafeBufferPointer
            {
                sourcePointer in

                result.withUnsafeMutableBufferPointer
                {
                    resultPointer in

                    nonisolated( unsafe ) let sourceBuffer = sourcePointer
                    nonisolated( unsafe ) let resultBuffer = resultPointer

                    PixelUtilities.parallelOrSerial( iterations: output.height )
                    {
                        outputY in

                        guard let sourceBase = sourceBuffer.baseAddress,
                              let resultBase = resultBuffer.baseAddress
                        else
                        {
                            return
                        }

                        let startY         = outputY * factor
                        let endY           = Swift.min( startY + factor, inputHeight )
                        let rowBlockHeight = endY - startY
                        let outputRowBase  = outputY * output.width * channels

                        // Vertical pass: sum this output row's `factor` input rows into
                        // a single row buffer with vDSP — the pass that reads every
                        // source sample.
                        var rowSum = [ Double ]( repeating: 0.0, count: rowLength )

                        rowSum.withUnsafeMutableBufferPointer
                        {
                            rowSumPointer in

                            guard let rowSumBase = rowSumPointer.baseAddress
                            else
                            {
                                return
                            }

                            rowSumBase.update( from: sourceBase + startY * rowLength, count: rowLength )

                            for inputY in ( startY + 1 ) ..< endY
                            {
                                vDSP_vaddD( rowSumBase, 1, sourceBase + inputY * rowLength, 1, rowSumBase, 1, vDSP_Length( rowLength ) )
                            }

                            // Horizontal pass: box-sum each `factor`-wide group of
                            // columns (per channel) on the reduced row and divide by
                            // the block's sample count, handling partial edge blocks.
                            for outputX in 0 ..< output.width
                            {
                                let startX     = outputX * factor
                                let endX       = Swift.min( startX + factor, inputWidth )
                                let count      = Double( ( endX - startX ) * rowBlockHeight )
                                let outputBase = outputRowBase + outputX * channels

                                for channel in 0 ..< channels
                                {
                                    var sum = 0.0

                                    for inputX in startX ..< endX
                                    {
                                        sum += rowSumBase[ inputX * channels + channel ]
                                    }

                                    resultBase[ outputBase + channel ] = sum / count
                                }
                            }
                        }
                    }
                }
            }

            buffer = try PixelBuffer( width: output.width, height: output.height, channels: channels, pixels: result, isNormalized: buffer.isNormalized )
        }

        /// Decimates the buffer in place, keeping every `factor`-th `blockSize ×
        /// blockSize` cell intact and discarding the rest. Any trailing partial cell
        /// along an edge is dropped; a no-op when the buffer already fits, when
        /// `blockSize` is not positive, or when the buffer is smaller than one cell.
        ///
        /// - Parameters:
        ///   - buffer:    The buffer to downsample.
        ///   - blockSize: The size of the square cell kept intact (`1` per sample,
        ///                `2` to preserve a Bayer mosaic's phase).
        ///
        /// - Throws: A `PixelBufferError` if the downsampled geometry is inconsistent.
        private func decimated( buffer: inout PixelBuffer, blockSize: Int ) throws
        {
            let factor = Self.factor( width: buffer.width, height: buffer.height, maxDimension: self.maxDimension )
            let cellsX = blockSize > 0 ? buffer.width  / blockSize : 0
            let cellsY = blockSize > 0 ? buffer.height / blockSize : 0

            guard factor > 1, cellsX > 0, cellsY > 0
            else
            {
                return
            }

            let outputCellsX = ( cellsX + factor - 1 ) / factor
            let outputCellsY = ( cellsY + factor - 1 ) / factor
            let channels     = buffer.channels
            let inputWidth   = buffer.width
            let source       = buffer.pixels

            // For each retained output cell, copy its whole `blockSize × blockSize`
            // block from the source. Within a source row the block's samples are
            // contiguous (`blockSize * channels` doubles), so the survivors keep
            // their exact values and their position within the cell — which is what
            // preserves a mosaic's colour phase.
            let pixels = ( 0 ..< outputCellsY ).flatMap
            {
                outputCellY -> [ Double ] in

                let sourceCellY = Swift.min( outputCellY * factor, cellsY - 1 )

                return ( 0 ..< blockSize ).flatMap
                {
                    rowInCell -> [ Double ] in

                    let sourceY = sourceCellY * blockSize + rowInCell

                    return ( 0 ..< outputCellsX ).flatMap
                    {
                        outputCellX -> [ Double ] in

                        let sourceX = Swift.min( outputCellX * factor, cellsX - 1 ) * blockSize
                        let base    = ( sourceY * inputWidth + sourceX ) * channels

                        return ( 0 ..< blockSize * channels ).map { source[ base + $0 ] }
                    }
                }
            }

            buffer = try PixelBuffer( width: outputCellsX * blockSize, height: outputCellsY * blockSize, channels: channels, pixels: pixels, isNormalized: buffer.isNormalized )
        }
    }
}
