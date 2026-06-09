# Architecture

Lucerne implements **Avenue A** (native AppKit + TextKit 1 exclusion paths) using
the **Avenue E** mental model: a page canvas holding one paginated text frame, plus
floating objects that *punch holes* in it. This document goes a level deeper than
`AGENTS.md`.

## The layout pipeline

```
              document.json model
                     │  AttributedStringBuilder
                     ▼
              NSTextStorage  ──────────────┐
                     │                      │ textStorageDidProcessEditing
                     ▼                      ▼
              NSLayoutManager  ──────> EditorController.relayout()
                /     |      \                 │ ensures page count,
               ▼      ▼       ▼                │ updates exclusions
        container[0] [1] …  [n]   <── ExclusionPathController
            │         │       │
            ▼         ▼       ▼
        PageTextView (one NSTextView per container, shared layout manager)
            │
            ▼
        PageContainerView (white page; isFlipped; hosts text view + FloatingImageViews)
            │
            ▼
        PageCanvasView (vertical stack of pages in an NSScrollView)
```

- **One** `NSTextStorage` + **one** `NSLayoutManager` for the document.
- **N** identical `NSTextContainer`s (D1), one per page. Text overflowing
  container *i* flows into *i+1* — that is the entirety of pagination.
- **N** `NSTextView`s, each bound to one container, all sharing the layout manager
  (Apple's documented multi-page pattern). TextKit 1 is forced by owning the layout
  manager ourselves.

## Pagination

`EditorController` keeps the number of pages in sync with the text:

1. After an edit (`NSTextStorageDelegate.textStorageDidProcessEditing`), call
   `ensurePageCount()`.
2. Force layout of the last container. If laid-out glyphs in it end before
   `numberOfGlyphs`, there's overflow → append a page (new container + text view +
   page view), recompute that page's exclusion paths, repeat.
3. Trim trailing empty pages (keep at least one).

Because pages are uniform (D1), there is no geometry-change reflow case — only the
boundary-straddling image, handled per D1.

## Coordinates — the part that bites

Three coordinate spaces, converted only at the boundaries:

| Space | Origin | Used by |
|---|---|---|
| **Model / page** | page top-left, y down | `document.json` `frame`, object positions |
| **Page view** | top-left, y down (`isFlipped`) | `PageContainerView` + image subviews |
| **Text container** | top-left, y down | `exclusionPaths`, glyph layout |

The page view's bounds equal the full page (incl. margins). The text view sits at
inset `(margins.left, margins.top)` with size `page.contentSize`. So:

```
imageView.frame (in page view)  ==  object.frame              // direct — both top-left/y-down
exclusionRect (in container)    ==  object.frame
                                       .offsetBy(-margins.left, -margins.top)
                                       .insetBy(-standoff)      // outward by the gutter
```

This single mapping is the crux of the "fiddly coordinate bookkeeping" the plan
warns about. It's isolated in `Layout/PageMetrics.swift` and exercised by unit
tests so it can't silently drift.

## Reflow triggers

| Event | What runs |
|---|---|
| Typing / paste / delete | text storage edit → `relayout()` → page count + exclusions |
| Dragging an image | `FloatingImageView` → update model `frame` → recompute that page's exclusions → relayout |
| Inserting/removing an image | rebuild that page's exclusions → relayout |
| Changing standoff / wrap | recompute exclusions → relayout |
| Window resize | none for text (pages are fixed size, D1); canvas just recentres |

## Module boundaries

- `Model/` — AppKit-free Codable model + Markdown export + geometry. Unit-tested.
- `Text/` — bridges the model to `NSAttributedString` and back, including the
  `.lucerneStyleRole` custom attribute that carries paragraph-style roles through
  round-trips.
- `Layout/` — `PageMetrics` (pure math), `ExclusionPathController`.
- `Views/` — canvas, page, text view, ruler, floating image.
- `IO/` — `MiniZip`, `.luce` archive, `NSDocument` subclass, PDF export.
- `Document/` — `EditorController`, the conductor wiring model ⇆ views.

## Known limitations

See `AGENTS.md` ▸ "Gotchas / known limitations" — cross-page selection,
boundary overhang, irregular wrap, and the scope of `MiniZip`.
