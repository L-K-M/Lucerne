# Design notes — page numbers, table of contents, tables

Exploratory design for three related features, with effort estimates and how each
fits Lucerne's architecture (TextKit 1, one layout manager + one container per page,
named paragraph styles, page-anchored objects). Estimates are rough developer-days.

## Shared primitive: page-number-for-character

Almost everything here needs "which page is character *i* on?". We already have the
machinery: the layout manager maps a glyph to its container, and containers map 1:1
to pages. So a small helper on `EditorController` underpins all of it:

```swift
func pageNumber(forCharacterAt index: Int) -> Int   // 1-based
// glyphIndexForCharacter → textContainer(forGlyphAt:) → pages.firstIndex(of: container)
```

Build this first; page numbers, the ToC's page column, and "jump to heading" all use it.

## 1. Page numbers (headers & footers)

Headers/footers are **repeated margin content**, not part of the flowing body — so
they don't belong in the shared `NSTextStorage`. Draw them per page in the top/bottom
margin of each `PageContainerView`.

- **Model:** add an optional `header`/`footer` to `page`, each with up to three
  zones (left/center/right) — the classic word-processor layout — where a zone is a
  short string that may contain field tokens: page number, page count, date, title.
  This is additive to the file format (bump nothing; new optional keys).
- **Rendering:** each page view draws its footer, substituting the page number
  (its index + 1) and total (`pages.count`). No interaction with body reflow, so it's
  cheap and stable.
- **Margins:** reserve a band inside the existing margin for the header/footer (or
  simply draw within the current margin). The body container size is unchanged.

**Effort**
- Auto footer only ("Page N" / "N of M"), set via a small dialog, non-interactive:
  **~0.5–1 day.** Recommended first step — high value, low risk.
- Fully editable headers/footers (click into the margin to edit, three tab zones,
  field insertion UI): **~3–5 days**, almost entirely UI.

## 2. Table of contents

We already have named heading styles (`heading1/2/3`) with markdown hints, which is
exactly the structure a ToC needs. Two flavors, independent:

**(a) Heading navigator (sidebar) — for navigation, not print.**
A source-list outline of the document's headings; click to scroll to one. Built by
scanning body paragraphs for heading style roles; uses the shared page-number helper
only to optionally show page numbers. No pagination coupling, no document mutation.
**Effort: ~1–2 days.** Recommended — cheap, very useful, and it validates the
heading-scanning code the printed ToC reuses.

**(b) Printed ToC (a generated block with page numbers).**
A generated region (usually page 1) listing each heading and its page, with a dotted
tab leader to a right/decimal tab. The wrinkle is that it's *generated* and goes
**stale** as the document changes, and inserting it shifts later content (which
changes the very page numbers it lists — converges in 1–2 passes, like our page-break
bands).

- Represent it as a **generated block**: a contiguer run of paragraphs tagged with a
  custom attribute (e.g. `.lucerneGeneratedToC`) so it can be located and replaced
  wholesale on "Update Table of Contents" (and before print/PDF/save).
- Each entry is a paragraph with a right tab + leader; page number from the shared
  helper. Regeneration is: remove the old tagged block, recompute, re-insert,
  re-paginate.
- It does **not** round-trip as structure — on save it's just paragraphs (and the
  tag, which we can persist like `lucerneStyleRole`). Re-running "Update" rebuilds it.

**Effort: ~2–4 days** (generated-block management + leader/tab formatting + refresh
triggers). Do after the navigator and page numbers.

## 3. Tables (future)

Good news: **TextKit 1 supports tables natively** via `NSTextTable` /
`NSTextTableBlock` attached to paragraph styles. Cells are ranges of the same text
storage, and the layout manager flows a table within the container and **paginates it
across pages** for us. So tables do *not* require a new layout engine — they fit the
current model.

- **Model:** tables are the first body content that isn't a flat paragraph list, so
  the file format needs a table block type (rows/cells, each cell a paragraph list).
  This is the largest model change of the three.
- **Editing:** cell navigation (Tab/arrows), insert/delete row/column, resize columns
  (the ruler could grow column markers later) — this is the bulk of the work.
- **Interaction with the above:** the page-number helper still works (cells have
  character indices); the ToC scanner ignores table content; headers/footers are
  unaffected.

**Effort: ~3–6 days** for basic tables (create, edit cells, add/remove rows/cols),
more for column resize and irregular spans.

## Suggested order

1. `pageNumber(forCharacterAt:)` helper (tiny, unblocks everything).
2. Auto page-number footer (cheap, visible win).
3. Heading navigator sidebar (cheap, high value, reuses heading scanning).
4. Printed ToC with page numbers (builds on 1 + 3).
5. Editable headers/footers (UI-heavy) and tables (model-heavy) as larger follow-ups.

Items 1–3 are each ~1–2 days and largely independent; 4 and 5 are the bigger lifts.
None require abandoning the TextKit-1 + per-page-container architecture.
