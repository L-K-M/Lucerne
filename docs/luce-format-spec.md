# The Lucerne `.luce` Document Format — Specification

- **Format identifier:** `lucerne-document`
- **`formatVersion`:** `1`
- **File extension:** `.luce`
- **UTI:** `ch.lkmc.lucerne.document` (conforms to `public.zip-archive`)
- **Status:** stable for version 1. This document is normative.

This specification defines the `.luce` document format precisely enough for an
independent party to read and write compatible files without reference to the
Lucerne source code. A friendlier overview is in
[`file-format.md`](file-format.md); where the two differ, **this document wins.**

## 1. Conventions

The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHOULD**, **SHOULD NOT**,
**MAY**, and **OPTIONAL** are to be interpreted as described in RFC 2119.

- A **reader** is software that opens `.luce` files. A **writer** produces them.
- "Absent" means a JSON object member is not present (or is JSON `null`).
- "Points" are typographic points: 1 pt = 1/72 inch.
- JSON terminology (object, array, number, string, boolean, null) is per RFC 8259.

## 2. The container

A `.luce` file **MUST** be a ZIP archive (PKWARE APPNOTE, the same format as
`.zip`). Because of this, renaming a `.luce` to `.zip` and extracting it **MUST**
yield the entries below.

### 2.1 Entry names

- Entry names **MUST** use `/` as the path separator and **MUST** be UTF-8.
- The following entries are defined at the archive root:

  | Entry | Presence | Meaning |
  |---|---|---|
  | `document.json` | **REQUIRED** | The canonical document model (§3–§7). The sole source of truth. |
  | `images/…` | optional | Image payload files referenced by placed objects (§7). |
  | `content.md` | recommended | A derived, human-readable Markdown rendering of the text (§8). Non-authoritative. |
  | `history/…` | optional | Dated, non-authoritative Markdown backups (§2.3) for recovery. |

- A reader **MUST** locate `document.json` by its exact name at the archive root.
- A writer **MUST** write exactly one `document.json` at the archive root.
- Entries other than those above (e.g. a future `preview.pdf`, `meta.json`)
  **MAY** be present; readers **MUST** ignore entries they do not understand and
  **MUST NOT** fail because of them.

### 2.2 Compression

- A writer **MAY** store entries uncompressed (STORED, method 0) or compressed
  with DEFLATE (method 8). The reference writer uses STORED, because image
  payloads are already compressed and the text payloads are small.
- A reader **MUST** support STORED entries and **SHOULD** support DEFLATE
  entries. Other compression methods are out of scope; a reader **MAY** reject
  them.
- ZIP64 extensions are not required for conformant version-1 files and **MAY** be
  unsupported by readers. Encryption **MUST NOT** be used.

### 2.3 `history/` — dated Markdown backups (optional)

A writer **MAY** keep a trail of past `content.md` renderings under `history/`, so a
person who accidentally deletes text and saves can still recover earlier prose by
unzipping the file. This is purely additive and does not change `formatVersion`.

- Each entry is named `history/<UTC-timestamp>.md`, where the timestamp is
  `yyyyMMdd'T'HHmmss'Z'` (e.g. `history/20260609T120000Z.md`).
- The bytes are a Markdown rendering identical in form to `content.md` (§8).
- Like `content.md`, history entries are **non-authoritative**: readers **MUST NOT**
  treat them as the source of truth.
- Retention is implementation-defined. The reference writer adds a snapshot on each
  save (skipping duplicates) and thins them with age — keeping the most recent dozen,
  then roughly hourly for a day, daily for a month, weekly for a year, and monthly
  beyond, capped to a maximum — so the trail stays small.

## 3. `document.json`

`document.json` **MUST** be a single JSON object encoded in UTF-8 (no BOM). It
**MUST NOT** contain comments (any `//` in this spec is explanatory only).

- Member order is **not** significant; readers **MUST NOT** depend on it.
- The reference writer emits sorted keys, pretty-printing, and unescaped `/` for
  diff-friendliness, but none of that is required of conformant files.
- Readers **MUST** ignore unknown members at every level (forward compatibility).

### 3.1 Top-level members

| Member | Type | Presence | Notes |
|---|---|---|---|
| `format` | string | REQUIRED | **MUST** be `"lucerne-document"`. |
| `formatVersion` | integer | REQUIRED | See §9. Version 1 files use `1`. |
| `page` | object | REQUIRED | Page geometry (§4). |
| `styles` | object | REQUIRED | Map of style role → style definition (§5). |
| `body` | array | REQUIRED | Ordered list of paragraphs (§6). MAY be empty. |
| `objects` | array | REQUIRED | List of placed objects (§7). MAY be empty. |
| `header` | object | optional | Running header (§3.2). |
| `footer` | object | optional | Running footer (§3.2). |
| `pageNumberStart` | integer | optional | 1-based page where numbering begins (§3.2). |

A reader **MUST** reject a file whose `format` is not `"lucerne-document"`.

### 3.2 Header and footer (page furniture)

`header` and `footer`, when present, are objects with three string zones —
`left`, `center`, `right` (each optional, default `""`) — drawn in the top/bottom
page margins of every page. A zone may contain these tokens, substituted at render
time:

| Token | Replaced with |
|---|---|
| `{page}` | the page number (1-based) |
| `{pages}` | the total page count |
| `{date}` | the current date (reader-formatted) |
| `{title}` | the document's display name |

Example: a `footer` of `{ "center": "Page {page} of {pages}" }`. These are
**presentational** and additive — they are not represented in `content.md`, and
adding them does not change `formatVersion`.

`pageNumberStart`, when present, is a positive integer: the 1-based physical page
on which the number substituted for `{page}` becomes `1`. Pages before it are
unnumbered, and `{pages}` counts only the numbered pages. For example,
`pageNumberStart: 3` makes physical page 3 show `1` (to skip a title page and a
contents page). Absent means every page is numbered starting at `1`. On an
unnumbered page a reader **SHOULD** suppress a zone that references a page-number
token rather than render a partial string. This is presentational and additive.

## 4. Coordinates, units, and page geometry

### 4.1 Coordinate system

- All distances are in **points** unless stated otherwise.
- The origin is the **page top-left**, with **x increasing rightward and y
  increasing downward**.
- A placed object's `frame` is **page-relative**: measured from the page's
  top-left corner, including the margin area (an object MAY sit in the margins).
- Paragraph indents and tab-stop positions are measured from the **left margin**
  (i.e. the left edge of the text area), not from the page edge.

### 4.2 `page` object (decision D1: one fixed size for the whole document)

| Member | Type | Presence | Notes |
|---|---|---|---|
| `size` | string | REQUIRED | Advisory preset name: `"A4"`, `"Letter"`, or `"custom"`. |
| `width` | number | REQUIRED | Page width in points. **Authoritative.** |
| `height` | number | REQUIRED | Page height in points. **Authoritative.** |
| `margins` | object | REQUIRED | `{ "top", "left", "bottom", "right" }`, all numbers (points). |

- `width`/`height` are authoritative; `size` is an advisory label for UI. A reader
  **MUST** use `width`/`height` for layout and **MUST NOT** infer dimensions from
  `size`. Reference dimensions: A4 = `595.28 × 841.89`, Letter = `612 × 792`.
- The page size applies to **every** page of the document (D1). There is no
  per-page size.
- The **text area** (text container) has size
  `(width − margins.left − margins.right) × (height − margins.top − margins.bottom)`
  and is identical on every page.

## 5. `styles` — named paragraph-style roles (decision D3)

`styles` **MUST** be a JSON object mapping a **style role key** (string) to a
**style definition** object. The role key (e.g. `"body"`, `"heading1"`) is what a
paragraph references via its `style` member (§6).

A writer **SHOULD** define a `"body"` role and **MUST** define every role
referenced by any paragraph's `style`.

### 5.1 Style definition object

| Member | Type | Presence | Default | Notes |
|---|---|---|---|---|
| `name` | string | REQUIRED | — | Human-readable name shown in UI (e.g. "Heading 1"). |
| `markdown` | string | REQUIRED | — | Markdown export hint (§8). One of `"p"`, `"h1"`, `"h2"`, `"h3"`, `"li"`, `"blockquote"`. |
| `font` | string | optional | `"Helvetica"` | Font family (or PostScript) name. |
| `size` | number | optional | `12` | Font size in points. |
| `bold` | boolean | optional | `false` | |
| `italic` | boolean | optional | `false` | |
| `lineSpacing` | number | optional | single | Line-height **multiple** (e.g. `1.2` = 120%). |
| `spaceBefore` | number | optional | `0` | Space above the paragraph, points. |
| `spaceAfter` | number | optional | `0` | Space below the paragraph, points. |
| `leftIndent` | number | optional | `0` | Left indent of the paragraph, points. |
| `firstLineIndent` | number | optional | `0` | First-line indent **relative to** `leftIndent`, points. |
| `alignment` | string | optional | natural | `"left"`, `"center"`, `"right"`, or `"justified"`. |
| `color` | string | optional | `"#000000"` | Text color (§6.3). |

- A reader encountering a `markdown` value it does not recognize **MUST** treat it
  as `"p"` for export purposes.
- A reader encountering an unknown style role (a paragraph references a key not in
  `styles`) **MUST** fall back to the `"body"` role, and if that is also absent,
  to a hard default of Helvetica 12, black, single-spaced, left/natural aligned.

## 6. `body` — paragraphs and runs

`body` is an ordered array of **paragraph** objects. The document's text is the
concatenation of paragraphs in order, separated by paragraph breaks.

> *Informative.* `body` is a flat list. Even **tables** keep it flat: a table is a
> run of consecutive paragraphs that each carry a `cell` object (§6.7) rather than a
> nested block type. Generated regions such as a printed table of contents are also
> just **ordinary paragraphs** — a writer MAY group them under a dedicated style role
> (the reference app uses `"toc"`), but they carry no special semantics, and a reader
> treats an unrecognized role per §5 (fall back to `body`). Lists remain out of scope
> for version 1 (see the project roadmap).

### 6.1 Paragraph object

| Member | Type | Presence | Notes |
|---|---|---|---|
| `id` | string | REQUIRED | Stable, unique within the document (§6.4). |
| `style` | string | REQUIRED | A style role key into `styles` (§5). |
| `runs` | array | REQUIRED | Ordered text runs (§6.2). An empty paragraph is `[{ "text": "" }]`; readers **MUST** also accept `[]`. |
| `align` | string | optional | Per-paragraph override of the style's `alignment`. |
| `indent` | object | optional | `{ "left"?, "right"?, "firstLine"? }`, each a number (points), each optional. Overrides the style. |
| `tabStops` | array | optional | Tab stops (§6.5). When present, replaces the default tab grid. |
| `lineSpacing` | number | optional | Override of the style's `lineSpacing` (line-height multiple). |
| `spaceBefore` | number | optional | Override of the style's `spaceBefore` (points). |
| `spaceAfter` | number | optional | Override of the style's `spaceAfter` (points). |
| `pageBreakBefore` | boolean | optional | When `true`, this paragraph starts on a new page (a forced page break precedes it). Default `false`. |
| `cell` | object | optional | Marks this paragraph as a table cell (§6.7). |

`indent.firstLine` is relative to the effective left indent; the first line begins
at `leftIndent + firstLine` from the left margin. A negative `firstLine` yields a
hanging indent. `indent.right` is measured inward from the right margin.

### 6.2 Run object

A **run** is a maximal span of text sharing the same inline formatting.

| Member | Type | Presence | Notes |
|---|---|---|---|
| `text` | string | REQUIRED | The run's characters. MAY be empty (only for an empty paragraph). |
| `bold` | boolean | optional | Overrides the style's `bold`. |
| `italic` | boolean | optional | Overrides the style's `italic`. |
| `underline` | boolean | optional | Underline. Default `false`. |
| `font` | string | optional | Overrides the style's `font`. |
| `size` | number | optional | Overrides the style's `size` (points). |
| `color` | string | optional | Overrides the style's `color` (§6.3). |

### 6.3 Colors

A color string **MUST** be one of: `"#RGB"`, `"#RRGGBB"`, or `"#RRGGBBAA"`
(hexadecimal, case-insensitive, sRGB). Writers **SHOULD** emit `"#RRGGBB"`.
Readers **MUST** accept all three forms; the alpha channel **MAY** be ignored by
readers that render opaque text.

### 6.4 Identifiers

`id` values (on paragraphs and objects) **MUST** be non-empty strings, **MUST** be
unique within the document, and **SHOULD** be stable across edits (they are used
for paragraph-anchored objects, §7, and for tooling). Their internal structure is
unspecified; readers **MUST** treat them as opaque.

### 6.5 Tab stops

`tabStops` is an array of objects:

| Member | Type | Presence | Notes |
|---|---|---|---|
| `pos` | number | REQUIRED | Position in points from the left margin. |
| `type` | string | optional | `"left"` (default), `"center"`, `"right"`, or `"decimal"`. |

A `"decimal"` tab aligns the text on the locale's decimal separator.

### 6.6 Inheritance and attribute resolution

A run's or paragraph's *effective* value for an attribute is resolved in order,
taking the first present:

1. **Run-level** field (`bold`, `italic`, `underline`, `font`, `size`, `color`).
2. **Paragraph-level** field where one exists (`align`, `indent.*`, `tabStops`,
   `lineSpacing`, `spaceBefore`, `spaceAfter`).
3. The paragraph's **style role** definition (§5).
4. The **hard default** (§5.1 / §5 fallback).

`underline` has no style-level field; absent means not underlined.

### 6.7 Table cells

A paragraph **MAY** be a **table cell** by carrying a `cell` object. Cells that share
a `table` id form one table; a reader lays them out on a grid by `(row, column)` and
their spans. The body stays a flat ordered list: a table is a run of consecutive cell
paragraphs, bounded above and below by ordinary (non-cell) paragraphs. A cell's text
and inline/paragraph formatting are expressed exactly as for any paragraph (§6.1–§6.6).

| Member | Type | Presence | Default | Notes |
|---|---|---|---|---|
| `table` | string | REQUIRED | — | Groups the cells belonging to one table. |
| `row` | integer | REQUIRED | — | 0-based row of the cell. |
| `column` | integer | REQUIRED | — | 0-based column of the cell. |
| `rowSpan` | integer | optional | `1` | Number of rows the cell spans. |
| `columnSpan` | integer | optional | `1` | Number of columns the cell spans. |
| `width` | number | optional | equal | The cell's column width as a percent of the table; cells in a column share it. Absent ⇒ equal columns. |

The table's **column count is derived** as the maximum `column + columnSpan` over its
cells; it is not stored separately. Cells **SHOULD** appear in the body in row-major
order. A reader that does not implement tables **MUST** still render each cell
paragraph's text as an ordinary paragraph (losing only the grid layout), per the
"ignore what you don't understand" rule (§3).

## 7. `objects` — placed objects (decision D2 + free placement)

`objects` is an array of **placed object** objects. Version 1 defines the image
type; readers **MUST** ignore objects whose `type` they do not understand.

| Member | Type | Presence | Default | Notes |
|---|---|---|---|---|
| `id` | string | REQUIRED | — | Unique within the document (§6.4). |
| `type` | string | optional | `"image"` | Object kind. |
| `src` | string | optional | — | Archive-relative path of the payload, e.g. `"images/lake.png"`. REQUIRED for images. |
| `anchor` | string | optional | `"page"` | `"page"` (free placement) or `"paragraph"` (moves with text). |
| `page` | integer | conditional | — | Zero-based page index. **REQUIRED when `anchor == "page"`.** |
| `frame` | object | conditional | — | `{ "x", "y", "width", "height" }` (points, page-relative). **REQUIRED when `anchor == "page"`.** |
| `anchorParagraph` | string | conditional | — | A paragraph `id`. **REQUIRED when `anchor == "paragraph"`.** |
| `offset` | object | optional | `{0,0}` | `{ "x", "y" }` offset from the anchor paragraph, points. Used when `anchor == "paragraph"`. |
| `wrap` | string | optional | `"rectangular"` | `"none"`, `"rectangular"`, or `"irregular"`. |
| `standoff` | number | optional | `12` | Gutter between the object box and wrapped text, points. |
| `z` | integer | optional | `0` | Stacking order; higher draws in front. |

### 7.1 Image payloads

- `src` **MUST** name an entry inside the archive, conventionally under `images/`.
- The bytes are the image's original encoded form (e.g. PNG, JPEG). Readers
  **SHOULD** support common raster formats; if a payload is missing or
  undecodable, a reader **SHOULD** render a placeholder and **MUST NOT** fail to
  open the document.
- A writer **SHOULD** include exactly the payloads referenced by `objects` and
  **MAY** omit unreferenced files. A `src` may be present with no matching entry
  (a dangling reference); this is valid and handled as a missing payload.

### 7.2 Text wrap and standoff

For a page-anchored object with `wrap != "none"`, body text **MUST** avoid the
object's box expanded outward on all sides by `standoff`. `"rectangular"` wraps the
bounding box; `"irregular"` is reserved for an outline-based wrap and, until
defined, readers **MAY** treat it as `"rectangular"`. `"none"` means the object
overlays the text without affecting layout.

How a reader handles a side gap too narrow to hold text, or an object overhanging a
page edge, is **implementation-defined** (the reference reader suppresses unusably
narrow wrap columns and clips overhang to the page).

## 8. `content.md` — derived Markdown (the escape hatch)

`content.md`, when present, is a **derived, non-authoritative** rendering of the
document's text. A reader **MUST NOT** read it as a source of truth; only
`document.json` is authoritative. A writer **SHOULD** regenerate it on every save.

This section is **informative** — `content.md` is a recovery convenience, and a
writer MAY format it differently — but the following describes the reference
derivation so tools can produce comparable output.

1. Each body paragraph becomes one Markdown block; blocks are separated by one
   blank line; the file ends with a trailing newline.
2. The block prefix is chosen by the paragraph's style `markdown` hint:
   `h1` → `# `, `h2` → `## `, `h3` → `### `, `li` → `- `, `blockquote` → `> `,
   and `p` (or anything else) → no prefix.
3. Within a paragraph, each run's text is emitted with emphasis markers from its
   *effective* bold/italic: bold → `**…**`, italic → `*…*`, both → `***…***`.
   Surrounding whitespace is moved outside the markers (so `"word "` italic emits
   `*word* `, not `*word *`); a run whose trimmed text is empty is emitted
   verbatim.
4. The characters `\` `*` `_` `` ` `` `[` `]` are backslash-escaped in run text.
5. Underline, color, font, exact size, and page breaks (`pageBreakBefore`) are
   **not** represented (by design — that presentational fidelity lives in
   `document.json` and any PDF rendering).
6. After all paragraphs, each image object with a `src` is appended as
   `![alt](src)`, ordered by `(page ascending, then z ascending)`; page-anchored
   objects with no page sort last. `alt` is the `src` filename without its
   extension, or the object `id` if no usable stem exists.

## 9. Versioning and migration

- `formatVersion` is a single integer. Version 1 is defined here.
- Adding new **optional** members, new style `markdown` hints, new object `type`s,
  or new entries to the archive is backward compatible and **does not** bump
  `formatVersion`. Readers ignore what they don't understand (§3, §7).
- A change that would cause a version-1 reader to misinterpret an existing member
  **MUST** bump `formatVersion`, and writers making such a change **MUST** emit the
  higher number.
- A reader **MUST** examine `formatVersion`. If it is greater than the highest
  version the reader implements, the reader **SHOULD** either refuse to open the
  file or open it best-effort with a clear warning; it **MUST NOT** silently
  discard data it cannot represent on save.

## 10. Conformance

- A **conformant reader** MUST: open the ZIP container (§2), parse `document.json`
  (§3) including the inheritance/default rules (§5–§7), honor authoritative page
  dimensions (§4.2), support STORED entries (§2.2), tolerate unknown
  members/entries/object types, and never treat `content.md` as authoritative.
- A **conformant writer** MUST: produce a valid ZIP containing a root
  `document.json` that satisfies the schema in Appendix A, include the image
  payloads it references, and set `format`/`formatVersion` correctly. It SHOULD
  also write a `content.md` per §8 and define a `"body"` style.

---

## Appendix A — JSON Schema for `document.json`

A JSON Schema (draft 2020-12) capturing §3–§7. Unknown members are permitted for
forward compatibility, so this validates structure, not the absence of extensions.
The `if/then` rules below enforce the `page`/`frame` and `anchorParagraph`
requirements only when `anchor` is stated explicitly; when `anchor` is omitted it
defaults to `"page"` and §7's requirement of `page`+`frame` still applies (the
prose in §7 is authoritative over the schema here).

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://lkmc.ch/schemas/luce-document-v1.json",
  "title": "Lucerne document (v1)",
  "type": "object",
  "required": ["format", "formatVersion", "page", "styles", "body", "objects"],
  "properties": {
    "format": { "const": "lucerne-document" },
    "formatVersion": { "type": "integer", "minimum": 1 },
    "page": { "$ref": "#/$defs/page" },
    "styles": {
      "type": "object",
      "additionalProperties": { "$ref": "#/$defs/style" }
    },
    "body": { "type": "array", "items": { "$ref": "#/$defs/paragraph" } },
    "objects": { "type": "array", "items": { "$ref": "#/$defs/object" } },
    "header": { "$ref": "#/$defs/furniture" },
    "footer": { "$ref": "#/$defs/furniture" },
    "pageNumberStart": { "type": "integer", "minimum": 1 }
  },
  "$defs": {
    "furniture": {
      "type": "object",
      "properties": {
        "left": { "type": "string" },
        "center": { "type": "string" },
        "right": { "type": "string" }
      }
    },
    "page": {
      "type": "object",
      "required": ["size", "width", "height", "margins"],
      "properties": {
        "size": { "type": "string" },
        "width": { "type": "number", "exclusiveMinimum": 0 },
        "height": { "type": "number", "exclusiveMinimum": 0 },
        "margins": { "$ref": "#/$defs/edgeInsets" }
      }
    },
    "edgeInsets": {
      "type": "object",
      "required": ["top", "left", "bottom", "right"],
      "properties": {
        "top": { "type": "number" }, "left": { "type": "number" },
        "bottom": { "type": "number" }, "right": { "type": "number" }
      }
    },
    "style": {
      "type": "object",
      "required": ["name", "markdown"],
      "properties": {
        "name": { "type": "string" },
        "markdown": { "type": "string" },
        "font": { "type": "string" },
        "size": { "type": "number", "exclusiveMinimum": 0 },
        "bold": { "type": "boolean" },
        "italic": { "type": "boolean" },
        "lineSpacing": { "type": "number", "exclusiveMinimum": 0 },
        "spaceBefore": { "type": "number" },
        "spaceAfter": { "type": "number" },
        "leftIndent": { "type": "number" },
        "firstLineIndent": { "type": "number" },
        "alignment": { "enum": ["left", "center", "right", "justified"] },
        "color": { "$ref": "#/$defs/color" }
      }
    },
    "paragraph": {
      "type": "object",
      "required": ["id", "style", "runs"],
      "properties": {
        "id": { "type": "string", "minLength": 1 },
        "style": { "type": "string", "minLength": 1 },
        "align": { "enum": ["left", "center", "right", "justified"] },
        "indent": { "$ref": "#/$defs/indent" },
        "tabStops": { "type": "array", "items": { "$ref": "#/$defs/tabStop" } },
        "lineSpacing": { "type": "number", "exclusiveMinimum": 0 },
        "spaceBefore": { "type": "number" },
        "spaceAfter": { "type": "number" },
        "pageBreakBefore": { "type": "boolean" },
        "cell": { "$ref": "#/$defs/cell" },
        "runs": { "type": "array", "items": { "$ref": "#/$defs/run" } }
      }
    },
    "cell": {
      "type": "object",
      "required": ["table", "row", "column"],
      "properties": {
        "table": { "type": "string", "minLength": 1 },
        "row": { "type": "integer", "minimum": 0 },
        "column": { "type": "integer", "minimum": 0 },
        "rowSpan": { "type": "integer", "minimum": 1 },
        "columnSpan": { "type": "integer", "minimum": 1 },
        "width": { "type": "number", "exclusiveMinimum": 0 }
      }
    },
    "indent": {
      "type": "object",
      "properties": {
        "left": { "type": "number" },
        "right": { "type": "number" },
        "firstLine": { "type": "number" }
      }
    },
    "tabStop": {
      "type": "object",
      "required": ["pos"],
      "properties": {
        "pos": { "type": "number" },
        "type": { "enum": ["left", "center", "right", "decimal"] }
      }
    },
    "run": {
      "type": "object",
      "required": ["text"],
      "properties": {
        "text": { "type": "string" },
        "bold": { "type": "boolean" },
        "italic": { "type": "boolean" },
        "underline": { "type": "boolean" },
        "font": { "type": "string" },
        "size": { "type": "number", "exclusiveMinimum": 0 },
        "color": { "$ref": "#/$defs/color" }
      }
    },
    "object": {
      "type": "object",
      "required": ["id"],
      "properties": {
        "id": { "type": "string", "minLength": 1 },
        "type": { "type": "string" },
        "src": { "type": "string" },
        "anchor": { "enum": ["page", "paragraph"] },
        "page": { "type": "integer", "minimum": 0 },
        "frame": { "$ref": "#/$defs/rect" },
        "anchorParagraph": { "type": "string" },
        "offset": { "$ref": "#/$defs/point" },
        "wrap": { "enum": ["none", "rectangular", "irregular"] },
        "standoff": { "type": "number", "minimum": 0 },
        "z": { "type": "integer" }
      },
      "allOf": [
        {
          "if": { "properties": { "anchor": { "const": "page" } },
                  "required": ["anchor"] },
          "then": { "required": ["page", "frame"] }
        },
        {
          "if": { "properties": { "anchor": { "const": "paragraph" } },
                  "required": ["anchor"] },
          "then": { "required": ["anchorParagraph"] }
        }
      ]
    },
    "rect": {
      "type": "object",
      "required": ["x", "y", "width", "height"],
      "properties": {
        "x": { "type": "number" }, "y": { "type": "number" },
        "width": { "type": "number" }, "height": { "type": "number" }
      }
    },
    "point": {
      "type": "object",
      "required": ["x", "y"],
      "properties": { "x": { "type": "number" }, "y": { "type": "number" } }
    },
    "color": { "type": "string", "pattern": "^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$" }
  }
}
```

## Appendix B — Worked example

### B.1 Archive layout

```
letter.luce  (ZIP)
├── document.json
├── images/
│   └── lake.png
└── content.md
```

### B.2 `document.json`

```json
{
  "format": "lucerne-document",
  "formatVersion": 1,
  "page": {
    "size": "A4",
    "width": 595.28,
    "height": 841.89,
    "margins": { "top": 72, "left": 72, "bottom": 72, "right": 72 }
  },
  "styles": {
    "body":     { "name": "Body",      "font": "Helvetica", "size": 12, "lineSpacing": 1.2, "spaceAfter": 6, "markdown": "p" },
    "heading1": { "name": "Heading 1", "font": "Helvetica", "size": 24, "bold": true, "spaceBefore": 18, "spaceAfter": 8, "markdown": "h1" }
  },
  "body": [
    { "id": "p1", "style": "heading1", "runs": [ { "text": "A Letter from the Lake" } ] },
    {
      "id": "p2",
      "style": "body",
      "indent": { "firstLine": 18 },
      "runs": [
        { "text": "Thanks for the " },
        { "text": "wonderful", "italic": true },
        { "text": " afternoon — see the view below." }
      ]
    }
  ],
  "objects": [
    {
      "id": "img1",
      "type": "image",
      "src": "images/lake.png",
      "anchor": "page",
      "page": 0,
      "frame": { "x": 320, "y": 180, "width": 200, "height": 140 },
      "wrap": "rectangular",
      "standoff": 12,
      "z": 1
    }
  ]
}
```

### B.3 Resulting `content.md`

```markdown
# A Letter from the Lake

Thanks for the *wonderful* afternoon — see the view below.

![lake](images/lake.png)
```

(The heading level comes from the `h1` hint; the italic run keeps its trailing
space outside the markers; the image is appended with its filename stem as alt
text. Placement, fonts, spacing, and the first-line indent are intentionally
absent from the Markdown — they live in `document.json`.)

## Appendix C — Defaults and enumerations

| Field | Default when absent |
|---|---|
| object `type` | `"image"` |
| object `anchor` | `"page"` |
| object `wrap` | `"rectangular"` |
| object `standoff` | `12` |
| object `z` | `0` |
| run/style `bold`, `italic`, `underline` | `false` |
| paragraph `pageBreakBefore` | `false` (absent) |
| effective `font` | `"Helvetica"` |
| effective `size` | `12` |
| effective `color` | `"#000000"` |
| style `lineSpacing` | single (1.0) |
| style `spaceBefore`/`spaceAfter`, indents | `0` |

| Enumeration | Allowed values |
|---|---|
| `page.size` | `"A4"`, `"Letter"`, `"custom"` (advisory) |
| `alignment` / paragraph `align` | `"left"`, `"center"`, `"right"`, `"justified"` |
| style `markdown` | `"p"`, `"h1"`, `"h2"`, `"h3"`, `"li"`, `"blockquote"` |
| tab `type` | `"left"`, `"center"`, `"right"`, `"decimal"` |
| object `anchor` | `"page"`, `"paragraph"` |
| object `wrap` | `"none"`, `"rectangular"`, `"irregular"` |
