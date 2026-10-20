import Foundation

/// Whether the voice server can be used, as a pure state machine with backoff re-probing.
///
/// The owner runs the probes: it asks `nextProbeDate(now:)` when to probe, reports
/// `.probeStarted` and then the probe's result, and reports playback failures and system wake or
/// network changes. Time is passed in as `now`, so tests control the clock.
public struct RemoteVoiceAvailability: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        /// The user turned the voice server off; nothing is probed.
        case disabled
        /// Enabled but not known yet; a probe is due now.
        case unknown
        /// A probe is in flight.
        case checking
        /// The last probe succeeded, taking `latency` seconds.
        case available(latency: TimeInterval)
        /// `failures` consecutive probes or playbacks failed; the next probe is due at `retryAt`.
        case unavailable(retryAt: Date, failures: Int)
    }

    public enum Event: Equatable, Sendable {
        case enabled
        case disabled
        case probeStarted
        case probeSucceeded(latency: TimeInterval)
        case probeFailed
        /// Speaking through the server failed (for example mid-reading).
        case playbackFailed
        /// The Mac woke or the network changed: earlier failures may no longer apply.
        case wokeOrNetworkChanged
    }

    /// Seconds to wait after the first, second, third and every later consecutive failure.
    public static let retryDelays: [TimeInterval] = [5, 15, 30, 60]

    public private(set) var state: State
    /// Consecutive failures, kept while `.checking` so the probe's outcome extends the count.
    private var failures = 0

    public init(enabled: Bool = false) {
        state = enabled ? .unknown : .disabled
    }

    /// The wait after `failures` consecutive failures (counted from 1; lower counts use the first
    /// delay).
    public static func retryDelay(afterFailures failures: Int) -> TimeInterval {
        retryDelays[min(max(failures, 1), retryDelays.count) - 1]
    }

    /// Probe results count only while `.checking`, so a result that arrives after a disable or a
    /// playback failure cannot overwrite the newer state. While disabled only `.enabled` counts.
    public mutating func handle(_ event: Event, now: Date) {
        if state == .disabled, event != .enabled { return }
        switch event {
        case .enabled:
            guard state == .disabled else { return }
            failures = 0
            state = .unknown
        case .disabled:
            failures = 0
            state = .disabled
        case .probeStarted:
            state = .checking
        case .probeSucceeded(let latency):
            guard state == .checking else { return }
            failures = 0
            state = .available(latency: latency)
        case .probeFailed:
            guard state == .checking else { return }
            recordFailure(now: now)
        case .playbackFailed:
            recordFailure(now: now)
        case .wokeOrNetworkChanged:
            guard state != .checking else { return }
            failures = 0
            state = .unknown
        }
    }

    /// When the owner should start the next probe: `now` while unknown, `retryAt` (or `now` once
    /// it has passed) while unavailable; nil while disabled, checking or available, where no probe
    /// is scheduled (a failure while available arrives as `.playbackFailed`).
    public func nextProbeDate(now: Date) -> Date? {
        switch state {
        case .disabled, .checking, .available: nil
        case .unknown: now
        case .unavailable(let retryAt, _): max(retryAt, now)
        }
    }

    private mutating func recordFailure(now: Date) {
        failures += 1
        state = .unavailable(retryAt: now + Self.retryDelay(afterFailures: failures), failures: failures)
    }
}
