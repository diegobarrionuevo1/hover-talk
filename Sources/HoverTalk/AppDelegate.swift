import AppKit
import HoverTalkCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let trustPollInterval: TimeInterval = 2

    private var statusItem: NSStatusItem?
    private let statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var trustPollTimer: Timer?
    private var readingSession: ReadingSession?

    func applicationDidFinishLaunching(_ notification: Notification) {
        readingSession = ReadingSession(player: Player(engine: AVSpeechEngine()), controller: ControllerPanel())
        installStatusItem()

        let presentation = AccessibilityPresenter.presentation(for: AccessibilityPermission.currentStatus())
        apply(presentation)

        if presentation.showsOnboarding {
            AccessibilityPermission.requestWithSystemPrompt()
            showOnboardingAlert()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopPolling()
    }

    // MARK: - Status item and menu

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: AppInfo.name)
            image?.isTemplate = true
            button.image = image
            button.toolTip = AppInfo.name
        }

        let menu = NSMenu()
        // Without auto-enabling, the status line stays disabled and the other items keep
        // their default enabled state.
        menu.autoenablesItems = false

        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        let openSettingsItem = NSMenuItem(
            title: AppCopy.openSettingsMenuTitle,
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        openSettingsItem.target = self
        menu.addItem(openSettingsItem)

        #if DEBUG
        // Manual audio and controller check until a text provider exists. Not in release builds.
        let readClipboardItem = NSMenuItem(title: "Read Clipboard", action: #selector(readClipboard), keyEquivalent: "")
        readClipboardItem.target = self
        menu.addItem(readClipboardItem)
        #endif

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: AppCopy.quitMenuTitle,
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    private func apply(_ presentation: AccessibilityPresentation) {
        statusMenuItem.title = presentation.statusTitle
        if presentation.keepsPolling {
            startPolling()
        } else {
            stopPolling()
        }
    }

    // MARK: - Trust polling

    private func startPolling() {
        guard trustPollTimer == nil else { return }
        let timer = Timer(timeInterval: Self.trustPollInterval, repeats: true) { [weak self] _ in
            // The timer is added to the main run loop below, so the block runs on the main thread.
            MainActor.assumeIsolated {
                self?.pollTrust()
            }
        }
        timer.tolerance = 0.5
        // `.common` keeps the timer firing while the status menu (event-tracking mode) or the
        // onboarding alert (modal-panel mode) is open.
        RunLoop.main.add(timer, forMode: .common)
        trustPollTimer = timer
    }

    private func stopPolling() {
        trustPollTimer?.invalidate()
        trustPollTimer = nil
    }

    private func pollTrust() {
        apply(AccessibilityPresenter.presentation(for: AccessibilityPermission.currentStatus()))
    }

    // MARK: - Onboarding

    private func showOnboardingAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = AppCopy.onboardingTitle
        alert.informativeText = AppCopy.onboardingMessage
        alert.addButton(withTitle: AppCopy.onboardingOpenSettingsButton)
        alert.addButton(withTitle: AppCopy.onboardingLaterButton)

        // An accessory app is not frontmost by default; activate so the alert is visible.
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(AccessibilityPresenter.settingsURL)
    }

    #if DEBUG
    @objc private func readClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        readingSession?.read(text)
    }
    #endif
}
