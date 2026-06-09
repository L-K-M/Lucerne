# PROGRESS.md — Lucerne implementation status

Live checklist for the Avenue A build. Updated as work lands. Legend:
`[x]` done · `[~]` partial / in progress · `[ ]` not started.

> **Verification:** authored on Linux (no Swift toolchain). Compilation is checked
> by the macOS CI workflow, not locally. **The macOS CI build + unit tests are
> green** as of the latest commit, so "done" means *implemented, compiling, and
> unit-tested* — pending interactive on-device QA on a Mac for the things tests
> can't cover (live reflow feel, ruler dragging, pagination across many pages).

## Current state at a glance

All four pillars of the brief are implemented and CI-green: the **editing surface**
(NSDocument-based, undo/redo, printing), **text formatting** (font/size/bold/italic/
underline/color/alignment/spacing + named paragraph styles), **rulers & tabs**, and
the defining feature — **free image placement with live text reflow** around
rectangular wrap, including dragging images across page boundaries. On top of those:
page zoom, forced page breaks, running headers/footers, a heading navigator, a
generated table of contents, `.luce` (ZIP) read/write with Markdown version history,
PDF + lossy RTF export, AppleScript, a welcome screen, and crash/draft recovery.

What's **not** done is tracked in Milestone 3 below and, with design notes and
effort estimates, in [`docs/roadmap.md`](docs/roadmap.md) — chiefly tables, lists,
cross-page selection, irregular wrap, dotted ToC leaders, and in-place header/footer
editing. The whole app still needs on-device QA (CI only verifies compile + units).

## Milestone 0 — scaffolding
- [x] Package manifest (`Package.swift`), executable + library + test targets
- [x] README, AGENTS, PROGRESS, docs skeleton
- [x] `.gitignore`
- [x] macOS CI workflow (build + test)
- [x] App bundle script + `Info.plist` (`.luce` UTI / document type)

## Milestone 1 — the hard feature (plan §6: de-risk first)
> One page, placeholder text, one draggable image, live reflow around it.
- [x] Document model (`document.json`) — Codable structs (§7)
- [x] Page metrics + exclusion-rect geometry (unit-tested)
- [x] model ⇆ `NSAttributedString` bridge
- [x] Paginated layout: one layout manager, per-page containers + text views
- [x] `PageCanvasView` / `PageContainerView` with flipped, point-based coords
- [x] `FloatingImageView` — draggable, updates model, triggers reflow
- [x] `ExclusionPathController` — page-anchored rect → container exclusion path
- [x] Default "sample letter" document so launch demonstrates reflow

## Milestone 2 — the pleasant 80%
### Editing surface
- [x] New / Open / Save / Save As via `NSDocument`
- [x] Undo/redo (via text view + NSDocument)
- [x] Printing
- [~] Multi-page editing (within-page selection; cross-page selection is future work)

### Text formatting
- [x] Bold / italic / underline
- [x] Font & size (font panel + toolbar)
- [x] Text color (color panel)
- [x] Alignment (left/center/right/justified)
- [x] Line spacing & paragraph spacing
- [x] Named paragraph styles (Body, Heading 1/2, List Item, Block Quote)

### Rulers & tabs
- [x] Horizontal ruler view
- [x] Draggable left/right/first-line indent markers
- [x] Tab stops (left/center/right/decimal), add/move/remove
- [x] Margin indicators

### Free placement (beyond milestone 1)
- [x] Insert image from file
- [x] Rectangular wrap with adjustable standoff
- [x] Wrap mode = none (overlay, no exclusion)
- [ ] Irregular (alpha-outline) wrap — modeled, falls back to rectangle
- [~] Page-anchored is the default; paragraph-anchored modeled, not yet wired in UI

### File format & IO
- [x] `MiniZip` (stored write; stored + deflate read)
- [x] `.luce` package read/write (`document.json` + `images/` + `content.md`)
- [x] `content.md` derivation (write-only escape hatch)
- [x] PDF export
- [x] RTF lossy export (text/formatting survive; free-placed images flatten out)
- [ ] DOCX lossy export

## Milestone 3 — polish (later)
> Design notes + effort estimates for these (and tables/lists) are in
> [`docs/roadmap.md`](docs/roadmap.md).
- [ ] Cross-page text selection
- [ ] Image overhang at page boundary (currently clipped)
- [ ] Irregular wrap from image alpha
- [ ] Lists (numbering / nesting)
- [ ] Document inspector (page size, margins) UI
- [ ] Preferences

## Tests (run on macOS CI)
- [x] Model JSON round-trip, geometry, Markdown export (`ModelTests`)
- [x] Text bridge round-trip — text/roles/ids/italic/alignment (`RoundTripTests`)
- [x] `MiniZip` stored round-trip + non-zip rejection
- [x] `.luce` package round-trip (model + image bytes + content.md present)
- [x] `PageMetrics` exclusion-rect + clamp geometry

## On-device feedback (round 6)
- [x] Ruler now spans the full window width (fixes the side rendering discontinuity);
  its scale is aligned to the page and tracks scroll/zoom
- [x] Ruler hover help + tooltip (add a tab, change tab type, move/delete, indents)
- [x] **Markdown version history** in the `.luce` (`history/`, staggered retention)
  so accidentally-deleted text can be recovered from the package
- [x] **Page-number footer / headers & footers** — `header`/`footer` with
  left/center/right zones and `{page} {pages} {date} {title}` tokens, drawn in the
  margins per page; Insert ▸ Page Number and Insert ▸ Header & Footer…
- [x] **Heading navigator** sidebar (View ▸ Show Navigator) listing headings;
  click to scroll to one. Built on `pageNumber(forCharacterAt:)` + `headingOutline()`.
- [x] **Printed table of contents** (Insert ▸ Table of Contents) — entries with a
  **dotted leader** to a right-aligned page number (converged via relayout),
  persisted as a `toc` paragraph style; re-run to update
- [ ] Editable header/footer click-zones, tables — `docs/roadmap.md`

## Design feedback (round 12)
- [x] **Classic format bar** — the toolbar is redrawn in the pre-flat Mac style
  (think iWork '09): a polished gradient strip with a 1 px top highlight and
  etched group dividers, holding hand-drawn gradient-bezel controls
  (`Views/ClassicControls.swift`): pop-ups with stacked chevrons in a hairline
  arrow well, a white inset size field joined to a preset menu well, B/I/U and
  alignment as single-outline segment groups with path-drawn glyphs, and a
  framed color-well swatch that goes sunken while active. Bar height 44 → 34.
- [x] The **status bar** and **ruler** join the chrome so the window reads as one
  piece: the footer becomes a gradient strip with engraved (white-drop) text and
  a momentary − / % / + bezel cluster replacing the borderless zoom buttons; the
  ruler gets the chrome gradient outside its writable band, hairline band edges,
  and an etched seam where it meets the format bar's border.
- [~] **Square bottom window corners** — the document window keeps rounded top
  corners but hard square bottom corners (the pre–Big Sur silhouette) via
  `ClassicWindow`, which answers the private `_cornerMask` shape hook with a
  top-rounded/bottom-square template. Degrades to stock rounded corners if a
  future macOS drops the hook; the hook is private API, so this one *needs
  on-device confirmation*.

## On-device feedback (round 11)
- [x] The default window now sizes itself to the **screen and the page format**: it
  picks a zoom so a whole page fits within ~90% of the screen (capped at 100%, never
  starting enlarged), then a window just big enough to show that page plus the
  toolbar/ruler/status — capped to the screen (`DocumentWindowController.initialLayout`)

## On-device feedback (round 10)
- [x] Ruler numbers no longer overlap the tick marks — taller ruler, with numbers
  centered above the ticks (the ticks rise from the bottom edge)
- [x] In a table, **↑/↓ arrows** move to the cell above/below in the same column
  (overrides `moveUp`/`moveDown`); at the table edge they step out normally
- [x] **Select Table** (Format ▸ Table or the context menu) selects the whole table
  so it can be deleted/cut/copied as a unit
- [x] **Merge cells** — select a rectangular block of cells and Format ▸ Table ▸
  Merge Cells (or the context menu) merges them into one spanning cell; spans persist
  (`cell.rowSpan`/`columnSpan`) and round-trip. (Structural row/column edits reset
  merges back to a full grid.)

## On-device feedback (round 9)
- [x] **Ruler units** default to **centimeters**, switchable in **Settings…** (⌘,);
  the ruler ticks/labels are unit-aware and refresh live (`Preferences`/`RulerUnit`)
- [x] **Context menu** on the page now carries Bold/Italic/Underline, paragraph
  styles, Insert Image/Table, and (in a cell) the table row/column commands
- [x] **Table row/column editing** — insert row above/below, insert column
  before/after, delete row/column (Format ▸ Table or the context menu); rebuilds the
  table preserving cell text
- [x] Inserting a table no longer leaves **phantom tab stops** on the ruler (cells
  use the Body paragraph style's empty tab array, not NSParagraphStyle's defaults)
- [x] A table at the **very start of the document** now keeps an empty line above it
  so you can place the caret and type above the table
- [x] **Table column resize** — drag the column dividers on the ruler when the caret
  is in a table (Format ▸ Table ▸ Distribute Columns Evenly to reset). Widths persist
  per column (`cell.width`)
- [~] Tables **split across page boundaries** via TextKit row-breaking + the existing
  overflow pagination (multi-row tables flow to the next page; a single row taller
  than a page can't split). Needs on-device QA to confirm rows don't clip

## On-device feedback (round 8)
- [x] **Tables** (Insert ▸ Table…) via `NSTextTable` — a rows×columns grid of
  editable cells that flows and paginates with the text. Cells round-trip to the
  model as `Paragraph.cell` (a flat list, no nested block type). v1: rectangular
  cells, no Tab-between-cells navigation or column resize yet
- [x] Formatting with **no selection** now works: a toolbar/menu command always has
  a target text view, sets the typing attributes, and returns focus to the page so
  the next typed text picks up the change
- [x] **Insert ▸ Page Number** now sets a plain centered page number (`{page}`),
  not the verbose "Page x of y" (Header & Footer… still does the full version)
- [x] **Start page numbering** at a chosen page (Header & Footer… → "Numbered from
  page") so a title page / contents page can be unnumbered; model `pageNumberStart`
- [x] About / Welcome windows load the real icon from a **bundled resource** (shows
  even when run unbundled), not just `NSApp.applicationIconImage`
- [x] Reverted autosave-in-place → the unsaved-changes **dot** and save-on-close
  prompt are back; crash recovery kept via **draft autosave** (`autosavesDrafts`)
- [x] Dotted leaders on the printed table of contents (see round 6)

## On-device feedback (round 7)
- [x] Custom About window with the app icon (replaces the stock panel)
- [x] Toolbar Bold/Italic/Underline are a segmented control now, so the selected
  ones take the accent color (matching alignment)
- [x] Crash/draft recovery for never-saved documents via **draft autosave**
  (untitled drafts are recovered on relaunch); saved docs restore via macOS Resume
- [x] **Welcome window** on launch when nothing is open: recent documents +
  New / Open / New Sample Letter

## On-device feedback (round 5)
- [x] Icons: artwork is edge-to-edge (clipped to the squircle/page; no white inset)
- [x] Nice About box (custom standard about panel: name, version, credits, icon)
- [x] Toolbar overflow: window minimum width fits the toolbar so controls can
  never be pushed off-screen (replaced the unreliable overlay scroller)
- [x] Higher contrast: stronger page shadow, darker canvas backdrop, defined
  toolbar/ruler/status borders
- [x] AppleScript support (`Scripts/Lucerne.sdef`; standard suite + document
  `text` (r/w) and `page count` (r) properties; `NSAppleScriptEnabled`)

## On-device feedback (round 4)
- [x] Zoom widget in the footer (− / % / +); click the % to reset to 100%
- [x] Removed the toolbar separator lines (grouping via spacing instead)
- [x] Drag images **between pages** — a moving image floats above pages, reflows
  live onto whichever page it's over, and re-anchors there on drop (undoable)
- [x] Page size moved to **File ▸ Page Setup** (drives the document page size and
  printing); **Document Setup** now holds margins (+ room for more)
- [x] App icon + derived document icon generated from `media-sources/icon.png`
  (`Scripts/GenerateIcons.swift`, wired into `make-app.sh`; validated in CI)

## On-device feedback (round 3)
- [x] Insert Image removed from the toolbar (menu item kept)
- [x] Dragging an image file/data onto a page makes a floating image at the drop
  point (no longer inserts the path as text)
- [x] **Document Setup** sheet to change page size + margins
- [x] **Page zoom** (View ▸ Zoom In/Out/Actual Size + pinch); ruler tracks the
  page under zoom and horizontal scroll; status bar shows zoom %
- [x] Default window sized to fit the toolbar; toolbar scrolls if narrower (overflow)
- [x] **Insert Page Break** (Insert ▸ Page Break) — `pageBreakBefore` paragraph
  flag enforced with a full-width exclusion band; isolated so break-free docs are
  unaffected
- [x] Replaced string `Selector("…")` literals with `#selector` (warnings)

## On-device feedback fixes (round 2)
- [x] Image resize keeps aspect ratio by default; hold **⇧** to resize freely
- [x] **Status-bar footer** showing contextual info (current style + page count)
  and hover help for toolbar controls and placed images
- [x] Ruler **tab stops are document-global** now (apply to every paragraph +
  typing attributes), not just the selection — indents stay per-paragraph
- [x] Font-size control now applies to the selection (was reading a stale combo
  value at action time)
- [x] Saving forces the **`.luce`** extension via `prepareSavePanel` (needed when
  run unbundled, where the UTI isn't OS-registered)

## Notes / decisions taken during implementation
- **Dark Mode:** the document window is pinned to the light (aqua) appearance
  (`window.appearance`) — it's a white-paper editor, so this keeps toolbar
  controls, ruler labels, and the caret visible on the white page in Dark Mode.
  (Fix for on-device report of an invisible toolbar in Dark Mode.)
- **Narrow wrap columns:** if a placed image leaves a side gap too small to hold
  text, the exclusion is extended to that margin so text doesn't clip into a
  sliver (`PageMetrics.exclusionRect` `minColumn`, default 1"). Fix for on-device
  report of text being cut off to the right of an image.
- ZIP handled by an in-repo `MiniZip` (no external dependency) so the project
  builds offline; *stored* entries are sufficient because payloads are
  pre-compressed images plus tiny text.
- Cross-page selection limitation accepted for v1 (inherent to the shared
  layout-manager / multi-text-view pattern); documented in AGENTS.md.
