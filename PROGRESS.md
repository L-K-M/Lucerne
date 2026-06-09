# PROGRESS.md — Lucerne implementation status

Live checklist for the Avenue A build. Updated as work lands. Legend:
`[x]` done · `[~]` partial / in progress · `[ ]` not started.

> **Verification:** authored on Linux (no Swift toolchain). Compilation is checked
> by the macOS CI workflow, not locally. "Done" here means *implemented and
> internally consistent*, pending a green CI build and on-device QA on a Mac.

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
- [ ] RTF / DOCX lossy export

## Milestone 3 — polish (later)
- [ ] Cross-page text selection
- [ ] Image overhang at page boundary (currently clipped)
- [ ] Irregular wrap from image alpha
- [ ] Lists (numbering / nesting)
- [ ] Document inspector (page size, margins) UI
- [ ] Preferences

## Notes / decisions taken during implementation
- ZIP handled by an in-repo `MiniZip` (no external dependency) so the project
  builds offline; *stored* entries are sufficient because payloads are
  pre-compressed images plus tiny text.
- Cross-page selection limitation accepted for v1 (inherent to the shared
  layout-manager / multi-text-view pattern); documented in AGENTS.md.
