import Foundation

/// The general pasteboard as `SelectionCopy` needs it. The app implements it with `NSPasteboard`;
/// `Saved` is whatever it takes to put the previous contents back, items of every type included.
public protocol PasteboardAccess {
    associatedtype Saved
    /// Increases every time the contents change, including when they are restored.
    var changeCount: Int { get }
    func save() -> Saved
    func restore(_ saved: Saved)
    func text() -> String?
}

/// Gets the selected text of the focused app by asking it to copy: send Cmd+C, read the
/// pasteboard, put the user's clipboard back.
public enum SelectionCopy {
    /// Calls `sendCopy`, then polls the pasteboard every `interval` seconds, up to `timeout`,
    /// until its change count moves. Returns the copied text, or `nil` when nothing changed (no
    /// selection, or an app that does not copy) or the copy is only whitespace. The previous
    /// contents are restored whenever the pasteboard changed.
    ///
    /// `sleep` is injected so the wait is not real time in tests; each call counts as `interval`.
    public static func copiedText<P: PasteboardAccess>(
        from pasteboard: P,
        sendCopy: () -> Void,
        sleep: (TimeInterval) async -> Void,
        timeout: TimeInterval = 0.5,
        interval: TimeInterval = 0.02
    ) async -> String? {
        let before = pasteboard.changeCount
        let saved = pasteboard.save()
        sendCopy()
        var waited: TimeInterval = 0
        while pasteboard.changeCount == before, waited < timeout {
            await sleep(interval)
            waited += interval
        }
        guard pasteboard.changeCount != before else { return nil }
        let text = pasteboard.text()
        pasteboard.restore(saved)
        return text.flatMap { $0.allSatisfy(\.isWhitespace) ? nil : $0 }
    }
}

/// Picks where the selected text comes from.
public enum SelectionReader {
    /// The Accessibility selection when it has text; otherwise the result of `copy`, for apps
    /// such as terminals that expose no selected text.
    public static func read(axSelection: () -> String?, copy: () async -> String?) async -> String? {
        if let selected = axSelection(), !selected.allSatisfy(\.isWhitespace) { return selected }
        return await copy()
    }
}
