# PROGRESS.md — Lucerne implementation status

Live checklist for the Avenue A build. Updated as work lands. Legend:
`[x]` done · `[~]` partial / in progress · `[ ]` not started.

> **Verification:** authored on Linux (no Swift toolchain). Compilation is checked
> by the macOS CI workflow, not locally. **The macOS CI build + unit tests are
> green** as of the latest commit, so "done" means *implemented, compiling, and
> unit-tested* — pending interactive on-device QA on a Mac for the things tests
> can't cover (live reflow feel, ruler dragging, pagination across many pages).

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
- [x] **Printed table of contents** (Insert ▸ Table of Contents) — entries with
  right-aligned page numbers (converged via relayout), persisted as a `toc`
  paragraph style; re-run to update
- [ ] Editable header/footer click-zones, dotted ToC leaders, tables — `docs/roadmap.md`

## On-device feedback (round 7)
- [x] Custom About window with the app icon (replaces the stock panel)
- [x] Toolbar Bold/Italic/Underline are a segmented control now, so the selected
  ones take the accent color (matching alignment)
- [x] Crash/draft recovery via `NSDocument` autosave-in-place (untitled drafts are
  recovered on relaunch); saved docs restore via macOS Resume
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
