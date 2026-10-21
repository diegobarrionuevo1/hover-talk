import CoreGraphics

/// A value-type snapshot of one accessibility element, built from a live tree by the app or by
/// hand in tests.
public struct AXNode: Equatable, Sendable {
    public var role: String
    public var subrole: String?
    /// The element's own readable text (its `AXValue` for text roles); `nil` when it has none.
    public var text: String?
    public var frame: CGRect
    public var isEditable: Bool
    public var isCode: Bool
    public var children: [AXNode]

    public init(
        role: String, subrole: String? = nil, text: String? = nil, frame: CGRect = .zero,
        isEditable: Bool = false, isCode: Bool = false, children: [AXNode] = []
    ) {
        self.role = role
        self.subrole = subrole
        self.text = text
        self.frame = frame
        self.isEditable = isEditable
        self.isCode = isCode
        self.children = children
    }
}

/// Where a character came from: the child-index path of its node from the root, and its
/// character offset in that node's text.
public struct AXTextAnchor: Hashable, Sendable {
    public let path: [Int]
    public let offset: Int

    public init(path: [Int], offset: Int) {
        self.path = path
        self.offset = offset
    }
}

/// A readable block of an accessibility tree.
public struct AXBlock: Equatable, Sendable {
    public let text: MappedText<AXTextAnchor>
    /// Frames of the text nodes that contribute to the block.
    public let rects: [CGRect]
    /// The path of the block's container from the root.
    public let path: [Int]
    /// For a continuation, the container path of each block joined, in order, so paragraph
    /// reading can stop at the end of one; empty for a single block or a selection.
    public var paragraphPaths: [[Int]] = []
}

/// Finds readable blocks in an accessibility tree: what a paragraph, heading, list item or code
/// block is, which elements are chrome, and how continuous reading and drag selection walk the
/// blocks. Pure; tested on synthetic trees.
///
/// Rules:
/// - Chrome is skipped with all its descendants: controls (buttons, menus, toolbars, tab groups,
///   scroll bars, check boxes), the banner, navigation and content-info landmarks, and editable
///   inputs. An editable input is also a *stop*: in chat apps it is the composer below the
///   transcript, so continuous reading ends there.
/// - A heading, list item, table cell, non-editable text area or field, or a code element forms
///   its own block.
/// - Otherwise a container whose descendants are all inline (static text, links, images, list
///   markers and groups of those) forms one block. In a mixed container, each run of
///   consecutive inline children forms a block and the other children are walked the same way;
///   a container with bare text among its children also joins its formatting groups into the
///   run (see `walk`).
/// - A row of two or more controls (see `isActionRow`) ends continuous reading like an
///   editable input: it closes an email or a chat answer.
/// - Code blocks read as a fenced block (```), so `TextCleaner` can replace them with
///   "Code omitted." or keep them, like terminal code fences.
public struct AXBlockReader: Sendable {
    /// Continuous reading stops before a block that would take the text past this many
    /// characters (the pointed block itself is always read).
    public let continuationCap: Int
    /// Vertical distance within which a point between lines still picks the nearest block.
    public static let snapDistance: CGFloat = 8

    private static let chromeRoles: Set<String> = [
        "AXButton", "AXMenuButton", "AXPopUpButton", "AXCheckBox", "AXRadioButton", "AXToolbar",
        "AXTabGroup", "AXMenuBar", "AXMenu", "AXMenuItem", "AXScrollBar", "AXSlider", "AXIncrementor",
        "AXDisclosureTriangle",
    ]
    private static let chromeSubroles: Set<String> = [
        "AXLandmarkNavigation", "AXLandmarkBanner", "AXLandmarkContentInfo",
    ]
    private static let inputRoles: Set<String> = ["AXTextArea", "AXTextField", "AXComboBox", "AXSearchField"]
    private static let ownBlockRoles: Set<String> = ["AXHeading", "AXListItem", "AXCell", "AXTextArea", "AXTextField"]
    /// `AXListMarker` (the "1." or bullet Chromium exposes per list item) is inline but never read.
    private static let inlineRoles: Set<String> = ["AXStaticText", "AXLink", "AXImage", "AXListMarker"]
    /// Roles whose descendants are read as a separate reading area.
    private static let areaRoles: Set<String> = ["AXWebArea", "AXScrollArea"]

    public init(continuationCap: Int = 50_000) {
        self.continuationCap = continuationCap
    }

    // MARK: - Queries

    public func blocks(in root: AXNode) -> [AXBlock] {
        items(in: root).compactMap { if case let .block(block, _) = $0 { block } else { nil } }
    }

    /// The block under `point`, or the nearest one within `snapDistance` vertically; `nil` over
    /// chrome or empty space.
    public func block(at point: CGPoint, in root: AXNode) -> AXBlock? {
        let all = items(in: root)
        return index(at: point, in: all).flatMap { if case let .block(block, _) = all[$0] { block } else { nil } }
    }

    /// The block at `point` followed by every later block of the same reading area, joined with
    /// line breaks. Chrome between blocks is skipped; an editable input ends the reading.
    public func continuation(from point: CGPoint, in root: AXNode) -> AXBlock? {
        let all = items(in: root)
        guard let start = index(at: point, in: all), case let .block(first, area) = all[start] else { return nil }
        var parts = [first]
        var count = first.text.text.count
        for item in all[(start + 1)...] {
            switch item {
            case let .stop(stopArea) where stopArea == area:
                return Self.joinedParagraphs(parts)
            case let .block(block, blockArea) where blockArea == area:
                let next = count + 1 + block.text.text.count
                guard next <= continuationCap else { return Self.joinedParagraphs(parts) }
                parts.append(block)
                count = next
            default:
                continue
            }
        }
        return Self.joinedParagraphs(parts)
    }

    /// The blocks whose rects meet the vertical span between `start` and `end`, in the reading
    /// area of the first of them, with the first block trimmed before the earlier point and the
    /// last block trimmed after the later point.
    ///
    /// Trimming is approximate: without per-character bounds, a point's character offset is its
    /// horizontal position across the block's text rects, taken as a fraction of their total
    /// width. Line rects of a wrapped paragraph make this close; one rect for a whole paragraph
    /// makes it coarse.
    public func selection(from start: CGPoint, to end: CGPoint, in root: AXNode) -> AXBlock? {
        let (early, late) = Self.readingOrder(start, end)
        let low = min(start.y, end.y), high = max(start.y, end.y)
        let candidates: [(AXBlock, [Int])] = items(in: root).compactMap {
            guard case let .block(block, area) = $0,
                  block.rects.contains(where: { $0.maxY >= low && $0.minY <= high }) else { return nil }
            return (block, area)
        }
        guard let area = candidates.first?.1 else { return nil }
        var blocks = candidates.filter { $0.1 == area }.map(\.0)
        let lastIndex = blocks.count - 1
        blocks[0] = Self.trimmed(blocks[0], from: Self.offset(of: early, in: blocks[0], roundingUp: false), to: nil)
        blocks[lastIndex] = Self.trimmed(
            blocks[lastIndex], from: nil,
            to: Self.offset(of: late, in: blocks[lastIndex], roundingUp: true)
        )
        let kept = blocks.filter { !$0.text.text.isEmpty }
        return kept.isEmpty ? nil : Self.joined(kept)
    }

    // MARK: - Walking the tree

    private enum Item {
        case block(AXBlock, area: [Int])
        /// An editable input: continuous reading in `area` ends here.
        case stop(area: [Int])
    }

    private struct Piece {
        let text: String
        let path: [Int]
        let frame: CGRect
    }

    private func items(in root: AXNode) -> [Item] {
        var result: [Item] = []
        walk(root, path: [], area: [], into: &result)
        return result
    }

    private func walk(_ node: AXNode, path: [Int], area: [Int], into result: inout [Item]) {
        if Self.isEditableInput(node) {
            result.append(.stop(area: area))
            return
        }
        if Self.isActionRow(node) {
            result.append(.stop(area: area))
            return
        }
        if Self.isChrome(node) { return }
        let area = Self.areaRoles.contains(node.role) ? path : area
        if node.isCode || Self.ownBlockRoles.contains(node.role) || Self.isInline(node) {
            if let block = Self.block(node, path: path) { result.append(.block(block, area: area)) }
            return
        }
        // A container with bare text or links among its children is a text container (a
        // paragraph or list item with inline formatting, as Chromium exposes `<li>` with
        // `<strong>`): its inline children, formatting groups included, join one run, and
        // controls inside the text (such as a citation button) are skipped without ending it.
        // In any other container an inline group is a paragraph of its own.
        let isTextContainer = node.children.contains(where: Self.isInlineLeafRun)
        var run: [Int] = []
        func flush() {
            guard !run.isEmpty else { return }
            let pieces = run.flatMap { Self.pieces(of: node.children[$0], path: path + [$0]) }
            if let block = Self.block(from: pieces, isCode: false, path: path) {
                result.append(.block(block, area: area))
            }
            run = []
        }
        for (index, child) in node.children.enumerated() {
            if Self.isInlineLeafRun(child) || (isTextContainer && Self.isInline(child)) {
                run.append(index)
            } else if isTextContainer && Self.isChrome(child) {
                continue
            } else {
                flush()
                walk(child, path: path + [index], area: area, into: &result)
            }
        }
        flush()
    }

    private static func isChrome(_ node: AXNode) -> Bool {
        chromeRoles.contains(node.role) || node.subrole.map(chromeSubroles.contains) == true
    }

    private static let controlRoles: Set<String> = [
        "AXButton", "AXMenuButton", "AXPopUpButton", "AXCheckBox", "AXRadioButton",
    ]

    /// A row of two or more controls and nothing else, such as Gmail's Reply and Forward under
    /// an email or the copy and retry buttons under a chat answer: the end of the text above it.
    private static func isActionRow(_ node: AXNode) -> Bool {
        func isControl(_ node: AXNode) -> Bool {
            controlRoles.contains(node.role)
                || (node.role == "AXGroup" && node.children.count == 1 && isControl(node.children[0]))
        }
        return node.children.count >= 2 && node.children.allSatisfy(isControl)
    }

    private static func isEditableInput(_ node: AXNode) -> Bool {
        node.isEditable && inputRoles.contains(node.role)
    }

    /// Static text, links and images, and plain groups made only of those.
    private static func isInline(_ node: AXNode) -> Bool {
        if node.isCode || isChrome(node) || isEditableInput(node) { return false }
        if inlineRoles.contains(node.role) { return true }
        return node.role == "AXGroup" && !node.children.isEmpty && node.children.allSatisfy(isInline)
    }

    /// Inline children of a mixed container that join their neighbours into one anonymous block:
    /// bare static text and links. Inline groups stay their own block.
    private static func isInlineLeafRun(_ node: AXNode) -> Bool {
        node.role == "AXStaticText" || node.role == "AXLink"
    }

    /// The text-bearing leaves under `node`, in tree order, skipping chrome.
    private static func pieces(of node: AXNode, path: [Int]) -> [Piece] {
        if isChrome(node) || isEditableInput(node) || node.role == "AXListMarker" { return [] }
        if node.children.isEmpty || inputRoles.contains(node.role) {
            guard let text = node.text, !text.isEmpty else { return [] }
            return [Piece(text: text, path: path, frame: node.frame)]
        }
        return node.children.enumerated().flatMap { pieces(of: $1, path: path + [$0]) }
    }

    private static func block(_ node: AXNode, path: [Int]) -> AXBlock? {
        block(from: pieces(of: node, path: path), isCode: node.isCode, path: path)
    }

    private static func block(from pieces: [Piece], isCode: Bool, path: [Int]) -> AXBlock? {
        var text = MappedText<AXTextAnchor>()
        if isCode { text.append("```\n", anchor: nil) }
        for (index, piece) in pieces.enumerated() {
            if index > 0 {
                if isCode {
                    text.append("\n", anchor: nil)
                } else if needsSpace(between: text.text.last, and: piece.text.first) {
                    text.append(" ", anchor: nil)
                }
            }
            for (offset, character) in piece.text.enumerated() {
                text.append(character, anchor: AXTextAnchor(path: piece.path, offset: offset))
            }
        }
        if isCode { text.append("\n```", anchor: nil) }
        guard pieces.contains(where: { !$0.text.allSatisfy(\.isWhitespace) }) else { return nil }
        let rects = pieces.map(\.frame).filter { !$0.isEmpty }
        return AXBlock(text: text, rects: rects, path: path)
    }

    private static func needsSpace(between previous: Character?, and next: Character?) -> Bool {
        guard let previous, let next else { return false }
        if previous.isWhitespace || next.isWhitespace { return false }
        return !".,;:!?)]}”’".contains(next) && !"([{“‘".contains(previous)
    }

    // MARK: - Points and offsets

    private func index(at point: CGPoint, in items: [Item]) -> Int? {
        var nearest: (index: Int, distance: CGFloat)?
        for (index, item) in items.enumerated() {
            guard case let .block(block, _) = item else { continue }
            if block.rects.contains(where: { $0.contains(point) }) { return index }
            for rect in block.rects {
                let distance = max(rect.minY - point.y, point.y - rect.maxY, 0)
                if distance <= Self.snapDistance, distance < (nearest?.distance ?? .infinity) {
                    nearest = (index, distance)
                }
            }
        }
        return nearest?.index
    }

    private static func readingOrder(_ a: CGPoint, _ b: CGPoint) -> (CGPoint, CGPoint) {
        (a.y, a.x) <= (b.y, b.x) ? (a, b) : (b, a)
    }

    /// The character offset `point` falls at, as the fraction of the block's text rects (in text
    /// order) lying before it.
    private static func offset(of point: CGPoint, in block: AXBlock, roundingUp: Bool) -> Int {
        let total = block.rects.reduce(0) { $0 + $1.width }
        guard total > 0 else { return roundingUp ? block.text.text.count : 0 }
        var before: CGFloat = 0
        for rect in block.rects {
            if point.y > rect.maxY {
                before += rect.width
            } else if point.y >= rect.minY {
                if point.x >= rect.maxX {
                    before += rect.width
                    continue
                }
                before += min(max(point.x - rect.minX, 0), rect.width)
                break
            } else {
                break
            }
        }
        let exact = Double(before / total) * Double(block.text.text.count)
        return Int(roundingUp ? exact.rounded(.up) : exact.rounded(.down))
    }

    /// `block` keeping the characters in `from..<to`, with whitespace at both ends dropped.
    private static func trimmed(_ block: AXBlock, from: Int?, to: Int?) -> AXBlock {
        var elements = Array(block.text.elements)
        let upper = min(to ?? elements.count, elements.count)
        let lower = min(from ?? 0, upper)
        elements = Array(elements[lower..<upper])
        while elements.first?.0.isWhitespace == true { elements.removeFirst() }
        while elements.last?.0.isWhitespace == true { elements.removeLast() }
        return AXBlock(text: MappedText(elements: elements), rects: block.rects, path: block.path)
    }

    private static func joined(_ blocks: [AXBlock]) -> AXBlock {
        var text = MappedText<AXTextAnchor>()
        for (index, block) in blocks.enumerated() {
            if index > 0 { text.append("\n", anchor: nil) }
            text.append(block.text)
        }
        return AXBlock(text: text, rects: blocks.flatMap(\.rects), path: blocks[0].path)
    }

    /// As `joined(_:)`, remembering each block's path (see `AXBlock.paragraphPaths`).
    private static func joinedParagraphs(_ blocks: [AXBlock]) -> AXBlock {
        var block = joined(blocks)
        block.paragraphPaths = blocks.map(\.path)
        return block
    }
}

/// Whether a web element is a code block, from its DOM class list (`AXDOMClassList`).
///
/// Only explicit highlighter and language classes count. A substring test for "code" is wrong:
/// Claude's desktop app tags plain prose with `[unicode-bidi:plaintext]` (probe, 2026-10-21).
public enum AXCodeHint {
    public static func isCode(domClasses: [String]) -> Bool {
        domClasses.contains { $0.hasPrefix("language-") || $0 == "hljs" || $0 == "code-block" }
    }
}
