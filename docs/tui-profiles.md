# Adding a TUI profile

A **profile** teaches HoverTalk the layout of one terminal program, so it reads the answer and skips the interface. Existing profiles: `OpenCodeProfile`, `ClaudeCodeProfile`, `GentleShellProfile` (in `Sources/HoverTalkCore/Terminal/Profiles/`). Anything else falls back to `PlainTerminalProfile`, which reads every row.

## How a screen is read

1. Ghostty gives the whole screen as one text area. `AXScreenRows` and `TerminalGrid` turn it into rows × columns of cells.
2. `PaneLayout` splits it into panes from tmux's divider lines, and sets the tmux status bar aside.
3. For each pane, `TUIProfileRegistry` asks each profile whether it `matches`; the first match reads the pane.
4. The profile labels every row as `.content`, `.chrome` or `.end`. `TerminalGridProvider` expands the pointed row to the run of content rows around it.

## Steps

1. **Capture a sanitized fixture** of the program on screen (never commit a raw one):

   ```sh
   swift run HoverTalkCapture ax --delay 5 --out Tests/HoverTalkCoreTests/Fixtures/ghostty-<program>.json
   ```

   Show a conversation, the input area and any sidebar. Skim the file for private text.

2. **Write the profile** in `Sources/HoverTalkCore/Terminal/Profiles/<Name>Profile.swift`, conforming to `TUIProfile`:
   - `matches(paneLines:)`: recognise the program by two or more independent markers (glyphs are better than words: they survive translation and sanitizing).
   - `role(of:)` or `roles(ofPane:)`: return `.chrome` for borders, headers, footers, key hints, tool output and input boxes; `.content(text, columns:)` for answer text. Use `roles(ofPane:)` when a row's role depends on other rows. Return `.end` for a row that ends a message (continuous reading stops there). `columns` limits where pointing counts, which is how a sidebar is cut out.

3. **Register it** in `TUIProfileRegistry.standard`, before any profile whose markers its screens could also show.

4. **Test it** against the fixture, like `GentleShellProfileTests`: detection (and non-detection on other fixtures), chrome rows give no block, answer rows do, and the sidebar is never read.

5. Run `swift test`, then open a pull request.

## Tips

- Judge rows from the data, not fixed positions: panes have any size.
- Keep the profile free of user-specific words, names or paths.
- If your program shows a floating overlay over text, mark the rows it crosses as chrome (see how `GentleShellProfile` handles its "Jump to latest" pill).
