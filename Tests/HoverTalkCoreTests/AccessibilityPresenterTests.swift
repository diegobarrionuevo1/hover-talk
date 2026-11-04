import Foundation
import Testing
@testable import HoverTalkCore

@Suite("AccessibilityStatus")
struct AccessibilityStatusTests {
    @Test("A trusted process maps to granted")
    func trustedMapsToGranted() {
        #expect(AccessibilityStatus(isTrusted: true) == .granted)
    }

    @Test("An untrusted process maps to notGranted")
    func untrustedMapsToNotGranted() {
        #expect(AccessibilityStatus(isTrusted: false) == .notGranted)
    }
}

@Suite("AccessibilityPresenter")
struct AccessibilityPresenterTests {
    @Test("Granted status shows an inert granted title, asks for no prompt, and stops polling")
    func grantedPresentation() {
        let presentation = AccessibilityPresenter.presentation(for: .granted)

        #expect(presentation.statusTitle == "Accessibility: Granted")
        #expect(presentation.statusOpensExplanation == false)
        #expect(presentation.requestsSystemPrompt == false)
        #expect(presentation.keepsPolling == false)
    }

    @Test("Not granted status offers the explanation from the status line, asks for the system prompt only, and keeps polling")
    func notGrantedPresentation() {
        let presentation = AccessibilityPresenter.presentation(for: .notGranted)

        #expect(presentation.statusTitle == "Accessibility: Not granted — Open Settings…")
        #expect(presentation.statusOpensExplanation == true)
        #expect(presentation.requestsSystemPrompt == true)
        #expect(presentation.keepsPolling == true)
    }

    @Test("The settings link opens the Accessibility pane of Privacy & Security")
    func settingsURL() {
        #expect(
            AccessibilityPresenter.settingsURL.absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }
}

@Suite("App copy")
struct AppCopyTests {
    @Test("The app name is defined in one place")
    func appName() {
        #expect(AppInfo.name == "HoverTalk")
    }

    @Test("The quit menu title uses the app name")
    func quitTitle() {
        #expect(AppCopy.quitMenuTitle == "Quit \(AppInfo.name)")
    }

    @Test("The open-settings menu title ends with an ellipsis")
    func openSettingsTitle() {
        #expect(AppCopy.openSettingsMenuTitle == "Open Accessibility Settings…")
    }

    @Test("The picker menu item shows its hotkey after two spaces, or no hotkey when it could not be registered")
    func pickTextTitle() {
        #expect(AppCopy.pickTextMenuTitle(for: .pickText) == "Pick Text to Read  ⌃⌥R")
        #expect(AppCopy.pickTextMenuTitle(for: nil) == "Pick Text to Read")
        #expect(AppCopy.readSelectionMenuTitle(for: .readSelection) == "Read Selection  ⌃⌥S")
        #expect(AppCopy.readAllMenuTitle(for: .readAll) == "Read All  ⌃⌥A")
        #expect(AppCopy.readAllMenuTitle(for: nil) == "Read All")
    }

    @Test("The picker's permission message says where to grant it and how to fix an outdated grant")
    func pickerNeedsAccessibilityCopy() {
        #expect(AppCopy.pickerNeedsAccessibilityMessage.contains("Privacy & Security > Accessibility"))
        // Observed 2026-10-20: toggling did not help after a rebuild; removing and re-adding did.
        #expect(AppCopy.pickerNeedsAccessibilityMessage.contains("remove it with the minus button"))
        #expect(AppCopy.pickerNeedsAccessibilityMessage.contains("add it again"))
    }

    @Test("The input-capture message says capture could not start with the permission on, suggests reopening first, then re-adding the app")
    func pickerInputCaptureRefusedCopy() {
        let message = AppCopy.pickerInputCaptureRefusedMessage

        #expect(AppCopy.pickerInputCaptureRefusedTitle == "\(AppInfo.name) could not start picking")
        #expect(message.contains("capture clicks and Esc"))
        // Shown only when `AXIsProcessTrusted()` is true, so it must not claim the permission is missing.
        #expect(message.contains("even though the Accessibility permission is on"))
        #expect(!message.contains("needs the Accessibility permission"))
        #expect(message.contains("Quit \(AppInfo.name) and open it again"))
        #expect(message.contains("Privacy & Security > Accessibility"))
        #expect(message.contains("remove it with the minus button"))
        #expect(message.contains("add it again"))
        #expect(message.contains("Input Monitoring"))
    }

    @Test("Onboarding names the app, explains the purpose, and says nothing leaves the Mac unless the user sets up a voice server")
    func onboardingCopy() {
        #expect(AppCopy.onboardingTitle.contains(AppInfo.name))
        #expect(AppCopy.onboardingMessage.contains("text under the pointer"))
        #expect(AppCopy.onboardingMessage.contains("no telemetry"))
        #expect(AppCopy.onboardingMessage.contains("Nothing leaves your Mac unless you set up your own voice server"))
        #expect(!AppCopy.onboardingMessage.contains("no network calls"))
        #expect(AppCopy.onboardingOpenSettingsButton == "Open System Settings")
        #expect(AppCopy.onboardingLaterButton == "Later")
    }

    @Test("The voice server settings state what is sent and name the setup guide")
    func voiceServerCopy() {
        #expect(AppCopy.voiceServerPrivacyNote == "The text being read is sent to this server. Nothing else is sent.")
        #expect(AppCopy.voiceServerToggleTitle == "Use my voice server when it is available")
        #expect(AppCopy.voiceServerURLPlaceholder == "http://192.168.1.50:8880")
        #expect(AppCopy.testConnectionButton == "Test Connection")
        #expect(AppCopy.voiceServerGuide.contains("docs/voice-server.md"))
    }
}
