#!/usr/bin/env bash
# Builds Lucerne.app (SwiftPM) and reveals it in Finder on success. Delegates the
# `swift build` + .app bundle assembly (icons, Info.plist, ad-hoc signing) to
# Scripts/make-app.sh; the engine wraps it with --clean/--run/--install/reveal.
# Thin stub for the shared lkm-build engine.
#
# Usage: Scripts/build.sh [--clean] [--debug] [--run] [--install] [--zip] [--dmg]
# Shared engine: https://github.com/L-K-M/release-tool (this stub only sets config).
set -euo pipefail
export BUILD_APP_NAME="Lucerne"
export BUILD_KIND="swiftpm"
export BUILD_SWIFTPM_ASSEMBLE="Scripts/make-app.sh"
export BUILD_PRODUCT_PATH="dist/Lucerne.app"
export BUILD_INVOKED_AS="Scripts/build.sh"
BIN="${LKM_BUILD_BIN:-lkm-build}"
command -v "$BIN" >/dev/null 2>&1 || {
  echo "error: lkm-build not found — clone https://github.com/L-K-M/release-tool and run ./install.sh" >&2
  exit 1
}
exec "$BIN" "$@"
