#!/usr/bin/env bash
# Verify that a Lucerne.app is complete and carries a valid ad-hoc signature.
set -euo pipefail

ALLOW_UNSIGNED=0
APP=""
for argument in "$@"; do
    case "$argument" in
        --allow-unsigned) ALLOW_UNSIGNED=1 ;;
        -h|--help)
            echo "usage: Scripts/verify-mac-app.sh [--allow-unsigned] <Lucerne.app>"
            exit 0
            ;;
        -*)
            echo "error: unknown option: $argument" >&2
            exit 2
            ;;
        *)
            if [[ -n "$APP" ]]; then
                echo "error: expected one app bundle" >&2
                exit 2
            fi
            APP="$argument"
            ;;
    esac
done

if [[ -z "$APP" ]]; then
    echo "error: app bundle path is required" >&2
    exit 2
fi

CONTENTS="$APP/Contents"
RESOURCES="$CONTENTS/Resources"
PLIST="$CONTENTS/Info.plist"

require_file() {
    if [[ ! -s "$1" ]]; then
        echo "error: required app resource is missing or empty: $1" >&2
        exit 1
    fi
}

[[ -d "$APP" ]] || { echo "error: app bundle not found: $APP" >&2; exit 1; }
require_file "$PLIST"
/usr/bin/plutil -lint "$PLIST" >/dev/null

EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST")"
[[ -n "$EXECUTABLE_NAME" ]] || { echo "error: CFBundleExecutable is empty" >&2; exit 1; }
if [[ ! -x "$CONTENTS/MacOS/$EXECUTABLE_NAME" ]]; then
    echo "error: bundle executable is missing or not executable: $EXECUTABLE_NAME" >&2
    exit 1
fi

require_file "$RESOURCES/Lucerne.sdef"
require_file "$RESOURCES/AppIcon.icns"
require_file "$RESOURCES/DocumentIcon.icns"
RESOURCE_BUNDLE="$RESOURCES/Lucerne_Lucerne.bundle"
if [[ ! -s "$RESOURCE_BUNDLE/Contents/Resources/icon.png" &&
      ! -s "$RESOURCE_BUNDLE/icon.png" ]]; then
    echo "error: required app resource is missing or empty: $RESOURCE_BUNDLE/icon.png" >&2
    exit 1
fi
/usr/bin/xmllint --noout "$RESOURCES/Lucerne.sdef"

if ! command -v codesign >/dev/null 2>&1; then
    if [[ "$ALLOW_UNSIGNED" -eq 1 ]]; then
        echo "warning: codesign is unavailable; bundle completeness verified only" >&2
        exit 0
    fi
    echo "error: codesign is required to verify the app bundle" >&2
    exit 1
fi

if ! codesign --verify --deep --strict "$APP"; then
    if [[ "$ALLOW_UNSIGNED" -eq 1 ]]; then
        echo "warning: app bundle is unsigned or has an invalid signature" >&2
        exit 0
    fi
    echo "error: app bundle signature verification failed" >&2
    exit 1
fi

echo "verified: $APP"
