import Foundation
import os

/// Single-producer / single-consumer sample FIFO between the network receive
/// queue (writer) and the audio render thread (reader).
///
/// Playback only starts once `prebufferSamples` are queued ("primed"), which
/// absorbs network jitter. If the sender outpaces playback the oldest samples
/// are dropped so latency stays bounded by `capacitySamples`. Critical
/// sections are just index math plus a bounded memcpy, so holding an unfair
/// lock on the render thread is acceptable here.
final class JitterBuffer {
    private let lock = OSAllocatedUnfairLock()
    private let storage: UnsafeMutablePointer<Int16>
    private let capacity: Int
    private let prebuffer: Int

    private var head = 0 // read position
    private var count = 0
    private var primed = false

    // Latency governor: clock drift between the two phones' crystals (and
    // loss bursts followed by catch-up) leave a standing backlog that would
    // otherwise persist as extra latency forever. Track the *minimum*
    // occupancy over ~2 s windows; anything above the prebuffer that never
    // drains on its own is standing latency and gets trimmed.
    private let trimCheckSamples = Int(Wire.sampleRate) * 2
    private var samplesSinceTrimCheck = 0
    private var minCountSinceCheck = Int.max

    private var totalDropped = 0
    private var totalUnderruns = 0
    private var totalTrimmed = 0

    init(capacitySamples: Int, prebufferSamples: Int) {
        capacity = capacitySamples
        prebuffer = min(prebufferSamples, capacitySamples)
        storage = .allocate(capacity: capacitySamples)
        storage.initialize(repeating: 0, count: capacitySamples)
    }

    deinit {
        storage.deallocate()
    }

    func write(_ samples: UnsafePointer<Int16>, count n: Int) {
        guard n > 0 else { return }
        lock.lock()
        defer { lock.unlock() }

        if n >= capacity {
            // Absurdly large write: keep only the newest full buffer.
            storage.update(from: samples + (n - capacity), count: capacity)
            head = 0
            count = capacity
        } else {
            let overflow = count + n - capacity
            if overflow > 0 {
                head = (head + overflow) % capacity
                count -= overflow
                totalDropped += overflow
            }
            var tail = (head + count) % capacity
            var remaining = n
            var src = samples
            while remaining > 0 {
                let chunk = min(remaining, capacity - tail)
                (storage + tail).update(from: src, count: chunk)
                tail = (tail + chunk) % capacity
                src += chunk
                remaining -= chunk
            }
            count += n
        }
        if !primed && count >= prebuffer {
            primed = true
        }
    }

    /// Fills `out` with exactly `n` samples, padding with silence when not
    /// primed or on underrun. Safe to call from the realtime render thread.
    func read(into out: UnsafeMutablePointer<Int16>, count n: Int) {
        guard n > 0 else { return }
        lock.lock()
        defer { lock.unlock() }

        guard primed else {
            out.update(repeating: 0, count: n)
            samplesSinceTrimCheck = 0
            minCountSinceCheck = Int.max
            return
        }

        let take = min(count, n)
        var copied = 0
        while copied < take {
            let chunk = min(take - copied, capacity - head)
            (out + copied).update(from: storage + head, count: chunk)
            head = (head + chunk) % capacity
            copied += chunk
        }
        count -= take
        if take < n {
            (out + take).update(repeating: 0, count: n - take)
            primed = false // re-prime before resuming to rebuild the cushion
            totalUnderruns += 1
            samplesSinceTrimCheck = 0
            minCountSinceCheck = Int.max
            return
        }

        samplesSinceTrimCheck += n
        minCountSinceCheck = min(minCountSinceCheck, count)
        if samplesSinceTrimCheck >= trimCheckSamples {
            let excess = minCountSinceCheck - prebuffer
            if excess > Int(Wire.sampleRate) * 20 / 1000 { // >20 ms standing backlog
                let trim = min(excess, count)
                head = (head + trim) % capacity
                count -= trim
                totalTrimmed += trim
            }
            samplesSinceTrimCheck = 0
            minCountSinceCheck = Int.max
        }
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        head = 0
        count = 0
        primed = false
        samplesSinceTrimCheck = 0
        minCountSinceCheck = .max
    }

    var bufferedMilliseconds: Int {
        lock.lock()
        defer { lock.unlock() }
        return count * 1000 / Int(Wire.sampleRate)
    }

    var metrics: (droppedSamples: Int, underruns: Int, trimmedSamples: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (totalDropped, totalUnderruns, totalTrimmed)
    }
}
