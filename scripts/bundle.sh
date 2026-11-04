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
# Icons come from scripts/make-icons.sh: the app icon, and the menu-bar image the app loads.
cp "$ROOT_DIR"/Resources/AppIcon.icns "$ROOT_DIR"/Resources/MenuBarIcon*.png "$CONTENTS_DIR/Resources/"

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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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

# Signing. macOS ties the Accessibility permission to the app's designated requirement.
# - With a certificate identity, that requirement names the bundle id and the certificate, so it
#   stays the same across rebuilds and the permission keeps working.
# - With an ad-hoc signature ("-"), the requirement is the binary's cdhash, which changes on every
#   rebuild: System Settings keeps showing the old entry as on, but it no longer matches, and the
#   app reads "not granted" until the entry is removed and added again.
# SIGN_IDENTITY overrides the choice ("-" forces ad-hoc). Otherwise the first valid
# "Apple Development" identity in the keychain is used (a free Apple ID in Xcode provides one).
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | awk '/"Apple Development: /{print $2; exit}')"
fi
if [[ -z "$SIGN_IDENTITY" || "$SIGN_IDENTITY" == "-" ]]; then
    SIGN_IDENTITY="-"
    echo "warning: ad-hoc signature; after each rebuild, remove $APP_NAME from Privacy & Security >" \
        "Accessibility and add it again. Set SIGN_IDENTITY or add an Apple ID in Xcode to avoid this." >&2
fi
codesign --force --timestamp=none --sign "$SIGN_IDENTITY" "$APP_DIR"
echo "designated requirement: $(codesign -d -r- "$APP_DIR" 2>&1 | sed -n 's/^designated => //p')"

echo "$APP_DIR"
