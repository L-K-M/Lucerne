# Lucerne forward analysis

Canonical unresolved work, consolidated on 2026-11-02 from the earlier analysis,
`sol.md`, `fable-is-awesome.md`, the three-repository review, and Solution 2.
Implemented work, including fixes in open PRs, is omitted. Open does not mean
merged or approved; implementation and verification belong to the relevant PR.
Historical audits remain historical, not duplicate live backlogs.

Solution 2 reviewed Lucerne source and ran 108 Swift core tests and all 10 Qt
suites on Linux. AppKit interaction, VoiceOver, real printers, and measured Mac
scrolling/typing latency remain unverified. Cross-repository Sion/Rigi findings
below are retained from the earlier analysis, not re-audited here.

Effort: **S** = hours to one day; **M** = roughly 2-5 days; **L** = weeks.
Earlier P0/P1 integrity priorities retain their stronger severity where a later
review described the same issue as optional. Performance risks need measurement,
not assumed frame-rate claims. Paths without a repository prefix are Lucerne paths.

## Important

### Normalize rich paste before it becomes canonical

bugs — important

RTF/HTML paste can display links, highlights, unsupported lists and attributes
that saving or style reapplication later removes. Cross-document copy also lacks
a lossless Lucerne fragment contract.

Normalize to representable attributes, mint paragraph IDs, disclose discarded
formatting, and add a private fragment pasteboard type. Test supported/unsupported
attributes and cross-document round trips. Effort M/L; data-preservation risk high.

### Preserve complete empty and trailing paragraph state

bugs — important

`Sources/LucerneKit/Text/AttributedStringReader.swift:18,35-65` cannot reconstruct
all empty/trailing paragraph overrides. Alignment, tabs, indents, spacing,
page-break/table state, identity, dirty tracking and undo can be lost. Empty cells
and forced-break paragraphs are the dangerous cases.

Carry the full representable state through builder, typing attributes, reader and
undo. Test sole, empty and trailing paragraphs across all fields. Effort M; risk high.

### Ordinary Return duplicates paragraph IDs

bugs — important

`Sources/LucerneKit/Views/PageTextView.swift:83-90` permits an ordinary split to
inherit `.lucerneParagraphID`. Both halves can save with the same ID, undermining
paragraph anchors and tooling.

Mint IDs on splits/paste and deduplicate defensively in `snapshotModel`. Test
ordinary Return, split, list continuation, heading demotion, page break and paste.
Effort S/M; needs Mac interaction QA.

### Make page-break metadata edit-stable

bugs — important

The break is carried by a disposable character. Deleting/replacing the first
character, or inserting before it, can separate layout behavior from saved state.

Normalize break metadata across the paragraph and separator. Test insertion,
deletion and replacement at paragraph start. Effort S/M; risk high.

### Define format evolution and unknown-field preservation

general issues — important

Lists were added under `formatVersion: 1`; older v1 writers can discard them.
Unknown object members are also destroyed on save. This threatens interchange
before any further semantic extension.

Choose version/capability rules and preserve unknown JSON or refuse destructive
saves. Add downgrade/list-schema golden tests. Apply the decision before text
boxes, sections or other format extensions. Effort M/L; risk high.

### Make Mac commands document-wide

usability — important

`Sources/Lucerne/MainMenu.swift:126-132` targets the first-responder page view.
Command-A, copy, delete and formatting do not consistently behave like commands
on one document; full cross-page drag/Shift selection remains a documented gap.

Provide storage-relative command surrogates first. Prove focus, copy, deletion,
formatting and find/reveal across page boundaries before unifying selection.
Effort M for surrogates, L for full selection; Mac QA required. Includes S2-19.

### Establish keyboard and accessibility foundations

usability — important

Classic controls lack complete roles, labels, values, actions, focus rings and
keyboard behavior. This affects the format bar, palettes, ruler, images, Welcome
and Navigator. `linux/src/app/PageCanvas.h` also lacks an accessible text interface.
Rigi's controls conflict with its interface guidelines at lines 55, 64-66 and
122-131; Sion's canvas exposes one group (`SionCanvasView.swift:154-156,2952-2973`).

Audit VoiceOver/AT-SPI output; add semantic text/object children, actions and
keyboard alternatives. Fix shared controls in Rigi, not local copies. Test the
New → write → format → list/table → image → save workflow with assistive tools.
Effort L. Includes S2-20.

### Establish signed distribution and update identity

general issues — important

Mac releases are ad-hoc signed and not notarized; installation requires removing
quarantine. Download-integrity work does not establish an independent publisher
signature or application identity.

Adopt Developer ID, hardened runtime, notarization/stapling and a signed update
channel with application-identity checks. Verify clean-Mac installation, offline
errors and altered-artifact rejection. Effort M/L; distribution risk high.

### Rebase typing state after stylesheet changes

bugs — important

Rebuilding styled storage can leave caret typing attributes based on the old
paragraph rather than the new definition.

Rebase typing attributes while preserving direct caret formatting, trailing-list
membership and representable overrides. Effort S/M; risk medium.

### Seal Style Editor sessions before unrelated undo transactions

bugs — important

A live style-edit session can remain open when a text transaction begins,
compromising undo ordering.

Seal the session before non-style text/undo work. Verify style-edit → type →
undo/redo on a Mac. Effort M; risk medium.

### Treat Page Setup as a complete transaction

bugs — important

Real geometry changes still need model-level undo and editing-context restoration;
view teardown is not a transaction. Fold-mark preservation and no-op handling are
already implemented and are not backlog.

Snapshot document/print configuration together. Restore global caret/selection,
typing state, responder, scroll anchor and image selection through undo/redo.
Effort M; risk medium.

### Navigate wrapped table cells by visual line

bugs — important

`Sources/LucerneKit/Views/PageTextView.swift:29-37` intercepts Up/Down for row
movement even when a cell contains several visual lines.

Move within the cell first; change rows only at the first/last visual line.
Effort M; needs Mac QA.

### Preserve implicit equal-share table widths

bugs — important

Equal-share columns become explicit percentages after a model/storage round trip,
changing the authored representation.

Preserve `nil = equal share` and add an idempotent bridge test. Effort S/M;
risk low-medium.

### Recover intact prose when image payloads are damaged

bugs — important

Corrupt or oversized image entries can prevent opening otherwise intact body text,
even when an image is unreferenced.

Keep `document.json` strict; recover body text with image placeholders and a
warning. Test referenced/unreferenced corrupt and oversized payloads. Effort M.

### Give broken style libraries a recoverable read-only UI

usability — important

Persistence error reporting alone does not define a safe UI for corrupt, future
or unreadable libraries. Mutation/export controls and recovery actions need a
consistent contract.

Disable unsafe mutation/export, offer Reveal/Back Up/Reset, and keep library
export atomic. Test corrupt/future/permission-denied states. Effort M.

### Complete semantic validation beyond numeric bounds

general issues — important

Bounded indexes and geometry do not establish unique IDs, valid table topology,
noncolliding cells, furniture-start rules, supported object semantics or a unified
repair policy across open, scripting and stationery.

Define validation versus repair at each entry point. Share conformance tests for
IDs, grids/spans/widths, furniture, unknown objects and cross-field invariants;
do not duplicate numeric guards already implemented or in open PRs. Effort M/L;
data-loss/architecture risk high.

### Make release assembly fail closed

general issues — important

`Scripts/make-app.sh:64-67` continues after ad-hoc signing fails, and
`.github/workflows/release.yml:79-86` tolerates DMG-tool failure. Artifact presence
alone does not prove a usable signed bundle.

Separate permissive local development from release gates. Fail on missing icons,
SDEF/signatures or invalid DMGs; mount/extract and validate published contents at
least as strictly as CI. Effort M; Mac runner required. Includes S2-07.

## Nice-to-have

### Preserve Swift recovery Markdown across embedded newlines

bugs — nice-to-have

`Sources/LucerneCore/Model/MarkdownExporter.swift` passes newlines through escaping
and checks block prefixes only on the first line. `a\n# b` can become a heading;
newlines can split GFM rows/list items in `content.md` and history.

Flatten/escape embedded newlines in inline output without losing text. Effort S.

### Preserve Swift table text when cell coordinates collide

bugs — nice-to-have

`Sources/LucerneCore/Model/MarkdownExporter.swift:133-138` can overwrite duplicate
coordinates or discard cells outside its assembled grid.

Fall back to plain paragraph blocks and signal the loss when a grid is invalid.
Keep this distinct from numeric decode bounds and the Qt Markdown fix. Effort S.

### Remove the empty-archive fallback API

general issues — nice-to-have

`Sources/LucerneCore/IO/MiniZip.swift:56-61` turns an unexpected writer error into
valid-looking empty `Data` through its nonthrowing overload.

Remove that overload or make an internal invariant failure explicit. Effort S.

### Extract tested seams from EditorController only when needed

general issues — nice-to-have

The large controller mixes behavior whose tests need clearer boundaries, but
splitting by line count would add churn without fixing behavior.

Extract coherent paste normalization, export preparation or table parsing/rebuild
collaborators when tests require them. Keep geometry/list numbering pure.
Effort incremental; risk medium.

### Preserve displaced direct indents when applying lists

bugs — nice-to-have

Custom list rendering derives a hanging indent; applying/removing lists can
replace the paragraph's prior direct indent choices.

Define and test restoration of authored indents separately from derived list
geometry. Coordinate with marker accessibility, interchange and caching below.
Effort M.

### Preserve table structure through advanced edits

missing features — nice-to-have

TextKit owns page-boundary row breaking; a row taller than a page cannot currently
split. Structural row/column rebuilds also reset merged cells.

Confirm page-boundary behavior on-device, support tall rows where TextKit permits,
and preserve merges during structural edits. Add accessible table/list semantics.
Effort M/L; do not reintroduce the already-fixed multi-paragraph-cell loss.

### Preserve lists in RTF and DOCX interchange

missing features — nice-to-have

Custom-drawn markers are absent from exported attributed strings, so these lossy
exports omit bullets and numbering.

Materialize standard list semantics or literal markers. Verify nesting, marker
formats and nondefault starts. Effort M.

### Resolve or explicitly reserve paragraph anchors

missing features — nice-to-have

The model/spec describe paragraph anchors while the app renders page anchors.

Implement anchor resolution or mark the v1 form reserved/unsupported while
preserving its data. Keep rectangular page-anchored placement the baseline.
Effort M/L.

### Skip unused archive payloads before inflation

performance — nice-to-have

Aggregate budgets do not eliminate decoding/copying unknown archive entries that
the document reader later ignores.

Extract required entries selectively within the existing safety budgets. Test
unknown payloads, optional recovery and external DEFLATE compatibility. Effort M.

### Keep spelling state document-wide

usability — nice-to-have

The standard spelling toggle may affect only the focused page text view; this
requires on-device confirmation.

If confirmed, store one editor-level flag and apply it to existing/new page views.
Coordinate with document/selection language support. Effort S/M.

### Pin release and CI supply-chain inputs

general issues — nice-to-have

Mutable action/tool references and permissive Xcode selection weaken reproducible
release verification.

Pin actions/packaging tools, require a known Xcode, and separate read-only build
permissions from publication. Effort S/M.

### Replace unchecked menu selectors or test them

general issues — nice-to-have

`Sources/Lucerne/MainMenu.swift:34-43` constructs `Selector(selector)` from strings,
so reachability is not compiler-checked.

Use `#selector` or walk menus in no-document, text, image, list and table states.
Effort M; verify the assembled app, not only library tests.

### Cover the application shell

general issues — nice-to-have

Unit tests do not establish launch, menu reachability, lifecycle/save-review,
AppleScript execution or updater behavior in the assembled application.

Add launch/menu/save-review/SDEF/updater fixtures and bundle smoke tests. Include
plist/SDEF validation and multi-document quit review. Effort M/L.

### Isolate the private corner-mask API

general issues — nice-to-have

Rigi's `_cornerMask` has a small visual benefit, uncertain future behavior and
App Store distribution risk. The earlier review deliberately retained a fallback.

Keep a tested public fallback; remove or isolate the private path for distribution
where required. Effort S/M; do not silently remove an intentional product choice.

### Update documentation and the image-demo screenshot together

general issues — nice-to-have

`screenshot.png` still shows a dashed “lake” placeholder although
`DefaultDocuments.sampleLetterImages()` now supplies bytes. More broadly, model,
spec/schema, architecture, progress, roadmap, help and screenshots can drift.

Capture the current app with platform/version context. Keep docs, both format
implementations and shared fixtures synchronized when features land. Effort S for
the screenshot; ongoing process for documentation. Includes S2-08.

### Separate scroll chrome from structural page layout

performance — nice-to-have

`Sources/LucerneKit/Document/DocumentWindowController.swift:496-506` calls container
layout on clip-bounds changes, which can frame every page even when geometry is
unchanged. Long Mac documents are the main risk.

Update ruler/status positioning independently of `PageCanvasView.layoutPages`.
Measure 25/100/250-page fixtures before/after. Effort M; ordering risk medium.
Includes S2-09.

### Coalesce duplicate formatting relayouts

performance — nice-to-have

Formatting commands relayout synchronously and again through the deferred storage
delegate (`EditorController.swift:586`).

Use one authoritative path or edit-generation coalescing. Effort M; Mac QA needed.

### Reduce whole-document work after edits

performance — nice-to-have

`EditorController.swift:225-269,2478-2503` scans page breaks, forces final layout
and broadly updates exclusions, images, stacking, pages and furniture.

Instrument phases; cache by edit generation, index objects by page and skip image
synchronization for pure text edits where safe. Effort M/L; change risk high.

### Cache Mac list numbering by storage generation

performance — nice-to-have

`Sources/LucerneKit/Text/ListMarkerLayoutManager.swift:35-61` rescans a list from
its start when drawing later items. Repeated page drawing can approach quadratic
work over long lists.

Cache resolved markers and invalidate from the edited item. Measure actual
scrolling/caret latency before changing drawing. Effort M. Includes S2-10.

### Avoid global Qt marker and navigator rebuilds

performance — nice-to-have

`linux/src/app/PageLayout.cpp:309-342` rebuilds markers for every block;
`linux/src/app/MainWindow.cpp:95-98,580-602` rebuilds the visible Contents list
after every layout change, even when text layout itself resumes incrementally.

Measure long lists/outlines; cache decorations and update changed ranges.
Effort M. Includes S2-11.

### Move bounded archive work off the editing thread

performance — nice-to-have

Mac save/autosave and `linux/src/app/Editor.cpp:137-150` snapshot text, generate
Markdown, checksum images and assemble the ZIP synchronously. Large images or
history can temporarily prevent input.

Capture immutable UI state on main, then archive/write asynchronously. Preserve
transactional history and error reporting; consider streaming only after profiling.
Effort L; concurrency risk high. Includes the save portion of S2-12.

### Decode and resize images without blocking input

performance — nice-to-have

Full-resolution Mac image decoding/drawing and
`linux/src/app/Editor.cpp:171-180,201-204` run on the UI thread. Image-heavy letters
and live resizing are the main risks.

Validate/decode off-main and cache display-size representations. Use a lower-cost
live-resize preview without changing original image bytes. Effort M/L; fidelity
risk medium. Includes the image portion of S2-12.

### Cache table ruler state

performance — nice-to-have

Caret movement reparses the current table even when its structure is unchanged.

Cache by table identity and storage generation. Effort M; risk low.

### Cache style-use counts

performance — nice-to-have

Style Editor scans paragraphs to count uses of a role on caret changes.

Cache role counts by text/attribute generation. Effort S/M; risk low.

### Diff selection-driven chrome state

performance — nice-to-have

Selection changes refresh the full toolbar/ruler, and some setters redraw values
that did not change.

Diff one immutable UI-state snapshot before assigning controls. Effort M; risk low.

### Profile resident page views before virtualizing

performance — nice-to-have

Every page view remains resident, which can matter for long/image-heavy documents.

Virtualize expensive decoration/image rendering first, keeping required TextKit
containers and the shared layout manager. Effort L; architecture risk high.

### Avoid decoding document.json twice

performance — nice-to-have

`Sources/LucerneCore/Model/DocumentCoding.swift:67-77` runs a version probe and then
a full decode.

Use one decode with an appropriate version check without weakening future-format
rejection. Effort S.

### Cache Find match counts

performance — nice-to-have

`Sources/LucerneKit/Views/FindPanelController.swift:175-194,215-245` scans the full
document to recount matches on each Find Next. This adds document-size work to
repeated Command-G; no quadratic runtime measurement was established.

Cache counts by query/options and storage generation. Effort S; Mac QA needed.

### Re-evaluate CI caching only if build time warrants it

performance — nice-to-have

There is no SPM cache; toolchain invalidation may erase its benefit.

Measure macOS CI time before adding a cache. Effort S; risk low.

### Prevent header and footer zones from colliding

visual issues and layout problems — nice-to-have

`Sources/LucerneKit/Views/PageContainerView.swift:99-116` and
`linux/src/app/Editor.cpp:571-582` draw left, center and right text into one band.
Long title/date/page combinations can overpaint on screen and in PDF/print.

Measure zones, reserve nonoverlapping rectangles and define truncation priority.
Add a compact live preview. Effort S/M; Mac visual QA needed. Includes S2-16.

### Size list gutters for actual labels

visual issues and layout problems — nice-to-have

`Sources/LucerneCore/Model/ListSupport.swift:18-31` and
`Sources/LucerneKit/Text/ListMarkerLayoutManager.swift:119-128` use a fixed 24-point
step. Wide decimal/Roman markers such as “1000.” at large sizes can touch item text.

Measure markers and widen each level's gutter consistently on both platforms.
Effort S/M; Mac QA needed. Includes S2-17.

### Display custom and mixed formatting honestly

usability — nice-to-have

`Sources/LucerneKit/Views/ToolbarView.swift:370,387-393` rounds fractional font sizes
and retains a previous line-spacing preset for custom spacing.
`linux/src/app/MainWindow.cpp:830-834` also retains stale spacing selections.

Preserve decimal sizes and show Custom/mixed values rather than an old preset.
Effort S/M plus UI QA. Includes S2-18.

### Activate Welcome and Navigator rows from the keyboard

usability — nice-to-have

`Sources/Lucerne/WelcomeWindowController.swift:103,185-188` has double-click
activation; `NavigatorView.swift:64-68,83` needs an explicit keyboard contract.

Support Return/Space, set an initial responder/default New action, preserve Escape
behavior and expose semantic heading indentation. Effort S/M. Includes S2-21.

### Disable palettes consistently without a document

usability — nice-to-have

`Sources/LucerneKit/Views/FloatingPalette.swift:243-303` makes Styles inert, but
Typefaces, Lists and footer actions can still appear actionable without a letter.

Use a consistent “No letter open” state and disable operations that would no-op.
Effort S.

### Make Style Editor quiet states explicit

usability — nice-to-have

Stale target values, partially enabled fields, missing fonts and a capped specimen
can imply an editable target or exact print preview when neither is available.

Clear/ghost stale values, disable all fields including size, identify missing
fonts and label the specimen a compact preview. Effort S/M.

### Define picker preview and commit behavior

usability — nice-to-have

Filtering and click-away behavior need a deterministic preview/selection contract.

Select/preview a predictable candidate and explain Return, Escape and click-away
semantics. Effort S/M.

### Give ruler edits live preview and cancellation

usability — nice-to-have

`Sources/LucerneKit/Views/LucerneRulerView.swift:258-334` commits on mouse-up; table
width changes can rebuild the full table. Hover/cursor/keyboard feedback is limited.

Add live preview, Escape revert, arrow adjustment, right-click tab types,
unit-aware readout and pixel alignment at arbitrary zoom. Effort M/L; Mac QA needed.

### Route blank-margin clicks deliberately

usability — nice-to-have

Clicks in blank paper margins do not have a clear text-targeting contract.

Route side-margin clicks to the nearest body position. Reserve explicit top/bottom
zones for future in-place furniture editing. Effort S/M.

### Add a narrow-window strategy

usability — nice-to-have

The wide minimum-window workaround does not scale to localization or accessibility
text sizes.

Provide a compact mode or classic overflow well while retaining every command in
menus. Effort M/L.

### Expose precise image controls without becoming a drawing app

missing features — nice-to-have

Floating-image users lack an object ticket for exact x/y/size, aspect lock,
crop/rotate, wrap/standoff, align/distribute, z-order, duplicate/copy and context
commands.

Build on image selection and existing model operations. Keep guides/snapping
optional and avoid a general drawing interface. Effort L.

### Improve navigator feedback and page navigation

usability — nice-to-have

The outline does not clearly highlight the current heading/page and needs a useful
empty state. Heading-free letters lack a thumbnail navigation option.

Add current-location feedback, an empty-state explanation, richer outline
navigation and optional page thumbnails. Effort M/L.

### Show update download progress and cancellation

usability — nice-to-have

`isDownloading` exists internally without a complete visible progress/cancel/error
state.

Show that state and handle cancellation/errors explicitly. Effort S/M.

### Add Copy Style and Paste Style

missing features — nice-to-have

These expected direct-formatting commands are absent.

Define supported attributes and test multi-page focus before adding them.
Effort M.

### Import existing prose explicitly

missing features — nice-to-have

`Sources/LucerneKit/IO/LucerneDocumentController.swift:33-39` and Qt's Open filters
accept `.luce`; writers must paste existing text manually.

Start with UTF-8 text, then Markdown; add RTF/DOCX only with fidelity reporting and
verified UTI/filter wiring. Keep `.luce` canonical. Effort M, then L for rich import.
Includes S2-15.

### Edit headers and footers in place

missing features — nice-to-have

The three-zone furniture model exists, but editing requires a dialog.

Make top/bottom margin zones editable in place without mixing them into body
storage. Effort M.

### Add Document Info

missing features — nice-to-have

Words/characters/paragraphs/pages/images, created/modified dates, language and
estimated reading time lack one document-level view.

Expose existing metadata and computed counts in a small Info view. Effort S/M.

### Make version history discoverable

missing features — nice-to-have

`Sources/LucerneCore/IO/DocumentHistory.swift` and `linux/src/core/History.cpp`
store dated Markdown snapshots without an in-app browser. Recovery requires
unzipping and recognizing raw timestamps.

Add a version list, preview/diff, Copy, Restore as New and raw-entry reveal. Explain
that Markdown snapshots do not preserve exact layout. Effort M per UI.
Includes S2-13 and the earlier version-browser idea.

### Support envelope presets and proofing

missing features — nice-to-have

Letter workflows need DL/#10 presets, address-window placement and print proofing.

Add those bounded presets and safe-region previews using the corrected DIN guides
and existing print pipeline. Effort M/L.

### Add strikethrough and superscript/subscript deliberately

missing features — nice-to-have

These text attributes lack a complete model/export contract.

Define both implementations' persistence and export behavior before exposing UI.
Effort M.

### Add hyperlinks with an explicit export promise

missing features — nice-to-have

There is no canonical hyperlink feature; rich-pasted links can misleadingly appear
supported before normalization.

Define the model and UI, including PDF annotations if links are promised outside
screen/RTF output. Effort M/L.

### Expose paragraph before/after spacing

missing features — nice-to-have

The model supports spacing before/after, but direct formatting controls are missing.

Expose predictable paragraph spacing using the existing model. Effort M.

### Support language per document or selection

missing features — nice-to-have

Spelling lacks an explicit document/selection language contract.

Add language support together with document-wide spelling state, keeping automatic
correction opt-in. Effort M/L.

### Add Linux table editing beyond the documented fallback

missing features — nice-to-have

`linux/README.md` documents table cells as ordinary paragraphs;
`linux/src/app/DocumentBridge.cpp:233-241` preserves descriptors rather than creating
visual grids. Cross-platform letters retain metadata but are not grid-editable.

Show a fallback notice first; implement table layout/editing separately without
silently dropping metadata. Effort S for the notice, L for parity. Includes S2-14.

### Add irregular wrap and image overhang only after rectangular flow

missing features — nice-to-have

Irregular alpha wrap falls back to a rectangle; page-boundary image overhang is
clipped in the supported baseline.

Keep page anchoring and rectangular wrap reliable. Implement alpha outlines and
overhang with explicit clipping/layout tests when needed. Effort L and M,
respectively; paragraph anchors are tracked separately.

### Treat floating text boxes as a format extension

missing features — nice-to-have

Floating text boxes need a real placed-object format contract, not a UI-only hack.

Resolve version/unknown-field preservation first, then update both apps, docs and
fixtures. Effort L.

### Add sections only for demonstrated letter workflows

missing features — nice-to-have

First-page furniture or mixed numbering may justify sections, but general
Word-style section complexity does not fit the product.

Start only from a concrete first-page/numbering need. Effort L.

### Ship task-oriented offline Help

usability — nice-to-have

`Sources/Lucerne/AppDelegate.swift:162-165` opens the GitHub README, which emphasizes
repository/build details rather than writing tasks.

Provide a short offline guide to writing, images/wrap, lists/tables, styles,
versions, stationery, recovery and shortcuts. Effort M. Includes S2-22.

### Decide the dark-mode contract across classic apps

aesthetics and theming — nice-to-have

`Sources/Lucerne/AppDelegate.swift:15-18` and
`Sources/LucerneKit/Document/DocumentWindowController.swift:42-44` pin Aqua.
`SionDocumentWindowController.swift:75` makes the same choice; Linux follows its
system palette. This is intentional consistency, not an accidental repaint bug.

Decide whether dark desk/chrome variants fit the classic style. Keep paper white,
use shared Rigi tokens and test contrast/accessibility overrides. Effort M+ across
Rigi/apps. Includes S2-23.

### Unify utility-window visual language

aesthetics and theming — nice-to-have

`Sources/LucerneKit/Views/FindPanelController.swift:25-33`, About and Settings use
stock windows beside ClassicWindow documents. Rigi's torn-off gallery palette
lacks autosave/title (`Rigi/Sources/RigiGallery/GalleryPalettes.swift:65-80`).

Share spacing, typography, etched sections, button hierarchy and window treatment
while retaining native accessible fields. Bring gallery examples into parity.
Effort S/M; Mac visual QA needed. Includes S2-24.

### Reveal actual wrapping with Wrap X-ray

novel, delightful, or quirky ideas worth trying — nice-to-have

`Sources/LucerneKit/Layout/ExclusionPathController.swift` and
`linux/src/core/PageMetrics.cpp:50-64` already compute exclusions. Standoff and the
narrow-column rule are otherwise invisible to image users.

Hold Option/Alt while dragging to ghost the actual exclusion boundary, including
standoff and sliver extension. Never print the overlay. Effort S/M per UI.
Includes S2-25.

### Show image geometry before adding magnetic guides

novel, delightful, or quirky ideas worth trying — nice-to-have

`EditorController.swift:2391` has `onStatusHint`; Qt's `PageCanvas::updateDrag`
already tracks page-relative positions. Letterhead alignment still needs trial
and error.

Show live x/y/width/height first. Add optional guides/snapping to margins, center,
furniture baselines, fold marks and other objects, with modifier bypass.
Effort S for readout, M for guides. Includes S2-26.

### Add a local Signature Shelf

novel, delightful, or quirky ideas worth trying — nice-to-have

Both editors already insert original image bytes. Repeat letter writers still
find and resize the same signature manually.

Reuse Application Support storage and insertion paths with size presets and
wrap-none placement. Preserve original images; no format fields are needed.
Effort S/M per UI. Includes S2-27.

### Add a Tab Laser

novel, delightful, or quirky ideas worth trying — nice-to-have

`LucerneRulerView.swift` and `linux/src/app/Ruler.cpp` already track drag positions,
but tab/indent/table-divider alignment has no canvas guide.

Draw a temporary unit-aware vertical guide and readout. Remove it on commit/cancel
and exclude it from PDF/print. Effort S per UI. Includes S2-28.

### Coalesce Mac image nudges

usability — nice-to-have

`Sources/LucerneKit/Views/FloatingImageView.swift:250-255` commits one “Move Image”
undo step per arrow keypress.

Coalesce a nudge burst into one undo group with a clear termination boundary.
Effort S.

### Add a Correspondent Card without mail-merge complexity

novel, delightful, or quirky ideas worth trying — nice-to-have

Sender/recipient data could drive envelope proofing and reusable stationery.

Add optional fields/tokens, address-window/safe-region overlays and stationery
integration. Keep it a letter workflow, not general mail merge. Effort M/L.

### Keep a small Ink Desk

novel, delightful, or quirky ideas worth trying — nice-to-have

Recent/favorite writing colors could be faster to reuse than a full color panel.

Offer five accessible named swatches: blue-black, sepia, graphite, deep red and
black. Effort S/M.

### Preview stationery visually

novel, delightful, or quirky ideas worth trying — nice-to-have

The template shelf lacks a restrained visual gallery.

Render Blank Letter/recent stationery thumbnails through the existing page/PDF
pipeline and provide Manage Stationery. Effort M.

### Combine existing formatting in a Quick Format Book

novel, delightful, or quirky ideas worth trying — nice-to-have

Styles, typefaces and list markers have separate selection surfaces.

Try one searchable keyboard specimen with used/favorite sections, reusing existing
commands rather than introducing another formatting model. Effort M.

### Consider nonprinting page-edge drafting notes

novel, delightful, or quirky ideas worth trying — nice-to-have

Small drafting notes could live beside the letter without entering print output.

Resolve unknown-field/version policy before adding a persisted notes feature.
Effort L.

### Keep typewriter sounds optional and noncanonical

novel, delightful, or quirky ideas worth trying — nice-to-have

Restrained key clicks and a margin bell could fit the writing ritual, but must
not disturb readers or alter documents.

Provide opt-in sounds and silent-hours behavior; never store this as document
state. Effort S/M.

### Offer a bounded letter ritual

novel, delightful, or quirky ideas worth trying — nice-to-have

Repeated dates, salutations and closing/signature positions suit stationery.

Try prompts learned per stationery, without expanding into mail merge. Effort M.

### Keep paper personality out of print

novel, delightful, or quirky ideas worth trying — nice-to-have

Warm/cool/proof canvas appearances could add character without changing output.

Keep PDF/print white and let accessibility settings override texture. Effort S/M.

### Sion: parse Mermaid arrows after the source node

bugs — nice-to-have

`Sion/Sources/SionCore/Import/MermaidImporter.swift:225-231` scans from column zero,
so `A|"-->"|--> B` can match an arrow inside the label and reject a valid link.

Scan after the parsed source node. Effort S; retained from the prior review.

### Sion: render previews for windowless saves

bugs — nice-to-have

`Sion/Sources/SionKit/Document/SionDrawingDocument.swift:156-161` uses only the first
window for preview rendering. Windowless autosave/revert omits it despite
`SionSceneRenderer` being available.

Fall back to renderer-backed previews. Effort S; Mac QA needed.

### Sion: avoid assuming document IO is main-actor isolated

bugs — nice-to-have

`Sion/Sources/SionKit/Document/SionDrawingDocument.swift:177-229` uses
`MainActor.assumeIsolated`; an off-main AppKit call would crash.

Hop to the main actor explicitly. Effort S; retained, not newly reproduced.

### Sion: detect history filename collisions

bugs — nice-to-have

`Sion/Sources/SionCore/Archive/SionArchive.swift:332-344` keys history by timestamp
and a 12-hex prefix; a collision can overwrite a revision.

Detect collisions and extend the prefix. Effort S.

### Sion: use the scene index while snapping

performance — nice-to-have

`Sion/Sources/SionKit/Canvas/SionCanvasView.swift:2566-2589` rebuilds rotated bounds
for visible elements on each drag sample instead of using the existing
`SceneRenderContext` spatial index.

Viewport-cull and use the index. Effort M; measure on-device.

### Sion: cache connector route samples

performance — nice-to-have

`Sion/Sources/SionCore/Geometry/ConnectorRouting.swift:150-230` resamples 24 points
per curve segment on each `point(atFraction:)`/`polylinePoints` call, including
connector labels and exports.

Lazily cache the sampled polyline. Effort S.

### Sion: avoid whole-scene work per gesture transaction

performance — nice-to-have

`Sion/Sources/SionCore/Editing/SceneCommand.swift` and `SceneEditor.swift:180-195`
perform O(n) scans/validation per pointer sample.

Use a revision-scoped ID index, incremental validation and change sets. Effort L.

### Sion: coalesce arrow-key nudges

usability — nice-to-have

`SionCanvasView.swift:646-655` calls `SionEditorController.swift:1030-1035` per
keypress, flooding Undo while an arrow is held.

Coalesce same-direction nudges within a short window. Effort M; Mac QA needed.

### Sion: offset repeated pastes

usability — nice-to-have

`Sion/Sources/SionKit/Canvas/SionCanvasView.swift:923-948` always pastes at the
visible center, placing copies directly on top of each other.

Cascade offsets or track pasteboard identity. Effort S.

### Sion: cycle overlapping objects

novel, delightful, or quirky ideas worth trying — nice-to-have

Repeated clicks could reach overlapping elements without changing stacking order.

Cycle candidate selections through existing `SionCanvasView` hit testing.
Effort S/M.

### Sion: expose tool shortcuts

novel, delightful, or quirky ideas worth trying — nice-to-have

Existing tools could be faster to reach from the canvas.

Try V/R/O/T/C shortcuts with visible hints. Effort S/M.

### Sion: make grid snapping explicit

novel, delightful, or quirky ideas worth trying — nice-to-have

`SceneSnapping` provides a seam for a simple snapping affordance.

Add a snap-to-grid toggle rather than hidden snapping behavior. Effort S/M.

### Sion: signal connector snap targets

novel, delightful, or quirky ideas worth trying — nice-to-have

Connector endpoints could show when they enter the snap radius.

Try a restrained snap flare using existing snapping geometry. Effort S/M.

### Sion: dim nonselected objects for focus

novel, delightful, or quirky ideas worth trying — nice-to-have

The existing canvas could support a lightweight focus mode.

Try Command-period dimming of nonselected objects without altering scene state.
Effort S/M.

### Rigi: verify popup positioning on flipped coordinates

visual issues and layout problems — nice-to-have

`Rigi/Sources/RigiUI/ClassicControls.swift:464` pops at `bounds.height + 1` on a
nonflipped control, unlike ClassicSizeField's intentional `y: 0`.

Verify on a Mac, then use the correct lower-edge anchor. Effort S.

### Rigi: pin ClassicWindow appearance consistently

aesthetics and theming — nice-to-have

`Rigi/Sources/RigiUI/ClassicControls.swift:924-950` depends on every application
setting `.aqua` itself.

Set the chosen appearance in initialization if classic Aqua remains the shared
contract. Coordinate with the dark-mode product decision. Effort S.

### Rigi: cache hot drawing allocations

performance — nice-to-have

`Rigi/Sources/RigiUI/ClassicControls.swift:51-69,180-202` creates gradients and
attributed glyph strings on every draw.

Cache the six bezel gradients and glyph strings. Effort S.

### Rigi: provide the promised status-bar hover API

missing features — nice-to-have

`Rigi/Sources/RigiUI/StatusBarView.swift:24-26` exposes only `message`, while
`docs/interface-guidelines.md:45` promises hover help.

Add `setHoverMessage(_:)` and view tracking. Effort S.

### Rigi: close segmented-control geometry gaps

visual issues and layout problems — nice-to-have

`Rigi/Sources/RigiUI/ClassicControls.swift:328-364` outlines all bounds while segment
widths can leave an unpainted strip. Separator phases differ from
`ClassicNativeControls.swift:38-41`.

Clip to bounds, round boundaries and unify separator phase. Effort S.

### Rigi: add segment hints and restrained hover previews

novel, delightful, or quirky ideas worth trying — nice-to-have

`ClassicSegmentedControl` could explain individual alignment segments; cached
bezel gradients also make a small active-segment hover animation inexpensive.

Add per-segment tooltips/live preview, respecting reduced motion. Keep the existing
private corner-mask fallback decision separate. Effort S/M.

## Verification still needed

Automated coverage should expand around:

1. Paragraph-ID uniqueness, normalized paste, complete empty/trailing paragraph
   state and page-break stability, including dirty tracking and undo.
2. Cross-field semantic invariants, list downgrade/version policy, canonical
   color/tab/list/empty-field bridge round trips and implicit table widths.
3. Corrupt-image recovery, selective extraction, style-library read-only/recovery
   UI, and RTF/DOCX list nesting/starts/markers.
4. Menu reachability, plist/SDEF execution, app lifecycle/save review, updater
   fixtures and assembled-artifact smoke tests.

Keep on-device QA separate from build/test results:

1. Ventura through current macOS, Intel where supported, Retina/non-Retina,
   arbitrary zoom and system light/dark appearance despite the Aqua pin.
2. VoiceOver/Full Keyboard Access/AT-SPI, Increase Contrast, Reduce Transparency,
   reduced motion and enlarged accessibility display settings.
3. 25/100/250-page scroll FPS/caret latency, long lists, large tables, image-heavy
   save/autosave and PDF/RTF/DOCX output.
4. Page-boundary selection/find/reveal, lists/tables/breaks, cross-page image drag,
   zoom, PDF and print; real hardware print margins and page handling.
5. Multiple documents and global palettes, live styles/delayed color updates,
   substitutions, spelling, updater alerts, save sheets and quit review.
6. Clean-Mac ZIP/DMG installation, Gatekeeper, update progress/cancel/offline errors
   and altered-artifact rejection after signing changes.

## Architecture constraints

- Keep one `NSTextStorage`, one TextKit 1 `NSLayoutManager` and identical per-page
  containers. Do not replace TextKit merely because TextKit 2 is newer.
- Keep one document-wide page size/margins; no per-page paper geometry.
- The model owns structure; live storage owns text while editing. Preserve
  `.lucerne*` attributes across every bridge/rebuild.
- Keep objects page-relative with top-left/y-down coordinates. Convert at view/
  container boundaries through `PageMetrics`.
- Keep `document.json` authoritative. Markdown/history are derived recovery lanes,
  PDF provides visual fidelity, and RTF/DOCX are explicitly lossy interchange.
- Keep body structure flat: consecutive `Paragraph.cell` descriptors for tables,
  `Paragraph.list` descriptors for lists. Markers are derived, not canonical text.
- Keep style roles independent of list/table membership and preserve representable
  direct formatting when styles change.
- Extract coherent tested collaborators, not forwarding layers or line-count
  refactors. Keep layout geometry/list numbering pure.
- Avoid collaboration, change tracking, cloud accounts, plugins, ribbon/inspector
  sprawl and turning image controls into a drawing application.

## Suggested sequence

1. Resolve format evolution, rich paste, paragraph identity, empty/trailing state,
   page-break stability and document-wide commands.
2. Establish accessibility/keyboard behavior and signed distribution before
   extending the format.
3. Measure long documents, then reduce redundant scroll/layout/list/table/style
   scans and main-thread archive/image work.
4. Add letter-specific depth: Help/history, editable furniture, object controls,
   Wrap X-ray, guides and envelope/signature workflows.
