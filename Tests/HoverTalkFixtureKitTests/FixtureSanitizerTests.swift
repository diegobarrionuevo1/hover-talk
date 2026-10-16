import Testing
@testable import HoverTalkFixtureKit

/// Letters become "x" and ASCII digits "9"; every other character is kept. Two texts with the
/// same shape differ only in which letters and digits they contain.
private func shape(_ text: String) -> String {
    String(text.map { character -> Character in
        if character.isLetter { return "x" }
        if ("0"..."9").contains(character) { return "9" }
        return character
    })
}

private func words(_ text: String) -> [String] {
    text.split(whereSeparator: { !$0.isLetter }).map(String.init)
}

@Suite("FixtureSanitizer")
struct FixtureSanitizerTests {
    private let sanitizer = FixtureSanitizer(salt: 0x5EED)

    @Test("Letter runs become words of the same length; everything else is kept verbatim")
    func keepsShape() {
        let input = "  ┃  Hello, World! — ✓ ⠸ ╹▀▀▀ │ 🚀 done:   "
        let output = sanitizer.sanitize(input)

        #expect(shape(output) == shape(input))
        #expect(output.hasSuffix(":   "))
        for word in ["Hello", "World", "done"] {
            #expect(!output.localizedCaseInsensitiveContains(word))
        }
    }

    @Test("The same word gets the same replacement within one capture, whatever its case")
    func repetition() {
        let output = words(sanitizer.sanitize("alpha beta alpha ALPHA Alpha"))

        #expect(output.count == 5)
        #expect(output[0] == output[2])
        #expect(output[3] == output[0].uppercased())
        #expect(output[4] == output[0].prefix(1).uppercased() + output[0].dropFirst())
    }

    @Test("The case pattern is kept letter by letter")
    func casePattern() {
        let output = words(sanitizer.sanitize("HELLO Hello hello hELLo"))

        #expect(output[0] == output[0].uppercased())
        #expect(output[1].first?.isUppercase == true && output[1].dropFirst() == output[1].dropFirst().lowercased())
        #expect(output[2] == output[2].lowercased())
        #expect(output[3].map(\.isUppercase) == [false, true, true, true, false])
    }

    @Test("Accented letters, including decomposed ones, count as one letter each")
    func accentedLetters() {
        let input = "canción ñandú Über cafe\u{301}"
        let output = sanitizer.sanitize(input)

        #expect(words(output).map(\.count) == [7, 5, 4, 4])
        let allASCII = output.unicodeScalars.allSatisfy(\.isASCII)
        #expect(allASCII)
        #expect(words(output)[2].first?.isUppercase == true)
    }

    @Test("Allowlisted chrome words are kept verbatim, case-insensitively")
    func allowlist() {
        let input = "esc interrupt · tab agents · OpenCode · Claude Code · BASH zsh fish tmux · tokens"
        #expect(sanitizer.sanitize(input) == input)
    }

    @Test("Allowlist entries are lowercase letter runs, the only form that can match")
    func allowlistEntries() {
        for word in ChromeAllowlist.words {
            #expect(!word.isEmpty && word.allSatisfy { $0.isLetter && $0.isLowercase })
        }
    }

    @Test("Allowlisted words inside longer words are not kept")
    func allowlistWholeWordsOnly() {
        let output = sanitizer.sanitize("escape tokenless rebuild")

        #expect(!output.contains("esc"))
        #expect(!output.contains("token"))
        #expect(!output.contains("build"))
        #expect(shape(output) == "xxxxxx xxxxxxxxx xxxxxxx")
    }

    @Test("Every digit changes, and a repeated number gets the same replacement")
    func digits() {
        let input = "$1.25 (45%) 2026-10-16 45"
        let output = sanitizer.sanitize(input)

        #expect(shape(output) == shape(input))
        for (original, replaced) in zip(input, output) where original.isNumber {
            #expect(original != replaced)
        }
        let numbers = output.split(whereSeparator: { !$0.isNumber })
        #expect(numbers[2] == numbers[6])
    }

    @Test("Non-ASCII decimal digits become one ASCII digit")
    func nonASCIIDigit() {
        let output = sanitizer.sanitize("[\u{0663}]")

        #expect(output.count == 3)
        #expect(output != "[3]")
        #expect(("0"..."9").contains(Array(output)[1]))
    }

    @Test("A word or digit is never replaced by itself, whatever the salt")
    func neverIdentity() {
        let digits = "0123456789"
        for salt in UInt64(0)..<64 {
            let sanitizer = FixtureSanitizer(salt: salt)
            #expect(sanitizer.sanitize("river") != "river")
            #expect(sanitizer.sanitize("a") != "a")
            for (original, replaced) in zip(digits, sanitizer.sanitize(digits)) {
                #expect(original != replaced)
            }
        }
    }

    @Test("Words longer than the longest neutral word keep their length")
    func longWords() {
        let input = "Supercalifragilisticexpialidocious"
        let output = sanitizer.sanitize(input)

        #expect(output.count == input.count)
        #expect(shape(output) == shape(input))
        #expect(output.first?.isUppercase == true)
        #expect(output != input)
    }

    @Test("Different salts give different replacements")
    func saltMatters() {
        let input = "the quick brown fox jumps over the lazy dog 12345"

        #expect(FixtureSanitizer(salt: 1).sanitize(input) != FixtureSanitizer(salt: 2).sanitize(input))
    }
}

@Suite("NeutralWords")
struct NeutralWordsTests {
    @Test("Every bucket holds at least two lowercase ASCII words of its length")
    func buckets() {
        for (index, bucket) in NeutralWords.byLength.enumerated() {
            #expect(bucket.count >= 2)
            for word in bucket {
                #expect(word.count == index + 1)
                #expect(word.allSatisfy { ("a"..."z").contains($0) })
            }
        }
    }

    @Test("Generated words have the requested length and are never allowlisted chrome words")
    func generated() {
        for length in 1...40 {
            for seed in UInt64(0)..<32 {
                let word = NeutralWords.word(length: length, seed: seed &* 0x9E37_79B9_7F4A_7C15)
                #expect(word.count == length)
                #expect(!ChromeAllowlist.words.contains(word))
            }
        }
    }
}
