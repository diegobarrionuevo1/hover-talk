/// Words that `FixtureSanitizer` keeps verbatim so fixtures still show the TUI chrome that
/// profile detection depends on. A letter run is kept only when the whole run equals one of
/// these words, compared case-insensitively.
///
/// This list must only contain generic, public UI vocabulary: key names, tool and shell names,
/// and footer labels. Never add names, project names, path components or any word taken from
/// conversation content.
enum ChromeAllowlist {
    static let words: Set<String> = [
        "esc", "interrupt", "ctrl", "tab", "enter",
        "commands", "agents", "shortcuts",
        "opencode", "claude", "code", "build", "plan",
        "tokens", "context", "cost",
        "tmux", "fish", "zsh", "bash",
    ]
}
