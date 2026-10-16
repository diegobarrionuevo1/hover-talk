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
    @Test("Granted status shows the granted title, no onboarding, and stops polling")
    func grantedPresentation() {
        let presentation = AccessibilityPresenter.presentation(for: .granted)

        #expect(presentation.statusTitle == "Accessibility: Granted")
        #expect(presentation.showsOnboarding == false)
        #expect(presentation.keepsPolling == false)
    }

    @Test("Not granted status shows the not-granted title, onboarding, and keeps polling")
    func notGrantedPresentation() {
        let presentation = AccessibilityPresenter.presentation(for: .notGranted)

        #expect(presentation.statusTitle == "Accessibility: Not granted")
        #expect(presentation.showsOnboarding == true)
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

    @Test("Onboarding names the app, explains the purpose, and states that nothing leaves the Mac")
    func onboardingCopy() {
        #expect(AppCopy.onboardingTitle.contains(AppInfo.name))
        #expect(AppCopy.onboardingMessage.contains("text under the pointer"))
        #expect(AppCopy.onboardingMessage.contains("Nothing leaves your Mac"))
        #expect(AppCopy.onboardingOpenSettingsButton == "Open System Settings")
        #expect(AppCopy.onboardingLaterButton == "Later")
    }
}
