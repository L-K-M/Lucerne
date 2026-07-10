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
- **Delayed style color retargeting (S, medium).** Flush the 250 ms pending color
  change before switching target documents so an event is neither lost nor applied
  to the wrong letter.
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
- **Aspect-preserving image insertion (S, medium).** Fit extreme portrait images
  with one scale factor rather than independently clamping width and height.
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
- **Markdown image-path escaping (S, low-medium).** Escape alt text and encode or
  angle-bracket destinations so `]`, `)`, slashes, whitespace, Unicode, backslashes,
  and newlines cannot corrupt the recovery artifact.
- **Archive parser hardening (M/L, medium-high for untrusted files).** Add aggregate
  compressed/uncompressed budgets and entry-count limits, extract only required
  entries, always validate CRC (including expected zero), and validate EOCD comment
  length/end position.
- **Save history transactionality (S, low).** Assign candidate history only after
  archive generation succeeds; failed saves must not leave phantom snapshots.
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
| P2 | Give each page layer a stable rectangular `shadowPath` and profile offscreen rendering. | S / low |
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
7. ZIP aggregate limits, entry count, expected CRC zero, EOCD-in-comment, duplicate
   names, local/central disagreement, and a real external DEFLATE fixture.
8. List-schema golden files, pre-v0.5 v1 downgrade behavior, and the eventual
   version/capability migration decision.
9. RTF/DOCX list preservation, including nesting, mixed marker formats, and starts.
10. Markdown image names with brackets, parentheses, spaces, slashes, Unicode,
    backslashes, and newlines.
11. Style-library corrupt/future/permission-denied UI behavior.
12. Canonical color, tab-stop, page-break, table equal-width, list, and empty-field
    model/storage round trips.
13. Menu action reachability and plist/SDEF validation from the assembled app.

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

1. Review and QA companion PRs #41-45; release their bounded correctness fixes.
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
