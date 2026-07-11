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

`EditorController.paginateAndExclude()` keeps the number of pages in sync with the
text and assigns each container's exclusion paths in one pass:

1. Reset every container to its image-wrap exclusion paths.
2. Force layout of the last container. If laid-out glyphs end before
   `numberOfGlyphs`, there's overflow → append a page and repeat.
3. If a paragraph is flagged `pageBreakBefore` and lands partway down a page, add a
   full-width **exclusion band** from its line to the page bottom, forcing it (and
   the text after it) onto the next page; then re-check overflow.
4. Trim trailing empty pages (keep at least one).

It runs after every edit (`NSTextStorageDelegate.textStorageDidProcessEditing`) and
after object changes. Because pages are uniform (D1), there is no geometry-change
reflow case — only the boundary-straddling image, handled per D1. Documents with no
page breaks skip step 3 entirely (identical to plain overflow pagination).

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

## Structural features on top of the pipeline

These were layered on without changing the core pipeline. All that need "which page
is character *i* on?" use one shared primitive,
`EditorController.pageNumber(forCharacterAt:)` (glyph → container → page index).

| Feature | Where it lives | Note |
|---|---|---|
| **Headers & footers** | `EditorController` resolves `{page}{pages}{date}{title}` per page; `PageContainerView` draws them in the margins | *Repeated margin content*, deliberately **not** in the shared `NSTextStorage`, so it never touches body reflow. Model: `header`/`footer` zones. |
| **Heading navigator** | `headingOutline()` scans body paragraphs by style role; `NavigatorView` lists them; `revealHeading` scrolls | No document mutation; pure read of the model + page lookup. |
| **Printed ToC** | `insertOrUpdateTableOfContents()` writes a `toc`-styled paragraph block with right-aligned page numbers | Generated, so it goes stale; inserting it shifts later pages, so it **converges over a ≤3-pass relayout loop** (same idea as page-break bands). Ordinary paragraphs in the model — no special block type. |
| **Forced page breaks** | `pageBreakBefore` paragraph flag → a full-width exclusion *band* in `paginateAndExclude()` | Isolated, so break-free documents are byte-for-byte the plain overflow case. |
| **Version history** | `IO/DocumentHistory.swift` appends a dated Markdown snapshot to `history/` on save; `HistoryPruner` thins with age | Recovery convenience; non-authoritative (`document.json` is the source of truth). |
| **Tables** | `EditorController.insertTable` builds `NSTextTable` cells; the bridge stores each cell as a `Paragraph.cell` and regroups them on load | TextKit flows and paginates the table — no new layout engine. Body stays a flat paragraph list (no nested block type). |
| **Lists** | `Paragraph.list` crosses the attributed-string bridge; `ListMarkers` derives counters/glyphs and `ListMarkerLayoutManager` draws the marker gutter | List membership is independent of named style. A list is a contiguous same-id paragraph run; markers are not canonical text. |

## Module boundaries

- `Model/` — AppKit-free Codable model + Markdown export + geometry/list numbering.
  Unit-tested.
- `Text/` — bridges the model to `NSAttributedString` and back, including the
  `.lucerneStyleRole` custom attribute that carries paragraph-style roles through
  round-trips.
- `Layout/` — `PageMetrics` (pure math), `ExclusionPathController`.
- `Views/` — canvas, page, text view, ruler, navigator, status bar, sheets, floating
  image, the hand-drawn classic control chrome (`ClassicControls.swift`, used by the
  format bar, status bar, ruler, and welcome screen, muting with window activation),
  and the live try-on pickers (`TryOnPopover.swift` + `PickerListView.swift`, the
  shared specimen-list UI behind the font/style popovers and floating palettes).
- `IO/` — `MiniZip`, `.luce` archive, version history, `NSDocument` subclass,
  PDF/print, and lossy RTF/DOCX export.
- `Document/` — `EditorController` (conductor: pagination, exclusions, furniture,
  outline, ToC) + `DocumentWindowController` (toolbar/ruler/canvas/status/navigator).
- `Support/` — small AppKit helpers (color↔hex, image↔data, geometry bridge).

## Known limitations

See `AGENTS.md` ▸ "Gotchas / known limitations" and `ANALYSIS.md` — cross-page
selection, boundary overhang, irregular wrap, the scope of `MiniZip`, dialog-only
header/footer editing, table row/merge limitations, and custom-list marker
interchange/accessibility. Tables, lists, Markdown table export, DOCX export, and the
printed ToC's dotted leader **are** implemented. The leader is drawn as measured `.`
text, since Cocoa tabs have no leader fill, and goes stale until the ToC command is
re-run. Interactive rendering and responder behavior still require Mac QA.
