# Lucerne on Ubuntu — Porting Research & Proposal

*Status: research complete, proposal awaiting decision. Authored by reviewing the
current codebase (~17,000 lines of Swift) and surveying the Linux text-layout
landscape. No code changes are implied by this document.*

## TL;DR

There is no shortcut: **the defining feature — free image placement with live
text flow — requires a text layout engine that accepts arbitrary per-line
exclusion regions, and no Linux UI toolkit ships one the way AppKit ships TextKit
1.** Every credible option is a substantial rewrite of the UI layer.

The recommended path is:

1. **Phase 0 (cheap, do first):** extract the already-portable core (model +
   `.luce` archive IO, ~2,700 lines) so it builds with Swift for Linux, and run
   the format-conformance tests on Ubuntu CI. This gives any future port a
   reference `.luce` reader/writer and a continuous file-format compatibility
   signal.
2. **Phase 1 (the real port):** build a native **Qt 6 (C++)** application that
   reimplements Lucerne's view/layout layers on `QTextDocument` + the low-level
   `QTextLayout` line API, which — like TextKit 1 — lets you set each line's
   width and position individually and therefore supports exclusion rectangles
   directly. Scribus proves at DTP scale that arbitrary free placement with text
   flow is achievable on exactly this stack. The `.luce` normative spec +
   JSON Schema + shared conformance fixtures are the compatibility contract
   between the two apps.

The credible runner-up — a **GNUstep Objective-C reimplementation** — preserves
the current architecture almost 1:1 but bets the product on the completeness of
GNUstep's text system and a dated user experience. Web/Electron/Tauri and
Swift-on-Linux-GTK options are analyzed and rejected below.

---

## 1. What would have to move

Line counts from `Sources/` (excludes 2,510 lines of tests):

| Layer | Lines | Portability |
|---|---|---|
| `LucerneKit/Model` | 1,367 | **Foundation-only, portable as-is.** Deliberately AppKit-free (`Geometry.swift` avoids even CoreGraphics). |
| `LucerneKit/IO` | 1,195 | Mostly portable. `MiniZip.swift` imports Apple's `Compression` framework (absent on Linux) — needs a zlib shim. `LucerneDocument`, printing, and the document controller are AppKit-bound (~half the folder). |
| `LucerneKit/Support` | 251 | `SemanticVersion.swift` portable; color/hex + image/data helpers are AppKit. |
| `LucerneKit/Layout` | 128 | Small; math is separable but the files import CoreGraphics/AppKit. |
| `LucerneKit/Text` | 840 | AppKit/TextKit (`NSAttributedString` bridge, `NSTextTable`, custom layout manager). **Rewrite.** |
| `LucerneKit/Views` | 5,474 | All AppKit. **Rewrite.** |
| `LucerneKit/Document` | 3,738 | `EditorController` is the conductor of the whole TextKit pipeline. **Rewrite.** |
| App target (`Sources/Lucerne`) | 1,488 | `NSApplication` bootstrap, menus, welcome/about, update checker. **Rewrite.** |

**Bottom line:** roughly **2,700 of 14,500 source lines (~19%) are directly
reusable on Linux** — the canonical model, JSON coding, Markdown export, list
support, `.luce` archive logic, history pruning, and style-library storage. The
other ~81% is tightly coupled to AppKit/TextKit, and that 81% is exactly where
the hard feature lives (`EditorController`, `ExclusionPathController`,
`PageTextView`, the pagination loop).

This reframes the port question. It is not "how do we port the app" but "**what
Linux stack can implement Avenue A — one paginated text flow with obstacle
rectangles — well enough to rebuild the 81% on?**"

## 2. The hard feature on Linux: a survey of text layout stacks

The plan (`lucerne-plan.md` §3) already established that the feature reduces to
*a text layout engine that supports obstacle regions at arbitrary page
coordinates*. Here is what each Linux-accessible stack offers:

### TextKit 1 (current, macOS-only)

`NSTextContainer.exclusionPaths` + one `NSLayoutManager` driving N identical
containers. The engine does the wrap; we do the geometry. This is why the Mac
version is ~14.5k lines instead of 50k.

### Pango (GTK's text engine) — ❌ no exclusion support

`PangoLayout` wraps a paragraph at **one fixed width**
(`pango_layout_set_width`). There is no API for per-line widths, line offsets,
or exclusion shapes, and the long-standing community answer to "flow text around
an image" is *do it yourself* — i.e., itemize and break lines manually with
`pango_itemize`/`pango_break`, or split the flow into per-segment layouts
(which breaks shaping/kerning at segment boundaries). `GtkTextView` exposes
nothing better. A GTK port therefore means writing Avenue C (a custom layout
engine) on Pango primitives, inside a young Swift-GUI ecosystem.

### Qt's `QTextLayout` — ✅ per-line width and position

Qt 6's low-level text API mirrors what we need:

- `QTextLayout::beginLayout()` / `createLine()` hands you one `QTextLine` at a
  time;
- `QTextLine::setLineWidth()` and `setPosition()` let **you** decide each line's
  width and x-offset.

That is sufficient to implement exclusion rectangles exactly the way
`ExclusionPathController` computes them today: for each line's vertical band,
subtract the obstacle rects that intersect it, take the widest remaining segment
(rectangular wrap with standoff), set width + position, continue. Shaping,
bidi, hyphenation, and font fallback remain Qt/HarfBuzz's problem, not ours.

Above the line API, `QTextDocument` provides the rich-text model (blocks,
frames, char/paragraph formats), undo/redo, and printing via `QPrinter`;
`QTextTable` maps to our `NSTextTable` usage; `QTextDocumentWriter` covers
ODF/HTML/Markdown/plaintext export.

**Precedent: Scribus.** A cross-platform Qt application that ships arbitrary
free placement of image frames with text flow around frame shapes *and* custom
contour lines — Lucerne's defining feature plus irregular wrap — built on this
stack with its own layout code. The feasibility question is settled; what
remains is the editor-surface work (see §4).

### GNUstep's text system — ⚠️ the mechanism exists, as a subclass hook

GNUstep implements the OpenStep/AppKit text stack in Objective-C:
`NSTextView`, `GSLayoutManager`/`NSLayoutManager`, `NSTextContainer`,
`NSRulerView`. There is **no `exclusionPaths` property**, but the older,
equally capable mechanism exists: `NSTextContainer` subclasses override
`lineFragmentRectForProposedRect:sweepDirection:movementDirection:remainingRect:`
to define arbitrary regions, and the header documents "layout flowing around
pictures" as an intended use, with `textContainerChangedGeometry:` for live
reflow. Multi-container pagination (one container per page) is a documented
pattern. Architecturally this is Avenue A verbatim.

The caveats are significant:

- **No Swift interop.** Open-source Swift on Linux cannot call Objective-C.
  The port is a *rewrite in Objective-C*, reusing only concepts and the
  Foundation-only model logic (re-implemented).
- **Text-system maturity risk.** GNUstep's text stack works (it ships demo
  editors and mail clients) but sees a fraction of AppKit's exercise;
  multi-container layouts with non-rectangular containers are the least-tested
  corner. Performance and correctness surprises are likely and hard to
  estimate in advance.
- **Dated UX.** Default theming reads as NeXT-era; blending into a modern
  Ubuntu desktop takes real effort.

### Web engines (Tauri/Electron) — ❌ per the plan's own analysis

`lucerne-plan.md` already analyzed this as Avenues B–D and the conclusions hold:
CSS cannot wrap text around an absolutely-positioned element (`shape-outside`
requires floats, which snap to the line box at their flow position); the
sliced-float spacer hack (Avenue D) is "fragile… the textbook trap"; a custom
canvas layout engine (Avenue C) is "the most expensive by far" with a
multi-month bug tail on selection, IME, and a11y. WebKitGTK under Tauri changes
nothing here.

### Compatibility layers (Darling) — ❌ not credible

Darling (a Wine-style macOS translation layer for Linux) cannot realistically
run a TextKit-heavy AppKit application; GUI app support remains experimental.
Shipping a VM is a licensing and UX non-starter.

### Summary

| Stack | Exclusion-capable? | Editing primitives | Precedent | Verdict |
|---|---|---|---|---|
| TextKit 1 (macOS) | ✅ native property | full | this app | keep for macOS |
| Qt 6 `QTextLayout` | ✅ per-line width/position | `QTextDocument`, undo, printing | **Scribus** | **recommended** |
| GNUstep text system | ⚠️ subclass hook | `NSTextView`, ruler | GNUstep apps | runner-up, high platform risk |
| Pango/GTK | ❌ | `GtkTextView` (no help) | — | custom engine required |
| Web (Tauri/Electron) | ❌ (CSS limits) | contenteditable (wrong model) | — | rejected by plan §3 |

## 3. File-format compatibility is the easy part — by design

`.luce` compatibility does **not** require sharing implementation code:

- `docs/luce-format-spec.md` is a normative, RFC 2119 specification with a JSON
  Schema, written explicitly so "an independent party [can] read and write
  compatible files without reference to the Lucerne source code."
- The container is plain ZIP; entries are `document.json`, `images/*`,
  `content.md`, `history/*`. A writer never needs compression (entries are
  stored), and a reader needs only DEFLATE inflate (zlib on Linux).
- The model layer is deliberately platform-independent: points, top-left
  origin, Codable JSON — no CoreGraphics, no AppKit.

The compatibility strategy for any port:

1. **Shared fixture corpus.** A set of `.luce` files exercising every feature
   (styles, tables, lists, headers/footers, ToC, anchored images, history)
   checked into the repo; both apps must round-trip them identically
   (byte-compare `document.json` after normalize-resave).
2. **Schema validation in both apps' CI** against the spec's JSON Schema.
3. **Render-diff testing (aspirational).** Export PDF from both apps for the
   fixture corpus and compare with a pixel tolerance. This is how "identical
   feature set" gets *verified* rather than asserted.

## 4. Evaluated options

### Option A — Qt 6 (C++) native port ✅ recommended

**What it is.** A new application, "Lucerne for Linux," in C++ against Qt 6
Widgets, reimplementing the view/document layers on `QTextDocument` +
`QTextLayout`'s manual line API, reading/writing `.luce` per the spec.

**How the hard feature works.** Avenue E's model (page canvas + obstacles),
same as today:

- One `QTextDocument` for the whole document body (mirrors the single
  `NSTextStorage`).
- A custom paginated layout: pages as `QWidget`/`QGraphicsItem` surfaces; for
  each page, lay out lines via `beginLayout`/`createLine`, applying
  `setLineWidth`/`setPosition` per line from the exclusion rects of that page's
  objects (a direct port of `ExclusionPathController.exclusionRects` — ~100
  lines of math, already unit-tested).
- Floating images are child widgets/graphics items on the page; drags update
  the model and relayout, exactly like `FloatingImageView` today.

**Feature mapping (the parity checklist):**

| Lucerne feature | Qt 6 equivalent |
|---|---|
| Editing, selection, undo | custom editor widget over `QTextDocument` (undo built in) |
| Font/size/B-I-U/color/alignment/spacing | `QTextCharFormat` / `QTextBlockFormat` |
| Ruler with draggable indents/tabs | custom `QWidget`; `QTextBlockFormat` tab stops (left/center/right/**decimal** all supported) |
| Page breaks, pagination | forced block page-breaks + the paginator |
| Headers/footers + tokens | drawn per page at paint/print time (same architecture as today) |
| Tables | `QTextTable` (cell merging via spans supported) |
| Lists with custom markers | `QTextList` or custom gutter painting (as today) |
| Printing | `QPrinter` / `QPagedPaintDevice` |
| PDF export | `QPdfWriter` / `QPrinter` |
| RTF export (lossy) | ⚠️ no built-in writer (Qt has none); hand-roll a lossy subset writer or defer. `QTextDocumentWriter` does cover ODF/HTML/Markdown/plaintext |
| DOCX export (lossy) | ⚠️ no built-in writer; needs a small third-party writer or deferred |
| Markdown export | port of `MarkdownExporter` (pure model code, trivial) |
| Version history (`history/`) | pure ZIP/JSON logic, trivial |
| Style library (`styles.json`) | pure JSON logic, trivial |
| AppleScript | → D-Bus interface and/or CLI (the Linux idiom) |
| Welcome screen, recents, crash recovery | plain widgets + QSettings |

**Effort.** The largest single-engine rewrite of the options, but every piece
has a known recipe. Realistic scoping: the exclusion-flow layout + paginated
editor surface is the risk center (the Mac equivalent is
`EditorController` + `PageTextView` + `ExclusionPathController` ≈ 3,200 lines,
but here the editing surface itself — caret, selection painting, IME via
`QInputMethodEvent`, hit-testing — must be built on top, which TextKit gave us
for free). Order of magnitude: a focused multi-month effort for parity; a
"Phase-0-plus-core-editor" milestone (open/save `.luce`, edit, format, free
placement, print/PDF) is achievable much sooner.

**Risks.** Editor-surface bug tail (selection/IME edge cases — the Avenue C
long tail, mitigated by `QTextDocument` doing the document model); DOCX export
gap; C++ reimplementation of the style round-trip logic must match the Mac
reader/writer semantics exactly (the shared fixtures catch drift).

**Upside beyond Ubuntu.** The same codebase ships Windows immediately and
could eventually become the single cross-platform codebase (Qt runs fine on
macOS).

### Option B — GNUstep Objective-C reimplementation (runner-up)

**What it is.** Rewrite the app in Objective-C against GNUstep's AppKit
implementation, keeping today's architecture: `NSTextView` per page, one
`GSLayoutManager`, per-page `NSTextContainer` subclasses overriding
`lineFragmentRectForProposedRect:…` to punch obstacle holes.

**Why it's attractive.** The text engine does the wrap for you — the only
Linux option where that's true. The Mac code is a mechanical-ish translation
guide (Swift→ObjC, same class names). `NSRulerView` exists. Printing exists.

**Why it's not the recommendation.**

- A **full rewrite** anyway (no Swift↔ObjC bridge on Linux), so "same
  architecture" saves design effort, not code.
- Bets the product on the least-exercised corner of a small-community
  framework: multi-container layout through non-rectangular containers. If it
  misbehaves, the fix is in *GNUstep*, and we become text-system maintainers.
- End-user UX (theming, font rendering, Wayland) trails a Qt app noticeably.
- Ubuntu packaging exists (`gnustep` packages in the archive), but the runtime
  dependency stack is unfamiliar to most users and packagers.

**When to reconsider:** if a spike (2–3 days) building a two-page
`NSTextView` + custom-container prototype shows GNUstep's text system handling
our load smoothly, this option's total effort could undercut Option A's. It is
worth that spike before committing.

### Option C — Swift on Linux + GTK (reuse-the-code dream) ❌

Swift runs fine on Ubuntu and the portable core (§1) compiles with
swift-corelibs-foundation after a zlib shim. But the GUI side — SwiftCrossUI
or the Adwaita bindings — is a young, small-community ecosystem with **no
rich-text editing or layout primitives**. This path means: rewrite the UI
*and* write a custom layout engine on Pango (which has no exclusion support),
in a language ecosystem where we can't lean on a Scribus. It combines the
highest technical risk with the least reuse. Rejected for the app; **its core
extraction is still Phase 0** because it serves every other option.

### Option D — Web app in a Tauri/Electron shell ❌

Rejected by the plan's own Avenue B/C/D analysis; nothing has changed. The
sliced-float hack (D) demos well and breaks on exactly our feature; a custom
canvas engine (C) is the most expensive option of all.

### Option E — `.luce` filter for LibreOffice / extend an existing suite ❌

A UNO import/export filter could make LibreOffice open `.luce` files, and LO
Writer does support arbitrary image placement with wrap. But the deliverable
would be LibreOffice's UI and behavior, not Lucerne's; "identical feature set"
is unachievable (styles, ruler behavior, ToC generation, version history all
differ), and the maintenance surface is a foreign C++/Java codebase. This
serves a different goal ("open my files on Ubuntu") than the one stated.

## 5. Recommendation

**Phase 0 — extract `LucerneCore` for Linux (days, do regardless of port
decision):**

1. Split Model + the portable half of IO (`LuceArchive`, `DocumentHistory`,
   `StyleLibrary`, `MiniZip`) into a `LucerneCore` target with no AppKit
   imports. The only real porting work is replacing `import Compression` with
   a zlib system-library shim for DEFLATE reads (writes are stored/uncompressed
   and need nothing).
2. Add an Ubuntu job to CI: `swift build && swift test` for that target,
   including `SpecConformanceTests` and the round-trip tests.
3. Result: a reference `.luce` library on Linux, a conformance harness any port
   can link or shell out to, and a permanent compatibility signal between
   platforms.

**Phase 1 — the Qt port (the actual product):**

1. **Spike (1–2 weeks):** prove the risk center — one page of editable text on
   `QTextDocument` with a draggable rectangle that text flows around live via
   manual `QTextLine` layout, then across a page boundary. If this feels
   solid, everything else is known-effort widget work. *(Run the GNUstep spike
   from Option B in parallel if appetite allows; pick the winner.)*
2. **Vertical slice:** open/save `.luce` (via the spec; ideally reusing the
   Phase-0 fixtures as tests), paragraph styles, ruler/tabs, print/PDF.
3. **Parity push:** tables, lists, headers/footers, navigator, ToC, history,
   style library, recovery. Track parity explicitly against `PROGRESS.md`.
4. **Distribution:** Flatpak and/or AppImage first (distro-agnostic), a `.deb`
   when stable. Name/icon per existing brand assets.

**Compatibility governance:** the `.luce` spec remains the single contract.
Any format change lands in `docs/luce-format-spec.md` + the shared fixture
corpus + both apps, with `formatVersion` bumps per the checklist in AGENTS.md.

## 6. Open questions

- **Fonts:** identical pagination across platforms is impossible in principle
  (font metrics differ). How much drift do we tolerate in render-diff tests?
  (Mitigation: ship a default serif/sans pair on both platforms.)
- **DOCX/RTF export:** find (or hand-roll) acceptable lossy writers for the Qt
  side, or document their absence as known parity gaps (ODF/HTML/Markdown —
  which Qt writes out of the box — cover the interop need; LibreOffice reads
  ODF natively).
- **Scripting:** is a D-Bus API + CLI a satisfying substitute for AppleScript
  on Linux, or do we embed a JS/Lua engine for user scripts?
- **Long-term:** if the Qt port succeeds, does it eventually replace the
  AppKit codebase as the single source (Qt-on-macOS), or do the two apps
  coexist indefinitely? (Recommendation: coexist; revisit only after the Qt
  app reaches full parity and the Mac maintenance burden is actually felt.)

---

*References: `lucerne-plan.md` §3 (avenue analysis, still authoritative for the
web options); `docs/luce-format-spec.md` (normative format contract);
Qt 6 documentation for `QTextLayout`/`QTextLine` ("lines with given widths…
positioned independently"); GNUstep `NSTextContainer.h` (subclass region hook,
"layout flowing around pictures"); Pango `PangoLayout` docs (single fixed wrap
width); Scribus (text-flow-around-frame/contour as a shipped Qt feature).*
