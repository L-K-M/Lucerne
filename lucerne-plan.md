# Lucerne — Planning Document

*A ClarisWorks-style word editor for the Mac: a small, pleasant tool for writing
letters, with rulers, tabs, and genuine free placement of images.*

A working outline of the goal, the candidate technical approaches, and the honest
tradeoffs of each. The intended audience is whoever builds this (you, a developer,
or an AI coding assistant), so it's deliberately concrete about *where the effort
actually goes*.

---

## 1. The goal

A small, pleasant word processor for writing letters, with the feel of
2011-era Pages / ClarisWorks 5 — not a desktop-publishing suite, not a
Word-style behemoth. Four required capabilities:

1. **A simple editing surface** — type, edit, select, undo, print, save/open.
2. **Basic text formatting** — font, size, bold/italic/underline, color,
   alignment, line spacing, paragraph spacing.
3. **Rulers and tabs** — a horizontal ruler with draggable margin markers and
   tab stops (left/center/right/decimal), plus indents.
4. **100% free image placement with text flow** — drop an image *anywhere* on the
   page at an arbitrary (x, y), and have the body text reflow around it, staying
   correct through every subsequent edit.

This should be a classic, simple word editor in the vein of 2010 Pages or Claris
Works 4/5 with a simple toolbar at the top of the page.

This is *not* a "content over chrome" tool. Good UX is important and should be
well-structured and pleasant to use.

See ./inspiration for screenshots.

### What "100% free placement" means precisely (the ClarisWorks behavior)

This is the feature that defines the whole project, so it's worth pinning down.

- The image is a **floating object**, not an inline character. It does not sit
  "between two words"; it occupies a rectangle on the page.
- It can be **page-anchored**: you drag it to a spot on the page and it *stays*
  there even as text above it is edited. (ClarisWorks also supported
  anchoring-to-text, where the object moves with its paragraph — useful, but the
  page-anchored mode is the iconic "free placement" one.)
- Body text **wraps around the object's bounding box** (and, in later
  ClarisWorks/AppleWorks versions, optionally around an *irregular* outline),
  with an adjustable standoff/gutter.
- Reflow is **live and stable**: edit a sentence three lines above the image and
  every line re-wraps correctly; nothing jumps or corrupts.

The key realization: this is not an "insert image" feature. It is a request for a
**text layout engine that supports obstacle regions at arbitrary page
coordinates.** That single sentence is the source of nearly all the difficulty
below.

### Decisions locked in

These questions are settled and should be treated as fixed constraints for the
rest of the document.

**D1 — Fixed, uniform page size.** The document has **one page size, chosen once at
creation** (e.g. A4), stored as a single document-level property. It applies to
every page; there is no per-page sizing and no mixed-size documents. This is a
deliberate simplification, and a helpful one: every page's text container has
identical dimensions and margins, so there is no reflow-on-geometry-change case to
handle, and a placed image's page-relative (x, y) means the same thing on every
page. The only residual edge case is an image positioned near a page boundary —
decide whether such an image clips at the boundary or is allowed to overhang
(recommended: allow overhang, render it on the page it's anchored to).

**D2 — Own format is canonical; RTF is not.** Storage is layered by purpose:

- **Canonical save format: a custom JSON (or plist) document** — text runs with
  their formatting, plus a list of placed objects, each carrying page index, x/y,
  size, wrap mode, and standoff. This maps one-to-one onto the app's model, round-
  trips losslessly, and is easy to version. *This is the format the app reads and
  writes by default.*
- **Share / print: PDF** — perfect visual fidelity, read-only.
- **Interchange: RTF / DOCX as an explicitly lossy export only** — offered for
  people who need an editable file elsewhere, with the understanding that free
  placement flattens (to inline, or at best margin-anchored) on the way out.

The reasoning is in §4 under *File format* — short version: the RTF spec can
*express* positioned frames, but Apple's text system (which Avenue A relies on)
does not round-trip them, so saving through it would silently destroy the one
feature the project exists for.

**D3 — The save file is a ZIP package with a built-in plain-text escape hatch.**
The canonical document (D2) is delivered as a **ZIP container** — the same pattern
as `.docx`, `.epub`, and Apple's own `.pages`. Inside:

- `document.json` — the canonical, lossless model (text runs + placed objects, per
  D2). *The only thing the app reads as the source of truth.*
- `images/` — the placed images as **separate, original files** (not base64 inside
  the JSON), referenced by name.
- `content.md` — a **derived Markdown copy of the text**, regenerated on every save.
- (room to grow: a `preview.pdf`, metadata, etc.)

The point of `content.md` is a graceful failure mode. If the app ever stops
working, someone can unzip the file and recover the **words and the pictures** —
the Markdown references the loose image files with ordinary `![](images/photo1.png)`
links — losing only the precise placement and fine formatting. That's a reassuring
worst case for a document you might want to open in twenty years.

Two rules keep this honest:

1. **`content.md` is write-only / derived.** The app regenerates it from
   `document.json` on every save and *never reads it back* as authority. It's a
   freshly-carved tombstone, not a second copy the app negotiates with. The instant
   the app trusts the Markdown for anything, the lossiness becomes authoritative
   rather than merely a backup.
2. **Meaningful Markdown requires a lightweight paragraph-style layer.** To emit
   real headings/lists rather than guessing from "18pt bold," each paragraph in
   `document.json` carries a **named style role** — a small set: Body (default), one
   or two Heading levels, List Item, Block Quote — where each role *maps to* visual
   attributes. The user applies "Heading 1" and it looks big and bold; the exporter
   knows it's a heading and writes `#`. This is not scope creep: paragraph styles via
   the ruler/stylesheet are exactly how ClarisWorks, Pages, and Nisus worked, so
   they're *period-appropriate* to what's being recreated — and a letter barely
   needs them anyway (mostly Body, which exports to clean prose for free). Inline
   bold/italic map straight to Markdown; underline, color, font, and exact size
   simply don't appear in the `.md`, which is correct — the fallback preserves
   **content and structure**, and appearance is the PDF lane's job.

The cost in the data model is one `style` field per paragraph. See §4 (*File
format*) for why Markdown can't be the canonical format itself.

**D4 — Name and on-disk identity: *Lucerne*, saving `.luce` files.** The product is
**Lucerne**; its documents use the extension **`.luce`** (short, lowercase, no
collision with common extensions, and it reads as *luce* — "light"). Two choices
make the name and the D3 package coexist cleanly:

- **The file is a real ZIP, sealed as one document.** Register `.luce` as a document
  type via a UTI that conforms to `public.zip-archive`, so the OS and the app treat
  it as a single opaque file even though it's a ZIP of `document.json`, `images/`,
  and `content.md` (D3). A curious or desperate user can rename `letter.luce` to
  `letter.zip`, unzip, and recover everything — so the escape-hatch promise gets
  *stronger*: the recovery path is literally "rename it to `.zip`."
- **ZIP, not a flat folder bundle.** macOS also supports bundle documents (a folder
  Finder shows as one file). A bundle saves trivially and is git-friendly, but it's
  fragile in transit — email, cloud sync, and Windows can explode it into loose
  files. Since Lucerne's whole purpose is *sending letters to other people*, a
  single sealed ZIP that travels safely wins over save-time convenience. Decided
  now because switching later is a migration.

---

## 2. Why one feature is hard and three are easy

| Feature | Difficulty | Why |
|---|---|---|
| Editing surface | Low | Mature components exist on every platform. |
| Text formatting | Low | Built into those same components. |
| Rulers and tabs | Low–Medium | Tab-stop *logic* is usually built in; the ruler *UI* is custom but well-understood. |
| Free placement + flow | **High** | Requires line-breaking that subtracts arbitrary obstacle rectangles and reflows on every edit. This is layout-engine work. |

The practical consequence: the first three features produce a convincing demo in a
weekend. The fourth determines whether the project is a weekend or a season. Plan
the whole effort around de-risking feature #4 first (see §6).

---

## 3. The avenues

### Avenue A — Native macOS, TextKit exclusion paths (AppKit / Swift)

**Approach.** Build a Mac app around `NSTextView` (the component TextEdit itself
uses). TextKit's text container exposes `exclusionPaths`: you hand the layout
engine a set of bezier paths and it flows text around them automatically. Each
floating image is a draggable view; on drag and on text edit you recompute its
rectangle (or its alpha outline) into an exclusion path in container coordinates.

**You get almost for free:** rich-text editing, the ruler with draggable tab stops
and indents, RTF read/write, font/color panels, printing, spell-check, undo.

**Why it's the strongest fit:** the hard feature is a *supported, intended*
mechanism rather than something you fight. Rectangular wrap is straightforward;
irregular (alpha-shaped) wrap is achievable because exclusion paths can be any
bezier. The layout engine is on your side.

**Issues / risks:**
- **Pagination is still yours to build, but D1 tames it.** `NSTextView` is a
  continuous scroll surface by default; a letter wants discrete A4 pages with
  margins and breaks. You build that yourself — but because every page is the same
  size (D1), it's N *identical* `NSTextContainer`s driven by one `NSLayoutManager`,
  with no geometry-change cases. The only interaction left with placement is an
  image near a page boundary (handled per D1: allow overhang).
- **Coordinate bookkeeping.** Exclusion paths live in *container* coordinates. With
  multiple page-containers, mapping a page-anchored image's screen position to the
  right container's path is fiddly and a likely bug source — though uniform pages
  (D1) make the page-to-container math regular rather than case-by-case.
- **Page-anchored vs text-anchored** behavior is yours to implement; the engine
  only gives you the wrap.
- **TextKit 1 vs TextKit 2.** Exclusion paths are most battle-tested in TextKit 1,
  which Apple is steering away from; TextKit 2's support has historically been
  thinner. Pick deliberately and verify on your target macOS version.
- **Mac-only**, and a Swift/AppKit learning curve if that's unfamiliar.

**Vibecoding outlook:** Good for the editor/ruler scaffolding and for wiring up a
single rectangular exclusion path. The pagination + multi-container coordinate
work is exactly where an assistant will produce plausible-but-wrong code, so treat
that as the part you understand yourself.

---

### Avenue B — Web, mature editor framework + CSS (ProseMirror / Lexical / TipTap)

**Approach.** Use a proven rich-text framework for the document model and editing,
images as nodes, and CSS for wrap.

**The wall:** CSS can wrap text around a *floated* element (`float`, refined with
`shape-outside` for non-rectangular shapes), but a float snaps to the left/right
of the line box **at its position in the text flow.** There is no native CSS way to
make body text wrap around an **absolutely-positioned** element at an arbitrary
(x, y). So plain CSS gives you margin-pinned wrap, not free placement.

**Issues / risks:**
- These frameworks model the document as a **linear stream**; a page-anchored
  floating object is an impedance mismatch you paper over constantly.
- You'll end up reaching for the hack in Avenue D anyway.

**Vibecoding outlook:** Excellent for editing, formatting, and *margin-anchored*
wrap. An assistant may not volunteer that arbitrary placement is outside CSS's
model — it'll happily generate float code that looks right and silently isn't free
placement. Know this going in.

**Verdict:** Great if you can relax "free placement" to "left/right of column."
Not, by itself, a path to true ClarisWorks behavior.

---

### Avenue C — Web, custom layout engine (canvas or positioned spans)

**Approach.** Write your own line-breaker. For each line, compute the available
horizontal segment(s) after subtracting any obstacle rectangles at that vertical
band, lay out text runs into those segments, and render to `<canvas>` or to
absolutely-positioned DOM. You own everything, so obstacles at any (x, y) are
natural.

**Issues / risks (the big one):**
- You are building a **text layout engine**: line breaking, word wrapping, font
  metrics, the caret, selection, hit-testing, text input / IME, undo, copy-paste,
  accessibility, and printing — none of which a framework is now providing.
- This is the "a small layout engine quietly becomes a product" scenario in its
  fullest form. Enormous surface area; long tail of subtle bugs.

**Vibecoding outlook:** An assistant will get you an impressive toy fast (text
wrapping one rectangle on a canvas) and then a multi-month bug tail on selection,
input, and edge cases. Highest risk of "looks done, isn't."

**Verdict:** The "technically correct" web path, and the most expensive by far.

---

### Avenue D — Web, sliced-float / per-line-spacer hack

**Approach.** Keep real, selectable HTML text. Position the image absolutely, then
inject invisible per-line spacers (or compute a `shape-outside` polygon) so text is
pushed away from the image's rectangle on the affected lines, recomputed on every
edit, resize, and font change.

**Issues / risks:**
- **Fragile.** The obstacle's *vertical* position is the hard part: floats attach
  at a flow position, so making a page-anchored image whose top is at y = 300px
  exclude exactly the right lines requires brittle bookkeeping.
- Multiple or overlapping images get ugly fast.
- Recompute-on-every-change is a performance and correctness minefield.

**Vibecoding outlook:** Demos beautifully, breaks on reflow/resize/multi-image —
the textbook trap.

**Verdict:** A pragmatic compromise if you're committed to the web *and* willing to
accept rough edges. Not a clean route to "correct every time."

---

### Avenue E — Reframe as "main text frame + obstacles" (a model, applicable to A/C/D)

**Approach (a mindset, not a platform).** Stop thinking "rich-text editor with
embedded images" and think like ClarisWorks/DTP actually did: a **page canvas**
holding one main (possibly paginated) text frame, plus floating objects that
*punch holes* in that frame. The editor's job becomes: maintain the text frame, and
maintain a set of obstacle regions the frame must avoid.

**Why it matters:** this framing is exactly what TextKit exclusion paths (Avenue A)
and a custom engine (Avenue C) want anyway. Adopting it early prevents you from
contorting a linear editor model into something it resists.

---

## 4. Cross-cutting issues (they bite on every avenue)

- **Pagination.** *Decided (D1):* true paginated pages, one fixed size for the whole
  document. This removes the geometry-change reflow case entirely; the only
  remaining interaction with free placement is a boundary-straddling image, handled
  by allowing overhang on the anchoring page.
- **Anchoring model.** Page-anchored vs paragraph-anchored. Pick the default
  (page-anchored matches the ClarisWorks "free" feel); ideally support both.
- **Rectangular vs irregular wrap.** Rectangular covers ~95% of letter use and is
  much simpler. Treat alpha-outline wrap as a later nicety.
- **Selection and caret around obstacles.** What happens when the user clicks in
  the gap beside an image, or drags a selection across wrapped lines?
- **File format.** *Decided (D2): own format is canonical; RTF is not.* The RTF
  *spec* can in principle express absolutely-positioned, page-anchored images —
  paragraph-frame control words (`\posx`/`\posy`, `\phpg`/`\pvpg`, `\dxfrtext`) and
  the `{\shp ...}` shape group carry position and wrap. **But the toolkit you'd
  actually use can't.** On Avenue A you save/load via `NSAttributedString`'s RTF
  reader/writer, and that machinery only understands images as *inline*
  `NSTextAttachment`s — it does not serialize floating frames, page anchors,
  exclusion paths, or wrap modes. Save through it and your free-placed images
  collapse to inline characters with their positions lost. You *could* hand-write an
  RTF emitter/parser in the frame/shape dialect, but it's fragile work bolted onto a
  format that resists you, and Word interop would still be uneven. So: a custom JSON
  (or plist) model is the canonical store (text runs + placed objects with page,
  x/y, size, wrap mode, standoff), delivered inside a ZIP package per D3 (with loose
  images and a derived `content.md`); PDF is the share/print format; and RTF/DOCX is
  an optional, explicitly lossy export only.
- **Why not Markdown as the *canonical* format?** It's the same failure mode as RTF,
  only more total — which is why it's a *derived* lane (D3), never the source of
  truth. Markdown is a **semantic/structural** format; this app is **presentational
  and spatial.** There's no Markdown syntax for font, size, color, alignment, line
  spacing, tabs, or indents (underline already needs inline HTML), and — fatally —
  no concept of an image at an arbitrary (x, y) with wrap and standoff, nor of pages
  or a fixed page size. Pure Markdown would flatten placement to inline, drop
  formatting to bold/italic, and lose pagination: everything distinctive about the
  app. Inventing a dialect (front-matter for page size, fenced `:::image{...}`
  directives, `style="..."` HTML spans) only throws away the portability that made
  Markdown attractive, leaving a custom format that merely *looks* like Markdown. The
  durable-plain-text virtues people actually want from it — open, readable,
  diffable, future-proof — are already delivered by the JSON model (also plain text)
  plus the `content.md` escape hatch, without crippling fidelity.
- **Performance.** Reflow must stay snappy while typing with several placed images.

---

## 5. Recommendation

For *this* goal — a Mac letters tool with genuine 100% free placement — **Avenue A
(native TextKit with exclusion paths) is the clear front-runner.** The single
hardest requirement is natively supported, and rulers, tabs, rich-text editing, and
printing come nearly free. With the page model fixed and uniform (D1), its main
remaining risk is the page-anchored coordinate bookkeeping across identical
containers — meaningful but bounded, and not a research problem. (Note that "comes
free" refers to editing and the built-in RTF *reader/writer*, not to saving — per
D2 the canonical format is your own JSON model, precisely because the built-in RTF
writer would flatten free placement.)

Choose otherwise only if a hard constraint forces it:
- **Need cross-platform / web?** Avenue C is the honest correct path but the most
  expensive; Avenue D is the pragmatic-but-fragile shortcut. Avenue B alone won't
  deliver true free placement.
- **Can you relax "free placement" to left/right-of-column?** Then Avenue B becomes
  easy and pleasant — but you've already said you can't, so that's noted only for
  completeness.

---

## 6. Suggested first milestone (de-risk the hard part first)

Do **not** build the polished editor first and bolt on wrapping later. Invert it.
Build the smallest thing that proves the hard feature on your chosen platform:

> A single page. A block of placeholder text. One image you can drag anywhere.
> Text reflows around its rectangle correctly, live, while you also edit the text.

If that holds up — stable through edits, drags, and a window resize — the project is
real and the remaining work (formatting, ruler, multi-page, save/open) is the
pleasant, well-trodden 80%. If it *doesn't* hold up cleanly, you've learned that in
a few days instead of a few months, and you can reconsider the avenue before
investing further.

Concretely, on Avenue A: an `NSTextView` in one container, one `NSImageView`
subclass you can drag, and an `exclusionPaths` update on every drag and text change.
Get that solid before adding a second page or a second image.

---

## 7. Document model — `document.json` sketch

The canonical payload inside the ZIP package (D3), realizing D1–D3. The example
below is annotated with `//` comments for readability; **real `document.json` is
plain JSON with no comments.**

```jsonc
{
  "format": "lucerne-document",
  "formatVersion": 1,                  // bump for migrations; readers check this

  // --- D1: one fixed page size for the whole document ---
  "page": {
    "size": "A4",                      // named preset, or "custom"
    "width": 595.28,                   // points (1/72"); authoritative when size = "custom"
    "height": 841.89,
    "margins": { "top": 72, "left": 72, "bottom": 72, "right": 72 }  // points
  },

  // --- D3: named paragraph-style roles → visual attributes + a markdown hint ---
  // Embedded in the file so it's self-contained and user-customizable.
  "styles": {
    "body":     { "name": "Body",        "font": "Helvetica", "size": 12, "lineSpacing": 1.2, "spaceAfter": 6,  "markdown": "p" },
    "heading1": { "name": "Heading 1",   "font": "Helvetica", "size": 24, "bold": true, "spaceBefore": 18, "spaceAfter": 8, "markdown": "h1" },
    "heading2": { "name": "Heading 2",   "font": "Helvetica", "size": 18, "bold": true, "spaceBefore": 14, "spaceAfter": 6, "markdown": "h2" },
    "listItem": { "name": "List Item",   "font": "Helvetica", "size": 12, "markdown": "li" },
    "quote":    { "name": "Block Quote", "font": "Helvetica", "size": 12, "italic": true, "leftIndent": 36, "markdown": "blockquote" }
  },

  // --- the text: an ordered list of paragraphs (the flowing main frame) ---
  "body": [
    {
      "id": "p1",
      "style": "heading1",             // role drives both look and markdown export
      "runs": [ { "text": "A Letter from the Lake" } ]
    },
    {
      "id": "p2",
      "style": "body",
      "align": "left",                 // optional per-paragraph overrides
      "indent": { "left": 0, "right": 0, "firstLine": 18 },
      "tabStops": [ { "pos": 240, "type": "left" } ],   // points from left margin
      "runs": [
        { "text": "Thanks for the " },
        { "text": "wonderful", "italic": true },        // run-level override of style
        { "text": " afternoon — see the view below." }
      ]
    }
  ],

  // --- D2 + free placement: floating objects that punch holes in the text frame ---
  "objects": [
    {
      "id": "img1",
      "type": "image",
      "src": "images/lake.png",        // loose file inside the ZIP (D3), not base64
      "anchor": "page",                // "page" = free placement; "paragraph" = moves with text
      "page": 0,                       // zero-based; required when anchor = "page"
      "frame": { "x": 320, "y": 180, "width": 200, "height": 140 },  // points, page-relative, origin top-left
      "wrap": "rectangular",           // "none" | "rectangular" | "irregular"
      "standoff": 12,                  // gutter between image box and text, in points
      "z": 1                           // stacking order among objects
      // when anchor = "paragraph", replace page/frame.x/y with:
      //   "anchorParagraph": "p2",
      //   "offset": { "x": 0, "y": 0 }   // relative to the paragraph's position
    }
  ]
}
```

**Conventions worth fixing now:**

- **Units are points** (1/72") everywhere — typographic-native and what the layout
  engine wants. A4 is ~595.28 × 841.89 pt.
- **Coordinate origin is the page top-left**, y increasing downward, matching how
  you'll place exclusion paths. (If you build on AppKit's flipped/unflipped quirks,
  convert at the boundary, not in the file.)
- **Runs inherit from their paragraph's style**; only *overrides* are stored on a
  run (the `"italic": true` above). Keeps the file small and the intent legible.
- **`markdown` per style is the export hint** that makes D3's `content.md` faithful
  instead of guessed — the exporter reads it, never infers from size/weight.
- **Two anchor modes share one object list:** `"page"` objects carry `page` + a
  page-relative `frame` (the free-placement case); `"paragraph"` objects carry
  `anchorParagraph` + `offset` and move with the text.

**Deliberately deferred (sketch, not spec):**

- *Irregular wrap shape.* When `wrap` is `"irregular"`, it'll need a stored outline
  (a polygon/bezier, or "derive from image alpha at load"). Left open until
  rectangular wrap is solid.
- *Color and font models.* Assume hex strings (`"#1a1a1a"`) and PostScript font
  names for now; revisit if you need font fallback or color spaces.
- *Lists.* `listItem` covers the markdown round-trip, but real list numbering/nesting
  (ordered vs unordered, indent levels) is unspecified here.
- *IDs.* Stable per-paragraph/object IDs are assumed (needed for paragraph anchoring
  and undo); generation scheme is an implementation detail.

This schema is small enough to hand to a coding assistant as the data contract for
the §6 milestone — though note the milestone only exercises `page`, one `body`
paragraph or two, and one `"anchor": "page"` object.

---

*This is a planning sketch, not a spec — it's meant to be argued with and revised as
the first milestone teaches you where the real edges are.*
