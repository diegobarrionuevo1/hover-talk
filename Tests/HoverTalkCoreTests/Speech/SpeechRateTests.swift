import Testing
@testable import HoverTalkCore

@Suite("SpeechRate")
struct SpeechRateTests {
    @Test("The default rate is 1.0x")
    func defaultRate() {
        #expect(SpeechRate.default.multiplier == 1.0)
    }

    @Test("Values outside 0.5...3.0 are clamped", arguments: [
        (0.1, 0.5), (0.0, 0.5), (-2.0, 0.5), (3.5, 3.0), (10.0, 3.0),
    ])
    func clamps(input: Double, expected: Double) {
        #expect(SpeechRate(input).multiplier == expected)
    }

    @Test("Infinite values clamp to the nearest bound and NaN falls back to the default")
    func nonFiniteValues() {
        #expect(SpeechRate(.infinity).multiplier == SpeechRate.maximum)
        #expect(SpeechRate(-.infinity).multiplier == SpeechRate.minimum)
        #expect(SpeechRate(.nan) == .default)
    }

    @Test("Values snap to the nearest 0.25 step", arguments: [
        (1.1, 1.0), (1.13, 1.25), (1.125, 1.25), (2.4, 2.5), (0.6, 0.5),
    ])
    func snapsToStep(input: Double, expected: Double) {
        #expect(SpeechRate(input).multiplier == expected)
    }

    @Test("faster() and slower() move one step")
    func steps() {
        #expect(SpeechRate.default.faster().multiplier == 1.25)
        #expect(SpeechRate.default.slower().multiplier == 0.75)
        #expect(SpeechRate(2.0).faster().faster().multiplier == 2.5)
    }

    @Test("faster() stops at the maximum and slower() stops at the minimum")
    func stepsStopAtBounds() {
        #expect(SpeechRate(SpeechRate.maximum).faster().multiplier == SpeechRate.maximum)
        #expect(SpeechRate(SpeechRate.minimum).slower().multiplier == SpeechRate.minimum)
    }
}
