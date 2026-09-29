#!/usr/bin/env bash
set -euo pipefail
# Build dist/lucerne-linux-amd64.flatpak by repacking the CPack .deb under
# flatpak's /app prefix — the bundle ships byte-for-byte what the .deb
# installs. Usage:
#   Scripts/build-flatpak.sh [--install]   # build the .deb first, then repack
#   Scripts/build-flatpak.sh path/to.deb   # repack an existing .deb (CI)
#
# The bundle names Flathub as its runtime's source, so installing it fetches
# the KDE runtime from there. Needs flatpak and flatpak-builder.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
readonly APP_ID=ch.lkmc.Lucerne
readonly MANIFEST="$ROOT/flatpak/$APP_ID.yml"
readonly FLATHUB_REPO=https://dl.flathub.org/repo/flathub.flatpakrepo
readonly WORK="$ROOT/dist/flatpak"

die() { echo "build-flatpak.sh: $*" >&2; exit 1; }

INSTALL=0
DEB=""
for argument in "$@"; do
  case "$argument" in
    --install) INSTALL=1 ;;
    -h|--help) awk 'NR==1&&/^#!/{next} /^set -euo pipefail/{next} /^#/{sub(/^# ?/,"");print;next} {exit}' "$0"; exit 0 ;;
    *.deb) [ -z "$DEB" ] || die "pass at most one .deb"; DEB="$argument" ;;
    *) echo "Unknown argument: $argument" >&2; exit 2 ;;
  esac
done

# A relative .deb argument names the caller's directory, not the
# repository root we cd'd into above.
if [[ -n "$DEB" && "$DEB" != /* ]]; then DEB="$OLDPWD/$DEB"; fi

command -v flatpak-builder >/dev/null 2>&1 ||
  die "flatpak-builder not found: install flatpak and flatpak-builder"
command -v dpkg-deb >/dev/null 2>&1 ||
  die "dpkg-deb not found: install dpkg"

if [[ -z "$DEB" ]]; then
  cmake -S linux -B linux/build -G Ninja -DCMAKE_BUILD_TYPE=Release
  cmake --build linux/build
  (cd linux/build && cpack -G DEB)
  DEB="$(find linux/build -maxdepth 1 -name 'lucerne_*_amd64.deb' -printf '%T@\t%p\n' 2>/dev/null | sort -rn | head -n1 | cut -f2- || true)"
fi
[ -f "$DEB" ] || die ".deb not found: $DEB"

# Debian /usr -> flatpak /app.
rm -rf "$WORK/debroot" "$WORK/stage" "$WORK/build" "$WORK/repo"
mkdir -p "$WORK"   # dpkg-deb creates the target dir but not its parents
dpkg-deb -x "$DEB" "$WORK/debroot"
mkdir -p "$WORK/stage"
cp -a "$WORK/debroot/usr/." "$WORK/stage/"

# Shipped text files (wrappers, launchers, python) hardcode /usr; inside flatpak the prefix is /app.
while IFS= read -r f; do
  sed -i '1!s|/usr/|/app/|g' "$f"
done < <(grep -rIl '/usr/' "$WORK/stage" 2>/dev/null || true)
while IFS= read -r f; do
  sed -i -e 's|Exec=/usr/bin/\|Exec=/app/bin/|Exec=|g' -e '/^TryExec=/d' "$f"
done < <(find "$WORK/stage/share/applications" -type f -name '*.desktop' 2>/dev/null)

# The deb already ships ch.lkmc.Lucerne.{desktop,png} — flatpak's
# app-id-named export names — so this is a verification pass, not a rename.
DESKTOP="$(find "$WORK/stage/share/applications" -type f -name '*.desktop' -print -quit 2>/dev/null || true)"
[ -n "$DESKTOP" ] || die "no .desktop file inside $DEB"
if [ "$(basename "$DESKTOP")" != "$APP_ID.desktop" ]; then
  mv "$DESKTOP" "$WORK/stage/share/applications/$APP_ID.desktop"
fi
DESKTOP="$WORK/stage/share/applications/$APP_ID.desktop"
# The launcher resolves Icon= through flatpak's exported name.
sed -i "s|^Icon=.*|Icon=$APP_ID|" "$DESKTOP"
if ! find "$WORK/stage/share/icons" "$WORK/stage/share/pixmaps" -name "$APP_ID.*" 2>/dev/null | grep -q .; then
  ICON="$(find "$WORK/stage/share/icons" -name '*.png' -printf '%s\t%p\n' 2>/dev/null | sort -rn | head -n1 | cut -f2- || true)"
  [ -n "$ICON" ] || die "no icon inside $DEB"
  mkdir -p "$WORK/stage/share/icons/hicolor/256x256/apps"
  cp "$ICON" "$WORK/stage/share/icons/hicolor/256x256/apps/$APP_ID.png"
fi

flatpak remote-add --user --if-not-exists flathub "$FLATHUB_REPO"
# --disable-rofiles-fuse: containers (CI) have no FUSE, and a copy-only build
# gains nothing from it.
flatpak-builder --user --install-deps-from=flathub --force-clean \
  --disable-rofiles-fuse \
  --state-dir="$WORK/state" --repo="$WORK/repo" \
  "$WORK/build" "$MANIFEST"

# Smoke check: the staged tree must leave an executable under
# /app/bin — catches a failed /usr->/app remap before the bundle
# ships.
COMMAND_NAME="$(sed -n 's/^command:[[:space:]]*//p' "$MANIFEST" | head -1)"
[ -n "$COMMAND_NAME" ] || die "no command: key in $MANIFEST"
flatpak-builder --run "$WORK/build" "$MANIFEST" \
  sh -c 'test -x "/app/bin/$1" || { echo "missing /app/bin/$1" >&2; ls -l /app/bin >&2; exit 1; }' _ "$COMMAND_NAME"

BUNDLE="$ROOT/dist/lucerne-linux-amd64.flatpak"
flatpak build-bundle --runtime-repo="$FLATHUB_REPO" \
  "$WORK/repo" "$BUNDLE" "$APP_ID"
if ((INSTALL)); then
  flatpak install --user -y --noninteractive "$BUNDLE"
fi
echo "Built ${BUNDLE#"$ROOT"/}"
