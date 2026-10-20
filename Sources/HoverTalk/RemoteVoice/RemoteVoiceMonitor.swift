import AppKit
import HoverTalkCore
import Network

/// Keeps `RemoteVoiceAvailability` current for the configured voice server.
///
/// It probes with `RemoteVoiceClient.fetchVoices()` whenever the state machine says a probe is
/// due (`nextProbeDate(now:)`), so an available server is probed once and an unreachable one
/// with backoff. Waking from sleep and network path changes reset the state, which probes again.
/// The voice list of the last successful probe of the current address is kept. Nothing is sent
/// while the server is off or has no address, except a Test Connection the user asks for.
@MainActor
final class RemoteVoiceMonitor {
    /// The longest a reading waits for an unknown server before it starts with the system voice.
    static let readingCheckTimeout: TimeInterval = 0.8

    /// Called after the state, the voice list or the settings changed.
    var onChange: (() -> Void)?
    private(set) var config: RemoteVoiceServerConfig
    private(set) var voices: [VoiceDescriptor] = []
    /// A client for the configured address, whether or not the server is enabled.
    private(set) var client: RemoteVoiceClient?

    private var availability: RemoteVoiceAvailability
    private var probe: (id: UUID, task: Task<Result<TimeInterval, RemoteVoiceError>, Never>)?
    private var probeTimer: Timer?
    /// Readings waiting in `checkBeforeReading()`, resumed when the probe ends or they time out.
    private var readingWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private let pathMonitor = NWPathMonitor()
    private var hasSeenFirstPath = false
    /// Kept for the app's lifetime; the block holds the monitor weakly.
    private var wakeObserver: (any NSObjectProtocol)?

    init(config: RemoteVoiceServerConfig) {
        self.config = config
        availability = RemoteVoiceAvailability(enabled: Self.isActive(config))
        client = config.address.map { RemoteVoiceClient(address: $0) }
        observeWakeAndNetwork()
        scheduleProbe()
    }

    var state: RemoteVoiceAvailability.State { availability.state }

    /// The client to read with: nil unless the server is enabled and has an address.
    var activeClient: RemoteVoiceClient? { Self.isActive(config) ? client : nil }

    /// The server's voices for the user's languages.
    func catalog() -> RemoteVoiceCatalog {
        RemoteVoiceCatalog(voices: voices, preferredLanguages: Locale.preferredLanguages)
    }

    /// Applies new settings. A new address forgets the previous server's state and voices.
    func update(config newConfig: RemoteVoiceServerConfig) {
        guard newConfig != config else { return }
        let addressChanged = newConfig.address != config.address
        config = newConfig
        if addressChanged {
            cancelProbe()
            voices = []
            client = newConfig.address.map { RemoteVoiceClient(address: $0) }
            availability.handle(.disabled, now: Date())
        }
        if Self.isActive(newConfig) {
            availability.handle(.enabled, now: Date())
        } else {
            cancelProbe()
            availability.handle(.disabled, now: Date())
        }
        scheduleProbe()
        onChange?()
    }

    /// Speaking through the server failed: counts as a failed probe and schedules a re-probe.
    func reportPlaybackFailed() {
        availability.handle(.playbackFailed, now: Date())
        scheduleProbe()
        onChange?()
    }

    /// Probes the configured address now, or joins the probe in flight, and returns its latency
    /// or error; nil without an address. For the Test Connection button: it also probes while
    /// the server is off, without changing the off state.
    func probeNow() async -> Result<TimeInterval, RemoteVoiceError>? {
        guard let client else { return nil }
        let task = probe?.task ?? startProbe(client)
        return await task.value
    }

    /// Whether a reading should call `checkBeforeReading()` first: the server is set up but its
    /// state is not known yet.
    var needsCheckBeforeReading: Bool {
        guard activeClient != nil else { return false }
        switch availability.state {
        case .unknown, .checking: return true
        case .disabled, .available, .unavailable: return false
        }
    }

    /// Starts or joins a probe and waits for it, at most `readingCheckTimeout` seconds. A probe
    /// that takes longer goes on and only counts for later readings.
    func checkBeforeReading() async {
        guard needsCheckBeforeReading, let client = activeClient else { return }
        if probe == nil {
            _ = startProbe(client)
        }
        let id = UUID()
        await withCheckedContinuation { continuation in
            readingWaiters[id] = continuation
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.readingCheckTimeout))
                self?.resumeReadingWaiter(id)
            }
        }
    }

    // MARK: - Probing

    private static func isActive(_ config: RemoteVoiceServerConfig) -> Bool {
        config.enabled && config.address != nil
    }

    private func startProbe(_ client: RemoteVoiceClient) -> Task<Result<TimeInterval, RemoteVoiceError>, Never> {
        probeTimer?.invalidate()
        probeTimer = nil
        // Ignored while disabled, so a Test Connection leaves the off state alone.
        availability.handle(.probeStarted, now: Date())
        let id = UUID()
        let task = Task { [weak self] () -> Result<TimeInterval, RemoteVoiceError> in
            let result: Result<(voices: [VoiceDescriptor], latency: TimeInterval), RemoteVoiceError>
            do throws(RemoteVoiceError) {
                result = .success(try await client.fetchVoices())
            } catch {
                result = .failure(error)
            }
            self?.probeFinished(result, id: id)
            return result.map(\.latency)
        }
        probe = (id, task)
        onChange?()
        return task
    }

    private func probeFinished(_ result: Result<(voices: [VoiceDescriptor], latency: TimeInterval), RemoteVoiceError>, id: UUID) {
        guard probe?.id == id else { return }
        probe = nil
        switch result {
        case .success(let answer):
            voices = answer.voices
            availability.handle(.probeSucceeded(latency: answer.latency), now: Date())
        case .failure:
            availability.handle(.probeFailed, now: Date())
        }
        for id in Array(readingWaiters.keys) {
            resumeReadingWaiter(id)
        }
        scheduleProbe()
        onChange?()
    }

    private func cancelProbe() {
        probe?.task.cancel()
        probe = nil
        for id in Array(readingWaiters.keys) {
            resumeReadingWaiter(id)
        }
    }

    private func resumeReadingWaiter(_ id: UUID) {
        readingWaiters.removeValue(forKey: id)?.resume()
    }

    /// Starts the due probe now, or sets a timer for it; nothing while a probe runs or none is due.
    private func scheduleProbe() {
        probeTimer?.invalidate()
        probeTimer = nil
        guard probe == nil, let client = activeClient, let due = availability.nextProbeDate(now: Date()) else { return }
        let delay = due.timeIntervalSinceNow
        guard delay > 0 else {
            _ = startProbe(client)
            return
        }
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            // Added to the main run loop below, so the block runs on the main thread.
            MainActor.assumeIsolated {
                self?.scheduleProbe()
            }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        probeTimer = timer
    }

    // MARK: - Wake and network changes

    private func observeWakeAndNetwork() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // `queue: .main` runs the block on the main queue.
            MainActor.assumeIsolated {
                self?.wokeOrNetworkChanged()
            }
        }
        pathMonitor.pathUpdateHandler = { [weak self] _ in
            // The monitor is started on the main queue below.
            MainActor.assumeIsolated {
                self?.networkPathChanged()
            }
        }
        pathMonitor.start(queue: .main)
    }

    private func networkPathChanged() {
        // The first update reports the path the monitor started with, not a change.
        guard hasSeenFirstPath else {
            hasSeenFirstPath = true
            return
        }
        wokeOrNetworkChanged()
    }

    private func wokeOrNetworkChanged() {
        availability.handle(.wokeOrNetworkChanged, now: Date())
        scheduleProbe()
        onChange?()
    }
}
