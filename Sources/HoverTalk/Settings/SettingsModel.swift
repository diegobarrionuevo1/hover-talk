import Foundation
import HoverTalkCore
import Observation

/// What the Settings window shows, read from `Preferences` and the voice list by `refresh()`.
/// Every change goes through `ReadingSession`, which stores it and applies it to the player.
@MainActor
@Observable
final class SettingsModel {
    private(set) var catalog = VoiceCatalog(voices: [], preferredLanguages: [])
    private(set) var selection = VoiceSelection.default
    private(set) var rate = SpeechRate.default
    private(set) var isContinuous = ReadingMode.default == .continuous
    var query = ""

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let voices: SystemVoiceProvider
    @ObservationIgnored private let readingSession: ReadingSession
    @ObservationIgnored private let previewer = VoicePreviewer()

    init(preferences: Preferences, voices: SystemVoiceProvider, readingSession: ReadingSession) {
        self.preferences = preferences
        self.voices = voices
        self.readingSession = readingSession
        refresh()
    }

    /// The catalog groups that match `query`.
    var groups: [VoiceGroup] {
        catalog.groups(matching: query, languageName: VoiceLanguageNames.name(for:))
    }

    /// Reads the current voice list (without asking the system again), voice selection, rate
    /// and reading mode.
    func refresh() {
        catalog = voices.catalog()
        selection = preferences.voiceSelection
        rate = preferences.speechRate
        isContinuous = preferences.readingMode == .continuous
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
}
