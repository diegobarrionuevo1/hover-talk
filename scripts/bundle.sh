#!/usr/bin/env bash
# Builds the release binary and wraps it in a menu-bar .app bundle at build/<APP_NAME>.app.
#
# Usage: scripts/bundle.sh
# Optional: BUNDLE_ID=com.example.MyApp scripts/bundle.sh
set -euo pipefail

# Must match the executable product name in Package.swift.
APP_NAME="HoverTalk"
BUNDLE_ID="${BUNDLE_ID:-io.github.hovertalk.HoverTalk}"
VERSION="0.1.0"
BUILD_NUMBER="1"
MIN_MACOS="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"

cd "$ROOT_DIR"

swift build -c release --product "$APP_NAME"
BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"

# Start from an empty bundle so files from earlier builds are not signed into this one.
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$BIN_PATH" "$CONTENTS_DIR/MacOS/$APP_NAME"

# Network keys, for the opt-in voice server only (the app sends nothing else):
# - NSAllowsLocalNetworking lifts App Transport Security (ATS) for plain http to unqualified host
#   names ("studio"), ".local" names ("studio.local") and IPv4/IPv6 addresses
#   ("http://192.168.1.50:8880"), per Apple's NSAllowsLocalNetworking reference. Since macOS 14,
#   ATS blocks IP addresses by default, so this key is required for numeric LAN addresses.
#   It does not cover other names: plain http to a Tailscale MagicDNS name
#   ("studio.tailnet.ts.net") or any public domain stays blocked, and the app reports it as
#   "Blocked: use https for this address" (RemoteVoiceError.insecureConnectionBlocked).
#   https always passes ATS.
# - NSLocalNetworkUsageDescription is the text of macOS's Local Network privacy prompt, shown the
#   first time the app contacts a host on the local network.
cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 $APP_NAME contributors. MIT License.</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
    <key>NSLocalNetworkUsageDescription</key>
    <string>$APP_NAME connects to the voice server you configure on your local network.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature: it identifies this exact binary, so it changes whenever a rebuild changes
# the binary. macOS ties the Accessibility permission to the signature, so it may ask for the
# permission again after rebuilding.
codesign --force --sign - "$APP_DIR"

echo "$APP_DIR"
