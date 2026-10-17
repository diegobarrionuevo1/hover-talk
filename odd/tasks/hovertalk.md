# HoverTalk (working name) — feature document

Single source of truth for this feature. Locator: `odd/tasks/hovertalk.md`. Engram mirror: topic `odd/hovertalk/tasks` (project `hover-talk`). Probe sources live in `spikes/ax-probes/`.

## Objective
Build an open-source macOS menu-bar utility that reads text aloud from any app. Press a hotkey, point at a block of text (it gets highlighted), click, and listen. The player has real controls: pause/resume, back/forward one sentence, and speed.

## Problem
- The macOS Spoken Content features are built for screen-reader navigation, not for this flow.
  - "Speak selection" reads unwanted UI chrome: titles, sidebars, buttons.
  - "Speak items under the pointer" runs continuously, can't be triggered by a hotkey, and reads either the whole terminal window or only a fragment (in one test it read just the first sentence of a paragraph, up to a colon).
- In Ghostty the built-in readers read the entire screen, starting with the tmux status bar.
- Nothing lets the user say "read exactly this block" anywhere, and then control playback.

## Why
- The founder works with long AI agent responses (OpenCode and Claude Code in Ghostty, OpenCode Web in a browser).
- They want to listen to those responses while doing something else.
- It must work across apps, not only inside one tool.

## Scope
- **Picker mode:** a global hotkey shows a highlight overlay over the text block under the cursor. Click reads it; Esc cancels.
- **Read selection** and **read all** (whole window or page) modes, each with its own hotkey.
- **Floating controller:** pause/resume, back/forward one sentence, speed −/+, stop.
- **Supported apps:**
  - Ghostty with the OpenCode TUI, Claude Code, and a plain shell, including inside tmux.
  - Safari, Chrome, and native apps.
- **Settings:** hotkeys, voice, rate, persisted locally.

## Out of scope (for now)
- Speech-to-text and microphones.
- Cloud voices.
- Kokoro/Piper (keep a `SpeechEngine` protocol so they can be added later).
- iOS (separate bookmarklet project).
- OCR (only as a last-resort fallback, and ask first).

## Constraints
- Swift and SwiftPM. Package as a menu-bar app (`LSUIElement`) with a small bundling script; avoid a heavy Xcode project if possible.
- Requires the Accessibility permission. Detect `AXIsProcessTrusted()` and guide the user to System Settings.
- **Privacy:** no network calls, and no telemetry.
- **Public fixtures:** sanitize screen dumps. They must not contain private paths, project names, usernames, or conversation content.
- MIT licence. Conventional Commits, no AI attribution.
- **Remote operations:** ask the founder before creating the GitHub repo, pushing, publishing a release, or planning notarization (it needs an Apple Developer account).
- **Name:** "HoverTalk" is a working name; confirm the final one with the founder before any remote step. A check on 2026-10-16 found 1 GitHub repo with that exact name and no Homebrew cask.

## Validated facts (probe on 2026-10-16: macOS 26.2, Ghostty 1.3.1, OpenCode TUI inside tmux)
The probe sources are in `spikes/ax-probes/`:
- `axprobe.swift` — element under the mouse and focused element.
- `axlines.swift` — line count, frame and parameterized attributes.
- `axpara.swift` — paragraph-under-mouse prototype.

Findings:
- **One text area for the whole screen.** Ghostty exposes the entire visible screen as ONE `AXTextArea`. Its `AXValue` was 45 lines × 209 columns, about 9.4k characters, with lines separated by `\n`.
- **Parameterized attributes supported:** `AXStringForRange`, `AXAttributedStringForRange`, `AXLineForIndex`, `AXReplaceRangeWithText`.
- **Not supported:** `AXRangeForPosition`, and no `AXSelectedText`.
- **Geometry:** `AXPosition`/`AXSize` give the frame (for example (0,65) with 1470×801). The AX coordinate origin is top-left, so convert `NSEvent.mouseLocation` with the screen height.
- **Row under the mouse:** `Int((mouseY - frame.y) / (frame.height / lineCount))`. The prototype found the correct row and expanded it to a paragraph bounded by blank lines.
- **TUI chrome breaks naive extraction.** When the mouse was over OpenCode's input box, the result mixed in the agent/model footer, the `╹▀▀▀` border, the cwd and the cost line. The chrome to strip:
  - OpenCode: the `┃` gutter on messages, the right sidebar after `│`, box-drawing borders, and the input box, footer and status lines.
  - Claude Code: different decorations (not probed yet).
  - tmux: the status bar on the first or last line.
- **Visible screen only.** OpenCode's TUI scrolls internally. Off-screen content needs scrolling, or a later OpenCode-specific mode using `opencode export <sessionID>`.
- **Chrome and Electron** expose their AX tree only when asked. Setting `AXManualAccessibility` or `AXEnhancedUserInterface` on the app element should enable it. NOT verified yet.
- **Selection** cannot come from Ghostty's AX. The fallback is to simulate Cmd+C, read the pasteboard, then restore its previous contents. NOT verified with OpenCode's own mouse selection or with tmux copy mode.

### Re-probe in the new repository (2026-10-16, same setup)
All three probes re-run from `spikes/ax-probes/`; `trusted=true`, frontmost Ghostty, under-mouse and focused element are the same `AXTextArea` (9449 chars, 45 lines × 209 columns, frame (0,65) 1470×801), same four parameterized attributes, `AXRangeForPosition` not supported. A content-masked shape dump (letters and digits replaced, never stored) showed:
- **tmux split panes share the one text area.** The screen was two side-by-side tmux panes. The `│` (U+2502) at the same column on every row below the status bar was the **tmux pane divider**, not an OpenCode sidebar. Each pane ran its own OpenCode TUI. Consequence: the provider must also map mouse X to a column, detect vertical dividers that are consistent across rows, and work only inside the pane under the mouse. Row-only mapping plus "cut after the last `│`" is wrong for splits.
- **tmux status bar** was row 0 (window list on the left, right-aligned status with `✓`, CPU/RAM).
- **OpenCode assistant text** has no gutter: a 5-space indent; list items `1.`/`-` with hanging indents on wrapped lines; blank lines separate paragraphs.
- **OpenCode message footer:** a line `▣  <agent> · <model> · <duration>` (U+25A3, U+00B7) after an assistant message.
- **OpenCode user/tool blocks** use the `┃` (U+2503) gutter with 2 leading spaces; a braille spinner (U+2838 etc.) marks running tools.
- **OpenCode input box:** rows of `  ┃` followed by an agent/model line, closed by `  ╹▀▀▀…` (U+2579, U+2580); the line below holds cwd, token count `(NN%)`, cost `$N.NN`, and a key hint. Progress dots `⬝` (U+2B1D) may appear there.

## Architecture
- **`TextProvider` protocol:** `blockAt(point) -> (text, rect)?`, `selection() -> String?`, `all() -> String?`.
  - `GenericAXProvider`: element at the position, walking up to a paragraph-level element. Covers Safari, native apps, and Chrome once its AX tree is enabled.
  - `TerminalGridProvider`: row mapping, paragraph expansion, and wrapped-line joining. Uses data-driven `TUIProfile`s (OpenCode, Claude Code, tmux, plain shell) detected by screen-content markers, so the community can add more.
- **`Overlay`:** a transparent, borderless, non-activating window that draws the highlight rectangle and captures the click only in picker mode.
- **`SpeechEngine` protocol**, with an `AVSpeechSynthesizer` implementation. It splits text into sentences so back/forward moves by sentence.
- **`TextCleaner`:** collapses whitespace, drops box-drawing and decorative glyphs, and turns code blocks into "code omitted" (configurable).
- **`Controller`:** a floating `NSPanel`.

## Delivery
- **Checkpoint after T6:** demo the picker on Ghostty with OpenCode and Claude Code to the founder before building settings and polish.
- **Commits:** one work-unit commit per task, with its tests.
- **Branches:** work on a feature branch, or on `main` while there is no remote yet. The founder decides pushes and PRs.
- **Delivery strategy:** `ask-on-risk`. Forecast for T1–T12 is well above 400 authored changed lines. There is no remote, so commits land on `main`; the chain strategy question (`stacked-to-main` or `feature-branch-chain`) is deferred until the founder authorizes a remote (T12). Slice boundaries are recorded in the task log below.
- **Review (RDD on, global):** after each work-unit commit run `gentle-ai review assess --committed-only` against the last reviewed boundary; the first boundary is the bootstrap commit that adds this document and the probes.

## Tasks
- [x] **T1** Scaffold: SwiftPM package, menu-bar app target, bundling script into `.app` (`LSUIElement`), Accessibility permission check and onboarding prompt, MIT `LICENSE`, `.gitignore`.
- [x] **T2** Sentence splitter and `SpeechEngine`. Playback queue with pause/resume, back/forward by sentence, rate change, stop. Unit tests for splitting and queue navigation.
- [x] **T3** Floating controller panel wired to `SpeechEngine`.
- [x] **T4** `TerminalGridProvider`: mouse → row mapping, paragraph expansion, wrapped-line joining, rect for the highlight. Tests with sanitized fixtures captured from real Ghostty dumps. Split into two work units (2026-10-16, because real-but-sanitized fixtures need a tool first):
  - [x] **T4a** Dev capture tool + sanitizer: reads the live Ghostty `AXTextArea` (or a tmux pane via `tmux capture-pane`), replaces every letter run with a same-length neutral word (salted, not reversible) and digits with digits, keeps punctuation, whitespace and TUI glyphs plus an allowlist of public TUI chrome words, refuses to write if the username, full name, hostname or home path survive. Writes JSON fixtures (`frame`, `lines`). Fixtures: the live tmux vertical split with two OpenCode panes (AX), a plain fish shell (tmux pane capture, no tmux chrome).
  - [x] **T4b** Provider: grid model, pane detection (tmux vertical/horizontal dividers, status row), mouse → (row, column) → pane, paragraph expansion inside the pane, wrapped-line joining (list markers start a new line), highlight rect in AX coordinates, a `TUIProfile` hook for T5 (plain profile only here), and an app-side Ghostty AX source.
- [ ] **T5** TUI profiles: OpenCode, Claude Code, tmux status bar, plain shell. Detection markers and chrome stripping. Fixture tests per profile.
- [ ] **T6** Picker mode: global hotkey, overlay highlight following the mouse, click to read, Esc to cancel. **Checkpoint demo with the founder.**
  - Follow-up from T1 review (R3/R4 warnings): trust polling stops once granted, so a revocation while running leaves the menu saying "Granted". When an AX read fails, re-check `AXIsProcessTrusted()`, update the status and restart polling. Also consider showing only one of the two first-launch dialogs (system prompt and our alert).
- [ ] **T7** `GenericAXProvider` for Safari and native apps, plus enabling Chrome's AX tree. Record a supported-apps matrix (works / partial / no) in the README.
- [ ] **T8** Read-selection mode: AX selection first, then the Cmd+C fallback with pasteboard restore. Verify in Ghostty with OpenCode's mouse selection and with tmux.
- [ ] **T9** Read-all mode (window or page, chrome-stripped).
- [ ] **T10** Settings: hotkeys, voice (recommend Premium/Enhanced voices), rate, code-block handling. Persisted locally.
- [ ] **T11** README in English: what it does, demo GIF placeholder, install, permissions, hotkeys, supported-apps matrix, how to add a TUI profile, limitations.
- [ ] **T12** Release prep. Ask the founder first: final name, GitHub repo creation, push, unsigned release build, notarization decision.

## Acceptance criteria
- In Ghostty with OpenCode, pointing at a paragraph of an assistant response highlights only that paragraph. It reads aloud without sidebar, borders, footer or tmux text.
- The same works with Claude Code in Ghostty.
- Back/forward moves exactly one sentence, and the speed change applies while playing.
- Safari and Chrome: pointing at a paragraph reads only that paragraph.
- No network access. Fixtures contain no private data.

## Checks
- `swift build` and `swift test` (unit tests for the pure logic).
- Manual checklist per app in the supported-apps matrix.

## Task log
Per task: route (inline or delegated, with trigger), commit, checks observed, review tier and outcome.

| Task | Route | Commit | Checks | Review |
|------|-------|--------|--------|--------|
| bootstrap | inline (mechanical move) | e0ff76d | structural readback | first boundary (no assess: empty base) |
| T1 | delegated (writer trigger: 7+ non-trivial files) | 421ff25 | `swift build` ok, no warnings; `swift test` 9/9 (RED observed first); `bundle.sh` ok; plist lint ok; `LSUIElement` true; codesign valid | high → granted → 4 lenses approved, acknowledged (boundary 421ff25) |
| T2 | delegated (writer trigger: 10 non-trivial files; resumed once after an API disconnect) | 0213aeb | `swift build` 0 warnings; `swift test` 79/79 (RED observed per suite first); `bundle.sh` ok | medium, `review_due` false: `under_budget` reported for 1427 changed lines (looks like a budget-classification defect in the tool; recorded, not overridden); slice stays pending from 421ff25 |
| T3 | delegated (writer trigger: 8 non-trivial files) | 7197ac5 | `swift build` 0 warnings; `swift test` 100/100 (RED observed; mutation check on negative tests); `bundle.sh` ok; release binary has no debug clipboard symbol | medium, `review_due` false: `under_budget` at 2107 changed lines since 421ff25 (same suspected tool defect); slice pending |
| T4a | delegated (writer trigger: 15 files; privacy-sensitive capture) | 1497c24 | `swift build` 0 warnings; `swift test` 131/131 (RED observed, mutation checks); `bundle.sh` ships only `HoverTalk`; parent leak grep on fixtures: username, hostname, home, name parts, project and branch tokens all 0 | medium, `under_budget` at 3201 lines (suspected tool defect); slice pending |
| T4b | delegated (writer trigger: 10 files; first worker aborted, second finished it) | see git log (`feat: add terminal grid provider with pane detection`) | `swift build` 0 warnings; `swift test` 168/168; failability proven by 8 mutation checks (test-first RED not observed by the finishing worker); `bundle.sh` ok | pending assess |

## Progress
- 2026-10-16: The AX feasibility probe on Ghostty is done (see Validated facts).
- 2026-10-16: Repository initialised (`main`), document moved here, probes moved to `spikes/ax-probes/`, probes re-run (see Re-probe). Environment: macOS 26.2, Swift 6.3.2, Xcode installed.
- 2026-10-16: T1 done. Targets `HoverTalkCore` (pure, no AppKit, Swift Testing), `HoverTalk` (AppKit executable), `HoverTalkCoreTests`. The working name lives in `AppInfo.name` and the top of `scripts/bundle.sh`. Gotchas: Swift 6 rejects `kAXTrustedCheckOptionPrompt` unless `ApplicationServices` is imported with `@preconcurrency` (kept to one file); the ad-hoc signature changes per build, so macOS may re-ask for Accessibility after rebuilding. Pending manual check: launch the app and confirm the onboarding alert, menu and polling flip to Granted.
- 2026-10-16: T2 done (~1.4k authored lines, 922 of them tests; over the 400 heuristic because the queue's state × command sequences and the stale-event race tests need it). `PlaybackQueue` is a pure state machine returning `SpeechCommand`s; every utterance has a UUID and stale engine events are ignored (prevents the late didFinish/didCancel double-skip). Rate change while playing re-speaks the rest of the sentence from the last word offset (UTF-16, rounded to a Character boundary). NLTokenizer facts (macOS 26.2): keeps "Dr.", "e.g.", "3.5", "v1.2.3", "Package.swift" intact; does not split "it works. then…" (lowercase after period). Unverified until T3 audio check: `AVSpeechEngine` delegate identity mapping, didCancel after stop, speak right after stop while paused. Product defaults to confirm at the checkpoint: next/previous do nothing while idle; stop resets to sentence 0. Spanish text may get a non-Spanish default voice until T10.
- 2026-10-16: T3 done (~676 authored lines). Core: `ControllerPresentation`, `ControllerPlacement`, `ControllerAction` + `Player.perform`. App: borderless non-activating `ControllerPanel` (AppKit, `acceptsFirstMouse`), `ReadingSession.read(_:)` as the single entry point for T6–T9, DEBUG-only "Read Clipboard" menu item for smoke tests via `swift run`. Not yet seen on screen: click-through, drag, HUD contrast, no focus steal, audio. Checkpoint defaults to confirm: previous disabled at sentence 1 and next at the last sentence; panel re-centers on the mouse's screen each time (no remembered position until T10).
- 2026-10-16: T4a done (~977 authored lines). Dev-only `HoverTalkCapture` (`swift run HoverTalkCapture ax|tmux-pane`) + pure `HoverTalkFixtureKit` sanitizer (same-length neutral words, salted, never identical, digits changed, chrome allowlist, leak guard on username/full name/hostname/home before writing). Fixtures: `ghostty-tmux-vsplit-opencode.json` (51×273, AX) and `plain-shell-fish.json` (44×104, tmux pane). Facts for T4b: the AX frame was on a second screen (x=1470, y=62, 1920×928), so never assume x=0 and convert `NSEvent.mouseLocation` with the PRIMARY screen height; a wide glyph (U+23F3) is one Character but two cells, so map mouse X to cells, not Character indices; `tmux capture-pane -p` trims trailing spaces while Ghostty AX pads rows.
- 2026-10-16: T4b done (~891 authored lines). `TerminalGrid` (cell-aware, wide glyphs = 2 cells), `TerminalGeometry` + `AXCoordinates.fromCocoa`, recursive `PaneLayout.detect` (vsplit fixture: status row 0, panes cols 0…142 and 144…272, divider col 143), `TUIProfile` + `PlainTerminalProfile`, `TerminalGridProvider.block(at:)`, app-side `TerminalAXSource` with typed failures (`notTrusted`, `noElement`, `notATextArea`, `noFrame`). Correction to the Re-probe: OpenCode ALSO has an in-pane right sidebar with no `│` separator (left pane from about cell 100, rows 1–28), so T5 must strip it by column, not by divider. The `┃` gutter is missing on some message rows. `TerminalAXSource` sets no AX messaging timeout yet (T6 should set one).

## Next step
T5 TUI profiles.
