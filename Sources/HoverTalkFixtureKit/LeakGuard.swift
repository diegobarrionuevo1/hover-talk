import Foundation

/// Last check before a fixture is written: finds identifying terms that survived sanitizing.
/// Matching ignores case and diacritics. Empty terms are skipped.
public struct LeakGuard: Sendable {
    /// What leaked. The raw value names the kind of term, never the term itself.
    public enum Term: String, Sendable, Equatable {
        case userName = "the user name"
        case fullNamePart = "a part of the full name"
        case hostName = "the host name"
        case homeDirectory = "the home directory path"
    }

    private let terms: [(kind: Term, value: String)]

    /// - Parameters:
    ///   - fullName: split on every non-alphanumeric character; parts shorter than 3 are skipped.
    ///   - hostName: checked whole and as its first label (the part before the first dot).
    public init(userName: String, fullName: String, hostName: String, homeDirectory: String) {
        let nameParts = fullName
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 3 }
        let hostLabel = hostName.split(separator: ".").first.map(String.init) ?? ""
        let candidates: [(kind: Term, value: String)] =
            [(.userName, userName)]
            + nameParts.map { (.fullNamePart, $0) }
            + [(.hostName, hostName), (.hostName, hostLabel), (.homeDirectory, homeDirectory)]
        terms = candidates.filter { !$0.value.isEmpty }
    }

    public static func forCurrentUser() -> LeakGuard {
        var buffer = [CChar](repeating: 0, count: 256)
        let hostName = gethostname(&buffer, buffer.count - 1) == 0
            ? buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            : ProcessInfo.processInfo.hostName
        return LeakGuard(
            userName: NSUserName(),
            fullName: NSFullUserName(),
            hostName: hostName,
            homeDirectory: NSHomeDirectory()
        )
    }

    public func firstLeak(in text: String) -> Term? {
        terms.first { text.range(of: $0.value, options: [.caseInsensitive, .diacriticInsensitive]) != nil }?.kind
    }
}
