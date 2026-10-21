import HoverTalkCore
import os

/// Picker diagnostics in the unified log. They hold only reason codes, AX error raw values,
/// `AXRole` strings, `AXIsProcessTrusted()` results and bundle identifiers, never screen text,
/// titles or values, so only those are marked `.public`. Entries use the default (notice) level
/// or above, which `log show` keeps. Read them with:
///
///     log show --last 10m --predicate 'subsystem == "io.github.hovertalk.HoverTalk"'
///
/// The subsystem is the bundle identifier `scripts/bundle.sh` sets by default.
enum PickerLog {
    private static let logger = Logger(subsystem: "io.github.hovertalk.HoverTalk", category: "picker")

    static func pickerStarted(session: Int) {
        logger.notice("picker started, session \(session, privacy: .public)")
    }

    static func pickerStopped(session: Int) {
        logger.notice("picker stopped, session \(session, privacy: .public)")
    }

    /// Whether `CGEvent.tapCreate` returned a tap.
    static func inputCapture(created: Bool) {
        if created {
            logger.notice("input capture started: CGEvent.tapCreate returned a tap")
        } else {
            logger.error("input capture refused: CGEvent.tapCreate returned nil")
        }
    }

    /// A lookup that read nothing at the point; `bundleID` is the app under the point, if known.
    static func lookupFailed(_ failure: TerminalAXSource.Failure, bundleID: String?) {
        let app = bundleID ?? "unknown"
        switch failure {
        case .notTrusted:
            logger.error("lookup failed: notTrusted (AXIsProcessTrusted false), app \(app, privacy: .public)")
        case let .hitTestFailed(axError):
            logger.notice("lookup failed: hitTestFailed, AX error \(axError, privacy: .public), app \(app, privacy: .public)")
        case .noElement:
            logger.notice("lookup failed: noElement, app \(app, privacy: .public)")
        case let .notATextArea(role):
            logger.notice("lookup failed: notATextArea, role \(role ?? "none", privacy: .public), app \(app, privacy: .public)")
        case .noFrame:
            logger.notice("lookup failed: noFrame, app \(app, privacy: .public)")
        }
    }

    /// Right before the alert for `reason` shows, with `AXIsProcessTrusted()` checked then.
    static func unavailableAlert(_ reason: PickerUnavailableReason, isTrusted: Bool) {
        logger.error("picker unavailable alert: \(reason.rawValue, privacy: .public), AXIsProcessTrusted \(isTrusted, privacy: .public)")
    }

    /// The AXError raw values of asking an app for its web accessibility tree (0 is success).
    static func webAccessibilityRequested(results: [Int32]) {
        logger.notice("web accessibility requested, AX errors \(results.map(String.init).joined(separator: ","), privacy: .public)")
    }
}
