import AppKit

@main
@MainActor
enum HoverTalkApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        // NSApplication holds its delegate weakly; keep it alive for the whole run loop.
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
