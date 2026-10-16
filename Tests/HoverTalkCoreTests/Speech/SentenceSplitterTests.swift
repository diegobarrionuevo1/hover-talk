import Testing
@testable import HoverTalkCore

@Suite("SentenceSplitter")
struct SentenceSplitterTests {
    private let splitter = SentenceSplitter()

    @Test("English sentences split at terminal punctuation")
    func englishSentences() {
        #expect(
            splitter.split("The build finished. All tests passed! Shall we ship it?")
                == ["The build finished.", "All tests passed!", "Shall we ship it?"]
        )
    }

    @Test("Spanish questions and exclamations keep their opening marks")
    func spanishSentences() {
        #expect(
            splitter.split("¿Cómo estás hoy? ¡Muy bien, gracias! El informe está listo.")
                == ["¿Cómo estás hoy?", "¡Muy bien, gracias!", "El informe está listo."]
        )
    }

    @Test("Common English abbreviations do not end a sentence")
    func englishAbbreviations() {
        #expect(
            splitter.split("Dr. Smith reviewed the plan. Use a formatter, e.g. a linter, before merging.")
                == ["Dr. Smith reviewed the plan.", "Use a formatter, e.g. a linter, before merging."]
        )
    }

    @Test("Decimal numbers do not end a sentence")
    func decimals() {
        #expect(
            splitter.split("Version 3.5 is faster than 2.0 in most cases. La media fue 4,5 puntos.")
                == ["Version 3.5 is faster than 2.0 in most cases.", "La media fue 4,5 puntos."]
        )
    }

    @Test("Ellipses inside a sentence")
    func ellipses() {
        #expect(
            splitter.split("Wait... the job is still running. Esperá… ya casi termina.")
                == ["Wait... the job is still running.", "Esperá… ya casi termina."]
        )
    }

    @Test("Text without terminal punctuation is one sentence")
    func noTerminalPunctuation() {
        #expect(splitter.split("a note without any final punctuation") == ["a note without any final punctuation"])
    }

    @Test("Hard line breaks are boundaries, so list items become separate sentences")
    func lineBreaks() {
        let text = """
            Next steps
            - update the parser
            - add tests for the new cases
            1. revisar el informe
            2. enviar los cambios
            """
        #expect(
            splitter.split(text) == [
                "Next steps",
                "- update the parser",
                "- add tests for the new cases",
                "1. revisar el informe",
                "2. enviar los cambios",
            ]
        )
    }

    @Test("Several sentences on one line and a line break in the same text")
    func sentencesAndLineBreaks() {
        #expect(
            splitter.split("First point. Second point\nThird point.")
                == ["First point.", "Second point", "Third point."]
        )
    }

    @Test("Whitespace is trimmed and empty pieces are dropped")
    func trimsAndDropsEmpty() {
        #expect(splitter.split("   Hello there.   \n\n\t  \r\n   Hola de nuevo.  ") == ["Hello there.", "Hola de nuevo."])
    }

    @Test("Empty and whitespace-only text produce no sentences", arguments: ["", "   ", "\n\n", " \t \r\n "])
    func emptyText(text: String) {
        #expect(splitter.split(text).isEmpty)
    }
}

/// Boundaries decided by `NLTokenizer` itself. These record the tokenizer's observed behavior
/// so a change in a future macOS release shows up as a failing test.
@Suite("SentenceSplitter tokenizer behavior")
struct SentenceSplitterTokenizerBehaviorTests {
    private let splitter = SentenceSplitter()

    @Test("An ellipsis followed by a capitalized word")
    func ellipsisBeforeCapital() {
        #expect(splitter.split("Wait... The job is still running.") == ["Wait...", "The job is still running."])
    }

    @Test("A Spanish abbreviation before a name")
    func spanishAbbreviation() {
        #expect(
            splitter.split("El Sr. García llegó tarde. Luego habló.")
                == ["El Sr. García llegó tarde.", "Luego habló."]
        )
    }

    @Test("A Spanish question in the middle of a line")
    func spanishMidLineQuestion() {
        #expect(splitter.split("Hola, ¿qué tal? Bien, gracias.") == ["Hola, ¿qué tal?", "Bien, gracias."])
    }

    @Test("A sentence that ends with etc. before a new sentence")
    func etcAtEnd() {
        #expect(splitter.split("Bring pens, paper, etc. Then start the meeting.") == ["Bring pens, paper, etc.", "Then start the meeting."])
    }

    @Test("File names and version numbers do not end a sentence")
    func fileNamesAndVersions() {
        #expect(
            splitter.split("Open Package.swift and bump it to v1.2.3 first. Then run the tests.")
                == ["Open Package.swift and bump it to v1.2.3 first.", "Then run the tests."]
        )
    }

    @Test("A closing quote after the period stays with its sentence")
    func closingQuote() {
        #expect(splitter.split("She said \"it works.\" Then she left.") == ["She said \"it works.\"", "Then she left."])
    }

    // Observed: the tokenizer keeps a lowercase continuation in the same sentence. Navigation
    // then moves over a longer unit, which is acceptable.
    @Test("A lowercase word after a period does not start a new sentence")
    func lowercaseAfterPeriod() {
        #expect(splitter.split("it works. then we ship it.") == ["it works. then we ship it."])
    }

    @Test("A period without a following space")
    func periodWithoutSpace() {
        #expect(splitter.split("First part.Second part.") == ["First part.Second part."])
    }
}
