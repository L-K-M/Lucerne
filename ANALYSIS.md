# Lucerne forward analysis

This is the canonical live forward-work document for Lucerne as of 10 July 2026.
It consolidates the unresolved portions of `sol.md` and `fable-is-awesome.md`.
Those files remain the detailed historical audits; completed historical findings
belong there, not in this backlog.

The review environment is Linux without Swift, AppKit, or interactive macOS access.
Source-level findings have been traced through the code, and macOS CI covers builds
and unit tests, but rendering, responder-chain behavior, VoiceOver, performance
magnitude, and interaction quality still require on-device QA.

Effort uses **S** (hours to about one day), **M** (roughly 2-5 days), and **L**
(one or more weeks). Risk describes data-loss or architectural danger, not effort.

## Pending companion PRs (CI green, awaiting review/merge)

These PRs are open and their macOS build-and-test checks pass. They remain pending
review/merge, are not described as completed, and their fixes are deliberately not
duplicated in the unresolved backlog below.

| PR | Findings addressed | Scope boundary |
|---|---|---|
| [#41](https://github.com/L-K-M/Lucerne/pull/41) | Sample Letter cannot save because its referenced image has no payload (`sol.md` 1.1) | Bundles and seeds the sample image; adds a real save/open regression. |
| [#42](https://github.com/L-K-M/Lucerne/pull/42) | Negative/extreme object pages and list levels can reach unsafe indexing/arithmetic (`sol.md` 1.2) | Adds object/list bounds and guards. A general semantic validation/repair policy remains backlog. |
| [#43](https://github.com/L-K-M/Lucerne/pull/43) | Page Setup drops fold marks, reloads on no-op, and DIN marks use thirds rather than 105/210 mm (`sol.md` 1.12, 1.16) | Preserves fold marks, guards no-ops, and corrects geometry. Page-config undo and editing-context restoration remain backlog. |
| [#44](https://github.com/L-K-M/Lucerne/pull/44) | Applying a style removes direct run formatting; table rebuilds discard later paragraphs in a cell (`sol.md` 1.3, 1.4) | Preserves direct/structural attributes and aggregates multi-paragraph cells, with regressions. Other table limitations remain backlog. |
| [#45](https://github.com/L-K-M/Lucerne/pull/45) | RTF/DOCX/PDF conversion failures can be reported as successful empty or partial exports (`sol.md` 1.18) | Makes conversion/assembly fail safely and validates output before atomic replacement. |
| [#47](https://github.com/L-K-M/Lucerne/pull/47) | Markdown image references can break, zero CRC/false EOCD handling is incomplete, and failed saves advance in-memory history (`sol.md` 1.23, 1.25, 1.26) | Escapes image references, tightens ZIP integrity checks, and commits history transactionally. Aggregate extraction budgets remain backlog. |
| [#48](https://github.com/L-K-M/Lucerne/pull/48) | Delayed style color can target the wrong document, initial image fitting can distort, and page shadows lack a stable path (`sol.md` 1.11, 1.14; performance 3.2) | Flushes before retarget, aspect-fits with pure tested geometry, and caches rectangular shadow paths. Interactive Mac QA remains. |

Review these independently, keep their CI signal visible, and perform targeted Mac
QA before release. Do not re-open their implementation as generic future work unless
review rejects or materially changes the fix.

## Immediate priorities

### P0: editing and format integrity

| Work | Why it matters | Effort | Risk |
|---|---|---:|---:|
| Normalize rich paste and define a Lucerne fragment pasteboard type | RTF/HTML paste can display links, highlights, unsupported lists, and other attributes that canonical save or style reapplication silently removes. Normalize to the representable whitelist, mint paragraph IDs, disclose discarded formatting, then add a private lossless Lucerne fragment for cross-document copy/paste. | M/L | High |
| Preserve complete empty/trailing paragraph state | Trailing and wholly empty paragraphs can lose alignment, tabs, indents, spacing, page-break/table state, identity, dirty tracking, and undo. Empty table cells and forced-break paragraphs are the dangerous variants. | M | High |
| Guarantee paragraph ID uniqueness | Ordinary Return can inherit `.lucerneParagraphID`; paragraph splits and paste need fresh IDs, and snapshot should repair duplicates defensively. Stable unique IDs are required for anchoring and tooling. | S/M | High |
| Make page-break metadata edit-stable | The break lives on one disposable character; deleting/replacing the first character or inserting before it can desynchronize layout and persistence. Stamp/normalize across the paragraph and separator. | S/M | High |
| Decide format evolution and unknown-field preservation | v0.5 writes list metadata under `formatVersion: 1`; pre-v0.5 v1 writers may ignore and discard it on save. Unknown object members are also destroyed. Before the next semantic extension, choose a version/capability policy and either preserve unknown JSON or refuse destructive saves. | M/L | High |
| Provide document-wide command surrogates | Per-page text views make Command-A, copy, delete, and formatting feel page-local. True cross-page drag/Shift selection is L effort, but storage-relative Select All and command surrogates are expected word-processor basics. | M now, L full | High UX |
| Establish keyboard and accessibility foundations | Most classic custom controls expose no roles, labels, values, actions, children, focus rings, or keyboard operation. This blocks VoiceOver and Full Keyboard Access across the format bar, palettes, ruler, image handles, Welcome, and Navigator. | L | High |
| Establish trustworthy distribution/update identity | Releases are ad-hoc signed and not notarized; installation removes quarantine, and updates lack an independent signature/digest/application-identity check. Adopt Developer ID, hardened runtime, notarization/stapling, and a signed update channel or at minimum strict SHA-256/host/type/size verification. | M/L | High |

### P1: correctness and workflow reliability

- **Style typing state after stylesheet changes (S/M, medium).** Rebase typing
  attributes against the rebuilt paragraph while preserving direct caret formatting,
  trailing-list membership, and representable overrides.
- **Style Editor undo ordering (M, medium).** Seal a live style session before the
  first non-style text/undo transaction. Verify style-edit -> type -> undo/redo on a
  Mac.
- **Page Setup transaction remainder (M, medium).** Add model-level undo and restore
  global caret/selection, typing state, first responder, scroll anchor, and image
  selection after a real geometry change. The no-op/fold-mark portion belongs to
  pending PR #43.
- **Table vertical navigation (M, medium).** Up/Down should move by visual line
  inside a wrapped cell and change rows only at the first/last visual line.
- **Table width normalization (S/M, low-medium).** Equal-share columns currently
  materialize as explicit percentages after one model/storage round trip. Preserve
  `nil = equal share` and add an idempotent bridge test.
- **Table polish (M/L, medium).** Confirm page-boundary row behavior on-device;
  support rows taller than a page if TextKit permits; keep merges through structural
  row/column edits; and expose table/list semantics accessibly.
- **Header/footer collision handling (M, medium).** Allocate collision-aware zones
  or measured truncation priorities and add a compact live preview.
- **List interchange (M, medium).** Custom-drawn markers do not exist in exported
  attributed strings, so RTF/DOCX lose bullets and numbers. Materialize standard
  semantics or literal markers and verify nesting/start values.
- **Corrupt-image recovery (M, medium).** Keep `document.json` strict but open intact
  body text when referenced or unreferenced image entries are corrupt/oversized;
  show placeholders and a warning.
- **Paragraph anchors (M/L, medium).** The model/spec describe paragraph anchoring,
  but the app renders only page anchors. Either implement resolution or mark the v1
  form reserved/unsupported while preserving it.
- **Style-library failure UI (M, medium).** Expose corrupt/future/permission errors
  as a read-only state, disable mutation/export, offer Reveal/Back Up/Reset, and make
  library export atomic.
- **Archive extraction budgets (M/L, medium-high for untrusted files).** Add
  aggregate compressed/uncompressed budgets and entry-count limits, and extract only
  required entries instead of inflating every unknown payload. CRC-zero and EOCD
  structure tightening belong to pending PR #47.
- **Document-wide spelling state (S/M, low-medium).** Confirm on-device whether the
  standard toggle affects only the focused page; if so, store one editor-level flag
  and apply it to every page text view.

## Engineering and architecture debt

- **Add semantic model validation (M/L, high).** Codable checks shape, not meaning.
  Define one validation/repair policy for page dimensions and margins, finite
  geometry, IDs, table grids/spans/widths, furniture start pages, object types, and
  all bounded indexes. Share it across open, scripting, stationery, and third-party
  conformance tests. Object/list bounds in pending PR #42 are the first slice, not
  the whole policy.
- **Extract tested seams from `EditorController` (incremental, medium).** Do not split
  it for line count. Extract coherent collaborators when tests demand them: paste
  normalization and export preparation are strong seams; table parsing/rebuild may
  follow after pending PR #44. Keep geometry/list numbering pure.
- **Treat page configuration as one transaction (M, medium).** Synchronize document
  and print state through complete old/new snapshots, undo, and context restoration,
  rather than view teardown side effects.
- **Own the obligations of custom list rendering (M/L, medium).** Markers need
  accessibility and interchange semantics; fixed 24-point gutters can be too narrow
  for large decimal/Roman labels; applying lists replaces displaced direct indents;
  marker resolution needs generation-based caching.
- **Make release assembly fail closed (M, high distribution risk).** Icon/signing,
  SDEF, and DMG failures must stop publication. Extract/mount and validate all
  published bundles, and make release checks at least as strict as CI.
- **Pin supply-chain inputs (S/M, medium).** Pin GitHub Actions and packaging tools,
  require a known Xcode, and isolate read-only build permissions from publication.
- **Replace raw selector strings or test them (M, medium).** `MainMenu.add` remains
  compile-unchecked. Prefer `#selector`, or walk the menu in no-document, text,
  image, list, and table states in macOS CI.
- **Cover the app shell (M/L, medium).** Add launch, menu reachability, lifecycle/
  save-review, SDEF execution, updater fixtures, and assembled-app smoke tests.
- **Remove/isolate private `_cornerMask` (S/M, distribution risk).** Its visual gain
  is small, future AppKit behavior is uncertain, and it is unsuitable for App Store
  review. Keep a tested public fallback if retained outside distribution builds.
- **Ship product Help (M, medium UX).** Replace repository/build-centric Help with a
  two-minute guide covering writing, images, lists/tables, styles, versions,
  stationery, recovery, and shortcuts.
- **Prevent documentation drift (process, low effort).** Feature landing must update
  the model contract, both format docs/schema, architecture, progress, roadmap or
  this file, tests, user help, and screenshots together.

## Performance and stuttering backlog

Measure 25-, 100-, and 250-page fixtures before restructuring. Letters-scale
performance is likely acceptable; these are risks for long lists, large tables,
image-heavy stationery, scrolling, and autosave.

| Priority | Path and action | Effort/risk |
|---|---|---|
| P1 | Scroll bounds changes currently trigger chrome synchronization plus all-page canvas layout. Separate ruler/status updates from structural page-frame layout. | M / medium ordering risk |
| P1 | Formatting commands relayout synchronously and then again through the deferred storage delegate. Coalesce by edit generation or make one path authoritative. | M / needs Mac QA |
| P1 | Every edit scans page breaks, forces final layout, updates exclusions/images/stacking/pages/furniture broadly. Instrument phases; cache page breaks/objects/furniture and skip image sync for pure text edits where safe. | M/L / high change risk |
| P1 | Long-list marker drawing repeatedly scans from the list start, approaching quadratic work. Cache resolved markers by storage generation and invalidate from the edited item. | M / medium |
| P1 | Saves/autosaves snapshot, export Markdown, CRC images, and build the full ZIP in memory on the main thread. Capture AppKit state on main, reuse one Markdown rendering, then archive/write asynchronously; consider streaming. | L / concurrency risk |
| P1 | Full-resolution image load/decode and resize drawing run on main. Validate/decode off-main and cache display-size representations with a lower-quality live-resize preview. | M/L / image fidelity risk |
| P2 | Table ruler state reparses the current table on each caret move. Cache by table identity and storage generation. | M / low |
| P2 | Style Editor counts every paragraph of a role on each caret move. Cache role counts by text/attribute generation. | S/M / low |
| P2 | Selection changes refresh the full toolbar/ruler and some setters redraw unchanged values. Diff one immutable UI-state snapshot before assignment. | M / low |
| P2 | Every page view remains resident. Profile first; virtualize expensive decoration/image rendering before disturbing required TextKit containers. | L / high architecture risk |
| P3 | CI has no SPM cache. Re-evaluate only if macOS time becomes material; toolchain cache invalidation may erase the gain. | S / low |

## UX, accessibility, and visual work

- **Mixed/custom formatting honesty (M).** Show mixed selection states, preserve
  decimal font sizes, and display Custom for non-preset line spacing instead of a
  stale prior value.
- **Welcome/Navigator keyboard behavior (S/M).** Return/Space should activate the
  selected recent/heading; provide a default New action, initial responder, and
  semantic heading indentation.
- **No-document palette states (S).** Typefaces, Lists, Styles, and footer actions
  must consistently say "No letter open" and disable operations that would no-op.
- **Style Editor quiet state (S/M).** Clear/ghost stale target values, disable every
  field including size, represent missing fonts explicitly, and call the capped
  specimen a compact preview rather than exact print output.
- **Picker preview/commit contract (S/M).** Filtering must select/preview a
  deterministic candidate and explain Return, Esc, and click-away behavior.
- **Ruler interaction (M/L).** Add live preview, Esc-to-revert, cursors/hover,
  right-click tab type, keyboard adjustment, unit-aware readout, and pixel alignment
  at arbitrary zoom.
- **Blank paper margins (S/M).** Route side-margin clicks to the nearest body text
  position; reserve explicit top/bottom furniture zones for future in-place editing.
- **Consistent utility-window language (M).** Keep native accessible controls but
  apply a shared spacing, typography, etched-section, and button hierarchy to Find,
  Settings, About, alerts, and sheets.
- **Narrow-window strategy (M/L).** Replace the wide minimum-window workaround with
  a compact mode or period-appropriate overflow well; menus must retain every
  command under localization and accessibility text.
- **Image object ticket (L).** Add exact x/y/size, aspect lock, crop/rotate, wrap,
  standoff, align/distribute, guides/snapping, z-order, duplicate/copy, and standard
  context commands when an image is selected.
- **Navigation feedback (M).** Highlight current heading/page, add a useful empty
  navigator state, and consider page thumbnails for heading-free letters.
- **Update download feedback (S/M).** Render progress/cancel/error state instead of
  exposing `isDownloading` only internally.
- **Copy Style / Paste Style (M).** Add the expected commands after checking the
  multi-page focus and supported-attribute contract on-device.

## Missing capabilities

### P1: letter-writing workflows

1. **Import plain text and Markdown (M), then RTF/DOCX (L).** Imports need explicit
   fidelity reporting and format/UTI wiring verified on-device.
2. **Editable headers/footers (M).** Click into top/bottom margin zones and edit the
   existing three-zone model in place.
3. **Document Info (S/M).** Words, characters, paragraphs, pages, images, created,
   modified, language, and estimated reading time.
4. **Visible version history (M).** Preview/diff existing archive snapshots, Copy,
   Restore as New, and reveal the raw entry.
5. **Envelope presets and proofing (M/L).** Add DL/#10 page presets, address-window
   placement, corrected DIN guides, and a print workflow.

### P2: bounded word-processing depth

1. **Strikethrough and superscript/subscript (M)** with explicit model and export
   behavior.
2. **Hyperlinks (M/L)** including PDF annotations if links are promised beyond
   screen/RTF output.
3. **Paragraph before/after spacing controls and Copy/Paste Style (M).** The model
   exists; expose predictable direct formatting.
4. **Language per document/selection and document-wide spelling state (M/L).**
5. **Paragraph-anchored objects (M/L), irregular alpha wrap (L), and image overhang
   (M).** Keep page anchoring and rectangular wrap as the supported baseline.
6. **Page thumbnails and richer outline navigation (M/L).**
7. **Floating text boxes (L).** This is a real placed-object format extension and
   must follow the version/unknown-field decision.
8. **Sections only for a demonstrated need (L).** First-page furniture or mixed
   numbering may justify them; avoid general Word-style section complexity.

Explicitly avoid collaboration, comments/change tracking, cloud accounts, plugin
systems, a ribbon/inspector maze, per-page paper sizes, replacing TextKit 1 merely
because TextKit 2 is newer, or turning image controls into a general drawing app.

## Product ideas

Ordered by fit and reuse of shipped machinery.

1. **Wrap X-ray (S/M).** Ghost the actual exclusion path, including standoff and
   narrow-column extension; Option can reveal it continuously while dragging.
2. **Magnetic image guides (M).** Snap to margins, center, furniture baselines, fold
   marks, and object edges with live x/y readout; Option bypasses snapping.
3. **Signature Shelf (S/M).** Reuse Application Support storage to insert original,
   unmodified signature images with scale presets and wrap-none placement.
4. **Correspondent Card and envelope proof (M/L).** Add optional sender/recipient
   fields and tokens, address-window/safe-region overlays, and stationery integration.
5. **Visible version browser (M).** Make the archive recovery promise discoverable
   with date list, preview, diff, Copy, and Restore as New.
6. **Ink Desk (S/M).** Five accessible recent/favorite named swatches: blue-black,
   sepia, graphite, deep red, and black.
7. **Tab Laser (S).** Draw a unit-aware vertical guide while dragging a tab, indent,
   or table divider.
8. **Stationery gallery (M).** Add restrained thumbnails for Blank Letter, recent
   stationery, and Manage Stationery, rendered through the page/PDF pipeline.
9. **Quick Format Book (M).** A searchable keyboard specimen combining styles,
   typefaces, and list markers with used/favorite sections.
10. **Page edge notes (L).** Optional non-printing drafting notes in the canvas;
    requires a format decision after unknown-field preservation.
11. **Typewriter mode (S/M).** Optional restrained key clicks and margin bell, never
    document state, with a silent-hours setting.
12. **Letter ritual mode (M).** Insert date, salutation position, and closing/
    signature prompts learned per stationery, without becoming mail merge.
13. **Paper personality (S/M).** Non-printing warm/cool/proof canvas appearances;
    print/PDF remain white and accessibility settings override texture.

## Test and QA plan

### Automated regressions still needed

1. Paragraph-ID uniqueness after ordinary Return, split, list continuation,
   heading demotion, page break, and normalized paste.
2. Empty/sole/trailing paragraph matrix covering style, alignment, tabs, spacing,
   page break, table cell, list, ID, dirty state, and undo.
3. Rich-paste fixtures containing every supported and unsupported attribute, plus
   Lucerne-fragment cross-document round trips.
4. Page-break stability when inserting, deleting, or replacing at paragraph start.
5. Full semantic-validation fixtures: non-finite geometry, impossible margins,
   duplicate IDs, table coordinates/spans/widths, furniture starts, and unknown
   objects, in addition to pending PR #42's object/list bounds.
6. Corrupt/oversized image entries opening intact body text with placeholders.
7. ZIP aggregate limits, entry count, duplicate names, local/central disagreement,
   selective extraction, and a real external DEFLATE fixture. CRC-zero and
   EOCD-in-comment coverage belongs to pending PR #47.
8. List-schema golden files, pre-v0.5 v1 downgrade behavior, and the eventual
   version/capability migration decision.
9. RTF/DOCX list preservation, including nesting, mixed marker formats, and starts.
10. Style-library corrupt/future/permission-denied UI behavior.
11. Canonical color, tab-stop, page-break, table equal-width, list, and empty-field
    model/storage round trips.
12. Menu action reachability and plist/SDEF validation from the assembled app.

### On-device matrix

1. Ventura through the current macOS release; Intel if supported; Retina and
   non-Retina scaling; system light/dark settings despite Lucerne's aqua choice.
2. VoiceOver and Full Keyboard Access for New -> type -> format -> list/table ->
   place image -> save/export.
3. Increase Contrast, Reduce Transparency, reduced motion, and large accessibility
   display settings.
4. 25/100/250-page scroll FPS and caret latency; long numbered lists; large tables;
   image-heavy save/autosave; PDF/RTF/DOCX export.
5. Page boundaries: document-wide commands, find reveal, tables, lists, page breaks,
   image drag, zoom, and print.
6. Multiple documents with global palettes, Style Editor, delayed color updates,
   smart substitutions, spelling, update alerts, save sheets, and quit review.
7. Clean-Mac ZIP/DMG install, Gatekeeper, update download/progress, offline/error
   paths, and altered-artifact rejection after signing work lands.

## Recommended sequence

1. Review and QA companion PRs #41-45 and #47-48; release their bounded fixes.
2. Resolve format evolution/unknown preservation, rich paste, paragraph identity,
   empty/trailing state, page-break stability, and document-wide commands.
3. Build accessible keyboard behavior and trustworthy signed distribution before
   expanding the format again.
4. Instrument long documents, then remove scroll-time all-page layout, duplicate
   relayout, list/table/style scans, and main-thread archive/image work.
5. Add letter-specific depth and delight: Help/history, editable furniture, object
   ticket, Wrap X-ray, magnetic guides, and envelope/signature workflows.

## Architecture constraints

- Keep one `NSTextStorage`, one TextKit 1 `NSLayoutManager`, and identical per-page
  `NSTextContainer`s. Do not migrate to TextKit 2 without a measured requirement.
- Keep one document-wide page size and margins; no per-page paper geometry.
- Keep the model canonical for structure and live text storage canonical while
  editing. Preserve `.lucerne*` attributes across every bridge/rebuild operation.
- Keep floating objects page-relative with top-left/y-down coordinates; convert only
  at view/container boundaries through `PageMetrics`.
- Keep `document.json` authoritative; Markdown/history are derived recovery lanes,
  PDF is visual fidelity, and RTF/DOCX are explicitly lossy interchange.
- Keep body structure flat. Tables use consecutive `Paragraph.cell` descriptors;
  lists use consecutive `Paragraph.list` descriptors. Visible list markers remain
  derived, never canonical text.
- Keep style roles independent from table/list membership and preserve representable
  direct formatting when styles are changed or reapplied.
- Prefer pure, testable model/layout helpers. Extract collaborators only around
  coherent behavior and tests, not to reduce line count.

---

# Phase 1 review consolidation (chonk.md, 2026-10-30)

Findings from the three-repo review (Lucerne, Sion at L-K-M/Sion, Rigi) that are
**not** yet implemented. Every blocking and important finding from that review is
implemented in an open PR (Lucerne #58-62, Sion #89-97, Rigi #4-6) and is therefore
not repeated here; see those PRs for verification notes. Paths are repo-qualified.
Remaining entries below are nice-to-have, ordered by value within each focus area.

## Bugs

### Mermaid arrow matched inside labels
bugs — nice-to-have
`Sion/Sources/SionCore/Import/MermaidImporter.swift:225-231` scans for the arrow
from column 0, so `A|"-->"|--> B` is rejected as unrecognized instead of parsed
as a link. Suggested fix: scan for the arrow after the parsed source node. Effort S.

### Newlines inside run text corrupt the recovery Markdown
bugs — nice-to-have
`Lucerne/Sources/LucerneCore/Model/MarkdownExporter.swift` passes `"\n"` through
`escape()` and `blockEscape` inspects only the first line, so a run `"a\n# b"`
exports a real heading and newlines split GFM table rows and list items in
`content.md` and every `history/` snapshot. Suggested fix: flatten/escape newlines
in `inlineMarkdown`. Effort S.

### Colliding or out-of-range table cells vanish from Markdown export
bugs — nice-to-have
`Lucerne/Sources/LucerneCore/Model/MarkdownExporter.swift:133-138` silently
overwrites duplicate coordinates and drops out-of-range cells. Suggested fix:
fall back to plain paragraph blocks and signal the loss. Effort S.

### Windowless Sion save writes no preview
bugs — nice-to-have
`Sion/Sources/SionKit/Document/SionDrawingDocument.swift:156-161` renders a preview
only via the first window; windowless autosave/revert skips it though
`SionSceneRenderer` exists. Suggested fix: fall back to renderer-backed preview.
Effort S. Needs on-device QA.

### Rigi ClassicPopUp menu may pop above its control
bugs — nice-to-have
`Rigi/Sources/RigiUI/ClassicControls.swift:464` pops at `y: bounds.height + 1` on a
non-flipped control (compare ClassicSizeField's deliberate `y: 0`). Verify visually
on a Mac, then use `y: 0`. Effort S.

### MainActor.assumeIsolated in nonisolated Sion document IO
bugs — nice-to-have
`Sion/Sources/SionKit/Document/SionDrawingDocument.swift:177-229` crashes if AppKit
ever calls these off-main. Suggested fix: hop to the main actor explicitly. Effort S.

### Sion history filename collisions can drop a revision
bugs — nice-to-have
`Sion/Sources/SionCore/Archive/SionArchive.swift:332-344` keys `history/` entries by
timestamp + 12-hex prefix; a collision silently overwrites. Suggested fix: detect
and extend the prefix. Effort S.

## General issues

### ClassicWindow does not pin the Aqua appearance itself
theming — nice-to-have
`Rigi/Sources/RigiUI/ClassicControls.swift:924-950` relies on each app setting
`window.appearance = .aqua`. Suggested fix: set it in `init`. Effort S.

### document.json parsed twice on open
performance — nice-to-have
`Lucerne/Sources/LucerneCore/Model/DocumentCoding.swift:67-77` runs a version probe
decode plus the full model decode. Suggested fix: single decode + post-hoc version
check. Effort S.

### Non-throwing MiniZip.archive returns empty Data on failure
general — nice-to-have
`Lucerne/Sources/LucerneCore/IO/MiniZip.swift:56-61` turns an "impossible" throw
into a valid-looking empty archive. Suggested fix: delete the overload or
`preconditionFailure`. Effort S.

### Raw selector strings and README-as-Help in Lucerne
general — nice-to-have
`Lucerne/Sources/Lucerne/MainMenu.swift:34-43` builds `Selector(selector)` unchecked;
`AppDelegate.swift:162-165` opens the GitHub README as Help. Suggested fix:
`#selector` + menu-walk test; a product Help book. Effort S-M. Needs on-device QA.

## Performance problems, stuttering, and jank

### Sion object snap scans the whole scene per mouse-move
performance — nice-to-have
`Sion/Sources/SionKit/Canvas/SionCanvasView.swift:2566-2589` rebuilds rotated bounds
for every visible element per `mouseDragged`; the spatial index in
`SceneRenderContext` exists but is unused here. Suggested fix: viewport-cull and use
the index. Effort M. Needs on-device QA.

### Per-keystroke whole-document work in Lucerne
performance — nice-to-have
`EditorController.swift:260-269, 225-251, 2478-2503, 586`, scroll-driven all-page
layout (`DocumentWindowController.swift:496-506`), double relayout per formatting
command, quadratic list-marker scans (`ListMarkerLayoutManager.swift:37-61`),
full-resolution image decode/draw on the main thread. Suggested fix: cache by edit
generation, index objects by page, coalesce relayout, decode off-main. Effort M-L.
Needs on-device QA.

### Rigi hot draw paths allocate per frame
performance — nice-to-have
`Rigi/Sources/RigiUI/ClassicControls.swift:51-69, 180-202` builds NSGradients and
attributed strings per draw. Suggested fix: cache the six bezel gradients and glyph
strings. Effort S.

### Connector route resampling recomputed per call
performance — nice-to-have
`Sion/Sources/SionCore/Geometry/ConnectorRouting.swift:150-230` resamples 24 points
per curve segment on every `point(atFraction:)`/`polylinePoints` call (per connector
label per frame and per export). Suggested fix: lazily cache the sampled polyline.
Effort S.

### Sion per-command O(n) scans and whole-scene validation per transaction
performance — nice-to-have
`Sion/Sources/SionCore/Editing/SceneCommand.swift`, `SceneEditor.swift:180-195` run
per-pointer-sample during gestures. Suggested fix: revision-scoped ID index,
incremental validation, change sets. Effort L.

## Missing features

### Rigi status bar has no hover-help API
missing feature — nice-to-have
`Rigi/Sources/RigiUI/StatusBarView.swift:24-26` exposes only `message`, but
`docs/interface-guidelines.md:45` promises hover help. Suggested fix:
`setHoverMessage(_:)` with tracking in the view. Effort S.

### Document-wide Select All / copy / delete are page-local in Lucerne
usability — nice-to-have (large)
`Lucerne/Sources/Lucerne/MainMenu.swift:126-132` targets the first-responder page
view only. A storage-relative surrogate is M effort; true cross-page drag selection
is L. Needs on-device QA.

### Ordinary Return duplicates .lucerneParagraphID
bugs — nice-to-have
`Lucerne/Sources/LucerneKit/Text/PageTextView.swift:83-90` lets Return inherit the
old paragraph ID, so both halves of a split save with the same ID. Suggested fix:
mint a fresh ID per split + defensive dedupe in `snapshotModel`. Effort S-M. Needs
on-device QA.

### Sion nudge keypresses each create an undo entry
usability — nice-to-have
`Sion/Sources/SionKit/Canvas/SionCanvasView.swift:646-655` ->
`SionEditorController.swift:1030-1035`; holding an arrow floods Undo. Suggested fix:
coalesce same-direction nudges within a short window. Effort M. Needs on-device QA.

### Repeated paste stacks exactly on top of itself in Sion
usability — nice-to-have
`Sion/Sources/SionKit/Canvas/SionCanvasView.swift:923-948` always pastes at the
visible canvas center. Suggested fix: cascade offset or pasteboard-identity
tracking. Effort S.

## Visual issues and layout problems

### Header/footer zones paint over each other
visual — nice-to-have
`Lucerne/Sources/LucerneKit/Views/PageContainerView.swift:99-116` draws all three
zones into one full-width rect with tail truncation; long left+center strings
overlap. Suggested fix: three measured columns with truncation priority. Effort S-M.
Needs on-device QA.

### Rigi segmented-control geometry leaves an unpainted strip
visual — nice-to-have
`Rigi/Sources/RigiUI/ClassicControls.swift:328-364` outlines all of `bounds` while
segments sum `widths`, and separator phases differ from
`ClassicNativeControls.swift:38-41`. Suggested fix: clip to bounds, round
boundaries, unify phase. Effort S.

### Fixed 24 pt list gutters overprint text for wide markers
visual — nice-to-have
`Lucerne/Sources/LucerneCore/Model/ListSupport.swift:18-31` +
`LucerneKit/Text/ListMarkerLayoutManager.swift:119-128`: a wide "1000." marker at
level >= 1 spills over item text. Suggested fix: measure the marker and widen the
gutter per level. Effort S-M. Needs on-device QA.

## Usability: is the interface fast, convenient, and clear?

### Custom controls are unreachable by keyboard and unlabeled for VoiceOver
usability — nice-to-have (large)
Rigi's hand-drawn controls (`ClassicControls.swift`, `StatusBarView.swift`) are
mouse-only with no focus rings or AX labels, contradicting
`Rigi/docs/interface-guidelines.md:55,64-66,122-131`; same for Lucerne's
ruler/palette/image handles and Sion's canvas (single AX group,
`SionCanvasView.swift:154-156,2952-2973`). Suggested fix: acceptsFirstResponder +
keyDown + AX roles/labels + focus rings; element-level canvas AX. Effort M-L. Needs
on-device QA.

### Find panel recounts the whole document on every Cmd-G
usability — nice-to-have
`Lucerne/Sources/LucerneKit/Views/FindPanelController.swift:175-194, 215-245` is
O(n*matches) per Find Next. Suggested fix: cache the count per (query, storage
generation). Effort S. Needs on-device QA.

### Welcome/Navigator not keyboard-operable; palettes active with no document
usability — nice-to-have
`Lucerne/Sources/Lucerne/WelcomeWindowController.swift:103,185-188`,
`NavigatorView.swift:64-68,83`, `FloatingPalette.swift:243-303` (only the Styles
palette goes inert with no letter open). Suggested fix: Return activation, initial
responder, semantic indentation, inert state for all palettes. Effort S-M. Needs
on-device QA.

### Ruler commits only on mouse-up
usability — nice-to-have
`Lucerne/Sources/LucerneKit/Views/LucerneRulerView.swift:258-334` applies via a full
table rebuild on mouse-up only. Suggested fix: live preview + Esc-revert + arrow-key
adjustment. Effort M. Needs on-device QA.

## Aesthetics and theming

### No dark-mode story; apps pinned to light Aqua
theming — nice-to-have (product decision)
`Sion/Sources/SionKit/Document/SionDocumentWindowController.swift:75` and Lucerne's
matching pin. Deliberate for Rigi-classic consistency; decide, then theme tokens.
Effort M+.

### Utility windows mix chrome styles
visual — nice-to-have
Lucerne About/Settings/Find use stock NSWindow/NSPanel vs ClassicWindow documents;
Rigi's gallery torn-off palette lacks autosave/title
(`Rigi/Sources/RigiGallery/GalleryPalettes.swift:65-80`). Suggested fix: shared
utility-window skin; gallery parity. Effort S-M. Needs on-device QA.

## Novel, delightful, or quirky ideas worth trying

### Lucerne: live x/y/w/h of a dragged image in the status bar
delight — nice-to-have
The `onStatusHint` channel already exists (`EditorController.swift:2391`); cheap
precursor to magnetic guides. Effort S.

### Lucerne: coalesce arrow-key image nudges into one undo group
delight — nice-to-have
`FloatingImageView.swift:250-255` commits one "Move Image" per keypress. Effort S.

### Sion: overlap click-cycling, tool shortcuts, snap-to-grid, snap flare, zen mode
delight — nice-to-have
Cheap delights on existing affordances (`SionCanvasView`, `SceneSnapping`): cycle
overlapping selections on repeated click, V/R/O/T/C tool shortcuts, a snap-to-grid
toggle, a flare when a connector endpoint enters snap radius, and Cmd-. dimming of
non-selected objects. Effort S-M each.

### Rigi: per-segment tooltips and gradient-cached hover animation
delight — nice-to-have
Per-segment tooltips on `ClassicSegmentedControl` that preview alignment live;
caching the six bezel gradients (above) also enables a cheap hover "breathe" on the
active segment. The private-API corner-mask fallback (`ClassicControls.swift:936`)
is deliberately kept. Effort S-M.
