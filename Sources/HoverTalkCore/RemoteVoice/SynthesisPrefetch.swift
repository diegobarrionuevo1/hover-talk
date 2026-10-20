/// One synthesis on the voice server: a text and the server voice that speaks it. The rate is
/// not part of it, because speech is always requested at normal speed
/// (`RemoteVoiceRequests.speechRequest`).
public struct SynthesisKey: Hashable, Sendable {
    public let text: String
    /// The server's voice name, for example "ef_dora".
    public let voice: String

    public init(text: String, voice: String) {
        self.text = text
        self.voice = voice
    }
}

/// Which syntheses a speech engine keeps: the current sentence and the next `upcomingLimit`
/// sentences, nothing else.
public enum SynthesisPrefetch {
    public static let upcomingLimit = 2

    public struct Plan: Equatable, Sendable {
        /// Syntheses to start, in reading order.
        public let start: [SynthesisKey]
        /// Cached syntheses to cancel and forget.
        public let drop: Set<SynthesisKey>
    }

    /// `cached` holds the syntheses started so far, `current` the one being spoken (nil when
    /// nothing is), and `upcoming` the following sentences in order.
    public static func plan(cached: Set<SynthesisKey>, current: SynthesisKey?, upcoming: [SynthesisKey]) -> Plan {
        var keep: Set<SynthesisKey> = current.map { [$0] } ?? []
        var start: [SynthesisKey] = []
        for key in upcoming.prefix(upcomingLimit) where keep.insert(key).inserted {
            if !cached.contains(key) {
                start.append(key)
            }
        }
        return Plan(start: start, drop: cached.subtracting(keep))
    }
}
