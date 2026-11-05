#!/usr/bin/env bash
# Renders the logo sources in assets/ into the files the app and the README use:
#   Resources/AppIcon.icns          app icon (from assets/app-icon.svg)
#   Resources/MenuBarIcon.png/@2x   menu-bar template image (from assets/menubar.svg)
#   docs/media/logo.png             README header (from assets/logo.svg)
#   docs/media/social-preview.png   GitHub social preview, 1280x640 (from assets/social-preview.html)
# Needs Google Chrome (headless, for the SVG rendering), sips and iconutil. Run it again after
# editing an SVG and commit the results.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
[[ -x "$CHROME" ]] || { echo "error: Google Chrome not found; set CHROME to a Chromium binary" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$ROOT_DIR/Resources" "$ROOT_DIR/docs/media"

# render <svg> <width> <height> <png>: transparent background.
render() {
    local svg="$1" width="$2" height="$3" png="$4"
    local page="$WORK/page.html"
    printf '<html><body style="margin:0;background:transparent"><img src="file://%s" width="%s" height="%s" style="display:block"></body></html>' \
        "$svg" "$width" "$height" > "$page"
    "$CHROME" --headless=new --disable-gpu --hide-scrollbars --default-background-color=00000000 \
        --window-size="$width,$height" --screenshot="$png" "file://$page" >/dev/null 2>&1
}

# App icon: 1024 master, then every size macOS asks for.
render "$ROOT_DIR/assets/app-icon.svg" 1024 1024 "$WORK/icon-1024.png"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$WORK/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z "$((size * 2))" "$((size * 2))" "$WORK/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ROOT_DIR/Resources/AppIcon.icns"

# Menu bar: 20 x 18 points, 1x and 2x.
render "$ROOT_DIR/assets/menubar.svg" 22 20 "$ROOT_DIR/Resources/MenuBarIcon.png"
render "$ROOT_DIR/assets/menubar.svg" 44 40 "$ROOT_DIR/Resources/MenuBarIcon@2x.png"

# README header.
render "$ROOT_DIR/assets/logo.svg" 440 400 "$ROOT_DIR/docs/media/logo.png"

# GitHub social preview (Settings > General > Social preview takes a manual upload).
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --window-size=1280,640 \
    --screenshot="$ROOT_DIR/docs/media/social-preview.png" "file://$ROOT_DIR/assets/social-preview.html" >/dev/null 2>&1

echo "wrote Resources/AppIcon.icns, Resources/MenuBarIcon*.png, docs/media/logo.png, docs/media/social-preview.png"
