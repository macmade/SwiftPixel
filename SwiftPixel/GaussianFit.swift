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

/// A least-squares fit of a 2D elliptical Gaussian to a set of samples, by the
/// Levenberg–Marquardt method.
///
/// This refines a full rotated Gaussian — amplitude, centre, the two axis widths,
/// orientation and a flat background — from scattered `(x, y, value)` samples,
/// giving an accurate sub-pixel centre and shape for a blob-like feature even
/// when it is noisy.
///
/// The fit uses a numerical (finite-difference) Jacobian rather than analytic
/// derivatives: the seven-parameter rotated model makes hand-coded derivatives
/// error-prone, while a central-difference Jacobian over a small window is both
/// cheap and robust. A non-converged, non-physical, or no-better-than-flat fit is
/// reported as `nil` so callers can drop it.
public enum GaussianFit
{
    /// The maximum number of Levenberg–Marquardt outer iterations.
    private static let maxIterations = 200

    /// The maximum number of damping (λ) adjustments per outer iteration.
    private static let maxDampingSteps = 20

    /// The relative cost improvement below which the fit is considered converged.
    private static let costTolerance = 1e-8

    /// The number of fitted parameters.
    private static let parameterCount = 7

    /// The parameters of a 2D elliptical Gaussian:
    /// `f(x, y) = background + amplitude · exp( −[xᵣ²/(2σx²) + yᵣ²/(2σy²)] )`,
    /// where `(xᵣ, yᵣ)` is `(x − x₀, y − y₀)` rotated by `theta`.
    public struct Parameters: Sendable, Equatable
    {
        /// The peak value above the background.
        public var amplitude: Double

        /// The centre column, in pixels.
        public var x: Double

        /// The centre row, in pixels.
        public var y: Double

        /// The standard deviation along the (rotated) x axis, in pixels.
        public var sigmaX: Double

        /// The standard deviation along the (rotated) y axis, in pixels.
        public var sigmaY: Double

        /// The rotation of the ellipse's axes, in radians.
        public var theta: Double

        /// The flat background level.
        public var background: Double

        /// Creates a parameter set from explicit values.
        public init( amplitude: Double, x: Double, y: Double, sigmaX: Double, sigmaY: Double, theta: Double, background: Double )
        {
            self.amplitude  = amplitude
            self.x          = x
            self.y          = y
            self.sigmaX     = sigmaX
            self.sigmaY     = sigmaY
            self.theta      = theta
            self.background = background
        }

        /// Evaluates the Gaussian model at a point.
        ///
        /// - Parameters:
        ///   - vx: The column to evaluate at.
        ///   - vy: The row to evaluate at.
        /// - Returns: The model value at `(vx, vy)`.
        public func value( atX vx: Double, y vy: Double ) -> Double
        {
            let dx   = vx - self.x
            let dy   = vy - self.y
            let cosT = Foundation.cos( self.theta )
            let sinT = Foundation.sin( self.theta )
            let xr   = ( dx * cosT ) + ( dy * sinT )
            let yr   = ( -dx * sinT ) + ( dy * cosT )
            let sx2  = Swift.max( self.sigmaX * self.sigmaX, 1e-12 )
            let sy2  = Swift.max( self.sigmaY * self.sigmaY, 1e-12 )

            return self.background + ( self.amplitude * Foundation.exp( -( ( ( xr * xr ) / ( 2 * sx2 ) ) + ( ( yr * yr ) / ( 2 * sy2 ) ) ) ) )
        }

        /// The parameters as a flat vector, in fitting order.
        fileprivate var vector: [ Double ]
        {
            [ self.amplitude, self.x, self.y, self.sigmaX, self.sigmaY, self.theta, self.background ]
        }

        /// Rebuilds the parameters from a flat vector, in fitting order.
        fileprivate init( vector v: [ Double ] )
        {
            self.init( amplitude: v[ 0 ], x: v[ 1 ], y: v[ 2 ], sigmaX: v[ 3 ], sigmaY: v[ 4 ], theta: v[ 5 ], background: v[ 6 ] )
        }
    }

    /// Fits a 2D elliptical Gaussian to the samples, starting from a guess.
    ///
    /// - Parameters:
    ///   - samples:      The window samples: each a pixel position and its value.
    ///   - initialGuess: The starting parameters.
    /// - Returns: The fitted parameters, or `nil` if the fit did not converge to
    ///   a physical Gaussian that explains the data better than a flat background.
    public static func fit( samples: [ ( x: Double, y: Double, value: Double ) ], initialGuess: Parameters ) -> Parameters?
    {
        guard samples.count >= Self.parameterCount
        else
        {
            return nil
        }

        let residuals: ( [ Double ] ) -> [ Double ] =
        {
            vector in

            let parameters = Parameters( vector: vector )

            return samples.map { parameters.value( atX: $0.x, y: $0.y ) - $0.value }
        }

        let cost: ( [ Double ] ) -> Double = { residuals( $0 ).reduce( 0 ) { $0 + ( $1 * $1 ) } }

        var current      = initialGuess.vector
        var currentCost  = cost( current )
        var lambda       = 1e-3
        var converged    = false
        var iteration    = 0

        while iteration < Self.maxIterations
        {
            iteration += 1

            let ( jtj, jtr ) = Self.normalEquations( at: current, residuals: residuals )
            var stepAccepted = false
            var dampingStep  = 0

            while dampingStep < Self.maxDampingSteps
            {
                dampingStep += 1

                // Marquardt damping: scale the diagonal of JᵀJ by (1 + λ), which
                // adapts to each parameter's curvature.
                let augmented = jtj.enumerated().map
                {
                    row in

                    row.element.enumerated().map { $0.offset == row.offset ? $0.element * ( 1 + lambda ) : $0.element }
                }

                guard let delta = Self.solve( augmented, jtr.map { -$0 } )
                else
                {
                    lambda *= 10

                    if lambda > 1e12 { break }

                    continue
                }

                let candidate     = zip( current, delta ).map( + )
                let candidateCost = cost( candidate )

                guard candidateCost < currentCost
                else
                {
                    lambda *= 10

                    if lambda > 1e12 { break }

                    continue
                }

                let improvement = ( currentCost - candidateCost ) / Swift.max( currentCost, 1e-30 )

                current      = candidate
                currentCost  = candidateCost
                lambda       = Swift.max( lambda * 0.3, 1e-12 )
                stepAccepted = true
                converged    = improvement < Self.costTolerance

                break
            }

            if converged || stepAccepted == false { break }
        }

        return Self.validated( current, samples: samples, cost: currentCost )
    }

    /// Builds the normal-equation matrices `JᵀJ` and the vector `Jᵀr` using a
    /// central-difference Jacobian.
    private static func normalEquations( at vector: [ Double ], residuals: ( [ Double ] ) -> [ Double ] ) -> ( jtj: [ [ Double ] ], jtr: [ Double ] )
    {
        let r = residuals( vector )

        // One Jacobian column per parameter, by central differences.
        let columns = vector.indices.map
        {
            index -> [ Double ] in

            let step = Swift.max( 1e-6, 1e-4 * abs( vector[ index ] ) )
            var plus = vector
            var minus = vector

            plus[ index ]  += step
            minus[ index ] -= step

            let rPlus  = residuals( plus )
            let rMinus = residuals( minus )

            return zip( rPlus, rMinus ).map { ( $0 - $1 ) / ( 2 * step ) }
        }

        let jtj = columns.map { columnA in columns.map { columnB in zip( columnA, columnB ).reduce( 0 ) { $0 + ( $1.0 * $1.1 ) } } }
        let jtr = columns.map { column in zip( column, r ).reduce( 0 ) { $0 + ( $1.0 * $1.1 ) } }

        return ( jtj: jtj, jtr: jtr )
    }

    /// Solves the linear system `A · x = b` by Gaussian elimination with partial
    /// pivoting. The small fixed system size makes index-based elimination the
    /// clearest form here.
    ///
    /// - Returns: The solution vector, or `nil` if the matrix is singular.
    private static func solve( _ a: [ [ Double ] ], _ b: [ Double ] ) -> [ Double ]?
    {
        let n      = b.count
        var matrix = a
        var rhs    = b

        for pivot in 0 ..< n
        {
            let candidate = ( pivot ..< n ).max { abs( matrix[ $0 ][ pivot ] ) < abs( matrix[ $1 ][ pivot ] ) } ?? pivot

            guard abs( matrix[ candidate ][ pivot ] ) > 1e-12
            else
            {
                return nil
            }

            matrix.swapAt( pivot, candidate )
            rhs.swapAt( pivot, candidate )

            ( ( pivot + 1 ) ..< n ).forEach
            {
                row in

                let factor = matrix[ row ][ pivot ] / matrix[ pivot ][ pivot ]

                ( pivot ..< n ).forEach { matrix[ row ][ $0 ] -= factor * matrix[ pivot ][ $0 ] }

                rhs[ row ] -= factor * rhs[ pivot ]
            }
        }

        var solution = [ Double ]( repeating: 0, count: n )

        stride( from: n - 1, through: 0, by: -1 ).forEach
        {
            row in

            let sum = ( ( row + 1 ) ..< n ).reduce( rhs[ row ] ) { $0 - ( matrix[ row ][ $1 ] * solution[ $1 ] ) }

            solution[ row ] = sum / matrix[ row ][ row ]
        }

        return solution
    }

    /// Applies the physical and quality guards to a converged parameter vector.
    ///
    /// - Returns: The fitted parameters with positive axis widths, or `nil` when
    ///   the fit is non-physical or no better than a flat background.
    private static func validated( _ vector: [ Double ], samples: [ ( x: Double, y: Double, value: Double ) ], cost: Double ) -> Parameters?
    {
        var fitted = Parameters( vector: vector )

        // The model is symmetric in the sign of each σ; report positive widths.
        fitted.sigmaX = abs( fitted.sigmaX )
        fitted.sigmaY = abs( fitted.sigmaY )

        let values   = samples.map { $0.value }
        let mean     = values.reduce( 0, + ) / Double( values.count )
        let flatCost = values.reduce( 0 ) { $0 + ( ( $1 - mean ) * ( $1 - mean ) ) }
        let spanX    = ( samples.map { $0.x }.max() ?? 0 ) - ( samples.map { $0.x }.min() ?? 0 )
        let spanY    = ( samples.map { $0.y }.max() ?? 0 ) - ( samples.map { $0.y }.min() ?? 0 )
        let span     = Swift.max( spanX, spanY )

        guard fitted.amplitude.isFinite, fitted.amplitude > 0,
              fitted.x.isFinite, fitted.y.isFinite, fitted.background.isFinite,
              fitted.sigmaX.isFinite, fitted.sigmaY.isFinite,
              fitted.sigmaX > 0, fitted.sigmaY > 0,
              fitted.sigmaX <= span, fitted.sigmaY <= span,
              cost < flatCost
        else
        {
            return nil
        }

        return fitted
    }
}
