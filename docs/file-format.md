# The `.luce` file format

> **Looking for the normative spec?** This page is a friendly overview. The
> complete, precise specification an independent implementer should follow —
> RFC-2119 wording, full field tables, the exact `content.md` derivation, a JSON
> Schema, and conformance requirements — is in
> [`luce-format-spec.md`](luce-format-spec.md). Where the two differ, the spec wins.

A `.luce` document **is a ZIP archive** whose UTI conforms to
`public.zip-archive` (D4). The recovery story is therefore literally: *rename it to
`.zip` and unzip*. This document describes the package layout and the canonical
`document.json` schema (plan §7).

## Package layout (D3)

```
my-letter.luce          (a ZIP archive)
├── document.json        canonical, lossless model — THE source of truth
├── images/              placed images as their original files
│   ├── lake.png
│   └── …
├── content.md           derived Markdown copy of the text (write-only escape hatch)
└── history/             optional dated Markdown backups (thinned with age) for recovery
    └── 20260609T120000Z.md
```

Rules that keep this honest:

1. **`document.json` is authority.** The app reads only this for structure and
   formatting. `images/` holds the bytes it references.
2. **`content.md` is write-only / derived.** Regenerated from `document.json` on
   every save and *never read back*. It preserves the words and the pictures (as
   `![](images/…)` links) so a future human can recover content even without this
   app — losing only precise placement and fine formatting. See
   `Sources/LucerneKit/Model/MarkdownExporter.swift`.
3. **Images are stored uncompressed** inside the ZIP. They're already compressed
   formats (PNG/JPEG), so this costs nothing and keeps the writer simple (see
   `MiniZip`).

## `document.json` schema (v1)

Units are **points (1/72")** everywhere. The coordinate origin is the **page
top-left, y increasing downward**.

```jsonc
{
  "format": "lucerne-document",
  "formatVersion": 1,

  // D1 — one fixed page size for the whole document
  "page": {
    "size": "A4",                 // "A4" | "Letter" | "custom" — an advisory label only
    "width": 595.28,              // points; always authoritative (readers use this, not size)
    "height": 841.89,             // points; always authoritative
    "margins": { "top": 72, "left": 72, "bottom": 72, "right": 72 }
  },

  // D3 — named paragraph-style roles → visual attributes + a markdown export hint
  "styles": {
    "body":     { "name": "Body",      "font": "Helvetica", "size": 12, "lineSpacing": 1.2, "spaceAfter": 6, "markdown": "p" },
    "heading1": { "name": "Heading 1", "font": "Helvetica", "size": 24, "bold": true, "markdown": "h1" }
    // … heading2, listItem, quote
  },

  // the flowing main text frame, as an ordered list of paragraphs
  "body": [
    { "id": "p1", "style": "heading1", "runs": [ { "text": "A Letter from the Lake" } ] },
    {
      "id": "p2", "style": "body",
      "align": "left",
      "indent": { "left": 0, "right": 0, "firstLine": 18 },
      "tabStops": [ { "pos": 240, "type": "left" } ],
      "runs": [
        { "text": "Thanks for the " },
        { "text": "wonderful", "italic": true },
        { "text": " afternoon." }
      ]
    },
    {
      "id": "p3", "style": "body",
      "list": { "list": "list1", "ordered": true, "marker": "decimal", "level": 0 },
      "runs": [ { "text": "First numbered item" } ]
    }
  ],

  // D2 + free placement — floating objects that punch holes in the text frame
  "objects": [
    {
      "id": "img1", "type": "image", "src": "images/lake.png",
      "anchor": "page",            // "page" = free placement; "paragraph" = moves with text
      "page": 0,                   // zero-based; required when anchor == "page"
      "frame": { "x": 320, "y": 180, "width": 200, "height": 140 },  // page-relative
      "wrap": "rectangular",       // "none" | "rectangular" | "irregular"
      "standoff": 12,              // gutter between image box and text, points
      "z": 1                       // stacking order
      // when anchor == "paragraph": replace page/frame with
      //   "anchorParagraph": "p2", "offset": { "x": 0, "y": 0 }
    }
  ]
}
```

(`document.json` on disk is plain JSON — the `//` comments above are for the reader.)

### Field notes

- **Runs inherit from their paragraph's style**; only *overrides* are stored on a
  run (e.g. `"italic": true`). Keeps the file small and legible.
- **`markdown` per style** is the export hint that makes `content.md` faithful
  rather than guessed — the exporter reads it, never infers from size/weight.
- **Styles are user-extensible.** Role keys are opaque identifiers (`name` is
  the display label), and a document may define any number of styles beyond the
  defaults. Optional style members `underline`, `rightIndent`, and `order` (a
  presentational list-ordering hint) are additive — see the spec, §5.1.
- **Two anchor modes share one object list.** `"page"` objects carry `page` + a
  page-relative `frame` (free placement). `"paragraph"` objects carry
  `anchorParagraph` + `offset` and move with the text.
- **Defaults on read.** `type` ("image"), `anchor` ("page"), `wrap`
  ("rectangular"), `standoff` (12), and `z` (0) are filled in if absent, so
  hand-edited or older files still load.
- **Optional `header` / `footer`.** Two top-level objects with three string zones
  (`left`/`center`/`right`) drawn in the page margins; each zone may contain the
  tokens `{page}`, `{pages}`, `{date}`, `{title}`. Additive and presentational —
  not represented in `content.md`. Full rules in the spec, §3.2.
- **Optional `pageNumberStart`.** A positive integer: the 1-based page where
  `{page}` becomes 1 (earlier pages are unnumbered, e.g. `3` to skip a title and a
  contents page). Absent means every page is numbered from 1.
- **Generated regions carry no special structure.** A printed table of contents,
  for example, is just ordinary paragraphs (the app tags them with a `toc` style
  role); the format has no dedicated "ToC" or "field" block. An unknown style role
  falls back to `body` on read.
- **Tables keep the body flat too.** A table is a run of consecutive paragraphs that
  each carry an optional `cell` object (`table` id + `row`/`column` + optional spans
  and a column `width`); the column count is derived from the cells. A tool that
  ignores `cell` still gets every cell's text as a plain paragraph. Full rules in the
  spec, §6.7.

### Lists

Lists also keep `body` flat. A list item is an ordinary paragraph with an optional
`list` object; list membership is independent of the paragraph's named `style`.
The marker shown beside the paragraph is derived and is never inserted into `runs`.

| `Paragraph.list` member | Presence | Meaning/default |
|---|---|---|
| `list` | required | Non-empty opaque id shared by items in one list. |
| `ordered` | required | `true` for numbering; `false` for bullets. |
| `marker` | required | Ordered: `decimal`, `lower-alpha`, `upper-alpha`, `lower-roman`, or `upper-roman`. Unordered: `disc`, `circle`, `square`, or `dash`. |
| `level` | optional | Zero-based nesting depth from `0` through `8`; default `0`. |
| `start` | optional | Positive starting number for the first ordered item whose counter begins at that level; default `1`. Ignored for unordered items. |

A list is the **maximal contiguous run** of body paragraphs carrying the same
`list.list` id. A paragraph without list metadata or with a different id ends the
run; reusing the id later starts numbering again. Counters are tracked per nesting
level. Entering a new level starts its counter, returning to a shallower level
resumes that level's counter, and leaving a level discards deeper counters. An
unordered item does not increment the ordered counter at its level, so numbering can
continue across an intervening bullet in the same run. Individual items may change
ordered state, marker, and level while retaining the list id.

The unordered markers render as `disc` = `•`, `circle` = `◦`, `square` = `▪`, and
`dash` = `–`. Ordered markers render the corresponding decimal, bijective alphabetic,
or Roman label followed by a period.

In `content.md`, each same-id run becomes one tight Markdown list with no blank lines
between items. Nesting uses four spaces per level. Bullets normalize to `-`; ordered
items use the resolved decimal number even when the on-page marker is alpha or Roman,
because portable Markdown has no corresponding marker syntax. Different adjacent
list ids are separated by a blank line. A legacy paragraph whose style has
`markdown: "li"` but no `list` metadata still exports as an ordinary `- ` block.
Table semantics take precedence if a paragraph carries both `cell` and `list`.

## Versioning

`formatVersion` starts at `1`. Bump it for changes that aren't backward compatible
and add a migration in the reader. Additive, optional fields don't require a bump.

**Compatibility caveat:** Lucerne v0.5 began writing the optional paragraph `list`
member while retaining `formatVersion: 1`. Pre-v0.5 v1 readers can open such files,
but writers that ignore and do not preserve unknown members may discard list
metadata when they save. Do not round-trip a list-bearing v1 file through an older
writer if list structure must survive. The project must decide versioning/capability
signaling and unknown-field preservation before its next semantic format extension;
that decision is tracked in [`ANALYSIS.md`](../ANALYSIS.md).

## What this format deliberately is *not*

- **Not RTF/DOCX as canonical.** Apple's text system flattens floating frames to
  inline attachments on round-trip, destroying free placement (plan §4). RTF/DOCX
  is offered only as an explicitly lossy *export*.
- **Not Markdown as canonical.** Markdown has no notion of page coordinates, wrap,
  standoff, pages, or presentational formatting. It's the *derived* escape hatch,
  never the source of truth.
