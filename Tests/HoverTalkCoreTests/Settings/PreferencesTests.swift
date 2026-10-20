import Testing
@testable import HoverTalkCore

@MainActor
@Suite("Preferences")
struct PreferencesTests {
    @Test("Continuous reading is the default while nothing is stored")
    func defaultsToContinuous() {
        #expect(Preferences(storage: InMemorySettingsStorage()).readingMode == .continuous)
        #expect(ReadingMode.default == .continuous)
    }

    @Test("A reading mode that is set is stored and read back by later preferences on the same storage")
    func persistsReadingMode() {
        let storage = InMemorySettingsStorage()
        let preferences = Preferences(storage: storage)

        preferences.readingMode = .paragraph

        #expect(preferences.readingMode == .paragraph)
        #expect(storage.string(forKey: Preferences.readingModeKey) == "paragraph")
        #expect(Preferences(storage: storage).readingMode == .paragraph)
        preferences.readingMode = .continuous
        #expect(Preferences(storage: storage).readingMode == .continuous)
    }

    @Test("A stored value this version does not know reads as the default")
    func unknownValue() {
        let storage = InMemorySettingsStorage()
        storage.setString("sideways", forKey: Preferences.readingModeKey)

        #expect(Preferences(storage: storage).readingMode == .continuous)
    }

    @Test("Toggling switches between the two modes")
    func toggled() {
        #expect(ReadingMode.continuous.toggled == .paragraph)
        #expect(ReadingMode.paragraph.toggled == .continuous)
    }

    @Test("The menu item that toggles continuous reading")
    func menuTitle() {
        #expect(AppCopy.continueReadingMenuTitle == "Continue Reading Below")
    }
}
