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
    }

    @Test("The picker's permission message says where to grant it and how to fix an outdated grant")
    func pickerNeedsAccessibilityCopy() {
        #expect(AppCopy.pickerNeedsAccessibilityMessage.contains("Privacy & Security > Accessibility"))
        #expect(AppCopy.pickerNeedsAccessibilityMessage.contains("turn it off and on again"))
    }

    @Test("Onboarding names the app, explains the purpose, and states that nothing leaves the Mac")
    func onboardingCopy() {
        #expect(AppCopy.onboardingTitle.contains(AppInfo.name))
        #expect(AppCopy.onboardingMessage.contains("text under the pointer"))
        #expect(AppCopy.onboardingMessage.contains("Nothing leaves your Mac"))
        #expect(AppCopy.onboardingOpenSettingsButton == "Open System Settings")
        #expect(AppCopy.onboardingLaterButton == "Later")
    }
}
