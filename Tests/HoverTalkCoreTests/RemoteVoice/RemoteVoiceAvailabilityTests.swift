import Foundation
import Testing
@testable import HoverTalkCore

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

/// An enabled availability after `failures` consecutive failed probes, the last one at `now`.
private func failing(_ failures: Int, now: Date = t0) -> RemoteVoiceAvailability {
    var availability = RemoteVoiceAvailability(enabled: true)
    for _ in 0..<failures {
        availability.handle(.probeStarted, now: now)
        availability.handle(.probeFailed, now: now)
    }
    return availability
}

@Suite("RemoteVoiceAvailability")
struct RemoteVoiceAvailabilityTests {
    @Test("Disabled by default and never probed; enabling makes it unknown, due for a probe now")
    func enableDisable() {
        var availability = RemoteVoiceAvailability()
        #expect(availability.state == .disabled)
        #expect(availability.nextProbeDate(now: t0) == nil)

        availability.handle(.enabled, now: t0)
        #expect(availability.state == .unknown)
        #expect(availability.nextProbeDate(now: t0) == t0)
        #expect(RemoteVoiceAvailability(enabled: true) == availability)

        availability.handle(.disabled, now: t0)
        #expect(availability.state == .disabled)
    }

    @Test("A successful probe makes the server available with its latency; no probe is scheduled meanwhile")
    func probeSucceeds() {
        var availability = RemoteVoiceAvailability(enabled: true)

        availability.handle(.probeStarted, now: t0)
        #expect(availability.state == .checking)
        #expect(availability.nextProbeDate(now: t0) == nil)

        availability.handle(.probeSucceeded(latency: 0.12), now: t0)
        #expect(availability.state == .available(latency: 0.12))
        #expect(availability.nextProbeDate(now: t0) == nil)
    }

    @Test("Consecutive failures back off 5, 15, 30, then 60 seconds at most", arguments: [
        (1, 5.0), (2, 15.0), (3, 30.0), (4, 60.0), (5, 60.0), (9, 60.0),
    ])
    func backoff(failures: Int, delay: TimeInterval) {
        let availability = failing(failures)

        #expect(availability.state == .unavailable(retryAt: t0 + delay, failures: failures))
        #expect(availability.nextProbeDate(now: t0) == t0 + delay)
        #expect(availability.nextProbeDate(now: t0 + 1_000) == t0 + 1_000)
    }

    @Test("A success resets the backoff, so the next failure waits 5 seconds again")
    func successResets() {
        var availability = failing(3)

        availability.handle(.probeStarted, now: t0)
        availability.handle(.probeSucceeded(latency: 0.05), now: t0)
        availability.handle(.probeStarted, now: t0)
        availability.handle(.probeFailed, now: t0)

        #expect(availability.state == .unavailable(retryAt: t0 + 5, failures: 1))
    }

    @Test("A playback failure makes an available server unavailable and counts as a failure")
    func playbackFailure() {
        var availability = RemoteVoiceAvailability(enabled: true)
        availability.handle(.probeStarted, now: t0)
        availability.handle(.probeSucceeded(latency: 0.1), now: t0)

        availability.handle(.playbackFailed, now: t0)
        #expect(availability.state == .unavailable(retryAt: t0 + 5, failures: 1))

        availability.handle(.probeStarted, now: t0 + 5)
        availability.handle(.probeFailed, now: t0 + 5)
        #expect(availability.state == .unavailable(retryAt: t0 + 20, failures: 2))
    }

    @Test("Probe results count only while checking", arguments: [
        RemoteVoiceAvailability.Event.probeSucceeded(latency: 0.1), .probeFailed,
    ])
    func resultsOnlyWhileChecking(result: RemoteVoiceAvailability.Event) {
        var unknown = RemoteVoiceAvailability(enabled: true)
        unknown.handle(result, now: t0)
        #expect(unknown.state == .unknown)

        var unavailable = failing(2)
        let before = unavailable
        unavailable.handle(result, now: t0)
        #expect(unavailable == before)

        var disabledWhileChecking = RemoteVoiceAvailability(enabled: true)
        disabledWhileChecking.handle(.probeStarted, now: t0)
        disabledWhileChecking.handle(.disabled, now: t0)
        disabledWhileChecking.handle(result, now: t0)
        #expect(disabledWhileChecking.state == .disabled)
    }

    @Test("A playback failure during a probe wins over that probe's late success")
    func playbackFailureDuringProbe() {
        var availability = RemoteVoiceAvailability(enabled: true)
        availability.handle(.probeStarted, now: t0)
        availability.handle(.playbackFailed, now: t0)

        availability.handle(.probeSucceeded(latency: 0.1), now: t0 + 1)

        #expect(availability.state == .unavailable(retryAt: t0 + 5, failures: 1))
    }

    @Test("Waking or a network change asks for a probe now and forgets earlier failures")
    func wokeOrNetworkChanged() {
        var unavailable = failing(4)
        unavailable.handle(.wokeOrNetworkChanged, now: t0 + 2)
        #expect(unavailable.state == .unknown)
        #expect(unavailable.nextProbeDate(now: t0 + 2) == t0 + 2)
        unavailable.handle(.probeStarted, now: t0 + 2)
        unavailable.handle(.probeFailed, now: t0 + 2)
        #expect(unavailable.state == .unavailable(retryAt: t0 + 7, failures: 1))

        var available = RemoteVoiceAvailability(enabled: true)
        available.handle(.probeStarted, now: t0)
        available.handle(.probeSucceeded(latency: 0.1), now: t0)
        available.handle(.wokeOrNetworkChanged, now: t0)
        #expect(available.state == .unknown)

        var checking = RemoteVoiceAvailability(enabled: true)
        checking.handle(.probeStarted, now: t0)
        checking.handle(.wokeOrNetworkChanged, now: t0)
        #expect(checking.state == .checking)
    }

    @Test("While disabled every event but enabling is ignored", arguments: [
        RemoteVoiceAvailability.Event.probeStarted, .probeSucceeded(latency: 0.1), .probeFailed, .playbackFailed, .wokeOrNetworkChanged, .disabled,
    ])
    func disabledIgnores(event: RemoteVoiceAvailability.Event) {
        var availability = RemoteVoiceAvailability()
        availability.handle(event, now: t0)
        #expect(availability.state == .disabled)
    }

    @Test("Disabling forgets failures; enabling an enabled server changes nothing")
    func reenable() {
        var availability = failing(3)
        availability.handle(.disabled, now: t0)
        availability.handle(.enabled, now: t0)
        availability.handle(.probeStarted, now: t0)
        availability.handle(.probeFailed, now: t0)
        #expect(availability.state == .unavailable(retryAt: t0 + 5, failures: 1))

        var available = RemoteVoiceAvailability(enabled: true)
        available.handle(.probeStarted, now: t0)
        available.handle(.probeSucceeded(latency: 0.2), now: t0)
        available.handle(.enabled, now: t0)
        #expect(available.state == .available(latency: 0.2))
    }
}
