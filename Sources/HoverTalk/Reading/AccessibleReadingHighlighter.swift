import AppKit
import ApplicationServices
import HoverTalkCore

/// Marks accessibility text while it is read: every text node of the reading with a light
/// fill, the current sentence with the strong mark, and the word being spoken (system voices
/// report it) with the word mark. The terminal counterpart is `ReadingHighlighter`.
///
/// Anchors name nodes by their child-index path from the reading area (`AXTextAnchor`). The
/// area is found again under the point the reading was picked at, the nodes are walked to by
/// path once and kept, and each Character's offset is checked against the node's live text, so
/// a node whose text changed (a page that re-rendered) is skipped instead of marked wrongly.
/// Rects come from `AXBoundsForRange` on the node, so they follow the text's lines; they are
/// read again every `refreshInterval`, which keeps the marks on the text while the page scrolls.
///
/// AX calls run on the main thread here; each is bounded by the process's messaging timeout
/// (`AppDelegate` sets it), and a node that does not answer is skipped from then on.
@MainActor
final class AccessibleReadingHighlighter {
    private static let refreshInterval: TimeInterval = 0.5

    private struct Reading {
        let anchors: SentenceAnchors<AXTextAnchor>
        let area: AXUIElement
        var sentence = 0
        var wordOffset: Int?
        /// Live nodes by path; `nil` for a path that could not be found or whose text changed.
        var nodes: [[Int]: AXUIElement?] = [:]
    }

    private let overlay = HighlightOverlay()
    private var isOverlayShown = false
    private var reading: Reading?
    private var timer: Timer?
    private var isSuspended = false

    /// Starts marking `anchors`, read from the reading area under `point` (AX coordinates).
    /// Without an area there, nothing is marked; reading goes on.
    func begin(_ anchors: SentenceAnchors<AXTextAnchor>, point: CGPoint) {
        end()
        guard let area = try? AccessibleAXSource.area(at: point) else { return }
        reading = Reading(anchors: anchors, area: area.element)
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            // Added to the main run loop below, so the block runs on the main thread.
            MainActor.assumeIsolated { self?.render() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        render()
    }

    func end() {
        timer?.invalidate()
        timer = nil
        reading = nil
        if isOverlayShown {
            overlay.hide()
            isOverlayShown = false
        }
    }

    func update(_ state: Player.State) {
        guard reading != nil else { return }
        switch state.status {
        case .idle, .finished:
            end()
        case .playing, .paused:
            let moved = reading?.sentence != state.currentIndex || reading?.wordOffset != state.wordOffset
            reading?.sentence = state.currentIndex
            reading?.wordOffset = state.wordOffset
            if moved { render() }
        }
    }

    func setSuspended(_ suspended: Bool) {
        isSuspended = suspended
        render()
    }

    // MARK: - Drawing

    private func render() {
        guard var reading, !isSuspended else {
            if isOverlayShown {
                overlay.hide()
                isOverlayShown = false
            }
            return
        }
        let anchors = reading.anchors
        var whole: [SentenceAnchors<AXTextAnchor>.Entry] = []
        for index in anchors.sentences.indices {
            whole += anchors.anchors(ofSentence: index)
        }
        let sentence = anchors.anchors(ofSentence: reading.sentence)
        let word = reading.wordOffset.map { anchors.word(inSentence: reading.sentence, atUTF16Offset: $0) } ?? []

        var shapes = rects(for: whole, in: &reading).map { HighlightOverlay.Shape(rect: $0, style: .light) }
        shapes += rects(for: sentence, in: &reading).map { HighlightOverlay.Shape(rect: $0, style: .strong) }
        shapes += rects(for: word, in: &reading).map { HighlightOverlay.Shape(rect: $0, style: .word) }
        self.reading = reading

        guard !shapes.isEmpty else {
            if isOverlayShown {
                overlay.hide()
                isOverlayShown = false
            }
            return
        }
        if !isOverlayShown {
            overlay.show()
            isOverlayShown = true
        }
        overlay.draw(shapes)
    }

    /// One rect per node covering the anchored Characters, in AX coordinates. A node whose
    /// live text no longer has the expected Characters at their offsets is skipped.
    private func rects(for entries: [SentenceAnchors<AXTextAnchor>.Entry], in reading: inout Reading) -> [CGRect] {
        var groups: [[Int]: [SentenceAnchors<AXTextAnchor>.Entry]] = [:]
        var order: [[Int]] = []
        for entry in entries {
            if groups[entry.anchor.path] == nil { order.append(entry.anchor.path) }
            groups[entry.anchor.path, default: []].append(entry)
        }
        return order.compactMap { path in
            guard let group = groups[path], let node = node(at: path, in: &reading) else { return nil }
            return Self.bounds(of: group, in: node)
        }
    }

    private func node(at path: [Int], in reading: inout Reading) -> AXUIElement? {
        if let cached = reading.nodes[path] { return cached }
        var element: AXUIElement? = reading.area
        for index in path {
            guard let current = element, let children = Self.children(of: current), index < children.count else {
                element = nil
                break
            }
            element = children[index]
        }
        reading.nodes[path] = .some(element)
        return element
    }

    // MARK: - AX helpers

    /// `AXBoundsForRange` for the Characters of `entries` in `node`'s text, converted to the
    /// UTF-16 range AX expects; the node's frame when the text cannot be measured. `nil` when
    /// the live text does not hold those Characters at those offsets.
    private static func bounds(of entries: [SentenceAnchors<AXTextAnchor>.Entry], in node: AXUIElement) -> CGRect? {
        guard let text = string(node, kAXValueAttribute) else { return frame(of: node) }
        let characters = Array(text)
        guard entries.allSatisfy({ $0.anchor.offset < characters.count && characters[$0.anchor.offset] == $0.character }),
              let lower = entries.map(\.anchor.offset).min(), let upper = entries.map(\.anchor.offset).max()
        else { return nil }
        let range = lower...upper
        let start = characters[..<range.lowerBound].reduce(0) { $0 + $1.utf16.count }
        let length = characters[range].reduce(0) { $0 + $1.utf16.count }
        var cfRange = CFRange(location: start, length: length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else { return frame(of: node) }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            node, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &result
        ) == .success, let result, CFGetTypeID(result) == AXValueGetTypeID() else { return frame(of: node) }
        var rect = CGRect.zero
        guard AXValueGetValue(result as! AXValue, .cgRect, &rect), !rect.isEmpty else { return frame(of: node) }
        return rect
    }

    private static func children(of element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return nil }
        return value as? [AXUIElement]
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value as? String : nil
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size
        else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent)
        else { return nil }
        let rect = CGRect(origin: origin, size: extent)
        return rect.isEmpty ? nil : rect
    }
}
