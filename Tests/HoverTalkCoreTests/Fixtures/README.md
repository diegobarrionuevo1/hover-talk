# Screen fixtures

Terminal screens for testing the text providers: real ones, sanitized, and hand-written synthetic ones (see "Synthetic fixtures"). Each file is JSON:

- `frame`: the `AXTextArea` frame in AX coordinates (top-left origin), or `null` when the source has no frame.
- `lines`: the screen text, one string per row.

## Capture

Fixtures are written by the development tool `HoverTalkCapture`. It is not part of the app bundle.

```sh
# Frontmost app's focused AXTextArea (fallback: the element under the mouse).
# --delay gives you time to bring the right window to the front.
swift run HoverTalkCapture ax --delay 5 --out Tests/HoverTalkCoreTests/Fixtures/<name>.json

# One tmux pane, read-only (`tmux capture-pane -p -t <target>`). Find the target with
# `tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_current_command}'`.
swift run HoverTalkCapture tmux-pane <target> --out Tests/HoverTalkCoreTests/Fixtures/<name>.json
```

The AX capture needs the Accessibility permission for the terminal that runs the tool. `tmux capture-pane -p` drops trailing spaces; the AX capture keeps them.

## Sanitization guarantees

Implemented in `Sources/HoverTalkFixtureKit`, tested in `Tests/HoverTalkFixtureKitTests`:

- Every run of letters becomes a neutral word of the same length, keeping the case of each letter. The choice uses a keyed hash with a random salt that exists only in memory during one capture, so the same word maps to the same replacement within one fixture, and a word never maps to itself.
- Every digit becomes a different digit; a repeated number gets the same replacement within one fixture.
- Whitespace (including trailing spaces), punctuation, symbols, box-drawing and block glyphs, braille and emoji are kept verbatim.
- A short allowlist of generic TUI words (`esc`, `ctrl`, `tab`, `opencode`, `tmux`, `fish`, …) is kept verbatim, as whole words only.
- Before writing, the tool refuses (exit status 3, no content printed) if the result still contains the user name, a part of the full name of three or more characters, the host name, or the home directory path.
- The raw capture is never written or printed; the tool prints only a sanitized summary.

Line count, line lengths, layout and glyphs are real; the words and numbers are not. Allowlisted words that also occur in ordinary prose stay readable.

## Synthetic fixtures

- `synthetic-claude-code.json` is hand-written, not captured: a Claude Code screen modelled on its well-known layout (welcome and input boxes, `⏺` messages and tool calls, `⎿` results, hint rows), with neutral made-up text and `frame: null`. It has not been checked against a live capture yet; replace it with a sanitized capture when one exists. Its rows carry no trailing spaces.

- `synthetic-gentle-shell-sidebar.json` is hand-written too: a full-width Gentle Shell under a tmux status row, with its right sidebar (sections behind `▾`), memory echo rows, the "Jump to latest message" pill, the editor frame and the footer. It is the layout of later Gentle Shell versions, which draw no `▎` gutters or `▔▔▔` rule in the conversation (the captured `ghostty-tmux-gentle-shell.json` is the earlier one). Neutral made-up text, `frame: null`. Replace it with a sanitized capture of a screen that shows the sidebar when one exists.

## Adding a fixture

1. Set up the screen you need and run one of the commands above with a descriptive name (`<app>-<layout>-<content>.json`).
2. Check the printed summary and skim the file: no readable sentences, names or paths.
3. Add a test that loads it with `ScreenFixture.load("<name>")` from `Support/`.
