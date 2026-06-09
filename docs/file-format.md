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
    "size": "A4",                 // "A4" | "Letter" | "custom"
    "width": 595.28,              // points; authoritative when size == "custom"
    "height": 841.89,
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
- **Generated regions carry no special structure.** A printed table of contents,
  for example, is just ordinary paragraphs (the app tags them with a `toc` style
  role); the format has no dedicated "ToC" or "field" block. An unknown style role
  falls back to `body` on read.

## Versioning

`formatVersion` starts at `1`. Bump it for changes that aren't backward compatible
and add a migration in the reader. Additive, optional fields don't require a bump.

## What this format deliberately is *not*

- **Not RTF/DOCX as canonical.** Apple's text system flattens floating frames to
  inline attachments on round-trip, destroying free placement (plan §4). RTF/DOCX
  is offered only as an explicitly lossy *export*.
- **Not Markdown as canonical.** Markdown has no notion of page coordinates, wrap,
  standoff, pages, or presentational formatting. It's the *derived* escape hatch,
  never the source of truth.
