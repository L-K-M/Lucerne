# sol.md - a Sol review of Lucerne

A thorough review of Lucerne at `eab9874` (`v0.5.0`, current `main`) on 10 July
2026. This follows `fable-is-awesome.md`, whose companion PRs #16-34 have all
landed, and also covers the list work merged in PRs #37-40.

## Method and limits

The review covered the product brief, progress and roadmap documents, the complete
source map, model and text bridge, pagination and free-placement engine, tables and
lists, archive and export paths, custom controls, app lifecycle, updater, build and
release workflows, tests, recent history, and all findings from the earlier review.
Five independent read-only audits examined the highest-risk areas; their concrete
claims were then traced against the current source.

This environment is Linux and has no AppKit or Swift toolchain. Source-level claims
below are marked confirmed only where the code path is clear, but rendering,
responder-chain details, VoiceOver behavior, and performance magnitude still need
on-device Mac QA. Current GitHub CI and the v0.5.0 release workflow are green; that
does not substitute for interactive testing.

## Pending companion PRs (review/CI)

The following companion PRs implement bounded findings from this audit. They are
open and pending review/CI acceptance; they are not described as merged or
completed. [`ANALYSIS.md`](ANALYSIS.md) keeps them separate from the unresolved live
backlog so their fixes are not duplicated as future work.

| PR | Audit findings addressed |
|---|---|
| [#41 — Make the sample letter self-contained](https://github.com/L-K-M/Lucerne/pull/41) | 1.1: bundle/load the sample image and cover the real sample save/open path. |
| [#42 — Reject unsafe document indexes before layout](https://github.com/L-K-M/Lucerne/pull/42) | 1.2: reject unsafe page/list indexes and add runtime guards; broader semantic validation remains separate. |
| [#43 — Preserve and correct page fold marks](https://github.com/L-K-M/Lucerne/pull/43) | 1.12 fold-mark preservation/no-op handling and 1.16 DIN 105/210 mm placement; page-setup undo/context restoration remains separate. |
| [#44 — Preserve formatting and multi-paragraph table cells](https://github.com/L-K-M/Lucerne/pull/44) | 1.3 and 1.4: retain all cell paragraphs through structural rebuilds and preserve direct/structural formatting when applying styles. |
| [#45 — Fail safely when exports are incomplete](https://github.com/L-K-M/Lucerne/pull/45) | 1.18: propagate RTF/DOCX/PDF conversion or assembly failures and validate output before replacement. |

## Overall assessment

Lucerne is much better than a typical AI-authored application. Its central design is
right: one text storage and layout manager, one TextKit 1 container per uniform page,
and page-anchored objects expressed as exclusion paths. `PageMetrics` keeps the
dangerous coordinate conversion isolated, the `.luce` format is unusually open and
recoverable, and the style system has a coherent model rather than being a pile of
formatting toggles. Tables and lists were added without abandoning the flat body
model. The classic chrome also has a specific visual point of view instead of looking
like a generic macOS sample.

The weaknesses are concentrated rather than architectural:

- Several ordinary editing operations still lose structure or direct formatting.
- The new list feature shipped ahead of its normative format and downgrade contract.
- A few prominent workflows, especially New Sample Letter, fail at save time.
- Custom controls are visually ambitious but remain mouse-centric and inaccessible.
- The page-per-text-view architecture still exposes selection and command seams.
- Long-document work is repeatedly performed on the main thread and on scroll/caret
  movement, although typical one-page letters conceal much of the cost.
- Documentation drift returned immediately after the previous housekeeping pass.

The project should spend one release on correctness, accessibility foundations,
format honesty, and performance instrumentation before adding another large content
feature.

## 1. Bugs and data-loss risks

Ordered by severity. "Confirmed" means the current source directly contains the
path; it does not mean the interaction has been reproduced on a Mac.

### 1.1 New Sample Letter cannot be saved

**Severity: high. Confidence: very high.**

`DefaultDocuments.sampleLetter()` creates an image object referencing
`images/lake.png` while explicitly supplying no bytes
(`Sources/LucerneKit/Model/DefaultDocuments.swift:89-134`).
`LucerneDocument.loadSampleContent()` does not populate `pendingImages`
(`Sources/LucerneKit/IO/LucerneDocument.swift:31-35`). The hardened archive writer
now refuses every referenced image missing from the image store
(`Sources/LucerneKit/IO/LuceArchive.swift:37-49`).

Choose **New Sample Letter**, edit it, and Save. Archive generation must fail with a
missing-image error. This is a prominent first-run workflow and an especially bad
place for a deterministic save failure. The tests hide the bug by supplying fake
lake bytes manually rather than exercising `loadSampleContent()`.

**Fix:** bundle a small real sample image and load its bytes with the sample, or make
the demonstration image an intentionally non-persistent view rather than a model
reference. Add an end-to-end sample archive test.

### 1.2 Negative or extreme object page indexes can crash while opening

**Severity: high. Confidence: very high.**

`PlacedObject` decodes any `Int` page (`DocumentModel.swift:451-465`) and there is no
post-decode semantic validation. Pagination computes `maxObjectPage + 1`
(`EditorController.swift:213-220`), which can overflow for `Int.max`.
`syncImageViews()` checks only `pageIndex < pages.count`
(`EditorController.swift:383-396`), so `-1` passes and is used as `pages[-1]`.

The same validation gap permits extreme table dimensions, list levels, non-finite
geometry, and impossible margins to travel much farther than they should.

**Fix:** add one model semantic validator after decoding, with finite/range checks
and bounded indexes, plus defense-in-depth guards before indexing and arithmetic.
Malformed optional objects should be omitted with a recoverable warning; malformed
canonical page/body structure should produce a normal open error, never a trap.

### 1.3 Table structure commands delete later paragraphs in a cell

**Severity: high. Confidence: very high.**

Return is allowed inside a table cell (`PageTextView.swift:82-89`), so TextKit can
create multiple consecutive paragraphs with the same table block and cell location.
`parseTable()` explicitly retains only the first paragraph for each row/column key
(`EditorController.swift:1588-1618`). Row/column edits, merging, resizing, and
column distribution rebuild and replace the whole table from that truncated grid
(`EditorController.swift:1647-1707`, `1721-1741`, `1880-1900`).

Type two paragraphs in a cell, then resize a column or insert a row. The second
paragraph disappears. The documented single-paragraph-cell assumption is not a
safety mechanism when the UI freely permits multiple paragraphs.

**Fix:** preserve all consecutive paragraphs belonging to a cell. As an immediate
safety stop, detect duplicate cell coordinates and refuse destructive structural
commands with an explanatory alert until the full representation is implemented.

### 1.4 Applying a paragraph style erases direct inline formatting

**Severity: high. Confidence: very high.**

The previous fix restored table blocks, page breaks, and list membership, but
`applyStyleRole` still calls `setAttributes` over every character in each paragraph
(`EditorController.swift:841-924`). That replaces bold, italic, underline, font,
size, and color overrides with one style dictionary.

Italicize one word, color another, then apply Body or Heading 1 to the paragraph.
The inline emphasis disappears. This contradicts the S3 style engine, where direct
formatting intentionally survives style definition changes.

**Fix:** recover representable direct run overrides against the old role, switch the
role, and rebuild against the new role. Cover inline formatting and structural
table/page-break/list attributes in the same regression test.

### 1.5 Rich paste promises formatting that save silently discards

**Severity: high. Confidence: very high.**

The text views are rich-text editors. `PageTextView.paste` only intercepts images;
all other content goes to `super.paste` (`PageTextView.swift:181-194`). Browser,
HTML, and RTF paste can therefore display links, strikethrough, highlighting,
superscript, unsupported lists, and arbitrary paragraph attributes. The canonical
reader persists only Lucerne's representable fields (`AttributedStringReader.swift:
147-193`), so unsupported appearance vanishes after save/reopen or any stylesheet
reapplication. Pasted paragraphs can also lack fresh Lucerne paragraph IDs.

**Fix:** normalize paste at the boundary to a documented supported-attribute
whitelist, mint paragraph identities, and make discarded attributes visible to the
user. A richer later step is a private Lucerne fragment pasteboard type carrying
paragraphs, styles, lists, and tables between Lucerne documents.

### 1.6 Empty and trailing-empty paragraphs still lose state

**Severity: high. Confidence: high.**

The trailing-paragraph fix preserves only role, ID, and list membership on the final
terminator (`AttributedStringReader.swift:34-64`). Alignment, tabs, indents, line
spacing, paragraph spacing, page breaks, and table-cell membership are rebuilt from
the role and lost. `modifyParagraphStyle` updates only typing attributes for a
zero-length trailing paragraph and does not dirty-track the change. A completely
empty storage is reconstructed as a new default paragraph
(`AttributedStringReader.swift:12-18`), losing even more model identity.

Create a trailing empty paragraph, center or indent it, save, and reopen. The change
is gone; in some paths there is no save prompt. Empty table cells and empty forced
break paragraphs are higher-risk variants.

**Fix:** represent all model-level trailing paragraph state explicitly and pass the
empty document's live typing/model state into snapshots. Route every trailing
paragraph command through undo and dirty tracking.

### 1.7 Ordinary Return can duplicate paragraph IDs

**Severity: medium-high. Confidence: high.**

Only special heading and list continuation paths mint a new ID after Return.
Ordinary `super.insertNewline` inherits typing attributes
(`PageTextView.swift:74-89`), including `.lucerneParagraphID`. Two body paragraphs
can consequently save with the same supposedly stable ID, violating the normative
identity contract and undermining paragraph anchoring and external tooling.

**Fix:** assign a fresh ID after every hard paragraph break, including paragraph
splits and trailing-empty state. Repair duplicates defensively during snapshot and
add a uniqueness assertion to tests.

### 1.8 Forced page breaks depend on one disposable character

**Severity: medium-high. Confidence: high.**

The bridge stores `.lucernePageBreakBefore` on the first character only; layout finds
all occurrences, while the reader checks only the paragraph's probe character
(`AttributedStringReader.swift:79-95`, `EditorController.swift:258-266`). Deleting
or replacing the first character can remove the marker, and inserting before it can
leave layout and persistence looking at different locations.

**Fix:** stamp page-break metadata over the entire paragraph including its separator,
or normalize and read it anywhere in the paragraph after edits.

### 1.9 Style reapplication drops trailing list and direct typing state

**Severity: medium. Confidence: high.**

After a stylesheet rebuild, `refreshTypingAttributesAfterStyleChange` reconstructs
typing attributes from role and paragraph ID but does not preserve list membership
or direct caret formatting (`EditorController.swift:2002-2040`). Editing a style
while the caret sits on a trailing list item can make subsequently typed text leave
the list; directly bold/colored typing state can also reset.

**Fix:** rebase pre-change typing attributes against the rebuilt paragraph, preserving
representable direct overrides and list state.

### 1.10 Style Editor undo can be registered out of chronological order

**Severity: medium. Confidence: very high.**

Live style changes suppress normal undo and seal one coalesced step only on close,
retarget, or explicit library action (`StyleEditorPanel.swift:194-207`, `749-771`).
Intervening typing does not seal the style session. Undo can therefore remove newer
typing first; closing the style editor later registers the older style edit above
newer work.

**Fix:** seal the style session before the first non-style text/undo transaction.
This needs an exact style-edit -> type -> undo/redo ordering test on macOS.

### 1.11 A delayed style-color edit can target the wrong document

**Severity: medium. Confidence: high.**

Color application is delayed 250 ms (`StyleEditorPanel.swift:217-235`), but
`retarget()` does not flush the pending color edit before replacing the controls'
target (`StyleEditorPanel.swift:185-192`). Switch documents immediately after a
color drag and the final event can be lost or read from the new target's controls.

**Fix:** flush pending color edits before every retarget and target-window switch.

### 1.12 Page Setup loses fold marks and all page changes lose editing context

**Severity: medium. Confidence: very high.**

`applyPageSize` constructs a new `PageConfig` with only size and margins, dropping
`foldMarks` (`DocumentWindowController.swift:596-603`). `updatePageConfig` snapshots
and reloads the complete editor (`EditorController.swift:2330-2335`), destroying
text views without preserving selection, first responder, scroll anchor, or image
selection. It registers no undo. Confirming an unchanged setup can still dirty and
reload the document.

**Fix:** preserve every `PageConfig` field, equality-guard no-op confirmations,
register model-level undo, and restore global caret/selection, typing state, focus,
scroll anchor, and image selection after reload.

### 1.13 Arrow keys cannot move within a wrapped table cell

**Severity: medium. Confidence: high.**

Every Up/Down command inside a table immediately invokes row navigation
(`PageTextView.swift:25-35`, `EditorController.swift:1744-1768`). In a cell with
three visual lines, Down on line one jumps to the next row rather than line two.

**Fix:** use normal visual-line movement unless the caret is already at the first or
last visual line of the current cell.

### 1.14 Extreme portrait images are distorted on insertion

**Severity: medium. Confidence: high.**

Insertion constrains width, derives height, then clamps dimensions independently to
the page (`EditorController.swift:460-466`, `PageMetrics.swift:62-70`). A tall image
therefore has its height shortened without recomputing width and is drawn stretched.

**Fix:** compute one aspect-preserving scale that fits both available dimensions.

### 1.15 Header/footer zones overlap each other

**Severity: medium. Confidence: high.**

Left, center, and right furniture strings are independently drawn into the same
full-width rectangle (`PageContainerView.swift:88-104`). Long content in two zones
can paint directly over itself despite tail truncation.

**Fix:** use three collision-aware columns or measure content and assign truncation
priorities. Add a miniature live preview to the furniture sheet.

### 1.16 DIN 5008 fold marks are at the wrong positions

**Severity: medium. Confidence: very high.**

The code draws exact thirds while its comment acknowledges the actual 105 mm and
210 mm offsets (`PageContainerView.swift:72-85`). On A4 the current marks are 99 mm
and 198 mm, off by 6 mm and 12 mm. The option is also offered for arbitrary page
sizes without qualification.

**Fix:** draw at 105/210 mm from the top for A4; label the setting as DIN A4 or
disable it for incompatible page formats.

### 1.17 List markers disappear from RTF and DOCX exports

**Severity: medium. Confidence: very high.**

Markers are custom layout-manager drawing rather than text or `NSTextList` metadata
(`ListMarkerLayoutManager.swift:11-15`). The attributed string exported to RTF/DOCX
therefore contains plain paragraphs with no bullets or numbers.

**Fix:** build an interchange attributed string that materializes standard list
semantics or literal markers. Verify nested lists and continuation numbering in both
formats.

### 1.18 Export conversion failure is reported as successful empty/partial output

**Severity: medium. Confidence: very high.**

RTF and DOCX conversion failures fall back to empty `Data`; PDF assembly silently
skips pages it cannot parse (`EditorController.swift:2612-2647`). The export helper
then atomically writes that result and reports success (`LucerneDocument.swift:
171-185`). Atomic writing protects the old file from a disk-full interruption, but
not from a deliberately generated empty result.

**Fix:** make every exporter throwing, reject empty output, preserve/report failed
PDF page indexes, and replace the destination only after validation.

### 1.19 Corrupt image data prevents otherwise intact text from opening

**Severity: medium. Confidence: high.**

`LuceArchive.read` treats all `images/` entries as non-droppable
(`LuceArchive.swift:66-72`). A CRC-damaged or oversized picture aborts archive open,
despite the format's stated placeholder behavior and recoverability goal.

**Fix:** keep `document.json` strict, but treat corrupt referenced images as missing
payloads and surface placeholders plus a warning. Unreferenced bad image entries
should never block the body text.

### 1.20 Paragraph-anchored images are specified but invisible

**Severity: medium. Confidence: very high.**

The model and normative documentation describe `anchor: "paragraph"`, but exclusion
and view synchronization explicitly process only page anchors
(`ExclusionPathController.swift:8-18`, `EditorController.swift:383-396`). A conforming
third-party document can therefore contain an image Lucerne silently does not show.

**Fix:** either implement anchor resolution or mark paragraph anchoring reserved and
unsupported in the v1 specification while preserving its data.

### 1.21 Unknown future object data is destroyed on save

**Severity: medium. Confidence: high.**

`PlacedObject` accepts unknown type strings but decodes only known members
(`DocumentModel.swift:408-466`). Saving rewrites the object without extension
payloads. This conflicts with the spec's claim that new object types need not bump
the format version.

**Fix:** preserve raw JSON for unsupported objects/members, or put the document in a
read-only/save-refusal state. Forward compatibility cannot be based on Codable
silently ignoring fields.

### 1.22 Style-library failure is safe but invisible

**Severity: medium. Confidence: high.**

The previous review correctly prevented a corrupt/future `styles.json` from being
clobbered, but call sites cannot report the failure. `load()` presents an empty
fallback and mutators only refuse/log. Export can write that empty fallback, and the
Style Library's export remains non-atomic (`StyleLibrary.swift:84-149`,
`StyleLibraryWindowController.swift:212-240`).

**Fix:** make load/save results explicit, expose a read-only error state, disable
mutations and export, and offer Reveal/Back Up/Reset actions. Use atomic writes.

### 1.23 Markdown image links are not escaped

**Severity: low-medium. Confidence: very high.**

Inserted filenames are retained in `src`, then emitted directly into alt text and
link destinations (`MarkdownExporter.swift:61-65`, `277-283`). Names containing
`]`, `)`, backslashes, or newlines can break `content.md`, the recovery artifact.

**Fix:** escape alt text and percent-encode or angle-bracket image destinations;
sanitize generated archive names where needed.

### 1.24 MiniZip lacks aggregate resource limits

**Severity: high for untrusted files, medium for this personal app. Confidence: high.**

The reader caps each uncompressed entry at 512 MiB but copies the entire archive,
inflates every entry, and retains every payload before `LuceArchive` filters it
(`MiniZip.swift:160-217`). Many legal-sized unknown entries can exhaust memory.

**Fix:** parse metadata first, extract only required names, add aggregate compressed
and uncompressed budgets plus an entry-count cap, and avoid inflating unknown data.

### 1.25 MiniZip skips a valid CRC value and accepts false EOCD signatures

**Severity: low. Confidence: high.**

CRC checking is skipped when the expected CRC equals zero even though zero is a
valid CRC-32 (`MiniZip.swift:204-208`). The backward EOCD scan accepts any matching
signature without validating comment length/end position (`MiniZip.swift:251-260`),
so a ZIP comment containing the signature can make a valid archive look corrupt.

**Fix:** always compare CRC and validate EOCD structure against the file boundary.

### 1.26 Save mutates in-memory history before archive generation succeeds

**Severity: low. Confidence: high.**

`LucerneDocument.data(ofType:)` assigns the updated history before
`LuceArchive.write` can throw (`LucerneDocument.swift:58-64`). A failed save leaves
a phantom snapshot in memory that appears in a later successful archive.

**Fix:** compute candidate history locally and assign it only after successful
archive generation.

## 2. General architecture and engineering issues

### 2.1 Lists shipped without a format/version contract

**Priority: P0.**

v0.5 writes `Paragraph.list` and `ListItemModel` while `currentFormatVersion` remains
1 (`DocumentModel.swift:27`, `225-345`). The normative spec explicitly says lists
are outside v1 and its schema omits `list`. `docs/file-format.md`, `PROGRESS.md`,
`AGENTS.md`, `docs/architecture.md`, and `docs/roadmap.md` are also stale.

An older v0.4 reader accepts v1, ignores list membership, and removes it on save.
The future-version guard therefore cannot protect a v0.5 list document from silent
downgrade. This is precisely the risk a canonical durable format should prevent.

**Decision needed:** preferably define format v2 with exact list semantics and v1
migration. If retaining v1 as an additive extension, explicitly acknowledge old
reader data loss and implement unknown-field preservation/capabilities. Update both
format documents and the JSON Schema in the same PR.

### 2.2 `EditorController` has become a change-risk hotspot

At roughly 2,800 lines it owns pagination, images, formatting, shortcuts, lists,
tables, styles, furniture, navigator/ToC, and exports. The class remains readable,
but interactions are mostly testable only through AppKit state and regressions now
occur at subsystem boundaries.

Do not split it merely for line count. Extract coherent stateful collaborators when
adding tests: table parsing/rebuild, paste normalization, and export preparation are
the clearest seams. Keep geometry and list numbering as pure helpers.

### 2.3 The model has no semantic validation phase

Codable validates shape, not meaning. Page dimensions, margins, finite geometry,
object indexes, IDs, table grids/spans/widths, list levels/markers, furniture start
pages, and object types need a documented validation/repair policy. This should be
shared by app open, scripting, stationery, and third-party format tests.

### 2.4 Forward compatibility is claimed but unknown JSON is not preserved

Optional additive fields work only when old readers do not resave documents. The
list downgrade and unknown-object loss show that the current "ignore what you do not
understand" policy is incomplete. Either preserve unknown members or use format
versions/capabilities whenever old writers would destroy semantics.

### 2.5 Page configuration and print configuration are weakly synchronized

Page Setup mutates the document model through a full reload but undo, focus, scroll,
selection, fold marks, and no-op detection are absent. This should become one
transaction with a complete old/new page snapshot rather than a view teardown side
effect.

### 2.6 Custom list rendering creates export, accessibility, and scaling obligations

The list renderer is clever and suitable for on-screen fidelity, but markers are not
semantic text. In addition to RTF/DOCX loss, fixed 24-point nesting gutters can be
too narrow for large decimal or Roman markers, and derived indents replace direct
pre-list indents. Cache marker resolution, widen gutters based on measured marker
content, preserve displaced direct indents, expose markers to accessibility, and
materialize semantics for interchange.

### 2.7 Release artifacts lack a trustworthy application identity

The release is ad-hoc signed and not notarized; installation instructions remove
quarantine. The updater trusts a GitHub asset without an independent signature,
digest, size, or application-identity check (`release.yml`, `make-app.sh`,
`UpdateDownloader.swift`). This is understandable for a personal project but is the
largest distribution-readiness gap.

Use Developer ID signing, hardened runtime, notarization, stapling, and release-time
verification. Prefer Sparkle or another independently signed update channel; at a
minimum verify GitHub's SHA-256 asset digest and expected host/type/size.

### 2.8 Release assembly fails open in several places

`make-app.sh` warns and continues after icon/signing failure, conditionally omits the
SDEF, and the release workflow tolerates DMG creation failure. CI's bundle assertions
are stronger than release's. Required release inputs should fail hard, and published
ZIP/DMG artifacts should be mounted/extracted and validated before upload.

### 2.9 Build/release supply-chain inputs are mutable

Actions use mutable major tags, Homebrew installs the current `create-dmg`, Xcode
selection failure is ignored, and local scripts execute unpinned external
`lkm-build`/`lkm-release` tools. Pin actions and packaging tools, require a known
Xcode, and separate read-only build permissions from the publication job.

### 2.10 Menu actions remain compile-unchecked strings

`MainMenu.add` constructs selectors from raw strings. Current selectors resolve, but
a rename compiles and yields a disabled command. Prefer `#selector` for app actions
and add a menu-walking test across no-document, text, image, list, and table states.

### 2.11 App-shell behavior has almost no automated coverage

The test target covers `LucerneKit`, not the app target/updater. There is no launch
smoke test, menu reachability test, lifecycle/save-review test, SDEF execution test,
or updater fixture suite. Move reusable updater logic into a testable target and add
assembled-app smoke tests on macOS CI.

### 2.12 Private `_cornerMask` is a compatibility and distribution risk

`ClassicWindow` implements an underscored AppKit hook (`ClassicControls.swift:
906-941`). It may break on future macOS and would be problematic for Mac App Store
review. The visual gain is small relative to the maintenance risk. Remove it for
distribution or isolate it behind a tested runtime fallback.

### 2.13 Help is a repository README, not product help

The Help command opens material centered on source/build/file format rather than
how to write, place images, use styles, recover versions, or create stationery.
Lucerne needs a short built-in user guide and searchable shortcut reference.

### 2.14 Documentation/status drift is systemic

Current docs still claim lists, DOCX export, and Markdown table rendering are
unfinished; AGENTS and architecture say lists do not exist; PROGRESS contradicts
itself about dotted ToC leaders and tables. Source comments and tests retain
pre-list-palette language. Add a feature-landing checklist that updates the format
contract, architecture, progress, roadmap, tests, and screenshots together.

## 3. Performance and stuttering risks

The one-to-five-page letter case is likely acceptable. These paths matter for long
letters, image-heavy stationery, tables, or the user's perception during scrolling.
Measure before and after with 25-, 100-, and 250-page fixtures.

### 3.1 Scrolling triggers full chrome and all-page layout work

Every clip-view bounds change calls `viewportChanged`, which calls
`EditorContainerView.layoutContents` (`DocumentWindowController.swift:494-503`).
That invokes `PageCanvasView.layoutPages` and visits every page
(`DocumentWindowController.swift:755-787`, `PageCanvasView.swift:41-64`) merely to
keep ruler geometry and page status current.

**Fix:** split scroll-time ruler/status synchronization from structural page layout.
Only relayout page frames when geometry/page count changes.

### 3.2 Page shadows have no stable `shadowPath`

Each page uses a live layer shadow without a path (`PageContainerView.swift:40-46`).
Core Animation may repeatedly derive the shadow from changing rendered content.
Set a rectangular path when page bounds change and profile offscreen rendering.

### 3.3 Formatting commands still relayout twice

`withUndo` synchronously relayouts after storage mutation, while the storage delegate
schedules another relayout next turn (`EditorController.swift:570-592`,
`2653-2668`). The prior audit identified this and it remains open.

**Fix:** coalesce explicit and delegate relayout by edit generation/token, or make the
deferred pass authoritative. Verify operation ordering and one-relayout-per-command.

### 3.4 Each edit still performs broad document/page/object work

Every ordinary text change scans storage for page breaks, forces final-container
layout, loops pages for exclusions, syncs image views, filters objects per page for
stacking, lays out pages, and resolves page furniture (`EditorController.swift:
207-359`, `383-425`). The exclusion dirty check fixed the largest invalidation, but
the orchestration remains broad.

Use `syncImages: false` for pure text edits where safe, index objects by page, cache
page-break positions by edit generation, update furniture only when token inputs or
page count change, and instrument each phase before larger restructuring.

### 3.5 Long-list marker drawing repeats prefix scans

`ListMarkerLayoutManager` walks backward to a list start and forward through prior
items to resolve markers. Drawing later pages of one long list repeats the prefix,
approaching quadratic total work. Cache resolved markers by storage generation and
invalidate from the edited list item onward.

### 3.6 Table ruler state reparses the whole table on every caret move

The previous fix stopped scanning from character zero, but `currentTableColumnWidths`
still parses every cell in the current table on selection changes
(`EditorController.swift:1596-1645`, `1712-1718`). Cache parsed tables by table
identity and text-storage generation.

### 3.7 Style Editor counts every paragraph on every caret move

The blast-radius label calls an O(document) style-role count whenever selection
changes (`StyleEditorPanel.swift:161-166`, `474-481`; `EditorController.swift:
2231-2251`). Cache role counts by text/attribute generation; caret movement does not
invalidate them.

### 3.8 Saves/autosaves run full serialization on the main thread

Each save snapshots the model, exports Markdown twice, updates history, CRCs images,
and constructs the complete ZIP in memory (`LucerneDocument.swift:58-64`,
`LuceArchive.swift:30-61`). Titled documents autosave elsewhere every 30 seconds, so
large images can cause periodic typing stalls.

Capture AppKit-bound state on main, reuse one Markdown result, then perform history,
ZIP construction, and writing off-main through supported asynchronous `NSDocument`
APIs. Streaming would also reduce peak memory.

### 3.9 Image decode, insertion, and resizing are main-thread/full-resolution

Drop/paste reads files and converts images synchronously (`PageTextView.swift:
224-237`). `FloatingImageView` draws the full-resolution source at every live resize
frame. Validate/load large data off-main, cache a display representation keyed to
effective screen size, use lower-quality preview during resize, and render full
quality on mouse-up/print.

### 3.10 Caret movement redraws more chrome than necessary

Every selection change synchronizes the complete toolbar and ruler. Several custom
control setters invalidate drawing even when the value is unchanged. Diff one
immutable UI-state snapshot before assigning controls and avoid disk/document scans
from selection observers.

### 3.11 All page views remain resident

The current design creates text and page views for every page. This is simple and
correct for letters, but gives memory and scrolling costs proportional to document
length. Do not virtualize blindly because TextKit containers still need layout;
first profile whether only expensive decoration/image/page rendering can be made
viewport-aware.

## 4. Visual, layout, accessibility, and interaction issues

### 4.1 Custom chrome is largely inaccessible and mouse-only

**Priority: P0/P1, not polish.**

The hand-drawn controls, chooser segments, palette rows, ruler markers, zoom widgets,
and image handles define almost no accessibility roles, labels, values, actions, or
children. Focus rings are often suppressed. Full Keyboard Access cannot reach or
operate much of the surface; VoiceOver cannot explain individual formatting states.

Keep the classic visual language, but make it a skin over native accessible control
behavior where possible. For truly custom controls implement explicit
`NSAccessibility`, visible keyboard focus, Return/Space activation, increment/
decrement actions, and a deliberate key-view loop. Audit with Accessibility
Inspector, VoiceOver, Increase Contrast, Reduce Transparency, and keyboard-only
New -> type -> format -> place image -> save.

### 4.2 Toolbar state is not honest for mixed/custom formatting

Decimal font sizes are rounded for display, custom line spacing can leave a stale
preset visible, and mixed selections are represented by the first run/paragraph
(`ToolbarView.swift:376-401`, `EditorController.swift:1978-1989`, `2337-2343`).

Show mixed states, preserve decimal sizes, and use a visible Custom value rather
than retaining an unrelated prior preset.

### 4.3 Welcome and Navigator lack standard keyboard activation

Navigator activation uses `clickedRow`, not keyboard `selectedRow`
(`NavigatorView.swift:63-67`). Welcome recents are double-click-only and no default
New button handles Return (`WelcomeWindowController.swift:86-104`, `185-187`).
Add Return/Space activation, an initial responder, a default New action, and semantic
heading indentation rather than literal spaces.

### 4.4 Floating palettes lie when no document is open

Only Styles has an explicit no-letter state. Typefaces and Lists remain populated
and active-looking but silently do nothing; style footer actions also look enabled
when their guards will discard the click (`FloatingPalette.swift:138-300`). All
palette kinds need a consistent "No letter open" state and honest enablement.

### 4.5 Style Editor's quiet state is stale and incomplete

When the target disappears, old specimen/field values remain visible; the size field
is omitted from disabled controls; missing fonts can leave a stale popup selection;
and a specimen capped at 18 pt cannot honestly be "exactly as it prints"
(`StyleEditorPanel.swift:359-437`, `537-549`, `782-815`). Clear or ghost stale
values, disable every control, show an explicit missing-font item, and describe the
specimen as a compact preview.

### 4.6 Picker filtering has ambiguous preview/commit behavior

When filtering removes the current candidate, the picker reloads without
deterministically selecting and previewing the first match. Return can commit the old
preview or an unclear selection; click-away always commits but the hint does not say
so (`PickerListView.swift:200-227`, `TryOnPopover.swift:97-115`). Make candidate
selection deterministic and explain Return, Esc, and click-away behavior.

### 4.7 Ruler interaction is not live or keyboard-friendly

Drag updates only local marker state and applies text/table changes on mouse-up
(`LucerneRulerView.swift:285-332`). There are no directional cursors for every
element, Esc cancellation, numeric readout, keyboard adjustment, or context menu;
tab type cycles only by double-click. Add live preview, Esc-to-revert, hover
highlight, right-click type choice, position readout in the status bar, and
pixel-aligned strokes at arbitrary zoom.

### 4.8 Clicking visible paper margins still does nothing

The text view covers only the content frame and `PageContainerView` has no click
handling. A click on white paper outside the body is silently swallowed. Route
ordinary side-margin clicks to the nearest text position; reserve explicit top/bottom
zones for future in-place furniture editing.

### 4.9 Auxiliary windows use an inconsistent visual language

Document, welcome, palette, and library windows use classic chrome, while Find,
Settings, About, alerts, and several sheets use unrelated stock layouts. Do not
custom-draw everything; instead apply one accessible utility-window spacing grid,
typography, etched section treatment, and button hierarchy over native controls.

### 4.10 The toolbar solves narrow windows by forbidding them

The fixed-width horizontal format bar forces a wide minimum window. This is fragile
with smaller displays, localization, and larger accessibility text. Add a compact
mode or period-appropriate overflow well while retaining menu access to every
command.

### 4.11 Image selection lacks a compact inspector and standard object commands

Wrap and standoff live in menus; there is no exact x/y/size control, aspect lock,
crop/rotate, align, distribute, z-order, duplicate/copy, or contextual inspector.
The selected object is the moment when classic object controls should replace generic
status text or appear as a small "object ticket."

### 4.12 Active page/navigation feedback is weak

Long or heading-free letters get little value from the navigator, and the canvas
does not strongly indicate the active page. Add a current-heading highlight,
friendly empty state, optional page thumbnails, and a subtle active-page emphasis.

## 5. User-facing gaps, prioritized

### P0 - correctness and expected basics

1. Reliable document-wide Select All, copy, delete, and formatting surrogates.
   True cross-page drag/Shift selection is a larger project, but Command-A should
   not behave like "this page only" in a word processor.
2. Accessible and keyboard-complete format bar, palettes, ruler, images, Welcome,
   and Navigator.
3. Paste normalization and a lossless Lucerne fragment for cross-document paste.
4. A documented, migration-safe list format.
5. Signed/notarized distribution and trustworthy updates.

### P1 - capabilities a letter writer will notice

1. Open/import plain text and Markdown; then RTF and DOCX import with an explicit
   fidelity report.
2. Preserve list semantics in RTF/DOCX export.
3. Copy Style / Paste Style and direct paragraph before/after spacing controls.
4. In-place header/footer editing.
5. Exact image inspector with position, size, wrap, standoff, crop, rotation,
   alignment guides, snapping, z-order, and duplicate.
6. Document Info: words, characters, paragraphs, pages, images, created, modified,
   language, and estimated reading time.
7. In-app version history browser with preview, Copy, Restore as New, and reveal in
   archive.
8. Real product Help with a two-minute tour and searchable shortcuts.

### P2 - useful classic word-processing depth

1. Strikethrough, superscript/subscript, and hyperlinks with honest export behavior.
2. Envelope page presets, address placement, and print workflow.
3. Paragraph-anchored objects.
4. Irregular alpha wrap and image overhang.
5. Page thumbnails and a richer outline navigator.
6. Better table behavior for multi-paragraph cells, row splitting, merged-cell
   structure edits, and accessible markers.
7. Language per document/selection and document-wide spelling state.
8. Sections only if they solve a concrete need such as first-page furniture or
   mixed numbering; avoid turning Lucerne into Word.

### Explicitly avoid for now

- Collaboration, comments, change tracking, cloud accounts, and plugin systems.
- A ribbon or inspector maze that undermines the deliberately small product.
- Replacing TextKit 1 solely because TextKit 2 is newer.
- A general drawing application before text boxes and image controls are excellent.
- Per-page paper sizes, which would undo one of the architecture's best simplifying
  constraints.

## 6. Delightful, quirky, and distinctive ideas

These are ordered by product fit and reuse of existing machinery, not novelty alone.

### 6.1 Wrap X-ray

When an image is selected, ghost the *actual* exclusion path, including standoff and
the narrow-column extension to the margin. This makes Lucerne's defining behavior
legible and turns a hidden safeguard into a delightful teaching tool. Add an
Option-held always-show mode while dragging.

### 6.2 Magnetic image guides

Snap images to margins, page center, furniture baselines, fold marks, and other
object edges. Show thin cyan/blue-black guide lines and a live x/y readout in the
existing status hint channel. Hold Option to bypass snapping.

### 6.3 Signature Shelf

Store scanned signatures under Application Support using the same pattern as
Stationery and Style Library. **Insert -> Signature** drops one as a wrap-none
floating image near the caret. Include scale presets but never modify the original.

### 6.4 Correspondent Card and envelope proof

Add optional sender/recipient fields with `{sender}` and `{recipient}` furniture
tokens. An Envelope Proof mode overlays the address window, real DIN fold marks,
and safe regions. This joins furniture, fold marks, stationery, and printing into a
feature no generic editor would bother to make.

### 6.5 Visible version browser

The archive already carries and loads Markdown history. A small classic browser with
a date list, read-only preview, diff against current text, Copy, and Restore as New
makes the twenty-year recovery promise tangible rather than hidden inside ZIP.

### 6.6 Ink Desk

Put five recent swatches beside the color well, seeded with blue-black, sepia,
graphite, deep red, and true black. Persist globally, show names in accessibility
labels, and let Option-click pin a favorite.

### 6.7 Tab Laser

While dragging a tab, indent, or table divider, draw a vertical guide down the active
page with a unit-aware coordinate. Decimal tabs especially benefit. This is tiny,
period-correct, and makes the ruler feel precise.

### 6.8 Stationery gallery

Turn the Welcome screen's New area into a restrained thumbnail shelf: Blank Letter,
recently used stationery, and Manage Stationery. Render thumbnails from the same page
PDF pipeline; keep opening stationery as an untitled copy.

### 6.9 Quick Format Book

A keyboard-invoked searchable specimen panel combining styles, typefaces, and list
markers, with "used in this letter" and favorites. It should feel like flipping
through a type specimen, not a command palette from a code editor.

### 6.10 Page edge notes

For personal drafting, allow temporary non-printing sticky notes in the gray canvas
beside a page. They should be clearly outside document content and optionally saved
as Lucerne-only annotations. This needs a format decision and should follow unknown
field preservation.

### 6.11 Typewriter mode

Optional restrained key clicks and a margin bell, disabled by default and never
stored in the document. Include a "silent after 10 p.m." courtesy option. It is
unnecessary, memorable, and exactly on theme.

### 6.12 Letter ritual mode

A minimal command that inserts today's date, positions the caret for salutation, and
offers a closing/signature at the end. It should be a gentle template assistant, not
mail merge. Learn choices per stationery rather than globally.

### 6.13 Paper personality

Offer non-printing canvas presentation choices such as warm paper, cool white, or
high-contrast proofing, while all print/PDF output remains pure page color. Respect
Increase Contrast and provide a no-texture mode.

## 7. Test and QA plan

The current pure-model tests are valuable, but feature interactions need a macOS
integration layer.

### Required automated regressions

1. `loadSampleContent()` followed by real `.luce` archive generation.
2. Malformed model ranges: negative/`Int.max` object pages, huge table coordinates
   and spans, huge list levels, non-finite geometry, invalid margins.
3. Paragraph ID uniqueness after ordinary Return, split, heading demotion, list
   continuation, page break, and paste.
4. Empty/sole/trailing paragraph matrix covering style, alignment, tabs, spacing,
   page break, table cell, list, ID, dirty state, and undo.
5. Multi-paragraph table cells through row/column edit, resize, distribute, merge,
   save, and undo.
6. Style application preserving italic/bold/underline/color/font/size plus table,
   list, and page-break structure.
7. Rich paste fixtures containing every supported and unsupported attribute.
8. Page-break stability when inserting/deleting/replacing at paragraph start.
9. Corrupt/oversized image entries opening body text with placeholders.
10. ZIP aggregate limits, entry count, CRC zero, EOCD-in-comment, duplicate names,
    local/central disagreement, and a real external DEFLATE fixture.
11. List schema golden files, v1/v2 migration, and older-reader downgrade behavior.
12. RTF/DOCX list preservation and injected export-converter failures.
13. Markdown image filenames with brackets, parentheses, slashes, spaces, Unicode,
    and newlines.
14. Style-library corrupt/future/permission-denied UI behavior.
15. Menu action reachability and plist/SDEF validation from the assembled app.

### On-device interaction matrix

1. Ventura through the current macOS release, Intel if still supported, Retina and
   non-Retina scaling, light/dark system settings despite Lucerne's aqua choice.
2. VoiceOver and Full Keyboard Access for a complete letter workflow.
3. Increase Contrast, Reduce Transparency, reduced motion, and large accessibility
   display settings.
4. 25/100/250-page scroll FPS and caret latency; long numbered lists; large tables;
   image-heavy save/autosave; PDF export.
5. Page boundaries: selection, find result reveal, tables, page breaks, image drag,
   zoom, and print.
6. Multiple open documents with global palettes, Style Editor, smart quotes/dashes,
   spell checking, update alerts, save sheets, and quit review.
7. Clean-Mac ZIP/DMG install, Gatekeeper, update download, offline/error paths, and
   altered artifact rejection after signing work lands.

## 8. Recommended implementation order

### Release 0.5.1 - stop data loss and broken first impressions

1. Fix Sample Letter persistence.
2. Validate malformed object/list/table ranges and prevent open-time traps.
3. Preserve direct formatting when applying styles.
4. Prevent multi-paragraph table-cell loss.
5. Make exports throw instead of writing empty/partial files.
6. Preserve page config fields and no-op behavior.
7. Correct fold marks.
8. Reconcile all status/format documentation.

### Release 0.6 - format and editing integrity

1. Specify/version lists and migration behavior.
2. Normalize rich paste and paragraph IDs.
3. Complete empty/trailing paragraph persistence.
4. Add document-wide command surrogates.
5. Preserve list semantics in RTF/DOCX.
6. Surface style-library failures and corrupt-image placeholders.

### Release 0.7 - inclusion, speed, and delight

1. Accessible keyboard-complete classic controls.
2. Remove scroll-time all-page layout and redundant relayouts.
3. Cache list/table/style-count work and move archive work off-main.
4. Add Wrap X-ray, magnetic guides, and the image object ticket.
5. Ship in-app history and better Help.

## 9. Relationship to `fable-is-awesome.md`

All companion branches listed in the earlier review are merged. Do not carry their
completed findings into a live backlog. The following earlier items remain open or
only partially fixed and are incorporated above:

- Style application preserves structure but not inline direct formatting.
- Rich-paste normalization.
- Style-editor undo sealing before intervening text edits.
- Page-setup undo/context preservation.
- Equal-share table-width round-trip normalization.
- Compile-unchecked menu selectors.
- Redundant formatting relayout.
- Style blast-radius count on caret movement.
- Main-thread save/archive construction.
- Full-resolution image redraw during resize.
- Custom-control accessibility.
- Copy/Paste Style.
- Blank-margin click behavior.
- Welcome/palette keyboard behavior.
- Update download progress.
- Cross-page selection and document-wide commands.
- Plain-text/Markdown import, strikethrough/super/subscript, hyperlinks, floating
  text boxes, envelopes, and the unimplemented delightful ideas.

Lists, DOCX export, Markdown table export, fold marks, stationery, Insert Date,
Markdown shortcuts, heading next-style behavior, page-of-N status, and the welcome
epigraph have shipped since or through that review. Their old "missing" entries are
historical and must not appear as active work.

The codebase is worth continuing. The best next move is not to out-feature Word; it
is to make every small promise Lucerne already makes completely trustworthy, fast,
keyboard-reachable, and charming.
