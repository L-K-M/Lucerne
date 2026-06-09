#!/usr/bin/env bash
#
# make-app.sh — assemble a double-clickable Lucerne.app around the SPM binary.
#
# `swift run Lucerne` is fine for development, but a real .app bundle is what
# gives Finder the Info.plist (menu identity, Dock behaviour) and registers the
# .luce document type / UTI (D4). Run this on macOS.
#
#   Scripts/make-app.sh [--debug]
#
set -euo pipefail

CONFIG="release"
if [[ "${1:-}" == "--debug" ]]; then
    CONFIG="debug"
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Lucerne"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"

echo "==> Building ($CONFIG)…"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
    echo "error: built binary not found at $BIN_PATH" >&2
    exit 1
fi

echo "==> Assembling $APP …"
rm -rf "$APP"
mkdir -p "$MACOS_DIR" "$RES_DIR"
cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
cp "$ROOT/Scripts/Info.plist" "$CONTENTS/Info.plist"

# Generate the app + document icons from media-sources/icon.png (Info.plist
# already references AppIcon / DocumentIcon).
if [[ -f "$ROOT/media-sources/icon.png" ]]; then
    echo "==> Generating icons…"
    ( cd "$ROOT" && swift Scripts/GenerateIcons.swift ) || \
        echo "warning: icon generation failed; building without custom icons." >&2
fi
[[ -f "$ROOT/Scripts/AppIcon.icns" ]] && cp "$ROOT/Scripts/AppIcon.icns" "$RES_DIR/AppIcon.icns"
[[ -f "$ROOT/Scripts/DocumentIcon.icns" ]] && cp "$ROOT/Scripts/DocumentIcon.icns" "$RES_DIR/DocumentIcon.icns"

# Ad-hoc codesign so Gatekeeper and the document system are happy locally.
if command -v codesign >/dev/null 2>&1; then
    echo "==> Ad-hoc signing…"
    codesign --force --deep --sign - "$APP" || \
        echo "warning: ad-hoc signing failed; the app may still run locally." >&2
fi

echo "==> Done: $APP"
echo "    open \"$APP\""
