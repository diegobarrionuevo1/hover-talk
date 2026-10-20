import Testing
@testable import HoverTalkCore

private func key(_ text: String, _ voice: String = "ef_dora") -> SynthesisKey {
    SynthesisKey(text: text, voice: voice)
}

@Suite("SynthesisPrefetch")
struct SynthesisPrefetchTests {
    @Test("Only the next two upcoming sentences are started")
    func startsTwo() {
        let plan = SynthesisPrefetch.plan(cached: [key("A")], current: key("A"), upcoming: [key("B"), key("C"), key("D")])

        #expect(plan.start == [key("B"), key("C")])
        #expect(plan.drop.isEmpty)
    }

    @Test("Entries already cached are not started again; entries that are neither current nor upcoming are dropped")
    func keepsAndDrops() {
        let plan = SynthesisPrefetch.plan(
            cached: [key("A"), key("B"), key("C")],
            current: key("B"),
            upcoming: [key("C"), key("D")]
        )

        #expect(plan.start == [key("D")])
        #expect(plan.drop == [key("A")])
    }

    @Test("The same text in another voice is another synthesis")
    func voiceIsPartOfTheKey() {
        let plan = SynthesisPrefetch.plan(
            cached: [key("A", "af_heart"), key("B", "af_heart")],
            current: key("A", "ef_dora"),
            upcoming: [key("B", "ef_dora")]
        )

        #expect(plan.start == [key("B", "ef_dora")])
        #expect(plan.drop == [key("A", "af_heart"), key("B", "af_heart")])
    }

    @Test("Repeated sentences are started once, and a sentence equal to the current one is not started")
    func repeats() {
        #expect(SynthesisPrefetch.plan(cached: [key("A")], current: key("A"), upcoming: [key("B"), key("B")]).start == [key("B")])
        #expect(SynthesisPrefetch.plan(cached: [key("A")], current: key("A"), upcoming: [key("A"), key("B")]).start == [key("B")])
    }

    @Test("With nothing current and nothing upcoming every entry is dropped")
    func dropsAll() {
        let plan = SynthesisPrefetch.plan(cached: [key("A"), key("B")], current: nil, upcoming: [])

        #expect(plan.start.isEmpty)
        #expect(plan.drop == [key("A"), key("B")])
    }

    @Test("The cache never holds more than the current sentence and two upcoming ones")
    func bounded() {
        let cached: Set = [key("A"), key("B"), key("C"), key("D")]
        let current = key("C")
        let upcoming = [key("D"), key("E"), key("F")]

        let plan = SynthesisPrefetch.plan(cached: cached, current: current, upcoming: upcoming)
        let kept = cached.subtracting(plan.drop).union(plan.start)

        #expect(kept == [key("C"), key("D"), key("E")])
        #expect(SynthesisPrefetch.upcomingLimit == 2)
    }
}
