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

/// A single stage in an image-processing pipeline that transforms a
/// `PixelBuffer` in place.
///
/// Stages are composed by `PixelPipeline`. Each stage documents its own
/// preconditions (e.g. channel count or whether the buffer must be normalized)
/// and throws if they are not met.
public protocol PixelProcessor: CustomStringConvertible
{
    /// A human-readable name for the stage, including its parameters.
    var name: String
    {
        get
    }

    /// Applies the stage to `buffer`, mutating it in place.
    ///
    /// - Parameter buffer: The buffer to transform.
    ///
    /// - Throws: A `RuntimeError` if the buffer does not meet the stage's
    ///           preconditions, or if processing fails.
    func process( buffer: inout PixelBuffer ) throws

    /// A textual representation of the stage; defaults to `name`.
    var description: String
    {
        get
    }
}

public extension PixelProcessor
{
    /// Defaults to `name`.
    var description: String
    {
        self.name
    }
}

/// A namespace for the built-in `PixelProcessor` implementations.
public enum Processors
{}
