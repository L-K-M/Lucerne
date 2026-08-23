# Building Lucerne

Two apps live in this repository: the original **macOS** AppKit app (this
page's main subject) and **Lucerne for Linux**, a native Qt 6 port under
[`linux/`](../linux/README.md) that reads and writes the same `.luce` files.

## Linux (Qt port)

```sh
sudo apt install qt6-base-dev qt6-base-dev-tools libgl1-mesa-dev zlib1g-dev \
                 cmake ninja-build
cmake -S linux -B linux/build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build linux/build
./linux/build/lucerne            # or --sample for the demo letter
ctest --test-dir linux/build     # headless test suites
```

See [`linux/README.md`](../linux/README.md) for packaging (.deb/AppImage),
architecture, and the parity list. The portable Swift core also builds on
Linux — `swift build && swift test` at the repo root exercises `LucerneCore`
and the `.luce` format-conformance suite (the AppKit targets are declared only
on macOS, so this works with a stock Swift toolchain).

## macOS

### Prerequisites

- **macOS 13 (Ventura) or later** for the AppKit app itself.
- **Swift 5.9+** — either Xcode 15+ (recommended) or the Swift.org toolchain.

> This repository was authored in a Linux container with no Swift toolchain, so it
> is **not compiled there**. The macOS GitHub Actions runner
> (`.github/workflows/ci.yml`) verifies it: `swift build`, `swift test`, and the
> icon generator (`swift Scripts/GenerateIcons.swift`). What CI *cannot* check is
> interactive behaviour, so on a Mac the first thing to do is `swift build` and then
> exercise the app — live reflow, ruler dragging, multi-page editing — and address
> anything CI hasn't already caught.

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
Scripts/build.sh           # release build → dist/Lucerne.app, revealed in Finder
Scripts/build.sh --debug   # debug configuration instead
Scripts/build.sh --run     # build, then launch the app
Scripts/build.sh --clean   # wipe .build/ + dist/ and rebuild from scratch
```

`Scripts/build.sh` is the recommended local build. It wraps the assembler
`Scripts/make-app.sh`, which compiles with SPM, lays out
`Lucerne.app/Contents/{MacOS,Resources}`, copies `Scripts/Info.plist` (which
declares the `.luce` document type and its `public.zip-archive`-conforming UTI),
and ad-hoc codesigns it; `build.sh` then reveals the result in Finder (and
launches it with `--run`).

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
  the unbundled binary. Use `Scripts/build.sh` and open the resulting `.app`.
- **TextKit 2 surprises.** Lucerne deliberately uses **TextKit 1** (it constructs
  and owns the `NSLayoutManager`). Don't introduce `NSTextLayoutManager` on the
  page text views; see `AGENTS.md` ▸ "Why TextKit 1".
- **Gatekeeper blocks the app.** It's ad-hoc signed for local use. Right-click ▸
  Open the first time, or sign with a Developer ID for distribution.
