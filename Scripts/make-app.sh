#!/usr/bin/env bash
#
# make-app.sh — assemble a double-clickable Lucerne.app around the SPM binary.
#
# `swift run Lucerne` is fine for development, but a real .app bundle is what
# gives Finder the Info.plist (menu identity, Dock behaviour) and registers the
# .luce document type / UTI (D4). Run this on macOS.
#
#   Scripts/make-app.sh [--debug] [--strict]
#
set -euo pipefail

CONFIG="release"
STRICT=0
for argument in "$@"; do
    case "$argument" in
        --debug)
            CONFIG="debug"
            ;;
        --strict)
            STRICT=1
            ;;
        *)
            echo "error: unknown option: $argument" >&2
            echo "usage: Scripts/make-app.sh [--debug] [--strict]" >&2
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

require_file() {
    local path="$1"
    if [[ ! -s "$path" ]]; then
        echo "error: required release input is missing or empty: $path" >&2
        exit 1
    fi
}

if [[ "$STRICT" -eq 1 ]]; then
    require_file "$ROOT/Scripts/Info.plist"
    require_file "$ROOT/Scripts/Lucerne.sdef"
    require_file "$ROOT/media-sources/icon.png"

    if [[ ! -x "$ROOT/Scripts/verify-app.sh" ]]; then
        echo "error: app verifier is missing or not executable: $ROOT/Scripts/verify-app.sh" >&2
        exit 1
    fi

    for command_name in codesign plutil; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            echo "error: required release command is unavailable: $command_name" >&2
            exit 1
        fi
    done
fi

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
for bundle in "$BIN_DIR"/*.bundle; do
    [[ -d "$bundle" ]] && cp -R "$bundle" "$RES_DIR/"
done
# AppleScript dictionary (referenced by Info.plist OSAScriptingDefinition).
if [[ -f "$ROOT/Scripts/Lucerne.sdef" ]]; then
    cp "$ROOT/Scripts/Lucerne.sdef" "$RES_DIR/Lucerne.sdef"
fi

# Generate the app + document icons from media-sources/icon.png (Info.plist
# already references AppIcon / DocumentIcon).
rm -f "$ROOT/Scripts/AppIcon.icns" "$ROOT/Scripts/DocumentIcon.icns"
if [[ -f "$ROOT/media-sources/icon.png" ]]; then
    echo "==> Generating icons…"
    if [[ "$STRICT" -eq 1 ]]; then
        ( cd "$ROOT" && swift Scripts/GenerateIcons.swift )
    else
        ( cd "$ROOT" && swift Scripts/GenerateIcons.swift ) || \
            echo "warning: icon generation failed; building without custom icons." >&2
    fi
fi
if [[ "$STRICT" -eq 1 ]]; then
    require_file "$ROOT/Scripts/AppIcon.icns"
    require_file "$ROOT/Scripts/DocumentIcon.icns"
fi
if [[ -f "$ROOT/Scripts/AppIcon.icns" ]]; then
    cp "$ROOT/Scripts/AppIcon.icns" "$RES_DIR/AppIcon.icns"
fi
if [[ -f "$ROOT/Scripts/DocumentIcon.icns" ]]; then
    cp "$ROOT/Scripts/DocumentIcon.icns" "$RES_DIR/DocumentIcon.icns"
fi

# Ad-hoc codesign so Gatekeeper and the document system are happy locally.
if [[ "$STRICT" -eq 1 ]]; then
    echo "==> Ad-hoc signing…"
    codesign --force --deep --sign - "$APP"
    "$ROOT/Scripts/verify-app.sh" "$APP"
elif command -v codesign >/dev/null 2>&1; then
    echo "==> Ad-hoc signing…"
    codesign --force --deep --sign - "$APP" || \
        echo "warning: ad-hoc signing failed; the app may still run locally." >&2
fi

echo "==> Done: $APP"
echo "    open \"$APP\""
