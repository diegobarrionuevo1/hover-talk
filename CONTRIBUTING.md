# Contributing

Thanks for helping. HoverTalk is small on purpose: keep changes focused.

## Setup

```sh
swift build
swift test
scripts/bundle.sh    # builds build/HoverTalk.app
```

Requires macOS 14+ and a Swift 6 toolchain. See the README for signing and the Accessibility permission.

## Ground rules

- **`HoverTalkCore` stays pure**: Foundation, CoreGraphics and NaturalLanguage only, never AppKit. Anything that touches the system goes in `HoverTalk`.
- **Tests first.** New behavior comes with a test that failed before the change. Terminal reading is tested against **sanitized fixtures** (below).
- **Privacy.** No telemetry, no new network calls. The only allowed traffic is the opt-in voice server.
- Commits follow [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:`…). Keep each commit one reviewable unit, with its tests.
- Open an issue before a large change.

## Fixtures must never contain private data

Screen captures include whatever was on your screen. Never commit a raw capture. Use the dev tool, which replaces every word and number with a neutral one of the same length and refuses to write if your user name, host name or home path survives:

```sh
swift run HoverTalkCapture ax --delay 5 --out Tests/HoverTalkCoreTests/Fixtures/<app>-<layout>.json
```

Skim the file before committing. Details in `Tests/HoverTalkCoreTests/Fixtures/README.md`.

## Adding support for a terminal program

See [docs/tui-profiles.md](docs/tui-profiles.md).

## Reporting bugs

Include the macOS version, the app and terminal, and, if you can, the structure-only output of `swift run HoverTalkCapture probe --delay 5` (it prints geometry and counts, never text).
