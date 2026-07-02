# CI/CD

Lucerne is a Swift Package Manager app. CI builds and tests it on a macOS runner (the
only place it actually compiles — the package is authored on Linux, which has no
AppKit), and the release workflow assembles an unsigned, ad-hoc-codesigned
`Lucerne.app`, packages it as a `.zip` and `.dmg`, and publishes a GitHub Release.

## Workflows

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| `.github/workflows/ci.yml` | Pushes to `main`/`claude/**`, PRs, manual | `swift build` + `swift test`, icon generation, and app-bundle assembly (`Scripts/make-app.sh`) on macOS. |
| `.github/workflows/release.yml` | Pushing a `v*` tag (e.g. `v1.2.0`) | Build `Lucerne.app`, package `.zip` + `.dmg`, and publish a GitHub Release. |

## Continuous integration (`ci.yml`)

Runs **Build & test** on `macos-14`: selects a recent Xcode, prints the Swift version,
then `swift build -v` and `swift test -v`. It then runs `Scripts/GenerateIcons.swift`
(asserting the two `.icns` files it should produce exist) and assembles the app bundle
with `Scripts/make-app.sh`, asserting the built `dist/Lucerne.app` contains its
executable, `Info.plist`, `Lucerne.sdef`, and the app/document icons — so bundle
breakage surfaces in the gated CI run, not first at release time.

> CI assembles the bundle with `Scripts/make-app.sh` — the same assembler
> `release.yml` uses (below); local developers use `Scripts/build.sh`, which wraps it
> and reveals the result in Finder (see [`docs/building.md`](docs/building.md)).

## Releases (`release.yml`)

To cut a release:

```
git tag v1.2.3
git push origin v1.2.3
```

Or use the helper, which bumps the committed `CFBundleShortVersionString`
(`Scripts/Info.plist`) and the README version line so local/dev builds report the same
number, then creates and pushes the matching tag:

```
Scripts/release.sh 1.2.3 --push
```

The version is derived from the tag with the leading `v` stripped (e.g. `v1.2.3` →
`1.2.3`), and the build number is the workflow run number. The job runs on `macos-14`.

Before building, the workflow **verifies the tag matches the committed version** — the
tag-derived version must equal both `Scripts/Info.plist`'s `CFBundleShortVersionString`
and the README version marker, failing with a clear message otherwise (this check runs
before the plist is stamped from the tag, so it sees the committed values) — and then
**runs `swift test`**, so a tag can't publish a release from a commit that never went
green.

It produces:

- An **unsigned** `Lucerne.app` assembled by `Scripts/make-app.sh` (`swift build -c
  release` → `dist/Lucerne.app`), with `CFBundleShortVersionString` **stamped from the
  tag** (so the released app's version always matches the tag, regardless of the
  committed plist).
- The app is **ad-hoc codesigned** (`codesign --force --deep --sign -`, done inside
  `make-app.sh`). This is not a Developer ID signature and the app is not notarized — it
  is only required so the app can launch on Apple Silicon.
- A `Lucerne-<version>.zip` (via `ditto`) and a `Lucerne-<version>.dmg` (via
  `create-dmg`).

Both files are attached to a GitHub Release (named `Lucerne <version>`, with
auto-generated notes) via `softprops/action-gh-release`. The release body explains that,
because the app is **unsigned and un-notarized, macOS Gatekeeper warns on first launch**,
and tells users to right-click → Open or run `xattr -dr com.apple.quarantine
/Applications/Lucerne.app`.

## Secrets

None. Neither workflow uses repository secrets beyond the automatically provided
`GITHUB_TOKEN` (which `action-gh-release` uses to create the release). Releases are
intentionally unsigned, so no Apple certificates or notarization credentials are
required.
