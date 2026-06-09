#!/usr/bin/env bash
#
# Cuts a release by pushing a "v<version>" tag, which triggers
# .github/workflows/release.yml to build Lucerne.app (via Scripts/make-app.sh),
# package it (.zip + .dmg), and publish the GitHub Release.
#
# The release workflow stamps the bundle version from the tag, so the tag is the
# source of truth — this script keeps the *committed* CFBundleShortVersionString
# (Scripts/Info.plist) and the README version line in step, so local/dev builds
# (`Scripts/make-app.sh`) and the About box report the same number.
#
#   Scripts/release.sh 1.3.0          # bump version + README, commit, tag v1.3.0
#   Scripts/release.sh 1.3.0 --push   # …also push the commit + tag (CI then publishes)
#   Scripts/release.sh                # tag the current version as-is
#
# Usage: Scripts/release.sh [X.Y[.Z]] [--push]
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Lucerne"
PLIST="Scripts/Info.plist"
VERSION_KEY="CFBundleShortVersionString"

# --- Parse args (an optional version, and/or --push, in any order) ----------------
NEW_VERSION=""
PUSH=false
for arg in "$@"; do
  case "$arg" in
    --push) PUSH=true ;;
    -*)     echo "error: unknown option '$arg'" >&2; exit 1 ;;
    *)
      if [[ -n "$NEW_VERSION" ]]; then echo "error: version given twice" >&2; exit 1; fi
      NEW_VERSION="$arg"
      ;;
  esac
done

VERSION_RE='^[0-9]+(\.[0-9]+){1,2}$'
if [[ -n "$NEW_VERSION" && ! "$NEW_VERSION" =~ $VERSION_RE ]]; then
  echo "error: version must look like 1.3 or 1.3.0 (got '$NEW_VERSION')" >&2
  exit 1
fi

# --- Read the current version (Scripts/Info.plist is the committed source) --------
read_version() { /usr/libexec/PlistBuddy -c "Print :${VERSION_KEY}" "$PLIST" 2>/dev/null; }
CURRENT=$(read_version || true)
if [[ -z "${CURRENT:-}" ]]; then
  echo "error: could not read ${VERSION_KEY} from ${PLIST}" >&2
  exit 1
fi

TARGET="${NEW_VERSION:-$CURRENT}"
TAG="v${TARGET}"

# --- Pre-flight checks (before mutating anything) ---------------------------------
if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: working tree has uncommitted changes — commit or stash them first." >&2
  exit 1
fi
if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
  echo "error: tag ${TAG} already exists." >&2
  echo "       Pass a newer version, e.g. Scripts/release.sh 1.3.0" >&2
  exit 1
fi

# --- Bump the plist version + README, then commit ---------------------------------
DID_COMMIT=false
if [[ -n "$NEW_VERSION" ]]; then
  if [[ "$NEW_VERSION" != "$CURRENT" ]]; then
    echo "Bumping ${VERSION_KEY} ${CURRENT} → ${NEW_VERSION}…"
    /usr/libexec/PlistBuddy -c "Set :${VERSION_KEY} ${NEW_VERSION}" "$PLIST"
    GOT=$(read_version || true)
    if [[ "$GOT" != "$NEW_VERSION" ]]; then
      echo "error: failed to set ${VERSION_KEY} in ${PLIST} (got '${GOT}')." >&2
      git checkout -- "$PLIST" 2>/dev/null || true
      exit 1
    fi
  fi

  # Reflect the version in README.md, between the <!-- version --> markers.
  if [[ -f README.md ]]; then
    sed -i '' -E "s|(<!-- version -->)[^<]*(<!-- /version -->)|\1${NEW_VERSION}\2|" README.md
    if ! grep -qF "<!-- version -->${NEW_VERSION}<!-- /version -->" README.md; then
      echo "note: README.md has no <!-- version --> marker — left unchanged." >&2
    fi
  fi

  # Keep the About box's unbundled-fallback version in step (used when Info.plist
  # can't be read, e.g. an unbundled `swift run`).
  ABOUT="Sources/Lucerne/AboutWindowController.swift"
  if [[ -f "$ABOUT" ]]; then
    sed -i '' -E "s/(static let fallbackVersion = \")[^\"]*(\")/\1${NEW_VERSION}\2/" "$ABOUT"
    if ! grep -qF "fallbackVersion = \"${NEW_VERSION}\"" "$ABOUT"; then
      echo "note: could not update the About box version in ${ABOUT}." >&2
    fi
  fi

  # Commit whatever the version change touched (plist, About box, and/or README).
  if [[ -n "$(git status --porcelain)" ]]; then
    git commit -am "Bump version to ${NEW_VERSION}" >/dev/null
    DID_COMMIT=true
    echo "Committed version bump (${PLIST} + About box + README)."
  else
    echo "Version is already ${NEW_VERSION}; nothing to bump."
  fi
fi

# --- Tag --------------------------------------------------------------------------
git tag -a "${TAG}" -m "${APP_NAME} ${TARGET}"
echo "Created tag ${TAG}."

# --- Push (optional) — pushing the tag triggers the release workflow ---------------
if $PUSH; then
  git push origin HEAD
  git push origin "${TAG}"
  echo "Pushed branch + ${TAG}."
  echo "CI (release.yml) will now build Lucerne.app, package (.zip + .dmg), and publish the GitHub Release for ${TAG}."
else
  echo "Local tag ${TAG} created (not pushed)."
  echo "Push it to trigger the release:  git push origin HEAD && git push origin ${TAG}"
  echo "Or undo:                         git tag -d ${TAG}$( $DID_COMMIT && echo " && git reset --hard HEAD~1" )"
fi
