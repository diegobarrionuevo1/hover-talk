import Foundation
import Testing
@testable import HoverTalkFixtureKit

/// All values are synthetic; tests never read the real user's names.
@Suite("LeakGuard")
struct LeakGuardTests {
    private let leakGuard = LeakGuard(
        userName: "jdoe",
        fullName: "Jane Q. Doe-Smith",
        hostName: "Studio-Box7.local",
        homeDirectory: "/Users/jdoe"
    )

    @Test("Text without any sensitive term passes")
    func clean() {
        #expect(leakGuard.firstLeak(in: "lantern oak river 42 ┃ │") == nil)
    }

    @Test("The user name is found case-insensitively")
    func userName() {
        #expect(leakGuard.firstLeak(in: "prompt JDOE >") == .userName)
    }

    @Test("Full-name parts of three or more letters are found; shorter parts are ignored")
    func fullNameParts() {
        #expect(leakGuard.firstLeak(in: "hello jane") == .fullNamePart)
        #expect(leakGuard.firstLeak(in: "DOE") == .fullNamePart)
        #expect(leakGuard.firstLeak(in: "smith") == .fullNamePart)
        #expect(leakGuard.firstLeak(in: "q. q q") == nil)
    }

    @Test("Accents do not hide a full-name part")
    func diacritics() {
        let leakGuard = LeakGuard(userName: "", fullName: "José Núñez", hostName: "", homeDirectory: "")
        #expect(leakGuard.firstLeak(in: "nunez") == .fullNamePart)
    }

    @Test("The full host name and its first label are both found")
    func hostName() {
        #expect(leakGuard.firstLeak(in: "studio-box7") == .hostName)
        #expect(leakGuard.firstLeak(in: "STUDIO-BOX7.LOCAL") == .hostName)
    }

    @Test("The home directory path is found")
    func homeDirectory() {
        let leakGuard = LeakGuard(userName: "", fullName: "", hostName: "", homeDirectory: "/srv/accounts/zq")
        #expect(leakGuard.firstLeak(in: "cd /SRV/accounts/zq/projects") == .homeDirectory)
        #expect(leakGuard.firstLeak(in: "cd /srv/accounts") == nil)
    }

    @Test("Empty values are ignored instead of matching everything")
    func emptyValues() {
        let leakGuard = LeakGuard(userName: "", fullName: "", hostName: "", homeDirectory: "")
        #expect(leakGuard.firstLeak(in: "anything at all") == nil)
    }
}

@Suite("FixtureExport")
struct FixtureExportTests {
    @Test("Writing is refused when a sensitive term survives sanitizing, without echoing the term")
    func refusesLeak() {
        // An allowlisted word survives sanitizing, so it stands in for a leaked user name.
        let leakGuard = LeakGuard(userName: "opencode", fullName: "", hostName: "", homeDirectory: "")
        let raw = ScreenFixture(frame: nil, lines: ["  opencode v1"])

        #expect(throws: FixtureExport.Failure.leak(.userName)) {
            try FixtureExport.prepare(raw, sanitizer: FixtureSanitizer(salt: 7), leakGuard: leakGuard)
        }
        let message = FixtureExport.Failure.leak(.userName).message
        #expect(message.contains("the user name"))
        #expect(!message.contains("opencode"))
    }

    @Test("Sensitive words made of letters are sanitized away, so writing goes ahead")
    func sanitizesThenPasses() throws {
        let leakGuard = LeakGuard(userName: "jdoe", fullName: "", hostName: "", homeDirectory: "/Users/jdoe")
        let raw = ScreenFixture(frame: nil, lines: ["jdoe@box /Users/jdoe/work $ "])

        let prepared = try FixtureExport.prepare(raw, sanitizer: FixtureSanitizer(salt: 7), leakGuard: leakGuard)
        let json = String(decoding: prepared.data, as: UTF8.self)

        #expect(!json.localizedCaseInsensitiveContains("jdoe"))
        #expect(!json.contains("work"))
        #expect(prepared.fixture == raw.sanitized(with: FixtureSanitizer(salt: 7)))
        #expect(try JSONDecoder().decode(ScreenFixture.self, from: prepared.data) == prepared.fixture)
    }
}
