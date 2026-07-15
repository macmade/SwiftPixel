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

import Darwin
import Foundation

/// A best-effort sampler for the memory an operation uses.
///
/// Memory accounting on Darwin is sampled rather than exact, so these figures
/// are approximate — meant for relative comparison between operations and across
/// baselines, not as authoritative allocation counts. When a specific processor
/// needs exact numbers, profile it with Instruments.
enum AllocationMeter
{
    /// Tracks the peak footprint observed across threads while an operation runs.
    ///
    /// A plain lock guards the value so the background sampler and the measured
    /// thread can both update it without a data race; the class is therefore
    /// safe to share and marked `@unchecked Sendable`.
    private final class PeakTracker: @unchecked
    Sendable
    {
        private let lock     = NSLock()
        private var peakValue = 0
        private var running   = true

        /// Records a footprint sample, keeping the largest increase over the
        /// baseline seen so far.
        func record( footprint: Int, baseline: Int )
        {
            self.lock.lock()

            defer
            {
                self.lock.unlock()
            }

            self.peakValue = max( self.peakValue, footprint - baseline )
        }

        /// Whether the background sampler should keep polling.
        var isRunning: Bool
        {
            self.lock.lock()

            defer
            {
                self.lock.unlock()
            }

            return self.running
        }

        /// Signals the background sampler to stop.
        func stop()
        {
            self.lock.lock()

            self.running = false

            self.lock.unlock()
        }

        /// The peak footprint increase observed, clamped to be non-negative.
        var peak: Int
        {
            self.lock.lock()

            defer
            {
                self.lock.unlock()
            }

            return max( 0, self.peakValue )
        }
    }

    /// The total number of bytes currently allocated by `malloc` across all
    /// zones, process-wide.
    ///
    /// Uses `malloc_zone_statistics`' `size_in_use`, which — unlike the resident
    /// footprint — reflects transient buffers even when the allocator reuses
    /// already-resident pages, making it a far better proxy for the memory an
    /// operation churns through.
    static func currentAllocatedBytes() -> Int
    {
        var stats = malloc_statistics_t()

        malloc_zone_statistics( nil, &stats )

        return Int( stats.size_in_use )
    }

    /// Runs `body` while polling the allocated-bytes counter, returning the
    /// approximate peak increase in bytes observed above the pre-run baseline.
    ///
    /// The peak is sampled from a background thread at a fixed interval, so it is
    /// approximate: allocation spikes shorter than the sampling interval can be
    /// missed, and unrelated process activity can inflate it. The counter is
    /// process-wide, so a fast operation that allocates and frees between samples
    /// may report `0`. The result is never negative.
    ///
    /// - Parameter body: The operation to measure.
    /// - Returns: The approximate peak increase in allocated bytes during
    ///            `body`.
    /// - Throws: Rethrows any error thrown by `body`.
    static func peakBytes( during body: () throws -> Void ) rethrows -> Int
    {
        let baseline = self.currentAllocatedBytes()
        let tracker  = PeakTracker()
        let finished = DispatchSemaphore( value: 0 )

        DispatchQueue.global( qos: .userInitiated ).async
        {
            while tracker.isRunning
            {
                tracker.record( footprint: self.currentAllocatedBytes(), baseline: baseline )

                usleep( 100 )
            }

            finished.signal()
        }

        // Ensure the sampler is always stopped and joined, even if `body` throws.
        defer
        {
            tracker.stop()
            finished.wait()
        }

        try body()

        tracker.record( footprint: self.currentAllocatedBytes(), baseline: baseline )

        return tracker.peak
    }
}
