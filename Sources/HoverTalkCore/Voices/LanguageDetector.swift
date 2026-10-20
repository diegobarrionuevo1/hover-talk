import Foundation
import NaturalLanguage

/// Finds the language a text is written in, with `NLLanguageRecognizer`.
public struct LanguageDetector: Sendable {
    /// Below this probability the top hypothesis counts as unknown: on macOS 26.2 "OK." scores
    /// Polish at 0.29, while a plain sentence scores about 0.98.
    public static let minimumConfidence = 0.5
    /// Only the first this many Characters are examined, which bounds the cost for long readings.
    public static let sampleLength = 2_000

    public init() {}

    /// The dominant language of `text` as a BCP-47 code such as "es", "en" or "zh-Hans"; nil
    /// when the recognizer finds none or its best guess is below `minimumConfidence`.
    public func language(of text: String) -> String? {
        // NLLanguageRecognizer is not Sendable, so each call creates its own instance.
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(Self.sampleLength)))
        guard let best = recognizer.languageHypotheses(withMaximum: 1).max(by: { $0.value < $1.value }),
              best.value >= Self.minimumConfidence
        else { return nil }
        return best.key.rawValue
    }
}
