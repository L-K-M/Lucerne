# fable-is-awesome.md — a Fable 5 review of Lucerne

A full review of the codebase (~11,300 lines of Swift) as of `f37ac34` ("CI/CD
updates and readme change", v0.4.0). This is the successor to
[`awesome.md`](awesome.md) (written at v0.2.0, whose companion PRs #8–13 all
landed); everything below was verified against the **current** source, and
items from the old review are only repeated when they were never implemented.

**Methodology.** Eleven specialized reviewers each read a slice of the codebase
completely (core editing, text bridge & model, IO & persistence, chrome views,
canvas views, app shell & updater, performance, UX, missing features, ideas,
docs/tests/CI). Every bug, performance, and visual claim was then handed to an
independent adversarial verifier instructed to *refute* it by tracing the actual
code paths — callers, callees, and reachability — not the quoted snippet. Of 80
code-level claims, **79 were confirmed and 0 refuted** (one remains plausible
but rests on AppKit documentation rather than repo source). Feature gaps and
ideas were checked against the source for genuine absence. Each entry carries a
location and severity; where a companion branch implements the fix, it says so
(section 9 has the full table).

**Overall impression, because it's earned:** Lucerne remains a genuinely
well-built codebase, and it has grown a lot since the last review without
losing its shape. The architecture is still exactly what the plan called for,
the styles engine (S1–S7) is thoughtfully designed and documented, the classic
chrome is drawn with real care, and the previous review's fixes all stuck.
The findings below cluster in three places: the *new* code (style
editor/library, palettes, chrome) shipped faster than its edge cases; the
model/spec contract has drifted in a few decode paths; and a handful of
per-keystroke code paths do whole-document work that letters forgive but
longer documents won't.

---

## 1. Bugs

Ordered by severity. All confirmed by adversarial verification against
`f37ac34` unless marked otherwise.

### High

#### 1.1 Applying a paragraph style destroys table membership and page breaks — `EditorController.swift:775`

`applyStyleRole` replaces every attribute of each selected paragraph with
`storage.setAttributes(attrs, range:)`, where `attrs` comes from
`AttributedStringBuilder.typingAttributes` — which never carries an
`NSTextTableBlock` or `.lucernePageBreakBefore`. So applying a style inside a
table cell pops the cell out of the grid (and on save,
`AttributedStringReader.tableCell` returns nil, so `paragraph.cell` is lost
from the model **permanently**); restyling a paragraph that starts a forced
page break silently deletes the break. Reachable from the context menu, ⌃⌘1–9,
the toolbar chooser, and the styles try-on palette (whose live preview applies
for real). Even re-applying the paragraph's *current* role triggers the wipe.
Undo recovers it until the document is saved or any stylesheet edit
re-canonicalizes the storage; after that the loss is permanent. Contrast with
`modifyParagraphStyle` and `setTabStops`, which correctly `mutableCopy` the
existing paragraph style. Related UX facet: the same `setAttributes` also wipes
**inline character formatting** (a bolded word, a colored phrase) in the
paragraph — inconsistent with the S3 engine, whose entire point is that direct
formatting survives style changes.
→ **Fixed in `claude/apply-style-preserves-structure`** (table blocks + page
breaks; the inline-formatting question is noted there as a follow-up design
decision).

#### 1.2 Images anchored to a trimmed page silently disappear on reopen — `EditorController.swift:326`

`syncImageViews` skips any object whose page index `>= pages.count`, then
removes its view. Pagination only grows pages for *text* overflow; during
editing a page hosting only an image survives because `lastPageIsTrulyEmpty()`
checks for live `FloatingImageView` subviews — but on open, `load(model:)`
tears everything down and paginates from text alone *before* any image views
exist. Scenario: two-page letter, image on page 2, delete text back to one
page (page 2 survives the session), save, reopen — the image is invisible with
no way to reach it from the UI, riding along in the `.luce` forever. Also
reachable without reopening via `updatePageConfig` (which reloads) and by
undoing an image deletion after its page was trimmed.
→ **Fixed in `claude/pagination-image-fixes`** (pagination now grows pages to
cover page-anchored objects, and trimming consults the model).

#### 1.3 A missing font permanently destroys the document's font names on save — `AttributedStringReader.swift:135`

`FontResolver.font` silently falls back (missing family → system font), and on
save `AttributedStringReader.makeRun` persists the **resolved** family, not the
requested one. Open a letter set in Garamond on a Mac without Garamond, save,
and every run that differed from its style's font is rewritten as a Helvetica
(system) override — bring the file back to the original Mac and the fonts are
gone for good. (The style *definitions* survive; what's destroyed is every
run-level font override, and style-level intent gets pinned as overrides on
every paragraph.) The fix is to preserve intent: stash the requested
family/traits in a private attribute when resolution falls back, and persist
that.
→ **Fixed in `claude/text-bridge-fixes`**, with a round-trip test using a
nonexistent family.

#### 1.4 Titled documents have zero crash recovery — `LucerneDocument.swift:43`

`autosavesInPlace = false` (deliberate — the beloved dot-and-prompt model) and
`autosavesDrafts = true` — but drafts only cover **never-saved** documents. For
a previously saved document with unsaved edits, AppKit's crash protection in
the non-autosave world is periodic autosave-elsewhere driven by
`NSDocumentController.autosavingDelay`, which defaults to 0 = **off**, and
nothing in the codebase sets it. An hour of editing on a titled letter + a
crash = an hour gone. One line (`autosavingDelay = 30`) enables classic
autosave-elsewhere (to `~/Library/Autosave Information`) without changing the
save-prompt behavior at all.
→ **Fixed in `claude/io-safety`.**

#### 1.5 Document Setup accepts margins larger than the page → runaway pagination — `DocumentSetupSheet.swift:41`

Margin fields are clamped only at the low end (`max(0, …)`), have no
`NumberFormatter` (non-numeric text silently becomes 0), and are never checked
against the page size. `PageMetrics.contentSize` clamps to zero width;
`paginateAndExclude` guards only the *height* — a zero-width (or
sliver-width) container lays out nothing, every page "overflows," and the app
churns to the 2000-page `maxPages` cap. Enter `400` in left+right margins on
A4 and watch it spin.
→ **Fixed in `claude/document-setup-fixes`** (validated fields, content-area
clamp, plus a defense-in-depth guard in pagination).

### Medium

#### 1.6 Spec-conformant `.luce` files fail to open: `TabStopModel` requires `type` — `DocumentModel.swift:303`

The spec (§6.5, and Appendix A's JSON Schema) says `pos` is required and
`type` optional (default `"left"`), but the synthesized Codable requires
`type` — decoding `{"pos": 72}` throws and **the whole document refuses to
open**. Lucerne's own writer always emits `type`, so this only bites
third-party writers following the normative spec — exactly the contract the
spec exists to protect. → **Fixed in `claude/format-decode-fixes`** (custom
decoder following the in-file `TableCellModel` pattern, plus a test).

#### 1.7 Same class of bug: `PageFurniture` requires all three zones — `DocumentModel.swift:98`

The spec (§3.2) and its own worked example (`{"center": "Page {page}"}`)
declare each zone optional with default `""`; the synthesized Codable requires
all three, so a partial footer fails the entire document decode.
→ **Fixed in `claude/format-decode-fixes`.**

#### 1.8 The trailing empty paragraph loses its identity on every save — `AttributedStringReader.swift:37`

The builder appends nothing for a trailing empty paragraph (the final `\n`
carries the *preceding* paragraph's attributes), so the reader reconstructs
the last paragraph with the previous paragraph's style role and formatting,
and a freshly minted id. Type a letter, press Return, style the empty line as
Heading 1, save, reopen: it's Body again. Its id also churns on every save,
polluting diffs of `document.json`. → **Fixed in `claude/text-bridge-fixes`**
(snapshot passes the live trailing paragraph's identity to the reader).

#### 1.9 Style/paragraph commands are silent no-ops on the trailing empty paragraph — `EditorController.swift:766`

For `"Hello\n"` with the caret at index 6 (after Return at the end — the most
common place to be), `paragraphRange` is `(6, 0)` and the per-paragraph loops
in `applyStyleRole`/`modifyParagraphStyle` never execute; the
typing-attributes fallback only covers `storage.length == 0`. So "Return →
pick Heading 1 → type" does nothing. On the menu path it still registers a
junk undo entry and dirties the document (the toolbar try-on path escapes
that). `currentStyleRole()` has the matching cosmetic bug: it reports the
previous paragraph's style for a collapsed caret instead of consulting typing
attributes. → **Fixed in `claude/apply-style-preserves-structure`.**

#### 1.10 Pasted rich text silently loses formatting on save — `EditorController.swift:125`

`isRichText = true` with no paste normalization: RTF/HTML paste injects
arbitrary attributes the model can't represent. Strikethrough, links,
superscript, background color survive **on screen** but vanish on save/reopen
with no warning — and any stylesheet edit strips them immediately (the S3
re-apply round-trips the storage through the reader). Pasted content can also
land without `.lucerneStyleRole`/`.lucerneParagraphID`, corrupting the
receiving paragraph's identity. Fixing this properly means re-baselining
pasted text at the boundary (map what's representable, drop the rest
*visibly*); documented here rather than patched, because the right whitelist
deserves a considered pass. (See also 6.4 — Paste and Match Style is the
everyday escape hatch, and it *is* implemented.)

#### 1.11 A corrupt or future-versioned `styles.json` is silently clobbered — `StyleLibrary.swift:57`

`load()` swallows every failure into "empty library" — including the
*deliberate* future-version rejection thrown by `decode()`. Every mutator is
read-modify-write on top of that: run a newer Lucerne once, then let an older
build save one style, and the newer library file is **overwritten wholesale**.
Same for a transiently unreadable file. → **Fixed in
`claude/style-library-robustness`** (load distinguishes missing from broken;
destructive writes refuse while in the failure state).

#### 1.12 Printed pages and exported PDFs carry the on-screen page border — `PageContainerView.swift:45`

`draw()` unconditionally strokes the 1 pt gray page-edge outline that exists
to separate the white page from the gray canvas; `makePagePDFs()` captures the
same drawing, so every print and PDF export has a hairline box around the
page. → **Fixed in `claude/window-sync-fixes`** (stroke only when drawing to
screen).

#### 1.13 Lucerne can save a `.luce` it then refuses to reopen — `MiniZip.swift:34`

The hardening PR capped *reads* at 512 MiB per entry, but `archive()` has no
size validation: drop a 600 MB TIFF in, save fine — and the document can never
be opened again (image entries are non-droppable on read, so the size guard
fails the whole archive). Entries over 4 GiB trap mid-save on the `UInt32`
conversion. → **Fixed in `claude/io-safety`** (write path enforces the same
cap and surfaces a normal save error).

#### 1.14 Style editor rewrites a style's font when the typeface isn't installed — `StyleEditorPanel.swift:364`

`fontPopup.selectItem(withTitle: def.font)` is a silent no-op when the family
isn't in `availableFontFamilies`, so the popup keeps showing the previous
selection (or the alphabetically-first family on a fresh panel), and the next
`readControls` writes that stale title into the style definition — editing
*any* property of a Garamond style on a Garamond-less Mac silently rewrites
its font. → **Fixed in `claude/style-editor-toolbar-fixes`** (missing-font
placeholder item).

#### 1.15 Style editor's library strip lies during live edits — `StyleEditorPanel.swift:214`

`apply(_:to:)` refreshes the specimen and labels but never `refreshStrip`, so
after tweaking a document style that matched the library, the strip keeps
claiming "Library: matches your copy ✓" (and hides Update Library / Use
Library Copy) until an unrelated retarget. One-line fix.
→ **Fixed in `claude/style-editor-toolbar-fixes`.**

#### 1.16 Style-edit undo sessions aren't sealed by intervening document edits — `StyleEditorPanel.swift:184`

Live tweaks apply with `registerUndo: false` and the coalesced step is only
registered on retarget/close. STYLES.md §6.3 explicitly requires that editing
the letter's text seals the session — that trigger is unimplemented. So: tweak
a style, type in the letter, press ⌘Z — the undo stack has no style step yet
(the typing undoes instead); when the session later seals, the style step
lands *above* newer edits, scrambling undo order. Fix: observe the undo
manager's group-close/will-undo notifications and seal. Documented for a
careful pass (undo-ordering surgery deserves one) rather than batch-fixed.

#### 1.17 Two try-on pickers can corrupt each other's undo baseline — `ToolbarView.swift:188`

`presentFontPicker` guards only against its own picker being open (and
vice-versa for styles). Both popovers are `.transient`, so clicking the other
chooser closes the first *asynchronously* — the second session's
`beginFormatPreview` can run before the first's `endFormatPreview`, replacing
the snapshot and making the first session's changes silently uncommittable.
→ **Fixed in `claude/style-editor-toolbar-fixes`** (cross-guard both pickers;
`beginFormatPreview` defends against double entry).

#### 1.18 Locale decimal commas are silently ignored in numeric fields — `StyleEditorPanel.swift:407`

Every numeric style-editor field (and the toolbar size field) parses with
locale-blind `Double(...)`: a user in a comma-decimal locale (de-DE, fr-CH…)
who types "1,5" gets a silent no-op while the field keeps displaying the
rejected value. → **Fixed in `claude/style-editor-toolbar-fixes`** (shared
locale-aware parse helper).

#### 1.19 Format ▸ Font ▸ Show Fonts (⌘T) is dead — `MainMenu.swift:151`

`orderFrontFontPanel:` is an action on `NSFontManager`, which is not an
`NSResponder` and is never in the responder chain; with a nil target the item
is permanently disabled. (Nib-based apps work because the template wires the
target explicitly.) One line: set the item's target to
`NSFontManager.shared`. → **Fixed in `claude/app-shell-and-menus`.**

#### 1.20 Opening a stale recent from the Welcome window shows nothing — `AppDelegate.swift:80`

`onOpenRecent` discards the completion error, and the welcome window closes
*before* the open is attempted — double-click a recent whose file was moved
and you're left staring at zero windows. → **Fixed in
`claude/app-shell-and-menus`** (present the error, bring the welcome back;
plus 5.6's broader close-after-success fix).

#### 1.21 Arrow-key cell navigation lands in the wrong cell in merged tables — `EditorController.swift:1195`

`cellStartOffset` walks the full rectangular grid adding
`grid[r][c].length + 1` for every position — but after Merge Cells the storage
contains *nothing* for covered positions, so every covered position before the
target adds a phantom +1 and ↑/↓ land past the intended cell (drifting further
right/down the more merges precede the target). → **Fixed in
`claude/table-fixes`** (spans-aware offsets).

#### 1.22 Merging a selection that clips an existing merged cell leaves uncovered holes — `EditorController.swift:1131`

`cellRegion` doesn't close over merges that intersect the selection's bounding
box: merge cells over a region that partially overlaps an existing span and
positions covered by neither cell get dropped from the rebuilt grid — a
malformed table that then round-trips to the file. → **Fixed in
`claude/table-fixes`** (region expands to span-closure before merging).

#### 1.23 Spec-conformant image paths outside flat `images/<file>` are destroyed — `LuceArchive.swift:72`

The spec says `src` MUST name an archive entry, "conventionally" under
`images/` — but the reader accepts only exact flat `images/x` names
(`FormatSafetyTests` even asserts nested paths are ignored), and the writer
then drops the unloaded bytes on the next save. A third-party file using
`images/2026/lake.png` loses its pictures after one open+save cycle. The
cheapest honest fix is to make the spec normative about the flat shape;
→ **spec tightened in `claude/docs-and-ci-housekeeping`**, and 2.6's
missing-image guard in `claude/io-safety` prevents the silent byte-dropping.

### Low

#### 1.24 `{title}` header token goes stale after Save As / rename — `DocumentWindowController.swift:154`

`editor.documentTitle` is assigned exactly once, in `showWindow`. Save
"Untitled" as "Offer Letter.luce" and headers keep printing "Untitled" —
including into PDF/print — until the document is reopened. Fix: override
`synchronizeWindowTitleWithDocumentName()`. → **Fixed in
`claude/window-sync-fixes`.**

#### 1.25 Word count cache is keyed only by text length — `DocumentWindowController.swift:199`

Same-length edits (select a word, paste an equal-length replacement) show a
stale count until the length changes. → **Fixed in
`claude/window-sync-fixes`** (edit-generation key; see also 3.2).

#### 1.26 Reader never validates `format` — `DocumentCoding.swift:45`

The spec says a reader MUST reject a file whose `format` isn't
`"lucerne-document"`; `decode()` probes only `formatVersion`. The codebase
already does this correctly for the style library. → **Fixed in
`claude/format-decode-fixes`.**

#### 1.27 Markdown escaping misses block-level metacharacters — `MarkdownExporter.swift:98`

Prose beginning `#`, `>`, `-`, `1.`, or 4+ spaces changes structure in
`content.md` (and every history snapshot): "# 1 rule of letters" exports as an
H1. Since `content.md` is the recovery artifact, a future human recovers wrong
structure. → **Fixed in `claude/export-commands`.**

#### 1.28 Pinch-zoom leaves the status-bar percentage stale — `DocumentWindowController.swift:365`

`allowsMagnification = true` but only the menu/footer zoom paths call
`statusBar.setZoom` — after a pinch to 173% the footer reads "100%" and the
reset button jumps confusingly. → **Fixed in `claude/window-sync-fixes`.**

#### 1.29 Ruler: left/first-line indents aren't clamped against the right indent — `LucerneRulerView.swift:293`

The right marker respects the left indent but not vice versa; drag the left
triangle past the right marker and the paragraph gets a negative writable
width (degenerate layout that also persists into the file). Two-line clamp.
→ **Fixed in `claude/document-setup-fixes`.**

#### 1.30 User-initiated Check for Updates… silently dropped while a background check runs — `UpdateChecker.swift:126`

`guard !isChecking else { return }` — pick the menu item during the launch
check's window and nothing happens, no alert, and the item is never disabled.
→ **Fixed in `claude/update-checker-fixes`.**

#### 1.31 Three inconsistent version fallbacks; unbundled runs get a spurious update alert — `UpdateChecker.swift:266`

About falls back to "0.4.0", Welcome to "Version —", UpdateChecker to `"0"` —
which parses as a valid SemanticVersion, so every `swift run` launch's
background check finds any release > 0 and pops the update alert. → **Fixed in
`claude/update-checker-fixes`** (shared fallback; no auto-check when
unbundled).

#### 1.32 `NSColor(hexString:)` accepts malformed hex and returns the wrong color — `NSColor+Hex.swift:16`

`Scanner.scanHexInt64` scans a *prefix* and honors `0x`: `"#12345G"` renders
as `#012345`, `"0xAABBCC"` sneaks through the 8-digit RGBA branch, `"#1G3"`
expands and half-parses. Hand-authored documents deserve a strict parse.
→ **Fixed in `claude/format-decode-fixes`.**

#### 1.33 Quit-time race can pop the welcome window mid-quit — `AppDelegate.swift:56`

The deferred welcome check never re-reads `isTerminating` (the comment claims
it's guarded); during a ⌘Q with the save-review sheet, the async block can
show the welcome window mid-termination. The flag also needs to be set
earlier (`applicationShouldTerminate`), since `applicationWillTerminate` fires
too late for the review path. → **Fixed in `claude/app-shell-and-menus`.**

#### 1.34 "Check Spelling While Typing" likely toggles only the focused page — `MainMenu.swift:137`

The toggle routes to the first-responder `PageTextView`; with one text view
per page and `isContinuousSpellCheckingEnabled` hard-coded `true` in
`makeTextView`, per-view divergence is the expected behavior (there is SDK
ambiguity about whether the setting is shared). Needs an editor-level flag
applied to all page views; left documented pending on-device confirmation of
the actual behavior.

#### 1.35 Old finding 1.7, still unfixed: `isChecking` can stick if the checker deallocates mid-flight — `UpdateChecker.swift:129`

The `guard let self` still runs before the `defer { isChecking = false }` is
registered. Structurally unobservable today (app-lifetime object), but the
fix is one line. → **Fixed in `claude/update-checker-fixes`.**

#### 1.36 `GenerateIcons.swift` ignores `iconutil`'s exit status — `Scripts/GenerateIcons.swift:121`

The CI step "validates the icon generator" but the script never checks
`terminationStatus` and the PNG writes are `try?` — it can pass while
producing nothing. → **Fixed in `claude/docs-and-ci-housekeeping`.**

#### 1.37 (Plausible, unconfirmed) `FontResolver` requests bold+italic in one `convert(toHaveTrait:)` call — `FontResolver.swift:14`

AppKit documents trait conversion as one-trait-at-a-time; a combined mask can
drop a trait for families needing stepwise conversion. Unprovable from repo
source alone. → **Hardened anyway in `claude/text-bridge-fixes`** (use
`font(withFamily:traits:weight:size:)` with a stepwise fallback + test).

---

## 2. General issues

#### 2.1 Header/footer and page-setup changes bypass undo — `EditorController.swift:1587`

`updatePageFurniture` and `updatePageConfig` register no undo while every
neighbouring mutation is carefully undoable. Accidentally clear the footer,
OK the sheet, ⌘Z does nothing (or undoes unrelated typing). Insert ▸ Page
Number (via the sheet) has the same hole. → **Furniture undo fixed in
`claude/window-sync-fixes`**; page-setup undo needs the reload path made
snapshot-friendly first (documented).

#### 2.2 Equal-share table column widths materialize into explicit percentages after one save — `AttributedStringBuilder.swift:110`

The builder bakes `100/n` into blocks with no explicit width; the reader
persists any positive percentage. One round trip turns "equal share" into
`"width": 33.333…` on every cell — not lossy, but not idempotent either, and
it pins future column-count edits. Documented (fix is easy but changes file
output; do it alongside a bridge round-trip test).

#### 2.3 `IDGenerator` ids are collision-prone across launches — `IDGenerator.swift:11`

Counter resets per process and the counter+random concatenation is ambiguous
(no separator, unpadded base-36), so uniqueness rests on a single 32-bit
random. Cheap hardening: separator + wider random. → **Fixed in
`claude/format-decode-fixes`.**

#### 2.4 MiniZip writes UTF-8 names without the EFS flag — `MiniZip.swift:58`

Flag-0 names are CP437 per APPNOTE; `images/Zürich.png` extracts garbled in
strict tools (Finder usually sniffs it right). For a format whose pitch is
"unzip it in twenty years," declare the encoding. → **Fixed in
`claude/io-safety`** (set bit 11; round-trip test).

#### 2.5 ZIP64 archives are misreported as "corrupt" — `MiniZip.swift:122`

No ZIP64 support is fine; the failure mode isn't: sentinel fields send the
cursor to `0xFFFFFFFF` and the user gets a generic corrupt error (worse,
`ZipError` isn't `LocalizedError`, so the alert drops the message entirely).
→ **Fixed in `claude/io-safety`** (detect sentinels → honest "unsupported"
error; `ZipError` gains `LocalizedError`).

#### 2.6 A referenced image missing from the store is silently dropped at save — `LuceArchive.swift:40`

`guard let data = images[src] else { continue }` — the saved `document.json`
still references the image but the archive doesn't contain it; save reports
success. One live edge route exists (zero-byte file through the insert
panel). → **Fixed in `claude/io-safety`** (save surfaces the problem instead
of quietly writing a broken document; empty inserts refused).

#### 2.7 PDF/RTF exports are written non-atomically — `LucerneDocument.swift:167`

`Data.write(to:)` with no options truncates in place: disk-full mid-export
destroys last week's PDF. Same pattern at the stylesheet-export site. One
word: `.atomic`. → **Fixed in `claude/io-safety`.**

#### 2.8 Two history snapshots in the same second collide — `DocumentHistory.swift:78`

Entry names have second granularity; a draft autosave racing a manual ⌘S
produces duplicate `history/…` entry names in the ZIP, and they persist for
the session. → **Fixed in `claude/io-safety`** (collision nudge).

#### 2.9 A failed page render silently drops pages from print — `PaginatedPrintView.swift:15`

`compactMap` over per-page PDFs: a failed parse shifts every subsequent page
into the wrong slot while `{page} of {pages}` footers still show the baked
numbers; total failure prints one blank sheet. The PDF export path
(`makePDFData`) has the same silent-drop shape. → **Fixed in
`claude/io-safety`** (placeholder page + error surfacing).

#### 2.10 Style Library window observers are never removed — `StyleLibraryWindowController.swift:256`

Installed on `show()`, no `windowWillClose` cleanup: once shown, a *closed*
Style Library window keeps reloading (with disk I/O) on every window-main
change and every library save, for the app's lifetime. → **Fixed in
`claude/style-library-robustness`.**

#### 2.11 The floating Styles palette never observes `StyleLibrary.didChange` — `FloatingPalette.swift:300`

Its Library section shows deleted/renamed styles until an unrelated caret
move; clicking a stale row is a silent no-op. → **Fixed in
`claude/style-library-robustness`.**

#### 2.12 The whole menu bar is wired through unchecked string selectors — `MainMenu.swift:36`

`Selector(selector)` from raw strings: a typo (or a rename of any of ~44
action methods) compiles clean and yields a permanently disabled menu item.
(PROGRESS.md's round-3 claim about `#selector` was about a different call
site; the helper has always been string-based.) All 41 custom selectors
currently resolve — verified — but nothing keeps it that way. Documented;
the right fix (compile-checked selectors or a menu-walking CI test) needs the
action methods' access levels sorted first.

#### 2.13 Release procedure depends on an external, unpinned tool — `Scripts/release.sh:29`

`release.sh`/`build.sh` exec an unpinned `lkm-release`/`lkm-build` from a
separate repo; nothing checks tag ↔ committed-version consistency. → **Version
consistency guard added in `claude/docs-and-ci-housekeeping`** (release.yml
warns on tag/plist mismatch).

---

## 3. Performance

The letters-scale story is fine; these are the paths that will make a
20-page document stutter, and most have one-line-shaped fixes.

#### 3.1 Every relayout reassigns `exclusionPaths` on ALL pages — `EditorController.swift:190` (**the big one**)

`paginateAndExclude` starts by assigning fresh exclusion arrays to every
container — including empty-over-empty for the common no-images case — and
setting `exclusionPaths` invalidates layout unconditionally. With
`allowsNonContiguousLayout = false`, that's whole-document relayout per
keystroke *and per image-drag mouse-move*. Dirty-checking the rect lists
before assigning preserves TextKit's incremental layout for the typical case.
→ **Fixed in `claude/pagination-image-fixes`.**

#### 3.2 Word count re-enumerates every word per keystroke — `DocumentWindowController.swift:197`

Every length change invalidates the cache, and `enumerateSubstrings(.byWords)`
walks the whole document on the selection-change path. → **Fixed in
`claude/window-sync-fixes`** (edit-generation cache; also fixes 1.25).

#### 3.3 `headingOutline()` walks every paragraph per relayout, even with the navigator hidden — `EditorController.swift:297`

`outlineObserver` fires unconditionally at the end of every relayout.
→ **Fixed in `claude/window-sync-fixes`** (gated on navigator visibility;
recomputed once on show).

#### 3.4 With the Styles palette open, `styles.json` is read from disk per caret move — `FloatingPalette.swift:343` / `StyleLibrary.swift:57`

`StyleLibrary.load()` is uncached synchronous file I/O + JSON decode, called
from the selection-change sync path. → **Fixed in
`claude/style-library-robustness`** (in-memory cache invalidated by `save()`).

#### 3.5 `parseTable()` scans from character 0 on every caret move inside a table — `EditorController.swift:936`

The ruler's column mode calls `currentTableColumnWidths()` per selection
change; everything before the table is always scanned, per keystroke.
→ **Fixed in `claude/table-fixes`** (scan outward from the caret's paragraph —
tables are contiguous, which the code already relies on).

#### 3.6 Color-well drags register a whole-document undo snapshot per tick — `ToolbarView.swift:247` / `StyleEditorPanel.swift:564`

`NSColorWell` fires continuously during a color-panel drag; the toolbar path
does a full storage copy + relayout + undo registration per tick (a 3-second
drag = dozens of snapshots on the undo stack), and the style editor runs a
full S3 stylesheet re-apply per tick. → **Fixed in
`claude/style-editor-toolbar-fixes`** (color drags ride the existing
try-on-session machinery: one snapshot, one undo).

#### 3.7 Every formatting command relayouts twice — `EditorController.swift:517`

`withUndo` relayouts synchronously *and* the storage-delegate pass queues a
second full relayout next turn. Harmless-looking, doubles the cost of every
bold/align/style/table command. Documented — the safe fix (make the deferred
pass the only one) changes operation ordering and deserves on-device QA.

#### 3.8 Replace All: one processEditing pass per match — `FindPanelController.swift:194`

No `beginEditing`/`endEditing` batching and per-match `didChangeText()`.
→ **Fixed in `claude/find-panel-improvements`.**

#### 3.9 `updateFurniture()` dirties every page on every relayout — `PageContainerView.swift:18`

Six string property setters fire `needsDisplay = true` with no `oldValue`
comparison — every visible page repaints its full sheet per keystroke even
when the resolved strings are identical. → **Fixed in
`claude/window-sync-fixes`** (one-line `didSet` guards).

#### 3.10 Style editor's blast-radius label rescans the document per caret move — `StyleEditorPanel.swift:436`

`paragraphCount(withStyleRole:)` is O(document) per selection change while
the panel is open. Documented (same generation-cache trick as 3.2 applies).

#### 3.11 Save runs entirely on the main thread — `LucerneDocument.swift:58`

Model snapshot + *two* full Markdown exports (one for history, one for
`content.md`) + CRC32 over every image byte + the whole ZIP built in memory.
Fine for letters; a beachball for image-heavy documents. Documented —
`canAsynchronouslyWrite` needs careful thought about which parts are
main-thread-bound.

#### 3.12 `FloatingImageView` rescales the full-resolution image every draw — `FloatingImageView.swift:58`

Including every frame of a live resize drag (the changing destination size
defeats NSImage's rep cache). Documented (cached downsample keyed to view
size).

#### 3.13 CI caches nothing — `.github/workflows/ci.yml`

Every push cold-builds ~11k lines on macos-14. Zero external dependencies, so
it's only `.build` incremental state — modest win, and macOS minutes are free
for public repos. Documented; skipped deliberately (SPM cache invalidation on
toolchain bumps tends to make this a wash).

---

## 4. Visual & layout

#### 4.1 Everything in floating palettes renders in the muted "inactive" state — `ClassicControls.swift:21`

`ClassicChrome.active(for:)` is `isMainWindow || isKeyWindow`, and
`ClassicPaletteWindow` is deliberately never main and only briefly key — so
every hand-drawn control in the Styles palette, style editor, and torn-off
pickers rests in the grayed-out look (and flickers active while you type in a
filter field). → **Fixed in `claude/classic-controls-polish`** (visible
palette panels count as active — matching their hides-on-deactivate
contract).

#### 4.2 Disabled classic controls look exactly like enabled ones — `ClassicControls.swift:766`

None of the `draw()` methods consult `isEnabled` (and `ClassicSizeField`
can't be disabled at all). The style editor's whole "go quiet" state (§6.5)
is currently invisible. → **Fixed in `claude/classic-controls-polish`.**

#### 4.3 Hairline separators straddle pixel boundaries — `ClassicControls.swift:346, 465, 622`

The 0.5 pt inset idiom is right for strokes but wrong for the three rect
*fills* — a blurry 2 px smear on non-retina. → **Fixed in
`claude/classic-controls-polish`.**

#### 4.4 Line-spacing popup (and style title) show stale values — `ToolbarView.swift:295`

`syncFromSelection` only updates the popup when the paragraph's
`lineHeightMultiple` matches a preset; visiting a 2.0 paragraph then clicking
into a default one leaves "2.0" showing. (Note: default Body is 1.2, which
*is* a preset — the bite is custom-spaced styles and true-default paragraphs.)
→ **Fixed in `claude/style-editor-toolbar-fixes`.**

#### 4.5 Dark Mode: alerts and system panels render dark against an all-aqua app — `AppDelegate` (8 per-window pins)

Every window pins `.aqua` individually but `NSApp.appearance` is never set —
so `NSAlert.runModal()`, the font/color panels, and the open/save panels
follow the system and come up dark over a light app. → **Fixed in
`claude/app-shell-and-menus`** (`NSApp.appearance = .aqua` once; per-window
pins kept as belt-and-braces).

#### 4.6 Headers/footers still render in hardcoded 10 pt system font — `PageContainerView.swift:57`

Old finding 2.5, never implemented; a Baskerville letter gets Helvetica
furniture, on screen *and in print*. → **Fixed in
`claude/window-sync-fixes`** (furniture uses the document's Body face).

#### 4.7 The whole custom chrome is invisible to VoiceOver and unreachable by keyboard — `ClassicControls.swift`

Old finding 2.6, still open, and the affected surface has tripled: exactly
one accessibility-related token exists in the entire codebase (a nil
description). Every segmented control, popup, button, color well, palette
row, and the ruler are unlabeled pictures. The classic aesthetic deserves
modern a11y — this is the review's largest single debt item. Documented as
its own workstream (per-control `NSAccessibility` adoption + key loop); too
large and QA-dependent to batch-fix blind.

---

## 5. UX

#### 5.1 Dragging an image can't scroll the canvas — `FloatingImageView.swift:128`

No `autoscroll(with:)` anywhere: at 100% zoom you literally cannot drag an
image to the next page (the headline feature, pinned at the viewport edge).
→ **Fixed in `claude/image-interaction-polish`.**

#### 5.2 Image handles don't scale with zoom — `FloatingImageView.swift:37`

Fixed 9 pt in page coordinates: ~4 screen px at fit-page zoom (a pixel hunt),
36 px at 400% (swallows a minimum-size image). → **Fixed in
`claude/image-interaction-polish`.**

#### 5.3 Deleting an image strands keyboard focus; Esc doesn't deselect — `EditorController.swift:467`

⌫ removes the first-responder view without restoring focus — typing goes
nowhere until you click. → **Fixed in `claude/image-interaction-polish`.**

#### 5.4 Images can be dragged in but not pasted — `PageTextView.swift:108`

Copy an image in Preview, ⌘V in Lucerne: beep. The drop path's
`imagePayload(from:)` already knows how to read the pasteboard. → **Fixed in
`claude/image-interaction-polish`** (paste inserts a floating image at the
caret's page).

#### 5.5 Tab inserts a literal tab inside table cells — `PageTextView.swift:28`

Tab/Shift-Tab between cells is the most ingrained table gesture there is;
cells even carry an empty tab-stop array, so the inserted tab looks like
nothing happened. → **Fixed in `claude/table-fixes`** (Tab/⇧Tab walk the grid
in row-major order).

#### 5.6 The welcome screen closes itself before its action completes — `WelcomeWindowController.swift:151`

Cancel the Open panel and you're left with zero windows. → **Fixed in
`claude/app-shell-and-menus`** (close on success).

#### 5.7 …and never closes when a document opens any other way — `AppDelegate.swift:49`

⌘N, ⌘O, Open Recent, Finder double-click: the welcome stays floating over
your new document. → **Fixed in `claude/app-shell-and-menus`.**

#### 5.8 Find is hardwired case/diacritic-insensitive, gives no match count, and Esc doesn't close it — `FindPanelController.swift:14`

Replace All of "us" → "them" also rewrites "US"; "cafe" also hits "café" —
silent, destructive over-matching with no Match Case option (every classic
Mac find panel had one). No "3 of 17" feedback; no Esc/cancel path. → **Fixed
in `claude/find-panel-improvements`.**

#### 5.9 No ⌘E / system find-pasteboard integration; ⌘G beeps in fresh windows — `DocumentWindowController.swift:18`

Find state is per-window and private; the select → ⌘E → ⌘G habit (and
carrying a search from Safari) doesn't work. → **Fixed in
`claude/find-panel-improvements`.**

#### 5.10 Edit menu is missing the standard word-processor commands — `MainMenu.swift:110`

No Paste and Match Style (⌥⇧⌘V — pasting styled web text into a letter has
*no escape*), no Copy/Paste Style, no Substitutions submenu, no
Transformations, no Jump to Selection. All are free `NSTextView` selectors.
→ **Paste and Match Style, Transformations, and Substitutions (smart
quotes/dashes, off by default — period-correct, see old idea 4.10) added in
`claude/app-shell-and-menus`**; Copy/Paste Style documented (needs the
multi-view focus story checked on-device).

#### 5.11 No Help menu — `MainMenu.swift:10`

Losing macOS's built-in menu-item search hurts extra in an app where
Header & Footer…, Merge Cells, and Style Library… live only in menus. Even an
empty Help menu buys the search field. → **Fixed in
`claude/app-shell-and-menus`.**

#### 5.12 Zoom In only answers ⌘⇧= — `MainMenu.swift:226`

`key: "+"` requires Shift on US layouts; the ⌘= chord everyone types falls
through. → **Fixed in `claude/app-shell-and-menus`.**

#### 5.13 Document Setup asks for margins in raw points — `DocumentSetupSheet.swift:33`

The ruler, style editor, and Settings all speak the user's unit (default cm);
this one sheet says "72 pt = 1 inch" and makes a Swiss user compute 56.7.
→ **Fixed in `claude/document-setup-fixes`** (unit-aware fields).

#### 5.14 Clicking the page margin or canvas does nothing — `PageContainerView.swift:42`

The natural "put my cursor here" gesture on the visible white paper outside
the text block is swallowed silently. Documented (nice small fix; needs care
with the future click-to-edit-furniture story, which wants the same real
estate).

#### 5.15 Welcome window and palettes lack standard keyboard behavior — `WelcomeWindowController.swift:67`

No default button (Return does nothing), recents open only on double-click,
palettes ignore Esc/⌘W. Documented.

#### 5.16 Update download has no progress UI and a second Download click is swallowed — `UpdateChecker.swift:195`

`isDownloading` is `@Published` and rendered nowhere (old finding 3.7's
remainder). → **Minimal fix in `claude/update-checker-fixes`** (concurrent
click opens the release page instead of doing nothing); progress UI
documented.

---

## 6. Missing features

Ordered by how much a letter-writer would miss them.

1. **Lists (bullets & numbering)** — the single biggest classic-word-processor
   gap left, acknowledged everywhere (roadmap: ~2–4 days). `NSTextList`
   attaches to paragraph styles; the model needs a per-paragraph list
   descriptor. Not attempted blind — it's a file-format change deserving the
   full spec/test treatment on a Mac. (`docs/roadmap.md:80`)
2. **Insert ▸ Date** — old finding 3.8, *still* missing, in an app that
   already owns the perfect date formatter for its `{date}` token. Dating the
   letter is the first thing a letter-writer does.
   → **Implemented in `claude/insert-date`.**
3. **Stationery / letterhead templates** — ClarisWorks's best idea and the
   most on-brand missing feature: save a letterhead once, every new letter
   starts from it as an untitled copy. All machinery exists (self-contained
   stylesheets, snapshotModel, welcome shelf).
   → **Implemented in `claude/stationery`** (`stationery` flag in the model —
   additive — Save as Stationery…, File ▸ New from Stationery submenu).
4. **Export as / Copy as Markdown** — the exporter is complete and runs on
   every save; only commands are missing (old idea 4.6). Plus **DOCX export**,
   which is one `NSAttributedString.DocumentType.officeOpenXML` call away on
   the existing RTF lane — recipients disproportionately ask for Word files.
   → **Both implemented in `claude/export-commands`**, along with Markdown
   **table** export (a table currently degrades to disconnected one-line
   paragraphs in `content.md` — the recovery artifact deserves a GFM pipe
   table).
5. **Cross-page text selection / whole-document Select All** — still the
   largest editing-surface gap (inherent to the per-page-text-view pattern;
   multi-week). A cheap 80% exists: document-wide command surrogates
   (Select All over the full storage, formatting commands acting on
   storage-relative ranges). Documented for the roadmap.
6. **Open .txt / .md files** — the app reads exactly one format; ClarisWorks
   opened plain text natively. Cheap (the scripting `text` setter already
   maps lines → paragraphs) but touches Info.plist/UTI wiring that deserves
   on-device verification. Documented.
7. **Smart quotes / substitutions control** — no in-app toggle; behavior
   silently follows a system default the user can't see. → **Edit ▸
   Substitutions implemented in `claude/app-shell-and-menus`.**
8. **Strikethrough** (and super/subscript) — the model stops at underline;
   strikethrough is a mirror of the underline lane end-to-end and additive to
   the format. Documented (good first file-format extension after lists).
9. **Hyperlinks** — no link field on runs; even letters cite URLs. Bounded
   value: the PDF exporter renders via `dataWithPDF`, which produces no link
   annotations, so links would be screen/RTF-only without extra work.
   Documented.
10. **Floating text boxes** — the ClarisWorks hybrid's defining object; the
    architecture is unusually ready (floating objects already punch exclusion
    holes). A `type: "text"` PlacedObject is a real format-version bump —
    roadmap material. Documented.
11. **Envelope printing** — page presets (DL/#10) + a stationery envelope
    template gets 90% of it once stationery exists. Documented.

---

## 7. Ideas — novel, cool, delightful, quirky

Checked against the source: none of the old review's §4 ideas were
implemented. The keepers are re-upped below alongside new ones; each is
grounded in machinery that already exists.

1. **Fold marks for windowed envelopes** *(new)* — two hairline ticks in the
   left margin at the DIN 5008 fold positions, drawn in
   `PageContainerView.draw` — which means they print automatically, because
   print/PDF capture the real page drawing. A checkbox in Document Setup.
   The most letter-writerly feature imaginable for one draw call.
   → **Implemented in `claude/document-setup-fixes`.**
2. **Browse Version History in-app** *(new)* — every save already appends
   dated Markdown snapshots inside the `.luce`, and they're already decoded
   into memory on open; the only recovery path today is "unzip the file."
   A small classic window with a date list and a read-only preview makes the
   twenty-year-safety pitch *visible*. (M)
3. **Signature shelf** *(new)* — Insert ▸ Signature drops your scanned
   signature PNG at the caret as a floating image with wrap "none" (already
   supported), from `~/Library/Application Support/Lucerne/Signatures/` —
   the StyleLibrary storage pattern, reused. Letters end with signatures. (S/M)
4. **Show the wrap** *(old 4.1, still excellent)* — ghost the exclusion
   rectangle when an image is selected. Extra motivation discovered this
   review: `PageMetrics` silently extends the exclusion to the margin when a
   side gap is under 72 pt, so text sometimes skips a whole line-width with
   no visible cause. Ghosting the *true* exclusion explains the app's
   cleverest safeguard. (S)
5. **Snap to margins/center + live position readout while dragging** *(old
   4.2)* — `didChangeFrameLive` sees every frame; the status-bar hint pipe
   already exists. Pure function + two hairlines. Hold ⌥ to bypass, matching
   classic behavior. (M)
6. **Letter tokens `{sender}` / `{recipient}`** *(old 4.9)* — two optional
   model fields; feeds letterhead furniture, stationery personalization, and
   the future envelope story. (S)
7. **"Page 2 of 5" in the status bar** *(new)* — the scroll observer and the
   page-hit-test both exist; a classic word processor always told you where
   you are. → **Implemented in `claude/window-sync-fixes`.**
8. **Recent-inks row** *(old 4.5)* — five little swatches beside the color
   well, seeded with period-correct letter inks (blue-black, sepia, deep
   red). Crayon-picker energy; `NSColor+Hex` already does persistence both
   ways. (S/M)
9. **Document Info** *(old 4.7, half-landed)* — the word count made it to the
   status bar; the classic dialog (words/characters/paragraphs/pages/images/
   created/modified) never did, and created/modified are invisible anywhere
   in the app today. (S)
10. **Tab-stop guide line** *(old 4.4)* — a vertical hairline down the page
    while dragging a tab/indent/column divider; the ruler already computes
    the exact screen x. Decimal tabs especially. (S)
11. **Page thumbnails in the navigator** *(old 4.11)* — `makePagePDFs()`
    renders pixel-faithful pages already; short letters (often heading-less,
    navigator empty today) get a reason to open the sidebar. (M)
12. **Typewriter mode** *(old 4.8)* — key clicks + margin bell, off by
    default, in Settings. Useless. Perfect. (S/M, wants tasteful sounds)
13. **A rotating letter-writing epigraph on the welcome screen** *(new)* —
    one engraved italic line, indexed by day of year ("To write is human, to
    receive a letter: divine." — Dickinson), in the exact spot the tagline
    already styles. → **Implemented in `claude/app-shell-and-menus`.**

---

## 8. Docs, tests & CI

#### 8.1 PROGRESS.md omits entire shipped subsystems — `PROGRESS.md`

Find/Replace, spell checking, word count, Fit Page/Fit Width, and the whole
update checker are absent; Preferences is still "[ ] not started" though
Settings ships. The old review's "follow-up housekeeping commit" never
happened. → **Fixed in `claude/docs-and-ci-housekeeping`.**

#### 8.2 AGENTS.md / architecture.md contradict the code — `docs/architecture.md:125`

Both still claim no dotted ToC leaders (they shipped, measured-dots style,
unit-tested) and architecture.md says tables aren't implemented; a renamed
file (`FontPickerPopover` → `TryOnPopover`/`PickerListView`) is stale too.
→ **Fixed in `claude/docs-and-ci-housekeeping`.**

#### 8.3 Spec §8.3 vs the exporter: "effective" vs run-level emphasis — `docs/luce-format-spec.md:365`

The spec says Markdown emphasis comes from *effective* (style-inherited)
bold/italic; the exporter (and the spec's own Appendix B example!) use
run-level only. The code's behavior is arguably nicer (`# **Title**` is
ugly); the spec should say what the reference implementation does.
→ **Spec aligned in `claude/docs-and-ci-housekeeping`.**

#### 8.4 Stale comments: "authoritative when size == custom" contradicts spec §4.2 — `DocumentModel.swift:116`

The spec (and the code) treat width/height as always authoritative; two
comments and file-format.md still say otherwise. Plus the markdown-hint
comments omit h3/h4/code, and the README's "An experimental Word processors"
grammar slip. → **Fixed in `claude/docs-and-ci-housekeeping`.**

#### 8.5 Release workflow publishes without running tests — `.github/workflows/release.yml:38`

Straight from checkout to publish; a tag on a commit that never saw CI ships
a public release (v0.4.0's tag itself was cut mid-stream). → **Fixed in
`claude/docs-and-ci-housekeeping`** (`swift test` gate + tag↔version check).

#### 8.6 CI never exercises `make-app.sh`, though CICD.md says it does — `CICD.md:21`

Bundle-assembly breakage surfaces for the first time at release time — in
the one workflow with no test gate. → **Fixed in
`claude/docs-and-ci-housekeeping`** (CI assembles the bundle and asserts its
key artifacts).

#### 8.7 Test-coverage gaps that matter — `Tests/LucerneKitTests`

Zero tests for: the DEFLATE read path (spec says readers SHOULD support it;
a user who re-zips a `.luce` with real compression exercises it), header/
footer token resolution (`resolve` + numbering-start math is pure logic that
has never been under test), color/tab-stop/pageBreakBefore round-trips, and
Markdown escaping. → **Golden-file spec-conformance test** (decode the spec's
own Appendix B document + minimal-field variants — would have caught 1.6 and
1.7 before they shipped) **added in `claude/format-decode-fixes`**; furniture
token tests in `claude/window-sync-fixes`; escaping tests in
`claude/export-commands`.

---

## 9. Companion branches

Implemented from this review, each on its own branch. File overlap between
branches was minimized (disjoint files where possible, disjoint regions where
not); the two documentation files everyone wants to touch (PROGRESS.md,
AGENTS.md) are updated only in the housekeeping branch to keep the rest
conflict-free.

| Branch | Contents |
|---|---|
| `claude/format-decode-fixes` | 1.6, 1.7, 1.26, 1.32, 2.3 + spec golden-file tests (8.7) |
| `claude/text-bridge-fixes` | 1.3, 1.8, 1.37 + round-trip tests |
| `claude/apply-style-preserves-structure` | 1.1, 1.9 |
| `claude/pagination-image-fixes` | 1.2, 3.1, and the stale-empty-page-after-drag trim |
| `claude/table-fixes` | 1.21, 1.22, 3.5, 5.5 (Tab/⇧Tab cell navigation) |
| `claude/app-shell-and-menus` | 1.19, 1.20, 1.33, 4.5, 5.6, 5.7, 5.10 (partial), 5.11, 5.12, idea 13 |
| `claude/insert-date` | Missing feature 2 |
| `claude/find-panel-improvements` | 3.8, 5.8, 5.9 |
| `claude/io-safety` | 1.4, 1.13, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9 + tests |
| `claude/style-library-robustness` | 1.11, 2.10, 2.11, 3.4 |
| `claude/style-editor-toolbar-fixes` | 1.14, 1.15, 1.17, 1.18, 3.6, 4.4 |
| `claude/classic-controls-polish` | 4.1, 4.2, 4.3 |
| `claude/window-sync-fixes` | 1.12, 1.24, 1.25, 1.28, 2.1 (furniture undo), 3.2, 3.3, 3.9, 4.6, idea 7 + furniture-token tests |
| `claude/document-setup-fixes` | 1.5, 1.29, 5.13, idea 1 (fold marks) |
| `claude/image-interaction-polish` | 5.1, 5.2, 5.3, 5.4 |
| `claude/update-checker-fixes` | 1.30, 1.31, 1.35, 5.16 (minimal) |
| `claude/export-commands` | 1.27, missing feature 4 (Markdown export/copy, DOCX, Markdown tables) + tests |
| `claude/stationery` | Missing feature 3 |
| `claude/docs-and-ci-housekeeping` | 1.23 (spec), 1.36, 2.13, 8.1–8.6 |

Everything **not** in the table is deliberately documented-only: either it
needs on-device QA that a Linux container can't provide (7.x ideas, 4.7
accessibility, 3.7's relayout reordering), it's a file-format change deserving
the full spec treatment (lists, strikethrough, text boxes), or the right fix
involves a design decision the maintainer should make (1.10's paste
whitelist, 1.16's undo sealing).

*— Fable 5, 2 July 2026*
