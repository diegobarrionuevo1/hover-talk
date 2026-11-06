import AppKit
import HoverTalkCore

/// Where the reading highlighter reads again the terminal screen a document came from.
struct ReadingScreenSource {
    let resolver: TerminalHoverResolver
    let anchor: ReadingAnchor
    /// A point in AX coordinates over the terminal's text area, to read it again from.
    let point: CGPoint
}

/// Marks on screen what is being read from a terminal: every row of the document with a light
/// fill, and the sentence being read with a stronger, outlined one that moves with the player.
///
/// About twice a second it reads the screen again at its probe point, through the source's
/// resolver and its screen cache, and finds the document's rows with `ReadingAnchor` on every
/// read: the marks follow the rows when they scroll, and the text area's frame when its window
/// moves while the probe point still falls on it. When only some rows are found, because the
/// rest scrolled out of view or the program is still writing the last ones, the marks cover
/// those rows alone. They hide while no terminal text area is read at the probe point or no row
/// can be found there; reading goes on. Once found, the probe point moves to the middle of the
/// first visible row: a window covering that point should then hide the marks, since AX
/// reports that window's element there (not yet seen live).
@MainActor
final class ReadingHighlighter {
    private static let refreshInterval: TimeInterval = 0.5

    private struct Reading {
        let document: ReadingDocument
        let source: ReadingScreenSource
        var probe: CGPoint
        /// The player's current sentence; `nil` until the player reports playing or paused.
        var sentence: Int?
        /// See `Player.State.wordOffset`.
        var wordOffset: Int?
        /// Where the document is on the latest screen read; `nil` before the first read or
        /// while its rows cannot be found.
        var placement: Placement?
    }

    private struct Placement {
        let geometry: TerminalGeometry
        let rows: ReadingAnchor.Placement
    }

    private let overlay = HighlightOverlay()
    private var isOverlayShown = false
    private var reading: Reading?
    private var timer: Timer?
    private var isRefreshing = false
    /// Increases whenever a reading begins or ends, so a screen read that finishes afterwards
    /// is dropped.
    private var generation = 0
    private var isSuspended = false

    /// Starts marking `document`, replacing any previous one. Nothing shows until `update(_:)`
    /// reports the player playing or paused.
    func begin(_ document: ReadingDocument, source: ReadingScreenSource) {
        end()
        reading = Reading(document: document, source: source, probe: source.point)
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            // Added to the main run loop below, so the block runs on the main thread.
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        // `.common` keeps refreshing while a menu runs its own run loop mode.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    /// Stops marking and hides the marks.
    func end() {
        timer?.invalidate()
        timer = nil
        reading = nil
        generation += 1
        render()
    }

    /// Follows the player: idle or finished ends the marks; playing or paused moves the strong
    /// mark to the current sentence.
    func update(_ state: Player.State) {
        guard reading != nil else { return }
        switch state.status {
        case .idle, .finished:
            end()
        case .playing, .paused:
            reading?.sentence = state.currentIndex
            reading?.wordOffset = state.wordOffset
            render()
        }
    }

    /// Hides the marks while `suspended` (the picker draws its own highlight meanwhile) and
    /// shows them again after.
    func setSuspended(_ suspended: Bool) {
        isSuspended = suspended
        render()
    }

    private func refresh() {
        guard let reading, !isRefreshing else { return }
        isRefreshing = true
        let generation = generation
        let resolver = reading.source.resolver
        let probe = reading.probe
        Task { [weak self] in
            let screen = await resolver.screen(at: probe)
            self?.finishRefresh(screen, generation: generation)
        }
    }

    private func finishRefresh(_ screen: ParsedScreen?, generation: Int) {
        isRefreshing = false
        guard generation == self.generation, var reading else { return }
        if let screen, let rows = reading.source.anchor.placement(in: screen) {
            reading.placement = Placement(geometry: screen.geometry, rows: rows)
            if let first = screen.geometry.rects(for: rows.visible(reading.document.spans), rowOffset: rows.rowOffset).first {
                reading.probe = CGPoint(x: first.midX, y: first.midY)
            }
        } else {
            reading.placement = nil
        }
        self.reading = reading
        render()
    }

    private func render() {
        guard let reading, !isSuspended, let sentence = reading.sentence, let placement = reading.placement else {
            if isOverlayShown {
                overlay.hide()
                isOverlayShown = false
            }
            return
        }
        func shapes(_ spans: [RowSpan], _ style: HighlightOverlay.Style) -> [HighlightOverlay.Shape] {
            placement.geometry.rects(for: placement.rows.visible(spans), rowOffset: placement.rows.rowOffset).map { HighlightOverlay.Shape(rect: $0, style: style) }
        }
        let current = reading.document.sentenceSpans.indices.contains(sentence) ? reading.document.sentenceSpans[sentence] : []
        if !isOverlayShown {
            overlay.show()
            isOverlayShown = true
        }
        let word = reading.wordOffset.map { reading.document.wordSpans(sentence: sentence, utf16Offset: $0) } ?? []
        overlay.draw(shapes(reading.document.spans, .light) + shapes(current, .strong) + shapes(word, .word))
    }
}
