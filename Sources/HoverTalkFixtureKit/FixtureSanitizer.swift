/// Replaces private screen text with neutral text of the same shape.
///
/// - Each maximal run of letters (Unicode categories L*, counted in Characters, so combining
///   marks stay with their letter) becomes a `NeutralWords` word of the same length, with the
///   case of each letter copied over. Runs equal to a `ChromeAllowlist` word, ignoring case,
///   are kept.
/// - Each decimal digit becomes a different ASCII digit.
/// - Every other Character is kept verbatim.
///
/// Replacements are derived from a keyed hash of the run (FNV-1a plus a SplitMix64 mix, not a
/// cryptographic MAC) and a random salt held only in this value, so the same run maps to the
/// same replacement within one capture. Recovery is limited by what a replacement keeps: a
/// word keeps its length, its case pattern and a few hash-picked bucket indices; a digit keeps
/// only the fact that it differs from its replacement.
public struct FixtureSanitizer: Sendable {
    private let salt: UInt64

    /// A sanitizer with a fresh random salt. Use one instance per capture.
    public init() {
        self.init(salt: UInt64.random(in: .min ... .max))
    }

    init(salt: UInt64) {
        self.salt = salt
    }

    public func sanitize(_ text: String) -> String {
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let kind = Self.kind(of: text[index])
            guard kind != .other else {
                result.append(text[index])
                index = text.index(after: index)
                continue
            }
            var end = text.index(after: index)
            while end < text.endIndex, Self.kind(of: text[end]) == kind {
                end = text.index(after: end)
            }
            let run = text[index..<end]
            result += kind == .letter ? replacement(forWord: run) : replacement(forDigits: run)
            index = end
        }
        return result
    }

    private enum Kind { case letter, digit, other }

    private static func kind(of character: Character) -> Kind {
        guard let scalar = character.unicodeScalars.first else { return .other }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
            return .letter
        case .decimalNumber:
            return .digit
        default:
            return .other
        }
    }

    private func replacement(forWord word: Substring) -> String {
        let key = word.lowercased()
        if ChromeAllowlist.words.contains(key) { return String(word) }

        let seed = keyedHash("w:" + key)
        var neutral = NeutralWords.word(length: word.count, seed: seed)
        if neutral == key {
            neutral = NeutralWords.word(length: word.count, seed: seed ^ 1)
        }
        var result = ""
        for (original, replacement) in zip(word, neutral) {
            result += original.isUppercase ? replacement.uppercased() : String(replacement)
        }
        return result
    }

    private func replacement(forDigits run: Substring) -> String {
        var state = keyedHash("d:" + run)
        var result = ""
        for character in run {
            state = NeutralWords.mix(state)
            let value = character.unicodeScalars.first?.properties.numericValue.map { Int($0) } ?? 0
            // An offset of 1...9 guarantees the digit changes.
            result += String((value + 1 + Int(state % 9)) % 10)
        }
        return result
    }

    /// FNV-1a over the salt and the key's UTF-8 bytes, then mixed.
    private func keyedHash(_ key: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        let bytes = withUnsafeBytes(of: salt.littleEndian, Array.init) + Array(key.utf8)
        for byte in bytes {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        return NeutralWords.mix(hash)
    }
}
