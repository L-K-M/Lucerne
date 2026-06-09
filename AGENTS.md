# AGENTS.md — engineering guide for Lucerne

This file orients anyone (human or AI) working on the Lucerne codebase. Read
[`lucerne-plan.md`](lucerne-plan.md) first for the *why*; this file is the *how*.
Keep it and [`PROGRESS.md`](PROGRESS.md) updated as the code evolves.

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
| `Sources/Lucerne/AppDelegate.swift` | app lifecycle, document controller |
| `Sources/Lucerne/MainMenu.swift` | programmatic menu bar (File/Edit/Format/View) |
| `Sources/LucerneKit/Model/` | Codable `document.json` model + Markdown export |
| `Sources/LucerneKit/Text/` | model ⇆ `NSAttributedString` bridge |
| `Sources/LucerneKit/Layout/` | page metrics, pagination, exclusion paths |
| `Sources/LucerneKit/Views/` | canvas, page views, text views, ruler, floating images |
| `Sources/LucerneKit/IO/` | `MiniZip`, `.luce` archive read/write, `NSDocument` |
| `Sources/LucerneKit/Document/` | the editor controller tying model↔views together |

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

## Adding a feature — checklist

1. If it touches the file format, update `Model/` structs **and both**
   `docs/file-format.md` (overview) and `docs/luce-format-spec.md` (the normative
   spec + JSON Schema), and bump `formatVersion` if the change isn't backward
   compatible. The spec is the contract third-party tools build against — keep it
   exact.
2. If it affects layout, add/adjust a geometry test in `Tests/`.
3. Update `PROGRESS.md` (and this file if architecture shifts).
4. On a Mac: `swift build && swift test`. Otherwise rely on CI.
