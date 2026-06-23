# CI/CD

Lucerne is a Swift Package Manager app. CI builds and tests it on a macOS runner (the
only place it actually compiles — the package is authored on Linux, which has no
AppKit), and the release workflow assembles an unsigned, ad-hoc-codesigned
`Lucerne.app`, packages it as a `.zip` and `.dmg`, and publishes a GitHub Release.

## Workflows

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| `.github/workflows/ci.yml` | Pushes to `main`/`claude/**`, PRs, manual | `swift build` + `swift test` (+ validate the icon generator) on macOS. |
| `.github/workflows/release.yml` | Pushing a `v*` tag (e.g. `v1.2.0`) | Build `Lucerne.app`, package `.zip` + `.dmg`, and publish a GitHub Release. |

## Continuous integration (`ci.yml`)

Runs **Build & test** on `macos-14`: selects a recent Xcode, prints the Swift version,
then `swift build -v`, `swift test -v`, and runs `Scripts/GenerateIcons.swift` to make
sure the icon generator still works.

> CI builds the bundle with `Scripts/make-app.sh` (see `release.yml` below); local
> developers use `Scripts/build.sh`, which wraps the same assembler and reveals the
> result in Finder (see [`docs/building.md`](docs/building.md)).

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
