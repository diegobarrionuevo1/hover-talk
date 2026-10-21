import CoreGraphics
import Testing
@testable import HoverTalkCore

/// Synthetic trees modeled on the shapes Chromium and WebKit expose. No captured content.
private enum Trees {
    static func text(_ value: String, _ y: CGFloat, x: CGFloat = 20, width: CGFloat = 400) -> AXNode {
        AXNode(role: "AXStaticText", text: value, frame: CGRect(x: x, y: y, width: width, height: 18))
    }

    static func group(_ children: [AXNode], role: String = "AXGroup", subrole: String? = nil) -> AXNode {
        AXNode(role: role, subrole: subrole, children: children)
    }

    static func buttons(_ y: CGFloat) -> AXNode {
        group([
            AXNode(role: "AXButton", frame: CGRect(x: 20, y: y, width: 24, height: 24),
                   children: [text("Copy", y, width: 24)]),
            AXNode(role: "AXButton", frame: CGRect(x: 50, y: y, width: 24, height: 24),
                   children: [text("Retry", y, x: 50, width: 24)]),
        ])
    }

    /// A chat transcript: two answers with a heading, a list, a code block and a button row
    /// each, and an editable composer at the bottom.
    static let chat = AXNode(role: "AXWebArea", children: [
        group([text("Plan the trip.", 10)]),
        group([
            group([text("Alpha line one.", 40), AXNode(role: "AXLink", children: [text("link", 40, x: 140, width: 30)]), text("then more.", 40, x: 175, width: 80)]),
            AXNode(role: "AXHeading", children: [text("Steps", 70)]),
            AXNode(role: "AXList", children: [
                AXNode(role: "AXListItem", children: [text("First step.", 100)]),
                AXNode(role: "AXListItem", children: [text("Second step.", 120)]),
            ]),
            AXNode(role: "AXGroup", isCode: true, children: [text("let x = 1", 150)]),
            buttons(180),
        ]),
        group([
            group([text("Beta answer.", 220)]),
            buttons(250),
        ]),
        AXNode(role: "AXTextArea", text: "draft", frame: CGRect(x: 20, y: 300, width: 400, height: 40), isEditable: true),
        group([text("Gamma below composer.", 360)]),
    ])

    /// An article page with landmarks.
    static let article = AXNode(role: "AXWebArea", children: [
        group([text("Home", 5), text("News", 5, x: 80, width: 40)], subrole: "AXLandmarkBanner"),
        group([AXNode(role: "AXLink", children: [text("Sections", 30)])], subrole: "AXLandmarkNavigation"),
        AXNode(role: "AXHeading", children: [text("Title", 60)]),
        group([text("First paragraph", 90), AXNode(role: "AXLink", children: [text("with link", 90, x: 200, width: 60)]), text(".", 90, x: 260, width: 5)]),
        group([text("Second paragraph.", 120)]),
        group([text("Copyright line", 400)], subrole: "AXLandmarkContentInfo"),
    ])
}

@Suite("AXBlockReader")
struct AXBlockReaderTests {
    let reader = AXBlockReader()

    @Test("Blocks come in document order and skip buttons, landmarks of chrome and the composer")
    func chatBlocks() {
        let texts = reader.blocks(in: Trees.chat).map(\.text.text)
        #expect(texts == [
            "Plan the trip.",
            "Alpha line one. link then more.",
            "Steps",
            "First step.",
            "Second step.",
            "```\nlet x = 1\n```",
            "Beta answer.",
            "Gamma below composer.",
        ])
    }

    @Test("Inline links join their paragraph without doubled spaces and before punctuation")
    func articleBlocks() {
        let texts = reader.blocks(in: Trees.article).map(\.text.text)
        #expect(texts == ["Title", "First paragraph with link.", "Second paragraph."])
    }

    @Test("Every character is anchored to its node and offset")
    func anchors() throws {
        let block = try #require(reader.blocks(in: Trees.article).first { $0.text.text.hasPrefix("First") })
        let pairs = Array(block.text.elements)
        let firstW = try #require(pairs.first { $0.0 == "w" })
        #expect(firstW.1 == AXTextAnchor(path: [3, 1, 0], offset: 0))
        let firstF = try #require(pairs.first)
        #expect(firstF.1 == AXTextAnchor(path: [3, 0], offset: 0))
    }

    @Test("A block's rects are the frames of its text nodes")
    func rects() throws {
        let block = try #require(reader.blocks(in: Trees.chat).first { $0.text.text.hasPrefix("Alpha") })
        #expect(block.rects.count == 3)
        #expect(block.rects.allSatisfy { $0.minY == 40 })
    }

    @Test("Pointing at a paragraph returns it; pointing at a button returns nothing")
    func blockAtPoint() {
        #expect(reader.block(at: CGPoint(x: 60, y: 48), in: Trees.chat)?.text.text == "Alpha line one. link then more.")
        #expect(reader.block(at: CGPoint(x: 30, y: 190), in: Trees.chat) == nil)
        #expect(reader.block(at: CGPoint(x: 30, y: 320), in: Trees.chat) == nil)
    }

    @Test("A point just between lines snaps to the nearest block within 8 points")
    func nearestBlock() {
        #expect(reader.block(at: CGPoint(x: 60, y: 63), in: Trees.chat)?.text.text == "Alpha line one. link then more.")
        #expect(reader.block(at: CGPoint(x: 60, y: 210), in: Trees.chat) == nil)
    }

    @Test("Continuation reads down to the end of the message: its row of action buttons")
    func continuation() throws {
        let text = try #require(reader.continuation(from: CGPoint(x: 60, y: 102), in: Trees.chat)).text.text
        #expect(text == "First step.\nSecond step.\n```\nlet x = 1\n```")
    }

    @Test("Continuation stops at the composer when no action row comes first")
    func continuationStopsAtComposer() throws {
        let root = AXNode(role: "AXWebArea", children: [
            Trees.group([Trees.text("One.", 10)]),
            AXNode(role: "AXButton", children: [Trees.text("Lone button", 30)]),
            Trees.group([Trees.text("Two.", 50)]),
            AXNode(role: "AXTextArea", text: "x", frame: CGRect(x: 20, y: 80, width: 300, height: 30), isEditable: true),
            Trees.group([Trees.text("Three.", 120)]),
        ])
        #expect(reader.continuation(from: CGPoint(x: 30, y: 15), in: root)?.text.text == "One.\nTwo.")
    }

    @Test("A Gmail-like reply and forward row ends the email (buttons wrapping links)")
    func gmailActionRow() throws {
        let link: (String, CGFloat) -> AXNode = { title, x in
            AXNode(role: "AXButton", children: [AXNode(role: "AXLink", children: [Trees.text(title, 200, x: x, width: 60)])])
        }
        let root = AXNode(role: "AXWebArea", children: [
            Trees.group([Trees.text("Dear team,", 100)]),
            Trees.group([Trees.text("Body paragraph.", 130)]),
            Trees.group([link("Reply", 20), link("Forward", 90)]),
            Trees.group([Trees.text("Footer text.", 300)]),
        ])
        #expect(reader.continuation(from: CGPoint(x: 30, y: 105), in: root)?.text.text == "Dear team,\nBody paragraph.")
        #expect(reader.block(at: CGPoint(x: 30, y: 205), in: root) == nil)
    }

    @Test("Continuation never reads above the pointed block")
    func continuationStartsAtPoint() throws {
        let text = try #require(reader.continuation(from: CGPoint(x: 30, y: 225), in: Trees.chat)).text.text
        #expect(text == "Beta answer.")
    }

    @Test("Continuation stops at the character cap")
    func continuationCap() throws {
        let capped = AXBlockReader(continuationCap: 20)
        let text = try #require(capped.continuation(from: CGPoint(x: 30, y: 15), in: Trees.chat)).text.text
        #expect(text == "Plan the trip.")
    }

    @Test("A selection spans the blocks between both points and trims the first and last")
    func selection() throws {
        let start = CGPoint(x: 20 + 400 * 0.5, y: 100)
        let end = CGPoint(x: 20 + 400 * 0.5, y: 125)
        let text = try #require(reader.selection(from: start, to: end, in: Trees.chat)).text.text
        #expect(text == "step.\nSecond")
    }

    @Test("A backwards selection reads the same text")
    func backwardsSelection() throws {
        let start = CGPoint(x: 220, y: 100)
        let end = CGPoint(x: 220, y: 125)
        #expect(reader.selection(from: end, to: start, in: Trees.chat)?.text.text
            == reader.selection(from: start, to: end, in: Trees.chat)?.text.text)
    }

    @Test("A Chromium list item with inline formatting groups reads as one block (probe shape)")
    func chromiumListItem() {
        // Shape seen in Claude's desktop app: AXList > AXGroup > [AXListMarker, AXGroup, AXStaticText, …].
        let root = AXNode(role: "AXWebArea", children: [
            AXNode(role: "AXList", children: [
                Trees.group([
                    AXNode(role: "AXListMarker", text: "1.", frame: CGRect(x: 0, y: 10, width: 10, height: 18)),
                    Trees.group([Trees.text("Bold", 10, width: 30)]),
                    Trees.text(" rest of item", 10, x: 50, width: 100),
                    AXNode(role: "AXButton", children: [Trees.text("cite", 10, x: 150, width: 20)]),
                    Trees.group([Trees.text("code", 10, x: 170, width: 30)]),
                    Trees.text(" end.", 10, x: 200, width: 30),
                ]),
                Trees.group([Trees.text("Second item.", 40)]),
            ]),
        ])
        #expect(reader.blocks(in: root).map(\.text.text) == ["Bold rest of item code end.", "Second item."])
    }

    @Test("Sibling paragraph groups under a message stay separate blocks (probe shape)")
    func siblingParagraphs() {
        let root = AXNode(role: "AXWebArea", children: [
            Trees.group([
                AXNode(role: "AXHeading", children: [Trees.text("Head", 10)]),
                Trees.group([Trees.text("One.", 40)]),
                Trees.group([Trees.text("Two.", 70)]),
            ]),
        ])
        #expect(reader.blocks(in: root).map(\.text.text) == ["Head", "One.", "Two."])
    }

    @Test("Continuation stays in the pointed reading area")
    func continuationStaysInArea() throws {
        let window = AXNode(role: "AXWindow", children: [
            AXNode(role: "AXScrollArea", children: [Trees.group([Trees.text("Main one.", 10)]),
                                                    Trees.group([Trees.text("Main two.", 40)])]),
            AXNode(role: "AXScrollArea", children: [Trees.group([Trees.text("Side item.", 70)])]),
        ])
        let text = try #require(reader.continuation(from: CGPoint(x: 30, y: 15), in: window)).text.text
        #expect(text == "Main one.\nMain two.")
    }

    @Test("A selection over chrome only reads nothing")
    func emptySelection() {
        #expect(reader.selection(from: CGPoint(x: 30, y: 182), to: CGPoint(x: 60, y: 200), in: Trees.chat) == nil)
    }
}

@Suite("AXCodeHint")
struct AXCodeHintTests {
    @Test("Highlighter and language classes mark a code block")
    func codeClasses() {
        #expect(AXCodeHint.isCode(domClasses: ["language-swift"]))
        #expect(AXCodeHint.isCode(domClasses: ["hljs", "x"]))
        #expect(AXCodeHint.isCode(domClasses: ["code-block"]))
    }

    @Test("Utility classes that merely contain the letters code do not")
    func notCode() {
        #expect(!AXCodeHint.isCode(domClasses: ["[unicode-bidi:plaintext]", "text-body"]))
        #expect(!AXCodeHint.isCode(domClasses: ["inline-code-like"]))
        #expect(!AXCodeHint.isCode(domClasses: []))
    }
}

@Suite("HoverTarget from rects")
struct HoverTargetRectsTests {
    @Test("A target given as several rects outlines each and spans their union")
    func rects() {
        let a = CGRect(x: 0, y: 0, width: 10, height: 10)
        let b = CGRect(x: 20, y: 30, width: 10, height: 10)
        let target = HoverTarget(rects: [a, b], text: "t")
        #expect(target.rects == [a, b])
        #expect(target.rect == CGRect(x: 0, y: 0, width: 30, height: 40))
        #expect(target.block == nil)
    }
}
