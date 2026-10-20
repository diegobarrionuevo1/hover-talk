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
- Cloud voice vendors (paid APIs). A user-hosted OpenAI-compatible endpoint is allowed.
- Running Kokoro/Piper inside the app. A self-hosted server on another machine is IN scope (T6d); the app does not bundle a model.
- iOS (separate bookmarklet project).
- OCR (only as a last-resort fallback, and ask first).

## Constraints
- Swift and SwiftPM. Package as a menu-bar app (`LSUIElement`) with a small bundling script; avoid a heavy Xcode project if possible.
- Requires the Accessibility permission. Detect `AXIsProcessTrusted()` and guide the user to System Settings.
- **Privacy:** no telemetry. No network calls, except the opt-in voice server the user configures (founder request, 2026-10-19): off by default, only the URL the user enters, only the text being read is sent, never anything else.
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
- **Soft wraps (probe 2026-10-17):** Ghostty's `AXValue` has NO `\n` after a soft-wrapped row: a line wrapped over k rows arrives as one string of k × width cells (seen: 38 lines of 209 cells plus one of 1463 = 7 × 209). `AXScreenRows.split` restores screen rows.
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
- [x] **T5** TUI profiles: OpenCode, Claude Code, tmux status bar, plain shell. Detection markers and chrome stripping. Fixture tests per profile.
- [x] **T6** Picker mode: global hotkey, overlay highlight following the mouse, click to read, Esc to cancel. **Checkpoint demo with the founder.**
  - [x] Follow-up from T1 review (R3/R4 warnings): trust polling stops once granted, so a revocation while running leaves the menu saying "Granted". When an AX read fails, re-check `AXIsProcessTrusted()`, update the status and restart polling. Also consider showing only one of the two first-launch dialogs (system prompt and our alert).
- [x] **Checkpoint feedback (2026-10-19)** — founder asked for four changes before T7. Decisions taken autonomously by the orchestrator (founder authorized autonomous decisions):
  - [x] **T6a** Reading highlight on screen: while reading, the whole queued text keeps a light highlight and the current sentence gets a stronger one. Design: a `MappedText` (string + source cell per Character) flows through `TextCleaner` and the sentence splitter (ranges, not strings), so every sentence maps back to per-row cell rects. When the screen scrolls or changes, re-anchor by finding the captured rows again inside the pane (vertical shift); if they are gone, hide the highlight but keep reading.
  - [x] **T6b** Continuous reading + drag selection. Continuous: a controller toggle (default ON); a click reads the pointed paragraph and then every following readable paragraph of the same pane down to the end of the visible content (chrome such as the input box stops it). Off-screen continuation (scrolling the TUI) stays out of scope. Drag: press, drag and release selects a cell range in reading order inside one pane (chrome stripped) and reads exactly that; a press without movement (threshold 4 pt) stays a paragraph click. The overlay shows the live drag selection.
  - [x] **T6c** System voices: a voice catalog from `AVSpeechSynthesisVoice` grouped by language with quality (default / enhanced / premium); the menu gets a Voice submenu and "Download More Voices…" which opens System Settings > Accessibility > Spoken Content. Minimal Settings window and `UserDefaults` persistence pulled forward from T10 (voice, rate, remote server).
  - [x] **T6d** Remote voice: `RemoteSpeechEngine` for any OpenAI-compatible `/v1/audio/speech` (tested target: Kokoro-FastAPI on the founder's other PC). Health check with a short timeout, an availability state machine with backoff re-probing, prefetch of the next sentences, playback through `AVAudioEngine` + time-pitch so rate changes apply live. If the server is off or fails mid-reading, fall back to the system voice immediately for the rest of that reading and show the status in the menu; go back to the remote voice at the start of the next reading once a probe succeeds. Docs: how to run the server. Setting up the other PC is a remote operation and needs the founder.
- [ ] **T7** `GenericAXProvider` for Safari and native apps, plus enabling Chrome's AX tree. Record a supported-apps matrix (works / partial / no) in the README.
- [ ] **T8** Read-selection mode: AX selection first, then the Cmd+C fallback with pasteboard restore. Verify in Ghostty with OpenCode's mouse selection and with tmux.
- [ ] **T9** Read-all mode (window or page, chrome-stripped).
- [ ] **T10** Settings: hotkeys and code-block handling (voice, rate and continuous mode moved into T6c). Persisted locally.
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
| T4b | delegated (writer trigger: 10 files; first worker aborted, second finished it) | 29d9273 | `swift build` 0 warnings; `swift test` 168/168; failability proven by 8 mutation checks (test-first RED not observed by the finishing worker); `bundle.sh` ok | medium, `under_budget` at 4094 lines (suspected tool defect); slice pending |
| T5 | delegated (writer trigger: 16 files) | 418ecba | `swift build` 0 warnings; `swift test` 212/212 (RED: 36 failing tests first; 11 mutation checks) | medium, `under_budget` at 5279 lines (suspected tool defect); slice pending |
| T6 | delegated (writer trigger: 20+ files) | aa886ec | `swift build` 0 warnings; `swift test` 257/257 (RED: 63 issues on stubs first; 9 mutation checks); `bundle.sh` ok; live `probe` structural only | medium, `under_budget` at 6860 lines (suspected tool defect); slice pending |
| T6a | delegated (writer trigger: 20 files; first run returned empty, resumed) | 932ba16 | `swift build` 0 warnings; `swift test` 295/295 (RED: 29 failing first; 8 mutation checks) | medium, `under_budget` at 8050 lines (suspected tool defect); slice pending |
| T6b | delegated (writer trigger: 25 files) | cacd299 | `swift build` 0 warnings; `swift test` 330/330 (RED: 26 failing first; 13 mutation checks) | medium, `under_budget` at 9079 lines (suspected tool defect); slice pending |
| T6c | delegated (writer trigger: 25 files) | 47b3828 | clean build 0 warnings; `swift test` 369/369 (RED: 34 failing first; 13 mutation checks) | medium, `under_budget` at 10492 lines (suspected tool defect); slice pending |
| T6d-1 | delegated (split after two empty worker runs on the full T6d) | 626c896 | clean build 0 warnings; `swift test` 445/445 (RED: 62 failing first; 22 mutation checks) | assessed with T6d-2 |
| T6d-2 | delegated (writer trigger: 20 files) | see git log (`feat: add voice server engine, monitor and settings`) | clean build 0 warnings; `swift test` 476/476 (RED: 32 failing first; 5 mutation checks); `plutil -lint` ok; ATS keys present | assess vs 421ff25: high, `review_due` (14078 lines) → consent granted → START refused `lens_context_budget_exceeded` (no authority created). Consequence of the earlier `under_budget` misclassification: the unreviewed range grew past the reviewer budget. Remediation: review the riskiest slices separately (T6 event tap `418ecba..aa886ec`, T6d network `47b3828..574bfe8`) |

## Progress
- 2026-10-16: The AX feasibility probe on Ghostty is done (see Validated facts).
- 2026-10-16: Repository initialised (`main`), document moved here, probes moved to `spikes/ax-probes/`, probes re-run (see Re-probe). Environment: macOS 26.2, Swift 6.3.2, Xcode installed.
- 2026-10-16: T1 done. Targets `HoverTalkCore` (pure, no AppKit, Swift Testing), `HoverTalk` (AppKit executable), `HoverTalkCoreTests`. The working name lives in `AppInfo.name` and the top of `scripts/bundle.sh`. Gotchas: Swift 6 rejects `kAXTrustedCheckOptionPrompt` unless `ApplicationServices` is imported with `@preconcurrency` (kept to one file); the ad-hoc signature changes per build, so macOS may re-ask for Accessibility after rebuilding. Pending manual check: launch the app and confirm the onboarding alert, menu and polling flip to Granted.
- 2026-10-16: T2 done (~1.4k authored lines, 922 of them tests; over the 400 heuristic because the queue's state × command sequences and the stale-event race tests need it). `PlaybackQueue` is a pure state machine returning `SpeechCommand`s; every utterance has a UUID and stale engine events are ignored (prevents the late didFinish/didCancel double-skip). Rate change while playing re-speaks the rest of the sentence from the last word offset (UTF-16, rounded to a Character boundary). NLTokenizer facts (macOS 26.2): keeps "Dr.", "e.g.", "3.5", "v1.2.3", "Package.swift" intact; does not split "it works. then…" (lowercase after period). Unverified until T3 audio check: `AVSpeechEngine` delegate identity mapping, didCancel after stop, speak right after stop while paused. Product defaults to confirm at the checkpoint: next/previous do nothing while idle; stop resets to sentence 0. Spanish text may get a non-Spanish default voice until T10.
- 2026-10-16: T3 done (~676 authored lines). Core: `ControllerPresentation`, `ControllerPlacement`, `ControllerAction` + `Player.perform`. App: borderless non-activating `ControllerPanel` (AppKit, `acceptsFirstMouse`), `ReadingSession.read(_:)` as the single entry point for T6–T9, DEBUG-only "Read Clipboard" menu item for smoke tests via `swift run`. Not yet seen on screen: click-through, drag, HUD contrast, no focus steal, audio. Checkpoint defaults to confirm: previous disabled at sentence 1 and next at the last sentence; panel re-centers on the mouse's screen each time (no remembered position until T10).
- 2026-10-16: T4a done (~977 authored lines). Dev-only `HoverTalkCapture` (`swift run HoverTalkCapture ax|tmux-pane`) + pure `HoverTalkFixtureKit` sanitizer (same-length neutral words, salted, never identical, digits changed, chrome allowlist, leak guard on username/full name/hostname/home before writing). Fixtures: `ghostty-tmux-vsplit-opencode.json` (51×273, AX) and `plain-shell-fish.json` (44×104, tmux pane). Facts for T4b: the AX frame was on a second screen (x=1470, y=62, 1920×928), so never assume x=0 and convert `NSEvent.mouseLocation` with the PRIMARY screen height; a wide glyph (U+23F3) is one Character but two cells, so map mouse X to cells, not Character indices; `tmux capture-pane -p` trims trailing spaces while Ghostty AX pads rows.
- 2026-10-16: T4b done (~891 authored lines). `TerminalGrid` (cell-aware, wide glyphs = 2 cells), `TerminalGeometry` + `AXCoordinates.fromCocoa`, recursive `PaneLayout.detect` (vsplit fixture: status row 0, panes cols 0…142 and 144…272, divider col 143), `TUIProfile` + `PlainTerminalProfile`, `TerminalGridProvider.block(at:)`, app-side `TerminalAXSource` with typed failures (`notTrusted`, `noElement`, `notATextArea`, `noFrame`). Correction to the Re-probe: OpenCode ALSO has an in-pane right sidebar with no `│` separator (left pane from about cell 100, rows 1–28), so T5 must strip it by column, not by divider. The `┃` gutter is missing on some message rows. `TerminalAXSource` sets no AX messaging timeout yet (T6 should set one).
- 2026-10-16: T5 done (~1.25k changed lines). `OpenCodeProfile` (detection by `╹▀▀▀`, `▣`, status hints; input box, footer, spinner and tool blocks are chrome; `┃` gutter stripped; sidebar column found from the data: pane-relative 103 left, 89 right), `ClaudeCodeProfile` from a SYNTHETIC fixture (unverified against a live screen), `TUIProfileRegistry`, tmux status pane kind (nil), `TextCleaner` (decorative glyphs, markdown marks, fenced code → "Code omitted."). Highlight columns follow the cleaned content. Open for T6: wire `TextCleaner` before `read`; cache the parsed screen per AX value (`block()` ~4.7 ms release, ~32 ms debug); single-pane tmux keeps the status row inside the program pane (only peeled when the rest splits) — handle it by asking tmux for `status-position` or by a status-row shape check; long `┃` blocks with no blank rows read as one big paragraph.
- 2026-10-17: T6 done (~1.75k changed lines). ⌃⌥R (Carbon hotkey, also a menu item) starts picking; a per-screen, non-activating overlay outlines the block under the pointer; a `CGEventTap` consumes clicks and Esc (acts on release, so no orphan release reaches the terminal; Esc must never reach OpenCode). Click reads (text cleaned), a click on no block keeps picking, Esc or ⌃⌥R cancel. AX lookups run in an actor with a 0.25 s messaging timeout, cached per (AXValue, frame) via `ParsedScreen`. On launch only the system Accessibility prompt shows; a failed tap/AX read re-checks trust, restarts polling and alerts. Dev `swift run HoverTalkCapture probe` prints structure only. Not yet seen live: overlay, tap consumption, hotkey, focus. Known limits: Secure Keyboard Entry hides keys from taps (Esc would leak); every left click is consumed while picking; single-pane tmux status row; Claude Code profile still synthetic.
- 2026-10-19: Checkpoint feedback received: on-screen reading highlight, continuous reading, drag selection, voice choice (system voices plus a self-hosted server). Planned as T6a–T6d. Verified: Kokoro-FastAPI serves an OpenAI-compatible `POST /v1/audio/speech` (`model`, `input`, `voice`, `speed`, `response_format` wav/pcm/mp3) and `GET /v1/audio/voices`, default port 8880, Spanish voice `ef_dora` (source: github.com/remsky/Kokoro-FastAPI README).
- 2026-10-19: T6a done (~1.3k changed lines). `MappedText` (anchor per Character) flows through `TextCleaner.clean(_ mapped:)` and `SentenceSplitter.ranges(in:)` (both proven equivalent to the old string APIs); `ReadingDocument` gives per-sentence row spans; `ReadingAnchor` re-finds the block's own columns (not the whole row, so OpenCode sidebar updates do not break it) after scrolling; `ReadingHighlighter` refreshes every 0.5 s, light fill for the block, outlined strong fill for the current sentence, hidden while picking. Not yet seen live.
- 2026-10-19: T6b done (~1.4k changed lines). Continuous reading (default ON, `Preferences` in `UserDefaults`, controller toggle + "Continue Reading Below" menu item, applies to the next pick): reads from the pointed paragraph down to the pane's last content row; blank and chrome rows only separate paragraphs (tool blocks and footers between messages are skipped), and the input box ends reading naturally because everything below the last message is chrome. Drag selection: >4 pt movement = drag, live outline, release reads exactly the cells the profile reads, clamped to the start pane; continuous mode never applies to drags. Known gaps: plain shells read down to the prompt line; Esc during a held button lets the later mouse-up through.
- 2026-10-19: T6c done (~1.4k changed lines). `VoiceCatalog` (drops novelty voices and the 112 unflagged `com.apple.eloquence.*` voices; sorts preferred languages, then premium > enhanced > default; old voices like Fred last), `VoiceSelection` `.automatic` by default = best installed voice for the language `NLLanguageRecognizer` detects per reading (fallback: first preferred language). Voice change while playing restarts the current sentence. Voice submenu, "Download More Voices…" → `x-apple.systempreferences:com.apple.preference.universalaccess?TextToSpeech` (derived from the extension bundle, not opened yet), Settings window (⌘,) with voice search + preview, speed (now persisted), continuous mode, and a Voice Server placeholder. This Mac: 181 voices, only 1 premium (Marisol, es-ES), 54 after filtering. Gaps: no main menu, so ⌘C/⌘V do not work in the Settings search field; onboarding still says "no network calls" (T6d updates it).
- 2026-10-19: T6d done in two units (~3.8k changed lines). Core: `RemoteVoiceServerAddress` validation (accepts `…/v1`), in-memory `WAVDecoder` (no temp files), `RemoteVoiceAvailability` (backoff 5/15/30/60 s, re-probe on wake/network change), `RemoteVoiceCatalog` (Kokoro prefixes → language; automatic: `ef_dora` for es, `af_heart` for en-US), live-rate capability (`.setRate`), prefetch hint, `FallbackSpeechEngine` (failure → restart the current sentence on the system voice, stays there until the next reading, ignores events from the inactive engine). App: `RemoteVoiceClient` (ephemeral URLSession), `RemoteSpeechEngine` (AVAudioEngine + time-pitch, speed applied locally so one synthesis serves every rate, prefetch current + 2), `RemoteVoiceMonitor`, Settings Voice Server section with Test Connection, Voice menu status line, controller notice icon, onboarding copy updated, `docs/voice-server.md`. Verified in Apple's docs: `NSAllowsLocalNetworking` covers unqualified names, `.local` and IPv4/IPv6 addresses (required since macOS 14); `*.ts.net` over http is blocked (use https). Limits: availability probe needs `GET /v1/audio/voices` (OpenAI itself lacks it); full WAV download before playback (first-sentence latency = synthesis time); nothing run live yet.

- 2026-10-20: Demo bug fixed: the app froze (menu, hotkey, panel) after changing the voice. Sampled the live process: AVFoundation posted `availableVoicesDidChangeNotification` from a background thread and waited (`waitUntilFinished`) for our `queue: .main` observer, whose `AVSpeechSynthesisVoice.speechVoices()` waited on a semaphore held by that same thread: deadlock. Fix: observe with `queue: nil`, hop to main asynchronously and coalesce (0.5 s). Same pattern removed from the `AVAudioEngineConfigurationChange` observer. Rule: never observe AVFoundation notifications on `queue: .main` with synchronous AV work. Not unit-testable (app target); verified by the founder's re-test.

## Next step
**Second checkpoint demo** with the founder (T6a–T6d). Then T7.
