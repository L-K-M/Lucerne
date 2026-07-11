# Roadmap

Forward-looking plan for Lucerne. For the full, granular feature checklist see
[`PROGRESS.md`](../PROGRESS.md); for the file-format contract see
[`luce-format-spec.md`](luce-format-spec.md); for the canonical live backlog,
priorities, risk, ideas, and QA plan see [`ANALYSIS.md`](../ANALYSIS.md). This
document is the concise product roadmap: **what shipped and what comes next**, and
how each item fits the architecture: TextKit 1, one layout manager + one container per page
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
numbers, the ToC's page column, and the navigator's "jump to heading" all use it.

## Shipped (the roadmap so far)

The original exploration proposed five structural steps; all five are shipped, with
lists and additional export paths added since:

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
5. ✅ **Tables (v1)** — Insert ▸ Table… creates a rows×columns grid via `NSTextTable`
   / `NSTextTableBlock`. Cells are ordinary editable text; the table flows and
   **paginates with the body** (no new layout engine). The model stays a **flat
   paragraph list** — each cell is a paragraph with an optional `cell` descriptor
   (`table` id + `row`/`column` + spans) that the bridge regroups into shared
   `NSTextTable` instances on load. See "Table polish" below for what's deferred.
6. ✅ **Lists** — ordered/unordered markers, live numbering, starts, nesting,
   Return/Tab behavior, Markdown shortcuts, toolbar/menu/palette controls, and
   model/text round trips. `Paragraph.list` remains independent of named style and
   list markers are derived rather than canonical text.
7. ✅ **Interchange/recovery exports** — PDF, lossy RTF and DOCX, Markdown export/
   copy, nested Markdown lists, and GFM pipe-table rendering.

What remains — **editable** headers/footers, **table/list polish**, accessibility,
and editing integrity — plus items learned along the way, is below, roughly in
priority order.

## Next up

### Table polish · ~1–3 days

The v1 tables (above) now also have **row/column structure edits**, the **context
menu**, **column resize** (drag the dividers on the ruler; widths persist as
`cell.width`), **↑/↓ cell navigation** (Tab/Shift-Tab already worked), **Select
Table**, and **cell merging** (spans persist as `cell.rowSpan`/`columnSpan`).
Remaining:

- **Page-boundary splitting** — multi-row tables already flow to the next page via
  TextKit row-breaking + overflow pagination; needs on-device QA to confirm rows
  don't clip, and a single row taller than a page still can't split.
- **Structure edits vs. merges** — insert/delete row & column currently rebuild a
  full grid, which resets any merged cells; making them span-aware is future work.

### List interchange and polish · ~2–5 days

Lists are fully represented in `.luce`, Markdown, PDF, and print. Remaining work is
caused by their deliberate custom drawing: RTF/DOCX do not receive marker semantics,
VoiceOver cannot yet describe markers, fixed 24-point gutters can crowd large
decimal/Roman labels, direct pre-list indents are displaced, and long-list drawing
repeats prefix scans. Materialize interchange semantics, expose markers to
accessibility, measure gutters, preserve displaced indents, and cache numbering by
storage generation.

### Editable header/footer click-zones · ~3–5 days (almost all UI)

Headers/footers are edited in a dialog today. The richer experience is to click
into the margin band and type in place, with three tab zones and a field-token
insertion UI. This is hit-testing in the margins plus an inline editor overlay; **no
model change** is needed — the `header`/`footer` zones already exist.

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
- **Richer document settings.** Page size, margins, fold marks, ruler units, and
  update preferences ship; future settings should be driven by a concrete
  letter-writing need rather than a generic inspector.
- **Import.** Open plain text/Markdown first, then consider RTF/DOCX with an explicit
  fidelity report.
- **Document-wide commands and cross-page selection.** Add storage-relative command
  surrogates before attempting unified drag/Shift selection across page text views.

## Architectural through-line

None of the above requires abandoning the TextKit-1 + per-page-container
architecture. The shared `pageNumber(forCharacterAt:)` primitive, the
named-paragraph-style system, and the page-anchored object model are the
foundations each new feature builds on — which is exactly why the file format and
the layout pipeline have stayed stable as features accrue.
