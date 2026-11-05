<p align="center"><img src="docs/media/logo.png" alt="HoverTalk logo: a laptop with a smiling face and a speech bubble" width="220"></p>

<h1 align="center">HoverTalk</h1>

<p align="center"><strong>Point at text. Click. Listen.</strong></p>

HoverTalk is a macOS menu-bar app that reads text aloud from the place you point at. Press a hotkey, move the mouse over a paragraph (it gets outlined), click, and HoverTalk reads it and everything below it. It was built for people who listen to long AI-agent answers in the terminal while doing something else, and it also works in browsers and desktop apps.

<p align="center">
  <a href="docs/media/demo.mp4"><img src="docs/media/demo.gif" alt="HoverTalk in Ghostty: pointing at a paragraph outlines it, a click reads it aloud, and the reading follows the sentence and the word" width="800"></a>
  <br><sub>Click the demo to watch it with sound.</sub>
</p>

## Why not macOS "Speak Selection"?

macOS reads what it is told to, chrome included. In a terminal it reads the tmux status bar, the sidebar, the borders and the input box along with the answer. HoverTalk knows the layout of the programs it supports, so it reads **only the answer**.

- Reads exactly the block you point at, then continues below it. Switch between *paragraph* and *continuous* reading while it is playing.
- Skips interface chrome: tmux status bar, sidebars, gutters, borders, tool calls, input boxes, footers.
- Highlights the sentence and the word being spoken, on screen.
- A small floating player: pause, previous/next sentence, speed −/+, stop.
- Private: no telemetry, no accounts. The only network traffic is an optional voice server you configure yourself.

## What it reads

| Where | Status |
|---|---|
| **Ghostty** with plain shells, **tmux** (splits and separate windows), **Gentle Shell**, **OpenCode**, **Claude Code** | Works. Each program has a profile that strips its interface |
| **Chrome**, **Chromium and Electron apps** (such as the Claude and ChatGPT desktop apps) | Works, through the accessibility tree |
| **Safari** and other native apps | Uses the same accessibility reader; not verified app by app |
| Terminals other than Ghostty (iTerm2, Terminal.app, kitty, WezTerm…) | Untested. HoverTalk reads the text area Ghostty exposes for the whole screen; other terminals may expose less |

## Requirements

- macOS 14 (Sonoma) or newer
- Swift 6 toolchain (Xcode 16+, or the Command Line Tools)

## Install

There are no prebuilt releases yet; build it from source.

```sh
git clone https://github.com/diegobarrionuevo1/hover-talk.git
cd hover-talk
scripts/bundle.sh          # builds build/HoverTalk.app
open build/HoverTalk.app
```

HoverTalk lives in the menu bar (no Dock icon). To keep it, move `build/HoverTalk.app` to `/Applications`.

### Signing, and why it matters

macOS ties the Accessibility permission to the app's code signature.

- With an **Apple Development certificate** in your keychain (a free Apple ID in Xcode is enough), `bundle.sh` signs with it, and the permission survives rebuilds.
- Without one, it signs ad hoc. Then, after every rebuild, remove HoverTalk from *System Settings › Privacy & Security › Accessibility* and add it again, or macOS keeps showing it as enabled while denying it.
- `SIGN_IDENTITY="-" scripts/bundle.sh` forces ad hoc; `BUNDLE_ID=com.example.HoverTalk scripts/bundle.sh` changes the bundle id.

### Grant the Accessibility permission

HoverTalk reads text through the macOS Accessibility API, so it needs your permission:

1. Open HoverTalk. It asks for access the first time you pick text.
2. *System Settings › Privacy & Security › Accessibility*, turn on **HoverTalk**.

## Use it

HoverTalk has three ways to start reading. Each has a global hotkey and a menu-bar item.

| Mode | Hotkey | What it reads |
|---|---|---|
| **Pick text** | **⌃⌥R** | You point and click. Reads the block under the pointer and everything below it |
| **Read selection** | **⌃⌥S** | The text you have selected in the frontmost app |
| **Read all** | **⌃⌥A** | Everything the window under the pointer shows: a terminal pane, a page or an app area |

**Pick text**

1. Press ⌃⌥R, or choose *Pick Text to Read* from the menu-bar icon.
2. Move the mouse. The block under the pointer is outlined.
3. **Click** to read it. **Esc** cancels. Drag across text to read just that selection.
4. Control playback from the floating player: previous/next sentence, pause, speed, stop.

**Read selection** asks the app for its selected text. Apps that do not expose it (terminals such as Ghostty) are asked to copy with ⌘C, and HoverTalk puts your clipboard back right after. If the app has nothing selected, nothing is read. Some editors copy the current line when nothing is selected; there, that line is read.

**Read all** reads from the first paragraph to the last, without stopping at message ends. With the hotkey, put the pointer over the window you want. From the menu, it reads the focused window of the app you were using. In a terminal split, it reads only the pane under the pointer.

Open **Settings…** (⌘,) in the menu to choose the voice and the voice server. The hotkeys are fixed for now.

### Better voices

The *Voice* menu lists your macOS voices grouped by language and quality. Download enhanced or premium voices from *System Settings › Accessibility › Spoken Content*, or through *Download More Voices…* in the menu.

### Use your own voice server (optional)

If you run an OpenAI-compatible speech server such as [Kokoro-FastAPI](https://github.com/remsky/Kokoro-FastAPI) on another machine, HoverTalk can read with its voices and falls back to the system voice by itself when the server is off. It is off until you enable it. See [docs/voice-server.md](docs/voice-server.md).

## Privacy

- No telemetry, no analytics, no network calls by default.
- The only thing that can leave your Mac is the text being read, sent to the voice server **you** configured.
- The Accessibility permission lets HoverTalk read the screen under the pointer while you pick. It does not record or store what it reads.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Pressing a hotkey does nothing | Another app may hold that shortcut. The menu item then shows no hotkey next to its name |
| "Accessibility permission needed", but the toggle is on | Remove HoverTalk from the Accessibility list and add it again (see [Signing](#signing-and-why-it-matters)) |
| Nothing is outlined in a terminal | HoverTalk only reads Ghostty's text area today. Check the app is Ghostty |
| tmux status bar is still read | The bar is detected by asking `tmux list-clients`; HoverTalk looks for tmux in `/opt/homebrew/bin`, `/usr/local/bin` and `/usr/bin` |
| A TUI's sidebar or footer is read | Its layout has no profile yet. [Add one](docs/tui-profiles.md), it is small |

## Contributing

Pull requests are welcome, especially **TUI profiles** for the programs you use. Start with [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/tui-profiles.md](docs/tui-profiles.md).

```sh
swift build
swift test
```

## Layout

```
Sources/HoverTalkCore       pure logic: screen parsing, TUI profiles, speech queue (no AppKit)
Sources/HoverTalk           the menu-bar app: overlay, hotkey, accessibility, speech engines
Sources/HoverTalkCapture    dev tool: capture sanitized screen fixtures, probe the live screen
Sources/HoverTalkFixtureKit sanitizer behind HoverTalkCapture
Tests/                      unit tests and sanitized fixtures
scripts/bundle.sh           builds the .app
scripts/make-icons.sh       renders the logo in assets/ into the app icon, menu-bar icon and README image
assets/                     logo sources (SVG)
Resources/                  generated icons, copied into the .app
```

## License

[MIT](LICENSE)
