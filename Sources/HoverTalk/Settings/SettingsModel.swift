import Foundation
import HoverTalkCore
import Observation

/// What the Settings window shows, read from `Preferences`, the voice list and the voice server
/// monitor by `refresh()`. Every change goes through `ReadingSession`, which stores it and
/// applies it to the player.
@MainActor
@Observable
final class SettingsModel {
    private(set) var catalog = VoiceCatalog(voices: [], preferredLanguages: [])
    private(set) var selection = VoiceSelection.default
    private(set) var rate = SpeechRate.default
    private(set) var isContinuous = ReadingMode.default == .continuous
    var query = ""

    private(set) var server = RemoteVoiceServerConfig.default
    /// The URL field's text. It is applied (`commitServerURL()`) on Return, when the field loses
    /// focus, on Test Connection and on the toggle, never on every keystroke: a half-typed
    /// address must not be probed. `refresh()` leaves it alone.
    var serverURLText = ""
    private(set) var remoteVoices: [VoiceDescriptor] = []
    /// The latest Test Connection outcome; nil before the first test of the current address.
    private(set) var connectionTest: ConnectionTestStatus?

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let voices: SystemVoiceProvider
    @ObservationIgnored private let readingSession: ReadingSession
    @ObservationIgnored private let remoteVoice: RemoteVoiceMonitor
    @ObservationIgnored private let previewer = VoicePreviewer()

    init(preferences: Preferences, voices: SystemVoiceProvider, readingSession: ReadingSession, remoteVoice: RemoteVoiceMonitor) {
        self.preferences = preferences
        self.voices = voices
        self.readingSession = readingSession
        self.remoteVoice = remoteVoice
        refresh()
        resetServerURLText()
    }

    /// The catalog groups that match `query`.
    var groups: [VoiceGroup] {
        catalog.groups(matching: query, languageName: VoiceLanguageNames.name(for:))
    }

    /// Reads the current voice list (without asking the system again), voice selection, rate,
    /// reading mode and voice server settings.
    func refresh() {
        catalog = voices.catalog()
        selection = preferences.voiceSelection
        rate = preferences.speechRate
        isContinuous = preferences.readingMode == .continuous
        server = preferences.remoteVoiceServer
        remoteVoices = remoteVoice.voices
    }

    /// Shows the stored address in the URL field, dropping unapplied text; when the window opens.
    func resetServerURLText() {
        serverURLText = preferences.remoteVoiceServer.address?.baseURL.absoluteString ?? ""
    }

    func select(_ newSelection: VoiceSelection) {
        guard newSelection != selection else { return }
        selection = newSelection
        readingSession.setVoiceSelection(newSelection)
    }

    func setRate(multiplier: Double) {
        let newRate = SpeechRate(multiplier)
        guard newRate != rate else { return }
        rate = newRate
        readingSession.setRate(newRate)
    }

    func setContinuous(_ on: Bool) {
        isContinuous = on
        readingSession.setReadingMode(on ? .continuous : .paragraph)
    }

    /// Pauses the reading, if any, so two voices never overlap, then previews the voice the
    /// selection resolves to.
    func preview() {
        readingSession.pause()
        previewer.preview(readingSession.voice(for: selection), rate: rate)
    }

    func downloadVoices() {
        VoiceDownloads.openSystemSettings()
    }

    // MARK: - Voice server

    /// The hint under the URL field, or nil when the text is a valid address. An empty field
    /// shows no hint while the server is off.
    var urlValidationMessage: String? {
        if serverURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !server.enabled {
            return nil
        }
        do {
            _ = try RemoteVoiceServerAddress(validating: serverURLText)
            return nil
        } catch {
            return RemoteVoicePresenter.validationMessage(error)
        }
    }

    var connectionStatusText: String? {
        connectionTest.map(RemoteVoicePresenter.connectionStatus)
    }

    /// The server voices to choose from, plus the chosen one when the server does not list it
    /// (for example while it is unreachable), so the picker always shows the selection.
    var remoteVoiceChoices: [VoiceDescriptor] {
        guard case .voice(let id) = server.voice, !remoteVoices.contains(where: { $0.id == id }) else {
            return remoteVoices
        }
        return remoteVoices + [RemoteVoiceCatalog.descriptor(forVoiceID: id)]
    }

    /// For example "Dora — Spanish"; the name alone for a voice of unknown language, which
    /// `RemoteVoiceCatalog` tags "und".
    func label(for voice: VoiceDescriptor) -> String {
        guard voice.language != "und" else { return voice.name }
        return "\(voice.name) — \(VoiceLanguageNames.name(for: voice.language))"
    }

    func setServerEnabled(_ on: Bool) {
        var config = configWithURLText()
        config.enabled = on
        apply(config)
    }

    /// Stores the URL field's address: a valid one, or none while the text does not validate.
    func commitServerURL() {
        apply(configWithURLText())
    }

    func selectRemoteVoice(_ newSelection: VoiceSelection) {
        var config = server
        config.voice = newSelection
        apply(config)
    }

    /// Applies the URL field, then asks the server for its voices and shows the outcome; it
    /// sends nothing when the field does not hold a valid address.
    func testConnection() {
        commitServerURL()
        guard server.address != nil else {
            connectionTest = .invalidAddress
            return
        }
        connectionTest = .checking
        let address = server.address
        Task { [weak self] in
            guard let result = await self?.remoteVoice.probeNow() else { return }
            // A newer address was applied meanwhile; its own test, if any, reports.
            guard let self, self.server.address == address else { return }
            switch result {
            case .success(let latency): self.connectionTest = .available(latency: latency)
            case .failure(let error): self.connectionTest = .failed(error)
            }
            self.refresh()
        }
    }

    private func configWithURLText() -> RemoteVoiceServerConfig {
        var config = server
        config.address = try? RemoteVoiceServerAddress(validating: serverURLText)
        return config
    }

    private func apply(_ config: RemoteVoiceServerConfig) {
        guard config != server else { return }
        if config.address != server.address {
            connectionTest = nil
        }
        server = config
        readingSession.setRemoteVoiceServer(config)
        refresh()
    }
}
