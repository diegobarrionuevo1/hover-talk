import AppKit
import HoverTalkCore
import SwiftUI

/// Owns the Settings window, created on first use and kept (not released) when closed.
@MainActor
final class SettingsWindowController {
    private let model: SettingsModel
    private let voices: SystemVoiceProvider
    private var window: NSWindow?

    init(model: SettingsModel, voices: SystemVoiceProvider) {
        self.model = model
        self.voices = voices
    }

    /// Reads the voice list again (voices may have been downloaded meanwhile), then shows the
    /// window in front, centered the first time.
    func show() {
        voices.refresh()
        model.refresh()
        let window = self.window ?? makeWindow()
        // An accessory app is not frontmost by default; activate so the window gets focus.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Shows values changed elsewhere (controller, menu, voice downloads) while the window is open.
    func refresh() {
        model.refresh()
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = AppCopy.settingsWindowTitle
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        return window
    }
}
