import Testing
@testable import HoverTalkCore

@Suite("PickerUnavailableReason")
struct PickerUnavailableReasonTests {
    @Test("Input capture refused while the process is trusted is not reported as a missing permission")
    func refusedWhileTrusted() {
        #expect(PickerUnavailableReason(inputCaptureRefusedWith: .granted) == .inputCaptureRefused)
    }

    @Test("Input capture refused while the process is not trusted is the missing permission")
    func refusedWhileNotTrusted() {
        #expect(PickerUnavailableReason(inputCaptureRefusedWith: .notGranted) == .notTrusted)
    }
}

@Suite("PickerUnavailablePresenter")
struct PickerUnavailablePresenterTests {
    @Test("A missing permission keeps the Accessibility alert")
    func notTrustedPresentation() {
        let presentation = PickerUnavailablePresenter.presentation(for: .notTrusted)

        #expect(presentation.title == AppCopy.onboardingTitle)
        #expect(presentation.message == AppCopy.pickerNeedsAccessibilityMessage)
    }

    @Test("Refused input capture explains that capture could not start, not that the permission is missing")
    func inputCaptureRefusedPresentation() {
        let presentation = PickerUnavailablePresenter.presentation(for: .inputCaptureRefused)

        #expect(presentation.title == AppCopy.pickerInputCaptureRefusedTitle)
        #expect(presentation.message == AppCopy.pickerInputCaptureRefusedMessage)
        #expect(presentation.title != AppCopy.onboardingTitle)
        #expect(presentation.message != AppCopy.pickerNeedsAccessibilityMessage)
    }
}
