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
@testable import SwiftPixel
import Testing

/// Exactness guards for the `[Double]` order-statistic primitives
/// `PixelUtilities.percentileBounds(in:lower:upper:)`, `median(_:)` and
/// `medianAbsoluteDeviation(_:around:)`.
///
/// These pin the *exact* values a full ascending sort plus linear interpolation
/// produces, against an independent in-test sort-based reference. They exist so
/// that any change to how those order statistics are computed — e.g. swapping a
/// full sort for an O(n) selection — must reproduce the previous values exactly,
/// not merely within a tolerance. The reference deliberately mirrors the
/// historical arithmetic (ascending sort; interpolate at `(n − 1)·p/100`; drop
/// non-finite samples first).
///
/// Equality is exact value equality (`==`), which still catches any genuine
/// numerical difference down to the last ULP. The one thing it deliberately does
/// *not* pin is the sign of a zero result: `−0 == +0`, no downstream consumer can
/// observe the difference, and the sign is implementation-defined even for the
/// current sort (it depends on how equal ±0 samples happen to be ordered), so a
/// selection is free to land on either.
struct Test_PixelUtilities_OrderStatisticsExactness
{
    // MARK: - Robustness cases (heavy duplicates, sorted, reverse, large)

    /// A constant (flat calibration) frame is all duplicates: every percentile
    /// must resolve to the single value, exercising a duplicate-heavy partition.
    @Test
    func flatFrameYieldsThatValueEverywhere() throws
    {
        let flat = [ Double ]( repeating: 7.5, count: 2_000 )

        #expect( PixelUtilities.percentileBounds( in: flat, lower: 0.25, upper: 99.75 ) == ( 7.5, 7.5 ) )
        #expect( PixelUtilities.median( flat ) == 7.5 )
        #expect( PixelUtilities.medianAbsoluteDeviation( flat, around: 7.5 ) == 0 )
    }

    /// Ascending input is the classic quickselect worst case; the selection must
    /// stay correct (and, with median-of-three pivoting, linear).
    @Test
    func alreadySortedInputIsHandled() throws
    {
        let sorted = ( 0 ..< 1_001 ).map { Double( $0 ) }

        #expect( PixelUtilities.percentileBounds( in: sorted, lower: 0, upper: 100 ) == ( 0, 1_000 ) )
        #expect( PixelUtilities.median( sorted ) == 500 )
        #expect( PixelUtilities.percentileBounds( in: sorted, lower: 25, upper: 75 ) == ( 250, 750 ) )
    }

    /// Descending input must be selected identically to its ascending order.
    @Test
    func reverseSortedInputIsHandled() throws
    {
        let reversed = ( 0 ..< 1_001 ).map { Double( 1_000 - $0 ) }

        #expect( PixelUtilities.percentileBounds( in: reversed, lower: 25, upper: 75 ) == ( 250, 750 ) )
        #expect( PixelUtilities.median( reversed ) == 500 )
    }

    /// A large, duplicate-dense frame must select without trapping, overflowing
    /// the stack, or diverging from the sort reference — the scale at which the
    /// O(n) win matters.
    @Test
    func largeInputMatchesSortReferenceExactly() throws
    {
        var rng    = SplitMix64( seed: 0xF17_5C09E )
        let values = ( 0 ..< 100_000 ).map { _ in Double( Int.random( in: 0 ..< 512, using: &rng ) ) }

        #expect( PixelUtilities.median( values ) == sortReferenceMedian( values ) )

        let bounds         = PixelUtilities.percentileBounds( in: values, lower: 1, upper: 99 )
        let expectedBounds = sortReferencePercentileBounds( values, lower: 1, upper: 99 )

        #expect( bounds.lower == expectedBounds.lower )
        #expect( bounds.upper == expectedBounds.upper )
    }

    /// Signed zeroes must not perturb the *value* of the result relative to the
    /// sort reference (its sign is immaterial — see the type doc).
    @Test
    func signedZeroesMatchSortReferenceValue() throws
    {
        let values = [ -0.0, 0.0, -0.0, 3.0, -2.0, 0.0, 1.0, -0.0 ]

        for percentile in stride( from: 0.0, through: 100.0, by: 12.5 )
        {
            let actual   = PixelUtilities.percentileBounds( in: values, lower: percentile, upper: percentile ).lower
            let expected = sortReferencePercentileBounds( values, lower: percentile, upper: percentile ).lower

            #expect( actual == expected )
        }
    }

    // MARK: - Differential sweeps against the sort reference (bit-for-bit)

    /// `percentileBounds` must reproduce the sort reference exactly across a broad
    /// spread of sizes, value ranges, duplicate densities, signed zeroes,
    /// non-finite blanks and percentile pairs (including out-of-range and swapped
    /// bounds) — exact value, not tolerance.
    @Test
    func percentileBoundsMatchSortReferenceExactly() throws
    {
        var rng = SplitMix64( seed: 0x0BAD_F00D_CAFE_BABE )

        for _ in 0 ..< 500
        {
            let values = randomSamples( using: &rng )
            let lower  = Double.random( in: -20.0 ... 120.0, using: &rng )
            let upper  = Double.random( in: -20.0 ... 120.0, using: &rng )

            let actual   = PixelUtilities.percentileBounds( in: values, lower: lower, upper: upper )
            let expected = sortReferencePercentileBounds( values, lower: lower, upper: upper )

            #expect( actual.lower == expected.lower )
            #expect( actual.upper == expected.upper )
        }
    }

    /// `median([Double])` must reproduce the sort reference (the 50th-percentile
    /// interpolation) exactly, including the all-non-finite → `nil` case.
    @Test
    func medianMatchesSortReferenceExactly() throws
    {
        var rng = SplitMix64( seed: 0x5EED_1234_ABCD_0001 )

        for _ in 0 ..< 500
        {
            let values = randomSamples( using: &rng )

            #expect( PixelUtilities.median( values ) == sortReferenceMedian( values ) )
        }
    }

    /// `medianAbsoluteDeviation([Double])` must reproduce the sort reference
    /// exactly for arbitrary (including non-finite) centers — proving both the
    /// Accelerate deviation pass and the selection are exact.
    @Test
    func medianAbsoluteDeviationMatchesSortReferenceExactly() throws
    {
        var rng = SplitMix64( seed: 0x5EED_1234_ABCD_0002 )

        for _ in 0 ..< 500
        {
            let values = randomSamples( using: &rng )
            let center = randomCenter( using: &rng )

            let actual   = PixelUtilities.medianAbsoluteDeviation( values, around: center )
            let expected = sortReferenceMedianAbsoluteDeviation( values, around: center )

            #expect( actual == expected )
        }
    }

    /// The Accelerate-computed absolute deviations must be bit-identical to the
    /// scalar `|value − center|` the historical `median(values.map { … })` path
    /// produced — isolating the `vDSP`-vs-scalar equivalence from the selection.
    /// Bit-pattern equality is valid here: `abs` never yields `−0`, so the
    /// signed-zero ambiguity above cannot arise.
    @Test
    func absoluteDeviationsAreBitIdenticalToTheScalarFormula() throws
    {
        var rng = SplitMix64( seed: 0xD15E_A5E_0000_0003 )

        for _ in 0 ..< 500
        {
            let values = randomSamples( using: &rng )
            let center = randomCenter( using: &rng )

            let actual   = PixelUtilities.medianAbsoluteDeviation( values, around: center )
            let expected = PixelUtilities.median( values.map { abs( $0 - center ) } )

            #expect( actual?.bitPattern == expected?.bitPattern )
        }
    }

    /// A deviation that overflows to `+Inf` — a huge value measured about a huge
    /// opposite center — must be dropped as non-finite, exactly as the scalar
    /// formula drops it, rather than poisoning the median: `a + (−b)` overflows to
    /// the same `+Inf` as `a − b`, so the Accelerate path and the reference agree.
    @Test
    func overflowingDeviationsAreDroppedLikeTheScalarFormula() throws
    {
        let center = -1.0e308
        let values = [ 1.0e308, 1.0, 2.0, 3.0 ]

        let actual   = PixelUtilities.medianAbsoluteDeviation( values, around: center )
        let expected = PixelUtilities.median( values.map { abs( $0 - center ) } )

        #expect( actual == expected )
        #expect( actual?.isFinite == true )
    }
}

// MARK: - In-test sort-based reference and deterministic sampling

/// A small, deterministic `RandomNumberGenerator` (SplitMix64) so the exactness
/// sweeps are reproducible across runs and machines.
private struct SplitMix64: RandomNumberGenerator
{
    private var state: UInt64

    /// Seeds the generator.
    ///
    /// - Parameter seed: The initial state.
    init( seed: UInt64 )
    {
        self.state = seed
    }

    /// Returns the next pseudo-random word.
    mutating func next() -> UInt64
    {
        self.state = self.state &+ 0x9E37_79B9_7F4A_7C15

        var z = self.state

        z = ( z ^ ( z >> 30 ) ) &* 0xBF58_476D_1CE4_E5B9
        z = ( z ^ ( z >> 27 ) ) &* 0x94D0_49BB_1331_11EB

        return z ^ ( z >> 31 )
    }
}

/// Builds a random sample array exercising the tricky selection cases: a
/// variable length, a small distinct-value pool (so runs of duplicates are
/// common, like a flat frame), negative values, signed zeroes and the occasional
/// non-finite blank, shuffled into arbitrary order.
///
/// - Parameter rng: The deterministic generator to draw from.
/// - Returns: The generated samples.
private func randomSamples< G: RandomNumberGenerator >( using rng: inout G ) -> [ Double ]
{
    let count = Int.random( in: 1 ... 400, using: &rng )
    let pool  = Int.random( in: 1 ... Swift.max( 1, count / 2 ), using: &rng )
    let scale = Double.random( in: 0.5 ... 5_000.0, using: &rng )

    var values = ( 0 ..< count ).map
    {
        _ in ( Double( Int.random( in: 0 ..< pool, using: &rng ) ) - Double( pool ) / 2.0 ) * scale
    }

    if Bool.random( using: &rng ) { values.append(  .nan ) }
    if Bool.random( using: &rng ) { values.append(  .infinity ) }
    if Bool.random( using: &rng ) { values.append( -.infinity ) }
    if Bool.random( using: &rng ) { values.append( contentsOf: [ -0.0, 0.0 ] ) }

    values.shuffle( using: &rng )

    return values
}

/// A random center for the MAD sweeps: usually finite, occasionally non-finite
/// so the all-non-finite-deviation → `nil` path is exercised too.
///
/// - Parameter rng: The deterministic generator to draw from.
/// - Returns: The center value.
private func randomCenter< G: RandomNumberGenerator >( using rng: inout G ) -> Double
{
    switch Int.random( in: 0 ..< 10, using: &rng )
    {
        case 0:  return .nan
        case 1:  return .infinity
        default: return Double.random( in: -6_000.0 ... 6_000.0, using: &rng )
    }
}

/// An independent, sort-based reference for
/// ``PixelUtilities/percentileBounds(in:lower:upper:)``, mirroring the historical
/// arithmetic exactly: drop non-finite samples, sort ascending, then linearly
/// interpolate at position `(n − 1)·p/100` between adjacent order statistics.
///
/// - Parameters:
///   - array: The samples to analyze.
///   - lower: The lower percentile, as a percentage in `0...100`.
///   - upper: The upper percentile, as a percentage in `0...100`.
///
/// - Returns: The interpolated lower/upper values, or `(0, 0)` when no sample is
///   finite.
private func sortReferencePercentileBounds( _ array: [ Double ], lower: Double, upper: Double ) -> ( lower: Double, upper: Double )
{
    let finite = array.filter { $0.isFinite }

    guard finite.isEmpty == false
    else
    {
        return ( 0, 0 )
    }

    let sorted        = finite.sorted()
    let last          = sorted.count - 1
    let clampedLower  = Swift.min( Swift.max( lower, 0.0 ), 100.0 )
    let clampedUpper  = Swift.min( Swift.max( upper, 0.0 ), 100.0 )
    let orderedLower  = Swift.min( clampedLower, clampedUpper )
    let orderedUpper  = Swift.max( clampedLower, clampedUpper )
    let lowerPosition = Double( last ) * ( orderedLower / 100.0 )
    let upperPosition = Double( last ) * ( orderedUpper / 100.0 )
    let lowerIndex    = Int( floor( lowerPosition ) )
    let upperIndex    = Int( floor( upperPosition ) )
    let lowerWeight   = lowerPosition - Double( lowerIndex )
    let upperWeight   = upperPosition - Double( upperIndex )
    let lowerValue    = sorted[ lowerIndex ] * ( 1.0 - lowerWeight ) + sorted[ Swift.min( lowerIndex + 1, last ) ] * lowerWeight
    let upperValue    = sorted[ upperIndex ] * ( 1.0 - upperWeight ) + sorted[ Swift.min( upperIndex + 1, last ) ] * upperWeight

    return ( lower: lowerValue, upper: upperValue )
}

/// An independent, sort-based reference for the `[Double]`
/// ``PixelUtilities/median(_:)`` — the 50th percentile of the finite samples,
/// or `nil` when none are finite.
///
/// - Parameter values: The values to summarize.
/// - Returns: The median, or `nil`.
private func sortReferenceMedian( _ values: [ Double ] ) -> Double?
{
    guard values.contains( where: { $0.isFinite } )
    else
    {
        return nil
    }

    return sortReferencePercentileBounds( values, lower: 50, upper: 50 ).lower
}

/// An independent, sort-based reference for the `[Double]`
/// ``PixelUtilities/medianAbsoluteDeviation(_:around:)`` — the median of the
/// scalar absolute deviations about `center`.
///
/// - Parameters:
///   - values: The values to summarize.
///   - center: The center to measure deviations from.
/// - Returns: The median absolute deviation, or `nil`.
private func sortReferenceMedianAbsoluteDeviation( _ values: [ Double ], around center: Double ) -> Double?
{
    sortReferenceMedian( values.map { abs( $0 - center ) } )
}
