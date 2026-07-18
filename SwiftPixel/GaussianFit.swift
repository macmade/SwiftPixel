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

/// A least-squares fit of a 2D elliptical Gaussian to a set of samples, by the
/// Levenberg–Marquardt method.
///
/// This refines a full rotated Gaussian — amplitude, centre, the two axis widths,
/// orientation and a flat background — from scattered `(x, y, value)` samples,
/// giving an accurate sub-pixel centre and shape for a blob-like feature even
/// when it is noisy.
///
/// The fit uses the rotated model's analytic Jacobian: its seven partials are
/// known in closed form, so a single pass computes the model and all derivatives
/// together, avoiding the extra `exp`-laden passes a finite-difference Jacobian
/// would cost. A non-converged, non-physical, or no-better-than-flat fit is
/// reported as `nil` so callers can drop it.
public enum GaussianFit
{
    /// The maximum number of Levenberg–Marquardt outer iterations.
    ///
    /// A star fit converges in well under this; the cap only bounds the cost of a
    /// pathological source that never settles (which would otherwise dominate a
    /// frame's detection time, each such fit re-evaluating the model hundreds of
    /// times over its window).
    private static let maxIterations = 50

    /// The maximum number of damping (λ) adjustments per outer iteration.
    private static let maxDampingSteps = 20

    /// The relative cost improvement below which the fit is considered converged.
    ///
    /// Set for a star centroid and width, which are sub-pixel-meaningful long before
    /// the cost stops improving in the twelfth decimal — a tighter tolerance only
    /// spends iterations refining noise.
    private static let costTolerance = 1e-5

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

        // Contiguous coordinate/value arrays so the model evaluation — the fit's hot
        // path, dominated by a per-sample `exp` — runs vectorised on Accelerate.
        let xs = samples.map { $0.x }
        let ys = samples.map { $0.y }
        let vs = samples.map { $0.value }

        let residuals: ( [ Double ] ) -> [ Double ] = { Self.modelResiduals( $0, xs: xs, ys: ys, values: vs ) }
        let cost:      ( [ Double ] ) -> Double     = { vDSP.sumOfSquares( residuals( $0 ) ) }

        var current      = initialGuess.vector
        var currentCost  = cost( current )
        var lambda       = 1e-3
        var converged    = false
        var iteration    = 0

        while iteration < Self.maxIterations
        {
            iteration += 1

            let ( jtj, jtr ) = Self.normalEquations( at: current, xs: xs, ys: ys, values: vs )
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

    /// The model-minus-data residuals for a parameter vector, over the sample grid,
    /// evaluated vectorised on Accelerate.
    ///
    /// This is the fit's hot path — the Levenberg–Marquardt loop calls it for every
    /// cost evaluation — and it is dominated by a per-sample `exp`, so the whole
    /// model is built with `vDSP` element-wise math and a single batched
    /// `vForce.exp`, rather than a scalar per-pixel loop.
    ///
    /// - Parameters:
    ///   - vector: The parameter vector, in fitting order.
    ///   - xs:     The samples' columns.
    ///   - ys:     The samples' rows.
    ///   - values: The samples' measured values.
    /// - Returns: `model(xs, ys) − values`, per sample.
    private static func modelResiduals( _ vector: [ Double ], xs: [ Double ], ys: [ Double ], values: [ Double ] ) -> [ Double ]
    {
        let amplitude  = vector[ 0 ]
        let x0         = vector[ 1 ]
        let y0         = vector[ 2 ]
        let sigmaX     = vector[ 3 ]
        let sigmaY     = vector[ 4 ]
        let theta      = vector[ 5 ]
        let background = vector[ 6 ]

        let cosT  = Foundation.cos( theta )
        let sinT  = Foundation.sin( theta )
        let sx2   = Swift.max( sigmaX * sigmaX, 1e-12 )
        let sy2   = Swift.max( sigmaY * sigmaY, 1e-12 )
        let count = xs.count

        var dx  = [ Double ]( repeating: 0, count: count )
        var dy  = [ Double ]( repeating: 0, count: count )
        var xr  = [ Double ]( repeating: 0, count: count )
        var yr  = [ Double ]( repeating: 0, count: count )
        var tmp = [ Double ]( repeating: 0, count: count )

        // Centre: dx = x − x₀, dy = y − y₀.
        vDSP.add( -x0, xs, result: &dx )
        vDSP.add( -y0, ys, result: &dy )

        // Rotate: xr = dx·cosθ + dy·sinθ, yr = −dx·sinθ + dy·cosθ.
        vDSP.multiply( cosT, dx, result: &xr )
        vDSP.multiply( sinT, dy, result: &tmp )
        vDSP.add( xr, tmp, result: &xr )

        vDSP.multiply( -sinT, dx, result: &yr )
        vDSP.multiply( cosT, dy, result: &tmp )
        vDSP.add( yr, tmp, result: &yr )

        // Exponent: arg = −( xr²/(2σx²) + yr²/(2σy²) ).
        vDSP.multiply( xr, xr, result: &xr )
        vDSP.multiply( yr, yr, result: &yr )
        vDSP.multiply( -1 / ( 2 * sx2 ), xr, result: &xr )
        vDSP.multiply( -1 / ( 2 * sy2 ), yr, result: &yr )
        vDSP.add( xr, yr, result: &tmp )

        // model = background + amplitude·exp(arg); residual = model − value.
        var result = [ Double ]( repeating: 0, count: count )

        vForce.exp( tmp, result: &result )
        vDSP.multiply( amplitude, result, result: &result )
        vDSP.add( background, result, result: &result )
        vDSP.subtract( result, values, result: &result )

        return result
    }

    /// Builds the normal-equation matrices `JᵀJ` and the vector `Jᵀr` from the
    /// **analytic** Jacobian of the rotated Gaussian.
    ///
    /// A central-difference Jacobian re-evaluates the whole model twice per
    /// parameter — fourteen extra `exp`-laden passes over the window every
    /// iteration, which dominates a frame's detection time. The rotated Gaussian's
    /// partials are known in closed form (derived from `arg = −[xr²/(2σx²) +
    /// yr²/(2σy²)]` and the rotation of `(x−x₀, y−y₀)`), so a single pass computes
    /// the model and all seven derivatives together, accumulating `JᵀJ` and `Jᵀr`
    /// as it goes.
    ///
    /// - Parameters:
    ///   - vector: The parameter vector, in fitting order.
    ///   - xs:     The samples' columns.
    ///   - ys:     The samples' rows.
    ///   - values: The samples' measured values.
    /// - Returns: The symmetric `JᵀJ` and the gradient `Jᵀr`.
    private static func normalEquations( at vector: [ Double ], xs: [ Double ], ys: [ Double ], values: [ Double ] ) -> ( jtj: [ [ Double ] ], jtr: [ Double ] )
    {
        let amplitude  = vector[ 0 ]
        let x0         = vector[ 1 ]
        let y0         = vector[ 2 ]
        let sigmaX     = vector[ 3 ]
        let sigmaY     = vector[ 4 ]
        let theta      = vector[ 5 ]
        let background = vector[ 6 ]

        let cosT = Foundation.cos( theta )
        let sinT = Foundation.sin( theta )
        let sx2  = Swift.max( sigmaX * sigmaX, 1e-12 )
        let sy2  = Swift.max( sigmaY * sigmaY, 1e-12 )
        let sx3  = sigmaX * sx2
        let sy3  = sigmaY * sy2

        var jtj = [ [ Double ] ]( repeating: [ Double ]( repeating: 0, count: Self.parameterCount ), count: Self.parameterCount )
        var jtr = [ Double ]( repeating: 0, count: Self.parameterCount )

        for k in xs.indices
        {
            let dx = xs[ k ] - x0
            let dy = ys[ k ] - y0
            let xr = ( dx * cosT ) + ( dy * sinT )
            let yr = ( -dx * sinT ) + ( dy * cosT )
            let g  = Foundation.exp( -( ( ( xr * xr ) / ( 2 * sx2 ) ) + ( ( yr * yr ) / ( 2 * sy2 ) ) ) )
            let ag = amplitude * g

            // ∂/∂[ amplitude, x₀, y₀, σx, σy, θ, background ].
            let row = [
                g,
                ag * ( ( ( xr * cosT ) / sx2 ) - ( ( yr * sinT ) / sy2 ) ),
                ag * ( ( ( xr * sinT ) / sx2 ) + ( ( yr * cosT ) / sy2 ) ),
                abs( sx3 ) > 1e-18 ? ag * ( ( xr * xr ) / sx3 ) : 0,
                abs( sy3 ) > 1e-18 ? ag * ( ( yr * yr ) / sy3 ) : 0,
                ag * xr * yr * ( ( 1 / sy2 ) - ( 1 / sx2 ) ),
                1,
            ]

            let residual = background + ag - values[ k ]

            for i in 0 ..< Self.parameterCount
            {
                jtr[ i ] += row[ i ] * residual

                for j in i ..< Self.parameterCount
                {
                    jtj[ i ][ j ] += row[ i ] * row[ j ]
                }
            }
        }

        // Mirror the lower triangle: JᵀJ is symmetric.
        for i in 0 ..< Self.parameterCount
        {
            for j in 0 ..< i
            {
                jtj[ i ][ j ] = jtj[ j ][ i ]
            }
        }

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

            // The singularity floor is absolute rather than scaled to the matrix
            // norm. That is safe for this caller: the Levenberg–Marquardt loop
            // damps the diagonal of JᵀJ by (1 + λ), keeping the solved system
            // well-conditioned, and a marginally-conditioned solve that slips past
            // the floor still produces a step that the strict candidateCost <
            // currentCost acceptance gate rejects — so an ill-conditioned system
            // cannot drive an accepted update.
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
