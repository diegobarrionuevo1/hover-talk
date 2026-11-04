import Foundation
import HoverTalkCore

/// Asks tmux whether the terminal screen being read has a status bar (see `TmuxClients`).
/// A Finder-launched app has a minimal `PATH`, so tmux is looked up in the usual install
/// folders. The answer for the last `lifetime` seconds is reused: the screen is parsed on
/// every change while a program prints. When that answer has no client of the screen's size
/// (the window was just resized), tmux is asked again, at most every `retryInterval` seconds.
final class TmuxStatusProbe: @unchecked Sendable {
    private static let candidates = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
    private static let lifetime: TimeInterval = 1
    private static let retryInterval: TimeInterval = 0.2
    private static let timeout: TimeInterval = 1

    private let lock = NSLock()
    private var last: (output: String, time: Date)?

    /// The status bar edge for a screen of `columns` × `rows` cells, or `nil` when tmux is not
    /// installed, not running, or has no attached client of that size.
    func statusBar(columns: Int, rows: Int) -> StatusEdge? {
        let cached = clients(maxAge: Self.lifetime)
        if let edge = TmuxClients.statusBar(in: cached, columns: columns, rows: rows) { return edge }
        return TmuxClients.statusBar(in: clients(maxAge: Self.retryInterval), columns: columns, rows: rows)
    }

    private func clients(maxAge: TimeInterval) -> String {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        if let last, now.timeIntervalSince(last.time) < maxAge { return last.output }
        let output = Self.run() ?? ""
        last = (output, now)
        return output
    }

    private static func run() -> String? {
        guard let tmux = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tmux)
        process.arguments = ["list-clients", "-F", TmuxClients.listFormat]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { return nil }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}
