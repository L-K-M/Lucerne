#!/usr/bin/env bash
# Cuts a release: bumps the version, commits, tags "v<version>", and with --push
# pushes branch + tag — which triggers .github/workflows/release.yml to build
# Lucerne.app (via Scripts/make-app.sh), package it (.zip + .dmg), and publish the
# GitHub Release. CI stamps the bundle version from the tag, so the tag is the
# source of truth — this just keeps the committed CFBundleShortVersionString
# (Scripts/Info.plist), the About box's unbundled-fallback version string
# (Sources/Lucerne/AboutWindowController.swift), and the README version line in
# step, so local/dev builds (`Scripts/make-app.sh`) report the same number.
#
#   Scripts/release.sh 1.3.0          # bump version + About box + README, commit, tag v1.3.0
#   Scripts/release.sh 1.3.0 --push   # …also push the commit + tag (CI then publishes)
#   Scripts/release.sh                # tag the current version as-is
#
# Usage: Scripts/release.sh [X.Y[.Z]] [--push]
# Shared engine: https://github.com/L-K-M/release-tool (this stub only sets config).
set -euo pipefail

export RELEASE_APP_NAME="Lucerne"
export RELEASE_KIND="plist"
export RELEASE_PLIST="Scripts/Info.plist"
export RELEASE_CI_NOTE="CI (release.yml) will now build Lucerne.app, package (.zip + .dmg), and publish the GitHub Release."
export RELEASE_INVOKED_AS="Scripts/release.sh"
# Keep the About box's fallback version in step (used when Info.plist can't be
# read, e.g. an unbundled `swift run`); a missing file/pattern is a note, not a
# failure.
export RELEASE_POST_BUMP='f="Sources/Lucerne/AboutWindowController.swift"; if [ -f "$f" ]; then sed -i "" -E "s/(static let fallbackVersion = \")[^\"]*(\")/\1${RELEASE_NEW_VERSION}\2/" "$f"; grep -qF "fallbackVersion = \"${RELEASE_NEW_VERSION}\"" "$f" || echo "note: could not update the About box version in $f." >&2; fi'

BIN="${LKM_RELEASE_BIN:-lkm-release}"
command -v "$BIN" >/dev/null 2>&1 || {
  echo "error: lkm-release not found — clone https://github.com/L-K-M/release-tool and run ./install.sh" >&2
  exit 1
}
exec "$BIN" "$@"
