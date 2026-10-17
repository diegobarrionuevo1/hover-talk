import AppKit
import HoverTalkCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let trustPollInterval: TimeInterval = 2
    /// The longest any AX call may wait for an app, so a hung app cannot stall the picker.
    private static let axMessagingTimeout: Float = 0.25

    private var statusItem: NSStatusItem?
    private let statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var trustPollTimer: Timer?
    private var readingSession: ReadingSession?
    private var picker: PickerController?
    private var pickerHotkey: GlobalHotkey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        TerminalAXSource.setMessagingTimeout(seconds: Self.axMessagingTimeout)

        let session = ReadingSession(player: Player(engine: AVSpeechEngine()), controller: ControllerPanel())
        readingSession = session
        let picker = PickerController(readingSession: session)
        picker.onNeedsAccessibility = { [weak self] in
            self?.pickerNeedsAccessibility()
        }
        self.picker = picker
        pickerHotkey = GlobalHotkey(.pickText) { [weak self] in
            self?.picker?.toggle()
        }

        installStatusItem()

        let presentation = AccessibilityPresenter.presentation(for: AccessibilityPermission.currentStatus())
        apply(presentation)
        // Only the system prompt at launch; the app's explanation stays in the status line.
        if presentation.requestsSystemPrompt {
            AccessibilityPermission.requestWithSystemPrompt()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopPolling()
        pickerHotkey?.unregister()
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
        // Without auto-enabling, `apply(_:)` decides whether the status line is enabled and the
        // other items keep their default enabled state.
        menu.autoenablesItems = false

        let pickItem = NSMenuItem(
            title: AppCopy.pickTextMenuTitle(for: pickerHotkey == nil ? nil : .pickText),
            action: #selector(pickText),
            keyEquivalent: ""
        )
        pickItem.target = self
        menu.addItem(pickItem)
        menu.addItem(.separator())

        statusMenuItem.target = self
        statusMenuItem.action = #selector(showAccessibilityExplanation)
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
        // Manual audio and controller check without a text provider. Not in release builds.
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
        statusMenuItem.isEnabled = presentation.statusOpensExplanation
        if presentation.keepsPolling {
            startPolling()
        } else {
            stopPolling()
        }
    }

    @objc private func pickText() {
        picker?.toggle()
    }

    // MARK: - Trust polling

    private func startPolling() {
        guard trustPollTimer == nil else { return }
        let timer = Timer(timeInterval: Self.trustPollInterval, repeats: true) { [weak self] _ in
            // The timer is added to the main run loop below, so the block runs on the main thread.
            MainActor.assumeIsolated {
                self?.recheckTrust()
            }
        }
        timer.tolerance = 0.5
        // `.common` keeps the timer firing while the status menu (event-tracking mode) or an
        // alert (modal-panel mode) is open.
        RunLoop.main.add(timer, forMode: .common)
        trustPollTimer = timer
    }

    private func stopPolling() {
        trustPollTimer?.invalidate()
        trustPollTimer = nil
    }

    /// Polling stops once trust is granted, so a later revocation is only noticed when an AX
    /// read or the picker's input capture fails; this re-check then updates the status line
    /// and restarts polling.
    private func recheckTrust() {
        apply(AccessibilityPresenter.presentation(for: AccessibilityPermission.currentStatus()))
    }

    private func pickerNeedsAccessibility() {
        recheckTrust()
        // Shown from a later main-actor turn: this may run inside the hotkey's Carbon event
        // handler, and the alert runs a modal loop until it is dismissed.
        Task { @MainActor [weak self] in
            self?.showAccessibilityAlert(message: AppCopy.pickerNeedsAccessibilityMessage)
        }
    }

    // MARK: - Explanation

    @objc private func showAccessibilityExplanation() {
        showAccessibilityAlert(message: AppCopy.onboardingMessage)
    }

    private func showAccessibilityAlert(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = AppCopy.onboardingTitle
        alert.informativeText = message
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
