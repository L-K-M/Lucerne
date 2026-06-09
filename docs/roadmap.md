# Roadmap

Forward-looking plan for Lucerne. For the full, granular feature checklist see
[`PROGRESS.md`](../PROGRESS.md); for the file-format contract see
[`luce-format-spec.md`](luce-format-spec.md). This document focuses on **what's
next and why**, with rough effort estimates (developer-days) and how each item
fits the architecture: TextKit 1, one layout manager + one container per page
(D1), named paragraph styles (D3), and page-anchored objects that punch holes in
the text frame.

> **Verification reality.** The project is authored without a local Swift
> toolchain and is verified only by macOS CI (build + unit tests). Anything that
> can't be unit-tested needs on-device QA, so the working rhythm is: ship a first
> cut, QA on a Mac, iterate. Estimates below are for the *implementation*; budget
> extra for that QA loop.

## Shared primitive (the thing everything leans on)

Almost every structural feature needs "which page is character *i* on?". That's
shipped as `EditorController.pageNumber(forCharacterAt:)` (1-based; via
`glyphIndexForCharacter → textContainer(forGlyphAt:) → pages.firstIndex`). Page
numbers, the ToC's page column, and the navigator's "jump to heading" all use it,
and tables will too (cells have character indices).

## Shipped (the roadmap so far)

The original exploration proposed five steps; the first four are done:

1. ✅ **`pageNumber(forCharacterAt:)`** — the shared glyph→page primitive above.
2. ✅ **Headers & footers / page numbers** — three zones (left/center/right) with
   `{page} {pages} {date} {title}` tokens, drawn in the top/bottom page margins of
   every page. Set via a dialog (Insert ▸ Header & Footer…) and persisted as
   `header`/`footer` in `document.json`. They are *repeated margin content*, not
   part of the flowing `NSTextStorage`, so they don't interact with body reflow.
   Numbering can start on a chosen page (`pageNumberStart`) so a title/contents page
   stays unnumbered.
3. ✅ **Heading navigator** — a sidebar (View ▸ Show Navigator) listing the
   document's headings, built by scanning body paragraphs for heading style roles;
   click an entry to scroll to it.
4. ✅ **Printed table of contents** — Insert ▸ Table of Contents generates a block
   of entries with a **dotted leader** to a right-aligned page number. Because
   inserting it shifts later content (and thus the page numbers it lists), it
   **converges over a short relayout loop** (≤3 passes), like the page-break bands.
   It's persisted as a `toc` paragraph style and carries no special structure in the
   file (it's just paragraphs); re-run the command to refresh it.

What remains from the original plan — **editable** headers/footers and **tables** —
plus items learned along the way, is below, roughly in priority order.

## Next up

### Tables — `NSTextTable` (the big one) · ~3–6 days

**TextKit 1 supports tables natively** via `NSTextTable` / `NSTextTableBlock`
attached to paragraph styles. Cells are ranges of the same text storage, and the
layout manager flows a table within the container and **paginates it across pages**
for us — so tables do *not* require a new layout engine; they fit the current model.

- **Model.** Tables are the first body content that isn't a flat paragraph list, so
  the file format needs a table block type (rows/cells, each cell a paragraph list),
  or — to stay flat — a per-paragraph "this paragraph is cell (table, row, col,
  span)" descriptor that the reader regroups into shared `NSTextTable` instances on
  load. The flat approach keeps `body` an ordered paragraph array and round-trips
  through the existing bridge with one more custom attribute; it's the recommended
  first cut. Either way this is the largest model change of the roadmap (bump
  nothing if additive/optional; otherwise bump `formatVersion`).
- **Editing.** Cell navigation (Tab / arrows), insert/delete row & column, and later
  column resize (the ruler could grow column markers). This is the bulk of the work.
- **Interaction with shipped features.** The page-number helper still works (cells
  have character indices); the ToC scanner and heading navigator ignore table
  content; headers/footers are unaffected.
- **Known hard parts:** a table row straddling a page boundary, and serializing the
  shared-table object graph faithfully. Ship rectangular, non-splitting tables
  first; document the limits.

### Editable header/footer click-zones · ~3–5 days (almost all UI)

Headers/footers are edited in a dialog today. The richer experience is to click
into the margin band and type in place, with three tab zones and a field-token
insertion UI. This is hit-testing in the margins plus an inline editor overlay; **no
model change** is needed — the `header`/`footer` zones already exist.

### Lists (numbering / nesting) · ~2–4 days

`NSTextList` attaches to a paragraph style's `textLists`, so TextKit renders the
bullets/numbers and handles the indentation. Model: a per-paragraph list descriptor
(marker format + nesting level); bridge it through the text storage; expose it on
the Format menu + toolbar. The model round-trip is unit-testable. A natural
companion to tables.

## Later / backlog

- **Cross-page text selection.** Each `NSTextView` owns selection within its own
  page (a property of the shared-layout-manager pattern). Unifying selection and the
  caret across page boundaries is the largest editing-surface gap.
- **Irregular (alpha-outline) image wrap.** Modeled as `wrap: "irregular"` but today
  it falls back to the bounding rectangle. Build the outline path from image alpha.
- **Image overhang at page edges.** A floating image is currently clipped to its
  page; the plan permits overhang past the edge.
- **Paragraph-anchored objects in the UI.** The model supports `anchor: "paragraph"`
  (objects that move with their text); only page-anchored placement is wired into
  the UI so far.
- **DOCX lossy export.** RTF export exists; DOCX is the next interchange target.
- **Document inspector & preferences.** A panel for page size / margins / styles,
  and app-level preferences.

## Architectural through-line

None of the above requires abandoning the TextKit-1 + per-page-container
architecture. The shared `pageNumber(forCharacterAt:)` primitive, the
named-paragraph-style system, and the page-anchored object model are the
foundations each new feature builds on — which is exactly why the file format and
the layout pipeline have stayed stable as features accrue.
