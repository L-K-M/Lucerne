#!/usr/bin/env bash
#
# make-app.sh — assemble a double-clickable Lucerne.app around the SPM binary.
#
# `swift run Lucerne` is fine for development, but a real .app bundle is what
# gives Finder the Info.plist (menu identity, Dock behaviour) and registers the
# .luce document type / UTI (D4). Run this on macOS.
#
#   Scripts/make-app.sh [--debug] [--allow-unsigned]
#
set -euo pipefail

CONFIG="release"
ALLOW_UNSIGNED=0
for argument in "$@"; do
    case "$argument" in
        --debug) CONFIG="debug" ;;
        --allow-unsigned) ALLOW_UNSIGNED=1 ;;
        -h|--help)
            echo "usage: Scripts/make-app.sh [--debug] [--allow-unsigned]"
            exit 0
            ;;
        *)
            echo "error: unknown option: $argument" >&2
            exit 2
            ;;
    esac
done

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

# Copy SPM resource bundles (e.g. Lucerne_Lucerne.bundle, which holds the icon.png
# the About / Welcome windows load via Bundle.module) into Resources so they resolve
# in the bundled app.
BIN_DIR="$(dirname "$BIN_PATH")"
LUCERNE_RESOURCE_BUNDLE="$BIN_DIR/Lucerne_Lucerne.bundle"
if [[ ! -s "$LUCERNE_RESOURCE_BUNDLE/Contents/Resources/icon.png" &&
      ! -s "$LUCERNE_RESOURCE_BUNDLE/icon.png" ]]; then
    echo "error: required SwiftPM resource bundle is missing or incomplete: $LUCERNE_RESOURCE_BUNDLE" >&2
    exit 1
fi
for bundle in "$BIN_DIR"/*.bundle; do
    [[ -d "$bundle" ]] && cp -R "$bundle" "$RES_DIR/"
done
# AppleScript dictionary (referenced by Info.plist OSAScriptingDefinition).
if [[ ! -s "$ROOT/Scripts/Lucerne.sdef" ]]; then
    echo "error: Scripts/Lucerne.sdef is missing or empty" >&2
    exit 1
fi
cp "$ROOT/Scripts/Lucerne.sdef" "$RES_DIR/Lucerne.sdef"

# Generate the app + document icons from media-sources/icon.png (Info.plist
# already references AppIcon / DocumentIcon).
if [[ ! -s "$ROOT/media-sources/icon.png" ]]; then
    echo "error: media-sources/icon.png is missing or empty" >&2
    exit 1
fi
echo "==> Generating icons…"
rm -f "$ROOT/Scripts/AppIcon.icns" "$ROOT/Scripts/DocumentIcon.icns"
( cd "$ROOT" && swift Scripts/GenerateIcons.swift )
for icon in AppIcon.icns DocumentIcon.icns; do
    if [[ ! -s "$ROOT/Scripts/$icon" ]]; then
        echo "error: icon generation did not produce Scripts/$icon" >&2
        exit 1
    fi
    cp "$ROOT/Scripts/$icon" "$RES_DIR/$icon"
done

# Ad-hoc codesign so Gatekeeper and the document system are happy locally.
if command -v codesign >/dev/null 2>&1; then
    echo "==> Ad-hoc signing…"
    if ! codesign --force --deep --sign - "$APP"; then
        if [[ "$ALLOW_UNSIGNED" -ne 1 ]]; then
            echo "error: ad-hoc signing failed" >&2
            exit 1
        fi
        echo "warning: ad-hoc signing failed; continuing because --allow-unsigned was set" >&2
    fi
elif [[ "$ALLOW_UNSIGNED" -ne 1 ]]; then
    echo "error: codesign is required; use --allow-unsigned only for local development" >&2
    exit 1
else
    echo "warning: codesign is unavailable; continuing because --allow-unsigned was set" >&2
fi

if [[ "$ALLOW_UNSIGNED" -eq 1 ]]; then
    "$ROOT/Scripts/verify-mac-app.sh" --allow-unsigned "$APP"
else
    "$ROOT/Scripts/verify-mac-app.sh" "$APP"
fi

echo "==> Done: $APP"
echo "    open \"$APP\""
