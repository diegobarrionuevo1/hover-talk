import Foundation
import HoverTalkFixtureKit

/// Reads one tmux pane with `tmux capture-pane -p`, which only prints the pane and changes
/// nothing on screen. The raw text stays in memory; callers sanitize it.
enum TmuxCapture {
    enum Failure: Error {
        case launch
        case exitStatus(Int32)

        var message: String {
            switch self {
            case .launch:
                return "Could not launch tmux through /usr/bin/env."
            case let .exitStatus(status):
                // tmux's own stderr is discarded rather than echoed, so this message stays generic.
                return "tmux capture-pane failed with exit status \(status). Check the target with `tmux list-panes -a`."
            }
        }
    }

    static func capture(target: String) throws(Failure) -> ScreenFixture {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["tmux", "capture-pane", "-p", "-t", target]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw .launch
        }
        // Read before waiting so a full pipe cannot block tmux.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw .exitStatus(process.terminationStatus) }
        return ScreenFixture(frame: nil, lines: ScreenFixture.lines(fromTmuxCapture: String(decoding: data, as: UTF8.self)))
    }
}
