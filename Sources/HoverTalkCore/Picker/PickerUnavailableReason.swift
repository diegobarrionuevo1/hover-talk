/// Why picking stopped or could not start, and so which alert the app shows. A lookup that finds
/// nothing readable under the pointer is not one of these: the app's `PickerController` shows no
/// outline then and picking goes on.
public enum PickerUnavailableReason: String, Equatable, Sendable {
    /// The process lacks the Accessibility permission: `AXIsProcessTrusted()` returned false.
    case notTrusted
    /// macOS refused the input capture (`CGEvent.tapCreate` returned `nil`) while the process
    /// held the Accessibility permission.
    case inputCaptureRefused

    /// Why input capture could not start, given the permission status checked right after the
    /// refusal: only a missing permission is reported as `notTrusted`.
    public init(inputCaptureRefusedWith status: AccessibilityStatus) {
        switch status {
        case .granted: self = .inputCaptureRefused
        case .notGranted: self = .notTrusted
        }
    }
}

/// The alert's title and message for a `PickerUnavailableReason`.
public struct PickerUnavailablePresentation: Equatable, Sendable {
    public let title: String
    public let message: String

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }
}

public enum PickerUnavailablePresenter {
    public static func presentation(for reason: PickerUnavailableReason) -> PickerUnavailablePresentation {
        switch reason {
        case .notTrusted:
            PickerUnavailablePresentation(title: AppCopy.onboardingTitle, message: AppCopy.pickerNeedsAccessibilityMessage)
        case .inputCaptureRefused:
            PickerUnavailablePresentation(title: AppCopy.pickerInputCaptureRefusedTitle, message: AppCopy.pickerInputCaptureRefusedMessage)
        }
    }
}
