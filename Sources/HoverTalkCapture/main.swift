import Foundation
import HoverTalkFixtureKit

// Development tool that writes sanitized screen fixtures. Raw captured text is never written
// or printed: it is sanitized and checked by `FixtureExport.prepare` first, and only the
// sanitized summary reaches stdout.

let usage = """
    Usage:
      HoverTalkCapture ax --out <path> [--delay <seconds>]
          Frontmost app's focused AXTextArea (fallback: the element under the mouse).
      HoverTalkCapture tmux-pane <target> --out <path>
          One tmux pane via `tmux capture-pane -p -t <target>`.
    Exit status: 0 written, 1 capture or write failed, 2 usage error,
    3 refused (a sensitive term survived sanitizing; nothing written).
    """

enum Command {
    case ax(out: String, delay: Double)
    case tmuxPane(target: String, out: String)
}

func parse(_ arguments: [String]) -> Command? {
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
