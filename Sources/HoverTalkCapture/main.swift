import Foundation
import HoverTalkFixtureKit

// Development tool that writes sanitized screen fixtures. Raw captured text is never written
// or printed: it is sanitized and checked by `FixtureExport.prepare` first, and only the
// sanitized summary reaches stdout. `probe` prints structure only (see `Probe`).

let usage = """
    Usage:
      HoverTalkCapture ax --out <path> [--delay <seconds>]
          Frontmost app's focused AXTextArea (fallback: the element under the mouse).
      HoverTalkCapture tmux-pane <target> --out <path>
          One tmux pane via `tmux capture-pane -p -t <target>`.
      HoverTalkCapture probe [--delay <seconds>]
          Runs the picker's reading pipeline on the element under the mouse and prints its
          structure only (role, frame, grid, panes, profile, block geometry and counts).
      HoverTalkCapture pipeline --app <bundle id>
          Runs a terminal pick (hover, click, reading document, anchor) on the app's focused
          AXTextArea without the mouse; prints counts and row ranges only.
      HoverTalkCapture axtree --app <bundle id> [--depth <n>] [--enable-web-ax]
          Prints the frontmost window's accessibility tree as structure only (roles, counts,
          frames, attribute names; never text). --enable-web-ax first asks Chromium/Electron
          apps to build their web accessibility tree.
    Exit status: 0 written or probed, 1 capture or write failed, 2 usage error,
    3 refused (a sensitive term survived sanitizing; nothing written).
    """

enum Command {
    case ax(out: String, delay: Double)
    case tmuxPane(target: String, out: String)
    case probe(delay: Double)
    case axTree(bundleID: String, depth: Int, enableWebAX: Bool)
    case pipeline(bundleID: String)
}

func parse(_ arguments: [String]) -> Command? {
    var arguments = arguments
    // `--enable-web-ax` is the only option without a value.
    let enableWebAX = arguments.contains("--enable-web-ax")
    arguments.removeAll { $0 == "--enable-web-ax" }
    var positional: [String] = []
    var options: [String: String] = [:]
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        if argument.hasPrefix("--") {
            guard index + 1 < arguments.count, options[argument] == nil else { return nil }
            options[argument] = arguments[index + 1]
            index += 2
        } else {
            positional.append(argument)
            index += 1
        }
    }
    if positional == ["pipeline"], !enableWebAX {
        guard let bundleID = options.removeValue(forKey: "--app"), options.isEmpty else { return nil }
        return .pipeline(bundleID: bundleID)
    }
    if positional == ["axtree"] {
        guard let bundleID = options.removeValue(forKey: "--app") else { return nil }
        let depth = options.removeValue(forKey: "--depth").map { Int($0) } ?? AXTreeProbe.defaultDepth
        guard let depth, depth > 0, options.isEmpty else { return nil }
        return .axTree(bundleID: bundleID, depth: depth, enableWebAX: enableWebAX)
    }
    guard !enableWebAX else { return nil }
    if positional == ["probe"] {
        let delay = options.removeValue(forKey: "--delay").map { Double($0) } ?? 0
        guard let delay, delay >= 0, options.isEmpty else { return nil }
        return .probe(delay: delay)
    }
    guard let out = options.removeValue(forKey: "--out") else { return nil }
    if positional == ["ax"] {
        let delay = options.removeValue(forKey: "--delay").map { Double($0) } ?? 0
        guard let delay, delay >= 0, options.isEmpty else { return nil }
        return .ax(out: out, delay: delay)
    }
    if positional.count == 2, positional[0] == "tmux-pane", options.isEmpty {
        return .tmuxPane(target: positional[1], out: out)
    }
    return nil
}

func fail(_ message: String, status: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(status)
}

guard let command = parse(Array(CommandLine.arguments.dropFirst())) else {
    fail(usage, status: 2)
}

let raw: ScreenFixture
let outPath: String
switch command {
case let .probe(delay):
    if delay > 0 { Thread.sleep(forTimeInterval: delay) }
    exit(Probe.run())
case let .pipeline(bundleID):
    exit(MainActor.assumeIsolated { PipelineProbe.run(bundleID: bundleID) })
case let .axTree(bundleID, depth, enableWebAX):
    exit(MainActor.assumeIsolated { AXTreeProbe.run(bundleID: bundleID, depth: depth, enableWebAX: enableWebAX) })
case let .ax(out, delay):
    outPath = out
    if delay > 0 { Thread.sleep(forTimeInterval: delay) }
    do { raw = try AXCapture.capture() } catch { fail(error.message, status: 1) }
case let .tmuxPane(target, out):
    outPath = out
    do { raw = try TmuxCapture.capture(target: target) } catch { fail(error.message, status: 1) }
}

let prepared: FixtureExport.Prepared
do {
    prepared = try FixtureExport.prepare(raw, sanitizer: FixtureSanitizer(), leakGuard: .forCurrentUser())
} catch let failure as FixtureExport.Failure {
    fail(failure.message, status: 3)
} catch {
    fail("Could not encode the fixture.", status: 1)
}

do {
    try prepared.data.write(to: URL(fileURLWithPath: outPath), options: .atomic)
} catch {
    fail("Could not write \(outPath).", status: 1)
}

let summary = FixtureSummary(prepared.fixture)
print("wrote \(outPath)")
print("lines: \(summary.lineCount)")
print("max width: \(summary.maxWidth)")
print("non-ASCII scalars: \(summary.nonASCIIScalars.joined(separator: " "))")
print("first lines (sanitized):")
for line in summary.firstLines {
    print("  |\(line)|")
}
