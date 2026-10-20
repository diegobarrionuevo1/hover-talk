import Testing
@testable import HoverTalkCore

private func presentation(
    index: Int = 0,
    count: Int = 12,
    status: PlaybackStatus = .playing,
    rate: SpeechRate = .default,
    readingMode: ReadingMode = .continuous
) -> ControllerPresentation {
    ControllerPresentation(state: Player.State(currentIndex: index, count: count, status: status, rate: rate), readingMode: readingMode)
}

@Suite("ControllerPresentation")
struct ControllerPresentationTests {
    // MARK: Visibility

    @Test("The panel is visible while playing or paused and hidden when idle or finished", arguments: [
        (PlaybackStatus.playing, true), (.paused, true), (.idle, false), (.finished, false),
    ])
    func visibility(status: PlaybackStatus, isVisible: Bool) {
        #expect(presentation(status: status).isVisible == isVisible)
    }

    // MARK: Play/pause

    @Test("The play/pause button shows Pause while playing")
    func pauseWhilePlaying() {
        let shown = presentation(status: .playing)

        #expect(shown.playPauseMode == .pause)
        #expect(shown.playPause.symbolName == "pause.fill")
        #expect(shown.playPause.accessibilityLabel == "Pause")
    }

    @Test("The play/pause button shows Resume while paused")
    func resumeWhilePaused() {
        let shown = presentation(status: .paused)

        #expect(shown.playPauseMode == .resume)
        #expect(shown.playPause.symbolName == "play.fill")
        #expect(shown.playPause.accessibilityLabel == "Resume")
    }

    @Test("The play/pause button shows Play when idle or finished", arguments: [PlaybackStatus.idle, .finished])
    func playOtherwise(status: PlaybackStatus) {
        let shown = presentation(status: status)

        #expect(shown.playPauseMode == .play)
        #expect(shown.playPause.symbolName == "play.fill")
        #expect(shown.playPause.accessibilityLabel == "Play")
    }

    @Test("Play/pause is disabled only when nothing is loaded")
    func playPauseEnabled() {
        #expect(presentation(count: 0, status: .idle).playPause.isEnabled == false)
        #expect(presentation(count: 3, status: .idle).playPause.isEnabled == true)
        #expect(presentation(count: 3, status: .playing).playPause.isEnabled == true)
        #expect(presentation(count: 3, status: .paused).playPause.isEnabled == true)
    }

    // MARK: Progress

    @Test("Progress shows the 1-based sentence number and the sentence count")
    func progress() {
        let shown = presentation(index: 2, count: 12)

        #expect(shown.progressText == "3 / 12")
        #expect(shown.progressAccessibilityLabel == "Sentence 3 of 12")
    }

    @Test("Progress with nothing loaded shows zero of zero")
    func progressWhenEmpty() {
        let shown = presentation(index: 0, count: 0, status: .idle)

        #expect(shown.progressText == "0 / 0")
        #expect(shown.progressAccessibilityLabel == "No text loaded")
    }

    // MARK: Rate

    @Test("The rate label drops trailing zeros and ends with the multiplication sign", arguments: [
        (0.5, "0.5×"), (0.75, "0.75×"), (1.0, "1×"), (1.25, "1.25×"), (2.0, "2×"), (3.0, "3×"),
    ])
    func rateText(multiplier: Double, expected: String) {
        #expect(presentation(rate: SpeechRate(multiplier)).rateText == expected)
    }

    @Test("The rate accessibility label says normal speed at 1x and a multiple otherwise")
    func rateAccessibilityLabel() {
        #expect(presentation(rate: .default).rateAccessibilityLabel == "Normal speed")
        #expect(presentation(rate: SpeechRate(1.5)).rateAccessibilityLabel == "1.5 times normal speed")
        #expect(presentation(rate: SpeechRate(0.75)).rateAccessibilityLabel == "0.75 times normal speed")
    }

    @Test("Slower is disabled at the minimum rate and faster at the maximum rate")
    func rateBounds() {
        let slowest = presentation(rate: SpeechRate(SpeechRate.minimum))
        #expect(slowest.slower.isEnabled == false)
        #expect(slowest.faster.isEnabled == true)

        let fastest = presentation(rate: SpeechRate(SpeechRate.maximum))
        #expect(fastest.slower.isEnabled == true)
        #expect(fastest.faster.isEnabled == false)

        let normal = presentation(rate: .default)
        #expect(normal.slower.isEnabled == true)
        #expect(normal.faster.isEnabled == true)
    }

    // MARK: Sentence navigation

    @Test("Previous is disabled at the first sentence and enabled after it", arguments: [PlaybackStatus.playing, .paused])
    func previousEnabled(status: PlaybackStatus) {
        #expect(presentation(index: 0, count: 3, status: status).previous.isEnabled == false)
        #expect(presentation(index: 1, count: 3, status: status).previous.isEnabled == true)
        #expect(presentation(index: 2, count: 3, status: status).previous.isEnabled == true)
    }

    @Test("Next is disabled at the last sentence and enabled before it", arguments: [PlaybackStatus.playing, .paused])
    func nextEnabled(status: PlaybackStatus) {
        #expect(presentation(index: 0, count: 3, status: status).next.isEnabled == true)
        #expect(presentation(index: 1, count: 3, status: status).next.isEnabled == true)
        #expect(presentation(index: 2, count: 3, status: status).next.isEnabled == false)
    }

    @Test("Previous and next are disabled when idle or finished, because the queue ignores them then")
    func navigationDisabledWhenInactive() {
        let idle = presentation(index: 1, count: 3, status: .idle)
        #expect(idle.previous.isEnabled == false)
        #expect(idle.next.isEnabled == false)

        let finished = presentation(index: 1, count: 3, status: .finished)
        #expect(finished.previous.isEnabled == false)
        #expect(finished.next.isEnabled == false)
    }

    @Test("A single sentence has nowhere to move")
    func singleSentence() {
        let shown = presentation(index: 0, count: 1, status: .playing)

        #expect(shown.previous.isEnabled == false)
        #expect(shown.next.isEnabled == false)
    }

    // MARK: Stop

    @Test("Stop is enabled while the panel is visible", arguments: [
        (PlaybackStatus.playing, true), (.paused, true), (.idle, false), (.finished, false),
    ])
    func stopEnabled(status: PlaybackStatus, isEnabled: Bool) {
        #expect(presentation(status: status).stop.isEnabled == isEnabled)
    }

    // MARK: Identity of each control

    @Test("Each control carries its action, symbol and accessibility label")
    func controlIdentity() {
        let shown = presentation()

        #expect(shown.previous.action == .previous)
        #expect(shown.previous.symbolName == "backward.end.fill")
        #expect(shown.previous.accessibilityLabel == "Previous sentence")

        #expect(shown.playPause.action == .playPause)

        #expect(shown.next.action == .next)
        #expect(shown.next.symbolName == "forward.end.fill")
        #expect(shown.next.accessibilityLabel == "Next sentence")

        #expect(shown.slower.action == .slower)
        #expect(shown.slower.symbolName == "minus")
        #expect(shown.slower.accessibilityLabel == "Slower")

        #expect(shown.faster.action == .faster)
        #expect(shown.faster.symbolName == "plus")
        #expect(shown.faster.accessibilityLabel == "Faster")

        #expect(shown.stop.action == .stop)
        #expect(shown.stop.symbolName == "stop.fill")
        #expect(shown.stop.accessibilityLabel == "Stop")
    }

    // MARK: Reading mode

    @Test("In continuous mode the reading-mode toggle is on and says that reading continues below")
    func continuousToggle() {
        let toggle = presentation(readingMode: .continuous).readingMode

        #expect(toggle.isOn)
        #expect(toggle.symbolName == "text.line.first.and.arrowtriangle.forward")
        #expect(toggle.accessibilityLabel == "Continue reading below")
    }

    @Test("In paragraph mode the reading-mode toggle is off and says that only the paragraph is read")
    func paragraphToggle() {
        let toggle = presentation(readingMode: .paragraph).readingMode

        #expect(!toggle.isOn)
        #expect(toggle.symbolName == "paragraphsign")
        #expect(toggle.accessibilityLabel == "Read only this paragraph")
    }

    @Test("The panel title names the app")
    func panelTitle() {
        #expect(ControllerPresentation.panelTitle == "\(AppInfo.name) Controls")
    }

    // MARK: Voice server notice

    @Test("No voice server notice unless the system voice stands in for the voice server")
    func noNoticeByDefault() {
        #expect(presentation().voiceNotice == nil)
        #expect(ControllerPresentation(
            state: Player.State(currentIndex: 0, count: 3, status: .playing, rate: .default),
            readingMode: .continuous,
            usingFallbackVoice: false
        ).voiceNotice == nil)
    }

    @Test("While a reading uses the fallback voice the panel shows a small notice with a tooltip", arguments: [
        PlaybackStatus.playing, .paused,
    ])
    func noticeWhileVisible(status: PlaybackStatus) {
        let shown = ControllerPresentation(
            state: Player.State(currentIndex: 0, count: 3, status: status, rate: .default),
            readingMode: .paragraph,
            usingFallbackVoice: true
        )

        #expect(shown.voiceNotice == ControllerPresentation.Notice(
            symbolName: "wifi.exclamationmark",
            accessibilityLabel: "Voice server unreachable — using system voice"
        ))
    }

    @Test("A hidden panel shows no notice", arguments: [PlaybackStatus.idle, .finished])
    func noNoticeWhenHidden(status: PlaybackStatus) {
        let shown = ControllerPresentation(
            state: Player.State(currentIndex: 0, count: 3, status: status, rate: .default),
            readingMode: .continuous,
            usingFallbackVoice: true
        )

        #expect(shown.voiceNotice == nil)
    }
}
