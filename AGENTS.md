# AGENTS.md — engineering guide for Lucerne

This file orients anyone (human or AI) working on the Lucerne codebase. Read
[`lucerne-plan.md`](lucerne-plan.md) first for the *why*; this file is the *how*.
Keep it and [`PROGRESS.md`](PROGRESS.md) updated as the code evolves.

Lucerne is a native macOS application built on AppKit and TextKit 1. Its defining
feature is **100% free image placement with live text flow**: drop an image
anywhere on the page and the body text reflows around it, staying correct through
every subsequent edit. This is implemented the way the platform intends — via
`NSTextContainer.exclusionPaths` — rather than fought for. See
[`lucerne-plan.md`](lucerne-plan.md) for the full design rationale (this project
implements **Avenue A**).

> **Status:** the four core areas below are implemented and the macOS CI build +
> unit tests are green; the app is in interactive on-device QA. See
> [`PROGRESS.md`](PROGRESS.md) for the live feature checklist, [`AGENTS.md`](AGENTS.md)
> for the engineering guide, and [`docs/roadmap.md`](docs/roadmap.md) for what's next.

---

## What it does

1. **A simple editing surface** — type, edit, select, undo, print, save/open, on
   discrete A4 (or Letter) pages.
2. **Basic text formatting** — font, size, bold/italic/underline, color,
   alignment, line spacing, paragraph spacing.
3. **Rulers and tabs** — a horizontal ruler with draggable indent markers and tab
   stops (left/center/right/decimal).
4. **Free image placement with text flow** — drag an image to any `(x, y)` on a
   page; text wraps around its rectangle and reflows live as you edit. Drag it
   across a page boundary and it re-anchors on the page it lands on.

Built on top of those four pillars: named paragraph styles, forced page breaks,
page zoom, running **headers & footers** with page-number / date / title tokens, a
**heading navigator** sidebar, a generated **table of contents**, PDF and (lossy)
RTF export, AppleScript scripting, a welcome screen with recent documents, and
crash/draft recovery. See [`PROGRESS.md`](PROGRESS.md) for the full list.

## What this is

A native **macOS / AppKit / Swift** word processor implementing **Avenue A** of the
plan: editing on `NSTextView` with **TextKit 1**, and free image placement via
`NSTextContainer.exclusionPaths`. The mental model is **Avenue E**: a page canvas
holding one paginated text frame, plus floating objects that *punch holes* in it.

## Critical environment note

This repo was authored in a **Linux container with no Swift toolchain and no
AppKit**, so the code here was **not compiled locally** during authoring. It is
written to be correct by construction and is **compile-verified by CI**
(`.github/workflows/ci.yml`, on a macOS runner) — the build and unit tests are
**green**. What CI can't check is interactive behaviour (live reflow, ruler
dragging, multi-page editing); that still needs a human on a Mac. When you change
code:

- If you are on a Mac, run `swift build` / `swift test` and fix what breaks.
- If you are not, reason carefully and lean on the CI signal. Do not claim a build
  passes that you have not seen pass.

## Architecture at a glance

```
NSTextStorage ──> NSLayoutManager ──> [NSTextContainer]  (one per page, identical size — D1)
                        │                     │
                        │                     └── exclusionPaths  (one set per page)
                        │
                  drives layout / pagination
                        │
            [PageTextView]  (one NSTextView per container, shares the layout manager)
                        │
            PageContainerView  (one per page: white page, margins, hosts text view + images)
                        │
              PageCanvasView  (stacks pages vertically inside an NSScrollView)
```

- **One** `NSTextStorage` and **one** `NSLayoutManager` for the whole document.
- **N** `NSTextContainer`s, one per page, all the same size (D1). Text flows from
  container *i* into container *i+1* automatically — that *is* pagination.
- **N** `NSTextView`s, one bound to each container, all sharing the layout manager.
  This is Apple's documented multi-page pattern.
- Floating images are **subviews** of the per-page `PageContainerView`, which is
  `isFlipped = true` so its coordinate system matches the model (origin top-left,
  y down). An image's view frame in that page == its model `frame` directly.

### The hard feature, concretely

For a page-anchored object on page *p* with page-relative `frame` `(x,y,w,h)` and
`standoff` *s*:

1. Convert to that page's **text-container coordinates** by subtracting the page
   margins: `cx = x - marginLeft`, `cy = y - marginTop`.
2. Inflate by the standoff: exclusion rect = `(cx - s, cy - s, w + 2s, h + 2s)`.
3. Build an `NSBezierPath` and assign it to `container[p].exclusionPaths`.
4. The layout manager reflows text around it; overflow pushes onto later pages.

All of this lives in `Layout/ExclusionPathController.swift`. The rect↔container math
is in `Layout/PageMetrics.swift`. Geometry is unit-tested without a GUI.

## Why TextKit 1 (not TextKit 2)

The plan calls this out: `exclusionPaths` are battle-tested in TextKit 1, and the
multi-container "one layout manager, many containers" pagination model is a TextKit
1 idiom. We force TextKit 1 compatibility by **constructing and owning the
`NSLayoutManager` ourselves** and attaching it to the text storage; an `NSTextView`
that is handed an explicit `NSTextContainer`/`NSLayoutManager` stays on the TextKit
1 path. Do not call TextKit-2-only APIs (`textLayoutManager`, `NSTextLayoutManager`)
on these views.

## Source map

| Path | Responsibility |
|---|---|
| `Sources/Lucerne/main.swift` | `NSApplication` bootstrap |
| `Sources/Lucerne/AppDelegate.swift` | app lifecycle, welcome/about, document controller |
| `Sources/Lucerne/MainMenu.swift` | programmatic menu bar (File/Edit/Format/Insert/View) |
| `Sources/Lucerne/WelcomeWindowController.swift` | start screen (recents + New/Open/Sample) |
| `Sources/Lucerne/AboutWindowController.swift` | custom About window with the app icon |
| `Sources/LucerneKit/Model/` | Codable `document.json` model + Markdown export |
| `Sources/LucerneKit/Text/` | model ⇆ `NSAttributedString` bridge (`.lucerne*` attributes) |
| `Sources/LucerneKit/Layout/` | page metrics, pagination, exclusion paths |
| `Sources/LucerneKit/Views/` | canvas, page views, text views, ruler, navigator, status bar, sheets, floating images, try-on pickers + app-global floating palettes, the style editor panel + Style Library window |
| `Sources/LucerneKit/IO/` | `MiniZip`, `.luce` archive read/write, version history, the global style library (`styles.json`), `NSDocument`, printing |
| `Sources/LucerneKit/Document/` | `EditorController` + window controller tying model↔views together |
| `Sources/LucerneKit/Support/` | small AppKit helpers (color↔hex, image↔data, geometry bridge) |

### Feature subsystems (all on the core pipeline above)

- **Headers & footers** are *repeated margin content*, not part of the shared
  `NSTextStorage`. `EditorController` resolves `{page}{pages}{date}{title}` tokens
  per page and `PageContainerView` draws them in the top/bottom margins. Model:
  `header`/`footer` (`PageFurniture`, three zones). Edited via `HeaderFooterSheet`.
- **Heading navigator** (`NavigatorView`): `EditorController.headingOutline()` scans
  body paragraphs for heading style roles; clicking scrolls via `revealHeading`.
- **Printed table of contents**: `insertOrUpdateTableOfContents()` generates a block
  of paragraphs (a `toc` style role) with right-aligned page numbers, converged over
  a ≤3-pass relayout loop because inserting it shifts the very page numbers it lists.
  It is ordinary paragraphs in the model — no special block type.
- **Version history** (`IO/DocumentHistory.swift`): each save appends a dated
  Markdown snapshot under `history/` in the `.luce`, thinned with age
  (`HistoryPruner`) so accidentally-deleted prose is recoverable by unzipping.
- **Tables** (`NSTextTable`): each cell is a paragraph carrying a `Paragraph.cell`
  descriptor; `AttributedStringBuilder` regroups same-`table` cells into one shared
  `NSTextTable` (deriving the column count) and the reader maps the blocks back. The
  body stays a flat paragraph list — no nested block type in the model or file.
- The structural features that need page numbers lean on the shared
  `EditorController.pageNumber(forCharacterAt:)` glyph→page primitive.

## Conventions

- **Units are points (1/72")** everywhere, matching the file format and TextKit.
- **Coordinate origin is page top-left, y down.** Page/container views are
  `isFlipped`. Convert at view boundaries, never in the model.
- The **model is the source of truth for structure**; the live `NSTextStorage` is
  the source of truth for text *while editing*. On save we read the text storage
  back into the model (`Text/AttributedStringReader`). Paragraph style *roles* are
  carried as a custom attribute (`.lucerneStyleRole`) so they survive round-trips
  instead of being guessed from font size.
- Custom attributed-string keys live in `Text/LucerneAttributes.swift`.
- **Style definitions are baked into the storage at apply time.** Editing a
  definition must re-apply it (`EditorController.applyStylesheetChange`, the S3
  engine in STYLES.md) — never mutate `model.styles` for an in-use role without
  it, or the next save pins the old look as overrides on every paragraph.
- Prefer small, testable free functions for math; keep AppKit out of `Model/`.

## Gotchas / known limitations (keep this honest)

- **Cross-page selection** is not unified: each `NSTextView` owns selection within
  its own page (a property of the shared-layout-manager pattern). Editing within a
  page is full-featured. Unifying selection across pages is future work.
- **Image overhang at page boundaries**: v1 clips a floating image to its page
  bounds. The plan permits overhang; revisit if desired.
- **Irregular (alpha) wrap** is modeled (`wrap: "irregular"`) but currently falls
  back to the bounding rectangle. Rectangular wrap is the supported path.
- **MiniZip** writes *stored* (uncompressed) entries — fine because images are
  already compressed and text is tiny — and reads stored + deflate (via the
  `Compression` framework). It is not a general-purpose ZIP library.
- **Printed ToC** has no dotted tab leader (Cocoa's `NSTextTab` doesn't support
  one) and goes stale as the document changes until you re-run the command.
- **Headers/footers** are edited in a dialog; clicking into the margin to edit them
  in place is future work (the model already supports the three zones).
- **Tables** are v1: Insert ▸ Table… makes an editable `NSTextTable` grid that flows
  with the text, with insert/delete row & column, ↑/↓ cell navigation, Select Table,
  cell merging (spans), and column resize (drag the ruler dividers; widths persist as
  `cell.width`) — all via Format ▸ Table or the context menu. Deferred: page-boundary
  splitting relies on TextKit row-breaking (a single row taller than a page can't
  split); structural row/column edits reset merged cells (they rebuild a full grid);
  cells are assumed single-paragraph. **Lists** aren't implemented yet (`NSTextList`).
  See `docs/roadmap.md`.

Future direction lives in [`docs/roadmap.md`](docs/roadmap.md); the live feature
checklist is [`PROGRESS.md`](PROGRESS.md).

## Adding a feature — checklist

1. If it touches the file format, update `Model/` structs **and both**
   `docs/file-format.md` (overview) and `docs/luce-format-spec.md` (the normative
   spec + JSON Schema), and bump `formatVersion` if the change isn't backward
   compatible. The spec is the contract third-party tools build against — keep it
   exact.
2. If it affects layout, add/adjust a geometry test in `Tests/`.
3. Update `PROGRESS.md` (and this file if architecture shifts).
4. On a Mac: `swift build && swift test`. Otherwise rely on CI.
