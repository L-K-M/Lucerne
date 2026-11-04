#!/usr/bin/env bash
# Verify the release-critical structure and signature of a Lucerne app bundle.
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
    echo "usage: Scripts/verify-app.sh /path/to/Lucerne.app" >&2
    exit 2
fi

APP="$1"
CONTENTS="$APP/Contents"
RESOURCES="$CONTENTS/Resources"

require_file() {
    local path="$1"
    if [[ ! -s "$path" ]]; then
        echo "error: required app resource is missing or empty: $path" >&2
        exit 1
    fi
}

require_plist_value() {
    local key="$1"
    local expected="$2"
    local actual

    if ! actual="$(plutil -extract "$key" raw -o - "$CONTENTS/Info.plist" 2>/dev/null)"; then
        echo "error: Info.plist is missing $key" >&2
        exit 1
    fi
    if [[ "$actual" != "$expected" ]]; then
        echo "error: Info.plist $key is '$actual'; expected '$expected'" >&2
        exit 1
    fi
}

if [[ ! -d "$APP" ]]; then
    echo "error: app bundle does not exist: $APP" >&2
    exit 1
fi
if [[ ! -x "$CONTENTS/MacOS/Lucerne" || ! -s "$CONTENTS/MacOS/Lucerne" ]]; then
    echo "error: app executable is missing or not executable: $CONTENTS/MacOS/Lucerne" >&2
    exit 1
fi

require_file "$CONTENTS/Info.plist"
require_file "$RESOURCES/Lucerne.sdef"
require_file "$RESOURCES/AppIcon.icns"
require_file "$RESOURCES/DocumentIcon.icns"

# Swift 5.10 emits a flat resource bundle while Swift 6 uses the nested macOS
# bundle layout. Both are valid outputs from supported release toolchains.
FLAT_RESOURCE_ICON="$RESOURCES/Lucerne_Lucerne.bundle/icon.png"
NESTED_RESOURCE_ICON="$RESOURCES/Lucerne_Lucerne.bundle/Contents/Resources/icon.png"
if [[ ! -s "$FLAT_RESOURCE_ICON" && ! -s "$NESTED_RESOURCE_ICON" ]]; then
    echo "error: Lucerne_Lucerne.bundle is missing a nonempty icon.png" >&2
    exit 1
fi

plutil -lint "$CONTENTS/Info.plist" >/dev/null
/usr/bin/xmllint --noout "$RESOURCES/Lucerne.sdef"
require_plist_value CFBundleExecutable Lucerne
require_plist_value CFBundleIconFile AppIcon
require_plist_value OSAScriptingDefinition Lucerne.sdef
require_plist_value CFBundleDocumentTypes.0.CFBundleTypeIconFile DocumentIcon
codesign --verify --deep --strict "$APP"

echo "Verified app bundle: $APP"
