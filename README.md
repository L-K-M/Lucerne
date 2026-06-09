# Lucerne

*A ClarisWorks-style word editor for the Mac — a small, pleasant tool for writing
letters, with rulers, tabs, and genuine free placement of images.*

Lucerne is a native macOS application built on AppKit and TextKit 1. Its defining
feature is **100% free image placement with live text flow**: drop an image
anywhere on the page and the body text reflows around it, staying correct through
every subsequent edit. This is implemented the way the platform intends — via
`NSTextContainer.exclusionPaths` — rather than fought for. See
[`lucerne-plan.md`](lucerne-plan.md) for the full design rationale (this project
implements **Avenue A**).

> **Status:** under active construction. See [`PROGRESS.md`](PROGRESS.md) for the
> live feature checklist and [`AGENTS.md`](AGENTS.md) for the engineering guide.

---

## What it does

1. **A simple editing surface** — type, edit, select, undo, print, save/open, on
   discrete A4 (or Letter) pages.
2. **Basic text formatting** — font, size, bold/italic/underline, color,
   alignment, line spacing, paragraph spacing.
3. **Rulers and tabs** — a horizontal ruler with draggable indent markers and tab
   stops (left/center/right/decimal).
4. **Free image placement with text flow** — drag an image to any `(x, y)` on a
   page; text wraps around its rectangle and reflows live as you edit.

## Documents: the `.luce` file

Lucerne saves `.luce` files. A `.luce` file **is a ZIP archive** (it conforms to
`public.zip-archive`), so the recovery story is literally "rename it to `.zip` and
unzip." Inside:

```
document.json   canonical, lossless model — text runs + placed objects (the source of truth)
images/         the placed images as their original files
content.md      a derived, human-readable Markdown copy of the text (write-only escape hatch)
```

`content.md` is **regenerated on every save and never read back** — it exists so a
future human can recover the words and pictures even if this app is gone. A short
overview is in [`docs/file-format.md`](docs/file-format.md); the complete,
normative specification — enough to build a compatible tool, with a JSON Schema —
is in [`docs/luce-format-spec.md`](docs/luce-format-spec.md).

Other formats:

- **PDF** — share / print (perfect visual fidelity, read-only).
- **RTF** — explicitly lossy export (text & formatting survive; free-placed images
  flatten out — they remain in the `.luce` and PDF).
- **DOCX** — lossy export, *planned*.

## Building & running

> **Requires macOS** (Ventura 13+) and the Swift toolchain (Xcode 15+ or the
> Swift.org toolchain). This repository was authored on Linux, where AppKit is
> unavailable, so it **cannot be compiled in that environment** — build it on a
> Mac. Compilation is verified by the macOS GitHub Actions workflow.

Quick development run (no app bundle, panels-based open/save work):

```sh
swift run Lucerne
```

Produce a double-clickable `Lucerne.app` (with `.luce` document-type registration):

```sh
Scripts/make-app.sh        # writes dist/Lucerne.app
open dist/Lucerne.app
```

Run the tests (model, Markdown export, geometry — no GUI needed):

```sh
swift test
```

See [`docs/building.md`](docs/building.md) for details and troubleshooting.

## Project layout

```
Sources/
  Lucerne/        executable: NSApplication entry point + main menu
  LucerneKit/     library: Model, Text bridge, Layout engine, Views, IO
Tests/
  LucerneKitTests/  unit tests for the model, Markdown export, and geometry
Scripts/
  make-app.sh         assembles a .app bundle around the SPM-built binary
  Info.plist          bundle metadata + .luce document type / UTI declarations
  GenerateIcons.swift renders the app + document icons from media-sources/icon.png
media-sources/        artwork sources (icon.png, icon.af) for the icons
docs/                 architecture, file format, building, roadmap notes
```

## License

See [`LICENSE`](LICENSE) if present; otherwise treat as all-rights-reserved pending
a license decision.
