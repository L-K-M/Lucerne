# Building Lucerne

## Prerequisites

- **macOS 13 (Ventura) or later.** Lucerne is an AppKit app; it does not build or
  run on Linux/Windows.
- **Swift 5.9+** — either Xcode 15+ (recommended) or the Swift.org toolchain.

> This repository was authored in a Linux container with no Swift toolchain, so it
> is **not compiled there**. Compilation is verified on a macOS GitHub Actions
> runner (`.github/workflows/ci.yml`). If you are picking this up on a Mac, the
> first thing to do is `swift build` and address anything CI hasn't already caught.

## Develop (fast loop)

```sh
swift build          # compile
swift run Lucerne    # launch the app
swift test           # run model / markdown / geometry unit tests
```

Running via `swift run` launches a working editor: New/Open/Save panels, editing,
formatting, the ruler, image insertion, and live reflow all work. The one thing it
*doesn't* get is OS-level document-type registration (double-clicking a `.luce` in
Finder, the custom icon), because that comes from the bundle `Info.plist`. For that,
build the app bundle.

## Build a distributable app

```sh
Scripts/make-app.sh        # release build → dist/Lucerne.app (ad-hoc signed)
Scripts/make-app.sh --debug
open dist/Lucerne.app
```

The script compiles with SPM, lays out `Lucerne.app/Contents/{MacOS,Resources}`,
copies `Scripts/Info.plist` (which declares the `.luce` document type and its
`public.zip-archive`-conforming UTI), and ad-hoc codesigns it.

The app and document icons are generated automatically from
`media-sources/icon.png` by `Scripts/GenerateIcons.swift` (run by `make-app.sh`,
needs `iconutil`): the app icon is a rounded tile of the artwork, and the document
icon derives a folded-corner page from it. To regenerate them by hand:

```sh
swift Scripts/GenerateIcons.swift   # writes Scripts/{AppIcon,DocumentIcon}.icns
```

## Open in Xcode

`File ▸ Open…` the package folder (or `xed .`). Xcode reads `Package.swift`
directly; choose the `Lucerne` scheme to run. Note that running from Xcode without
the bundle still lacks Finder document-type registration — same caveat as
`swift run`.

## Troubleshooting

- **"document type couldn't be determined" when opening from Finder.** You launched
  the unbundled binary. Use `Scripts/make-app.sh` and open the resulting `.app`.
- **TextKit 2 surprises.** Lucerne deliberately uses **TextKit 1** (it constructs
  and owns the `NSLayoutManager`). Don't introduce `NSTextLayoutManager` on the
  page text views; see `AGENTS.md` ▸ "Why TextKit 1".
- **Gatekeeper blocks the app.** It's ad-hoc signed for local use. Right-click ▸
  Open the first time, or sign with a Developer ID for distribution.
