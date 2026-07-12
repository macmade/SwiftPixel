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

public extension Processors
{
    /// Reorients a buffer by a quarter-turn rotation and an optional horizontal
    /// mirror, rebuilding the geometry (a 90°/270° rotation swaps width and
    /// height).
    ///
    /// The transform is a pure permutation of the samples: values are unchanged,
    /// channels stay grouped, and the normalization flag is preserved. It works
    /// on a normalized or a raw buffer alike, so it can sit anywhere in a
    /// pipeline.
    struct Orient: PixelProcessor
    {
        /// A quarter-turn rotation, measured clockwise.
        public enum Rotation: Int, Sendable, Equatable, CustomStringConvertible, CaseIterable
        {
            /// No rotation.
            case none = 0

            /// A 90° clockwise rotation.
            case clockwise90 = 1

            /// A 180° rotation.
            case rotate180 = 2

            /// A 90° counter-clockwise rotation (270° clockwise).
            case counterClockwise90 = 3

            /// The number of clockwise quarter-turns this rotation represents
            /// (`0...3`).
            var quarterTurns: Int
            {
                self.rawValue
            }

            /// Builds a rotation from a clockwise quarter-turn count, taken
            /// modulo four.
            ///
            /// - Parameter quarterTurns: The number of clockwise quarter-turns.
            init( quarterTurns: Int )
            {
                self = Rotation( rawValue: ( ( quarterTurns % 4 ) + 4 ) % 4 ) ?? .none
            }

            /// A human-readable description of the rotation.
            public var description: String
            {
                switch self
                {
                    case .none:               return "0°"
                    case .clockwise90:        return "90° CW"
                    case .rotate180:          return "180°"
                    case .counterClockwise90: return "90° CCW"
                }
            }
        }

        /// A net image orientation: a quarter-turn rotation combined with an
        /// optional horizontal mirror.
        ///
        /// The mirror is applied first, then the rotation, so the eight possible
        /// values cover the whole dihedral group of square-preserving symmetries
        /// (every combination of 90° rotations and flips). The mutating
        /// operations (`rotatedClockwise()`, `flippedHorizontally()`, …) compose
        /// *screen-relative*: they transform the image as it is currently shown,
        /// matching how a user expects rotate/flip buttons to behave on an
        /// already-reoriented image.
        public struct Orientation: Sendable, Equatable, CustomStringConvertible
        {
            /// The quarter-turn rotation, applied after the mirror.
            public var rotation: Rotation

            /// Whether the image is mirrored left-to-right (across its vertical
            /// axis), applied before the rotation.
            public var mirroredHorizontally: Bool

            /// The unrotated, unmirrored orientation.
            public static let identity = Orientation( rotation: .none, mirroredHorizontally: false )

            /// Creates an orientation.
            ///
            /// - Parameters:
            ///   - rotation:             The quarter-turn rotation, applied after the mirror.
            ///   - mirroredHorizontally: Whether to mirror the image horizontally first.
            public init( rotation: Rotation = .none, mirroredHorizontally: Bool = false )
            {
                self.rotation             = rotation
                self.mirroredHorizontally = mirroredHorizontally
            }

            /// Whether this orientation leaves an image unchanged.
            public var isIdentity: Bool
            {
                self.rotation == .none && self.mirroredHorizontally == false
            }

            /// The orientation rotated a further 90° clockwise, as seen on screen.
            public func rotatedClockwise() -> Orientation
            {
                Orientation( rotation: Rotation( quarterTurns: self.rotation.quarterTurns + 1 ), mirroredHorizontally: self.mirroredHorizontally )
            }

            /// The orientation rotated a further 90° counter-clockwise, as seen on
            /// screen.
            public func rotatedCounterClockwise() -> Orientation
            {
                Orientation( rotation: Rotation( quarterTurns: self.rotation.quarterTurns - 1 ), mirroredHorizontally: self.mirroredHorizontally )
            }

            /// The orientation flipped left-to-right, as seen on screen.
            ///
            /// Composing a horizontal screen-flip onto an existing rotation also
            /// negates the rotation, because mirroring reverses the sense in which
            /// a subsequent turn reads — this keeps the flip acting on what the
            /// user sees rather than on the original image.
            public func flippedHorizontally() -> Orientation
            {
                Orientation( rotation: Rotation( quarterTurns: -self.rotation.quarterTurns ), mirroredHorizontally: self.mirroredHorizontally == false )
            }

            /// The orientation flipped top-to-bottom, as seen on screen.
            ///
            /// A vertical screen-flip is a horizontal mirror combined with a 180°
            /// turn; like `flippedHorizontally()` it composes in screen space.
            public func flippedVertically() -> Orientation
            {
                Orientation( rotation: Rotation( quarterTurns: 2 - self.rotation.quarterTurns ), mirroredHorizontally: self.mirroredHorizontally == false )
            }

            /// The output dimensions an image of the given source size takes once
            /// this orientation is applied (a quarter-turn swaps width and
            /// height).
            ///
            /// - Parameters:
            ///   - sourceWidth:  The source image width.
            ///   - sourceHeight: The source image height.
            /// - Returns: The reoriented width and height.
            public func outputSize( sourceWidth: Int, sourceHeight: Int ) -> ( width: Int, height: Int )
            {
                self.rotation.quarterTurns % 2 == 0 ? ( sourceWidth, sourceHeight ) : ( sourceHeight, sourceWidth )
            }

            /// Maps a coordinate in the reoriented (displayed) image back to the
            /// corresponding coordinate in the source image.
            ///
            /// This is the exact inverse of the pixel transform, so a value read
            /// at a display coordinate comes from the matching source sample —
            /// used to keep the cursor read-out correct after a rotation or flip.
            ///
            /// - Parameters:
            ///   - displayX:     The column in the reoriented image.
            ///   - displayY:     The row in the reoriented image.
            ///   - sourceWidth:  The source image width.
            ///   - sourceHeight: The source image height.
            /// - Returns: The source `(x, y)` coordinate.
            public func sourceCoordinate( displayX: Int, displayY: Int, sourceWidth: Int, sourceHeight: Int ) -> ( x: Int, y: Int )
            {
                let display = self.outputSize( sourceWidth: sourceWidth, sourceHeight: sourceHeight )

                return self.inverse.map( x: displayX, y: displayY, inputWidth: display.width, inputHeight: display.height )
            }

            /// The orientation that undoes this one.
            ///
            /// A mirrored orientation is its own inverse (a reflection is an
            /// involution); otherwise the inverse is the opposite rotation.
            var inverse: Orientation
            {
                if self.mirroredHorizontally
                {
                    return self
                }

                return Orientation( rotation: Rotation( quarterTurns: -self.rotation.quarterTurns ), mirroredHorizontally: false )
            }

            /// Maps a source coordinate to its position after this orientation is
            /// applied to an `inputWidth × inputHeight` image (the mirror first,
            /// then the rotation).
            ///
            /// - Parameters:
            ///   - x:           The source column.
            ///   - y:           The source row.
            ///   - inputWidth:  The width of the image the coordinate belongs to.
            ///   - inputHeight: The height of the image the coordinate belongs to.
            /// - Returns: The mapped `(x, y)` coordinate.
            func map( x: Int, y: Int, inputWidth: Int, inputHeight: Int ) -> ( x: Int, y: Int )
            {
                let mx = self.mirroredHorizontally ? inputWidth - 1 - x : x
                let my = y

                switch self.rotation
                {
                    case .none:               return ( mx, my )
                    case .clockwise90:        return ( inputHeight - 1 - my, mx )
                    case .rotate180:          return ( inputWidth - 1 - mx, inputHeight - 1 - my )
                    case .counterClockwise90: return ( my, inputWidth - 1 - mx )
                }
            }

            /// A human-readable description of the orientation.
            public var description: String
            {
                self.mirroredHorizontally ? "\( self.rotation ) mirrored" : "\( self.rotation )"
            }
        }

        /// The net orientation to apply.
        public let orientation: Orientation

        /// Creates an orientation stage.
        ///
        /// - Parameter orientation: The net orientation to apply.
        public init( orientation: Orientation )
        {
            self.orientation = orientation
        }

        /// A human-readable name including the orientation.
        public var name: String
        {
            "Orient (\( self.orientation ))"
        }

        /// Reorients the buffer in place, rebuilding its geometry.
        ///
        /// - Parameter buffer: The buffer to reorient.
        ///
        /// - Throws: A `PixelBufferError` if the reoriented geometry is inconsistent.
        public func process( buffer: inout PixelBuffer ) throws
        {
            guard self.orientation.isIdentity == false
            else
            {
                return
            }

            let inputWidth  = buffer.width
            let inputHeight = buffer.height
            let channels    = buffer.channels
            let orientation = self.orientation
            let output      = orientation.outputSize( sourceWidth: inputWidth, sourceHeight: inputHeight )
            let source      = buffer.pixels

            var result = [ Double ]( repeating: 0.0, count: source.count )

            result.withUnsafeMutableBufferPointer
            {
                nonisolated( unsafe ) let sendableResult = $0

                // One iteration per source pixel; each scatters its channels to a
                // distinct destination, so parallel writes never overlap.
                PixelUtilities.parallelOrSerial( iterations: inputWidth * inputHeight )
                {
                    let x             = $0 % inputWidth
                    let y             = $0 / inputWidth
                    let mapped        = orientation.map( x: x, y: y, inputWidth: inputWidth, inputHeight: inputHeight )
                    let sourceBase    = ( y * inputWidth + x ) * channels
                    let destinationBase = ( mapped.y * output.width + mapped.x ) * channels

                    for channel in 0 ..< channels
                    {
                        sendableResult[ destinationBase + channel ] = source[ sourceBase + channel ]
                    }
                }
            }

            buffer = try PixelBuffer( width: output.width, height: output.height, channels: channels, pixels: result, isNormalized: buffer.isNormalized )
        }
    }
}
