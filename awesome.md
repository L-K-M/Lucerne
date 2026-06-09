# awesome.md — a thorough review of Lucerne

A full review of the codebase (~8,700 lines of Swift) as of `976f0fd` ("Bump
version to 0.2.0"): bugs, general issues, missing features, and ideas. Every
file was read; the highest-stakes findings were verified by hand against the
source rather than taken on first impression. Each entry carries a location,
a severity, and a confidence — and, where a companion PR implements the fix,
a pointer to it.

**Overall impression first, because it's earned:** this is a genuinely
well-built codebase. The architecture is exactly what the plan called for
(one `NSTextStorage`/`NSLayoutManager`, N identical containers, exclusion
paths doing the defining feature), coordinate math is isolated and tested in
`PageMetrics`, the model is clean, the docs are honest about limitations, and
the save format delivers on the "recoverable in twenty years" promise. The
findings below are the gap between *very good* and *bulletproof*.

---

## 1. Bugs

### 1.1 MiniZip: out-of-bounds crash on a malformed central directory — **HIGH / verified**

`Sources/LucerneKit/IO/MiniZip.swift:124`

```swift
guard cursor + 46 <= bytes.count, readLE32(bytes, cursor) == centralHeaderSig else { … }
…
let name = String(decoding: bytes[cursor + 46 ..< cursor + 46 + nameLen], as: UTF8.self)
```

The guard checks that the fixed 46-byte header fits, but **not** that
`cursor + 46 + nameLen` does. A `.luce` (or any zip) whose central-directory
entry declares a `nameLen` reaching past the end of the file crashes the app
with an index-out-of-range instead of throwing the clean `ZipError.corrupt`
the API promises. Same family of problem: the cursor advance
`cursor += 46 + nameLen + extraLen + commentLen` is unchecked between
iterations (the guard at the top of the loop catches it next pass, so the
slice is the only live crash — but the invariant deserves to be explicit).

→ **Fixed in the "MiniZip hardening" PR**, with malformed-archive tests.

### 1.2 MiniZip: unbounded allocation from a declared uncompressed size — **MEDIUM / verified**

`Sources/LucerneKit/IO/MiniZip.swift:177`

`inflateRawDeflate` allocates `Data(count: expectedSize)` where
`expectedSize` comes straight from the archive's `uncompressedSize` field —
attacker-controlled, up to 4 GiB per entry. A 1 KB crafted file can demand
4 GiB of memory before the Compression framework ever sees a byte. A sanity
cap (and a check that the declared size is plausible relative to the
compressed payload) closes the hole.

→ **Fixed in the "MiniZip hardening" PR.**

### 1.3 MiniZip: CRCs are written but never verified on read — **MEDIUM / verified**

The writer dutifully computes CRC-32 for every entry
(`MiniZip.swift:46`), and the reader ignores the stored CRCs entirely. Bit
rot or truncated transfers in the *stored* (uncompressed) entries — which is
all Lucerne writes — are silently accepted. For a format whose pitch is
"your letter is safe in twenty years," integrity checking on read is cheap
and exactly on-brand.

→ **Fixed in the "MiniZip hardening" PR** (verify when the stored CRC is
nonzero, with a test).

### 1.4 SemanticVersion: prerelease comparison is lexical, not semver — **MEDIUM / verified**

`Sources/Lucerne/Updates/SemanticVersion.swift:57`

```swift
case let (l?, r?): return l < r // both pre-release: lexical fallback
```

SemVer §11 says dot-separated prerelease identifiers compare *numerically*
when numeric: `1.0.0-beta.2 < 1.0.0-beta.10`. The lexical fallback gets this
backwards (`"beta.10" < "beta.2"`), so a user on `-beta.10` would be offered
"-beta.2" as an upgrade — or not offered `-beta.10` at all. The numeric
components and release-vs-prerelease ordering are correct; only the
prerelease-vs-prerelease case is wrong. There were also **zero tests** for
this type.

→ **Fixed in the "updater polish" PR**: spec-correct identifier-by-identifier
comparison, with the type moved into `LucerneKit` so it's testable (matching
the project's own thin-executable philosophy), plus a test suite.

### 1.5 Formatting commands only apply to the first selected range — **LOW–MEDIUM / verified**

`Sources/LucerneKit/Document/EditorController.swift` — `toggleTrait` (:574),
`toggleUnderline` (:604), `applyFontTransform` (:696), `setTextColor` (:712)
all use `tv.selectedRange()` (the first range), while
`modifyParagraphStyle` (:664) and `applyStyleRole` (:727) correctly iterate
`tv.selectedRanges`. NSTextView supports discontiguous selection (⌘-drag);
bold/underline/font/color on a multi-range selection silently formats only
the first run. An inconsistency more than a design choice — half the
commands already do it right.

→ **Fixed in the "editor correctness & polish" PR.**

### 1.6 No `formatVersion` check on open — **MEDIUM / verified**

`Sources/LucerneKit/Model/DocumentCoding.swift:23` decodes without ever
looking at `formatVersion`, even though the plan (§7) says "readers check
this" and the spec is pitched as a contract. A `.luce` written by a future
Lucerne with `formatVersion: 2` and new fields opens silently in today's
app, the unknown fields are dropped on the floor, and the next save
**destroys them**. A guard that refuses (or warns about) future-versioned
files is the difference between "old app can't open this" and "old app
quietly ate my document."

### 1.7 Update checker: `isChecking` can stick if the checker deallocates mid-flight — **LOW**

`Sources/Lucerne/Updates/UpdateChecker.swift:127–129`: the
`guard let self else { return }` runs before the `defer { isChecking = false }`
is registered, so a dealloc during a check skips the reset. Harmless today
(the checker lives for the app's lifetime) but a trap for future lifetime
changes.

### 1.8 Ruler: a newly created tab is re-found by hit-testing — **LOW / unverified**

`Sources/LucerneKit/Views/LucerneRulerView.swift:271–277`: after appending
and sorting a new tab stop, the drag target is recovered with
`tabIndex(near:)` (±7 px tolerance) and falls back to `tabs.count - 1` —
which, post-sort, is the *rightmost* tab, not necessarily the new one. With
several tabs close together, the wrong tab can end up dragged. Recovering
the index by identity (find the tab whose location equals the just-inserted
value) would be exact.

### 1.9 Theoretical: `pageIndex(forCanvasPoint:)` assumes pages is non-empty — **LOW / verified as theoretical**

`EditorController.swift:1640` returns `0` when `pages` is empty and callers
immediately index `pages[target]`. Unreachable today (every path through
`load`/`paginateAndExclude` guarantees a page), so this is a defensive note,
not a live crash.

### 1.10 Reviewed and cleared (so nobody re-flags them)

- `insertImageCore`'s `image!.size.height` (`EditorController.swift:386`)
  looks alarming but is safe: `nativeW > 0` implies `image != nil`. Worth
  rewriting for hygiene, not a crash.
- MiniZip's EOCD field reads (`:109–110`) are safe: the backwards search
  starts at `count - 22`, so a found signature always has 22 bytes after it.
- Orphaned images do **not** bloat the archive: `LuceArchive.write` filters
  to referenced sources. Nice.
- Update downloads go to a unique temp-adjacent destination and fall back to
  the release page on failure; the flow is sound (signature verification is
  moot while builds are unsigned, and the release notes say so honestly).

---

## 2. General issues

### 2.1 Every keystroke schedules a full relayout, uncoalesced

`EditorController.swift:1548` — `didProcessEditing` fires
`DispatchQueue.main.async { relayoutText(syncImages: true) }` per edit, and
`paginateAndExclude` re-derives exclusion paths for *every* page and re-syncs
*every* image view. A burst of edits in one runloop turn (paste, IME,
find-replace-all someday) queues that many full relayouts back to back. A
one-line "already scheduled" flag coalesces the burst into a single pass.
(→ **included in the "editor correctness & polish" PR**.) Going further —
only recomputing exclusions for affected pages — is the real fix if long
documents ever feel sluggish, but isn't needed for letters.

### 2.2 Attribute undo snapshots the whole document

`EditorController.swift:492–508` — every bold/align/style change copies the
entire `NSTextStorage` for undo (and `restoreText` copies it again for redo).
Correct and simple — the comment even owns it ("small letters → cheap &
exact") — but memory grows with document size × undo depth. Fine for the
stated scope; revisit with ranged undo if Lucerne ever courts novelists.

### 2.3 `ensureTOCStyle` mutates the model outside the undo step

`EditorController.swift:1395` — inserting a ToC registers undo for the text
but the `toc` style added to `model.styles` survives the undo. Cosmetic
(an unused style definition lingers in the file).

### 2.4 ClassicChromeActivation installs app-lifetime global observers

`ClassicControls.swift:105–122` — four `object: nil` NotificationCenter
observers that are never removed. Not a leak, just unnecessary fan-out per
window event; per-window observers with cleanup would be tidier.

### 2.5 Page furniture renders at a hardcoded 10 pt system font

`PageContainerView.swift:57` — headers/footers ignore the document's fonts.
Acceptable default, but a `furnitureFont` (or the Body style at 80%) would
match the document's voice; a letter set in Baskerville gets Helvetica
footers today.

### 2.6 Custom controls carry no accessibility metadata

`ClassicSegmentedControl`, `ClassicPopUp`, `ClassicColorWell`, the ruler —
none expose `accessibilityLabel`/role/value. VoiceOver users get an unlabeled
picture of a 1999 toolbar. The classic aesthetic deserves modern a11y.

### 2.7 Latent zip-slip shape in archive reading

`LuceArchive.swift:67` accepts any entry name starting `images/` — including
`images/../../x`. Today the names are only dictionary keys, never file
paths, so it's inert; the moment anyone writes an "extract images" feature
it goes live. Normalize-or-reject on read is one line of cheap insurance.

### 2.8 Test coverage gaps worth closing

Strong where it exists (round-trips, geometry, history pruning, leader
dots), thin at the edges: no malformed-zip tests (→ added in the MiniZip
PR), no `SemanticVersion` tests (→ added in the updater PR), no
deflate-entry test, no underline/color/tab-stop round-trip tests, nothing
for paragraph-anchored objects, nothing for `resolve()`'s furniture tokens.

### 2.9 Misleading "You're up to date" on unparseable versions

`UpdateChecker.swift:135–139` — if a release tag doesn't parse as a version,
a user-initiated check reports "up to date" rather than the truth ("couldn't
understand the latest release"). Small UX fib.

### 2.10 The update download has no resource timeout

`UpdateDownloader.swift` — the *API call* has a 15 s timeout; the download
itself can stall forever with no progress UI and no way to cancel.
(→ **resource timeout added in the "updater polish" PR**; progress UI listed
under missing features.)

---

## 3. Missing features

Ordered roughly by how much a letter-writer would miss them.

1. **Find (and Replace).** The single biggest absence for a word processor.
   Edit ▸ Find items *exist* (`MainMenu.swift:106–114`) but are dead: they
   target NSTextView's legacy `performFindPanelAction(_:)`, and
   `usesFindPanel` is never enabled on any page text view, so the items
   never validate. They couldn't work anyway — with one text view per page,
   a match laid out in another page's container is beyond a single view's
   find panel. Even 1984's MacWrite had Find. A small classic Find panel
   over the shared `textStorage` fits the app's aesthetic perfectly.
   → **Implemented (Find / Find Next / Find Previous, Replace, Replace All)
   in PR #11.**
2. **Spell checking.** `NSTextView` ships it; Lucerne never turns it on —
   no red squiggles. (Edit ▸ Spelling menu items exist and route to the
   focused text view.) For an app whose whole purpose is sending letters to
   other humans, typo defense is core.
   → **Enabled in PR #10**, with a Check Spelling While Typing toggle in
   PR #11.
3. **Word count.** The classic statistic — ClarisWorks had it in Document
   Info; writers live by it. The status bar shows style + page count and has
   room for it. → **Added in the "find panel" PR** (status bar).
4. **Zoom: Fit Page / Fit Width.** The window *opens* at a computed fit zoom
   but offers no way back to it. → **Added in the "find panel" PR**
   (View menu).
5. **Arrow-key nudging of a selected image.** Pixel-precise placement by
   keyboard is the classic complement to free dragging (arrows = 1 pt,
   ⇧-arrows = 10 pt). Delete already works; arrows just beep.
   → **Added in the "editor correctness & polish" PR.**
6. **Escape to cancel an image drag.** Once you grab an image there's no
   abort; you must drag it back. (Also added, same PR.)
7. **Download progress + "last checked" in Settings.** `isDownloading` and
   `lastCheckDate` are `@Published` and rendered nowhere.
   → **"Last checked" added in the "updater polish" PR.**
8. **Insert ▸ Date.** A letters app should type "9 June 2026" for you. The
   furniture system already has `{date}`; the body deserves the same.
9. From the roadmap, acknowledged and still open: lists (`NSTextList`),
   cross-page selection, irregular (alpha) wrap, paragraph-anchored objects
   (modeled, unwired), in-place header/footer editing, DOCX export, image
   overhang at page boundaries.

---

## 4. Ideas — novel, cool, delightful, quirky

Things that would make Lucerne *more itself*, not just more.

1. **Show the wrap.** When an image is selected, ghost its exclusion
   rectangle (frame + standoff band) as a faint dashed outline so users see
   exactly where text will flow. Makes the invisible model tangible — very
   ClarisWorks-y, surprisingly rare in modern apps.
2. **Snap & guides while dragging images.** Light snapping to margins, page
   center, and other images' edges, with hairline guides flashing on — plus
   the live `(x, y)` in points in the status bar while dragging. Free
   placement with breadcrumbs.
3. **Stationery.** ClarisWorks's best idea: documents that open as untitled
   copies. A "Save as Stationery…" flag in the model plus a Welcome-screen
   shelf of letterheads would complete the letters story.
4. **Tab-stop guide line.** While dragging a tab or indent on the ruler,
   draw a vertical hairline down the page so you can see what it will align
   with. (Decimal tabs especially.)
5. **Recent-colors row.** A small palette of the last six text colors above
   the color well — period-appropriate (the classic crayon picker energy)
   and a real time-saver.
6. **`content.md` as a feature, not just a tombstone.** A "Copy as
   Markdown" command — the exporter already exists; the escape hatch becomes
   an everyday export.
7. **Document Info.** The classic dialog: words, characters, paragraphs,
   pages, images, created/modified, with that engraved-label look. Pairs
   with the word count.
8. **Quirky, optional, wonderful: typewriter mode.** A Preferences toggle
   for subtle key-click sounds and a margin-bell *ding* near the right
   margin. Useless. Perfect.
9. **Letter-specific tokens.** `{recipient}` and `{sender}` document fields
   that fill the furniture and a future envelope/print view — leaning into
   "letters tool" over "generic word processor."
10. **Smart quotes, period-correctly.** `isAutomaticQuoteSubstitutionEnabled`
    with an Edit-menu toggle: curly quotes were a *feature* you turned on in
    1995, and they should be here too.
11. **Page-flip affordance in the navigator.** Tiny page thumbnails (the
    `makePagePDFs()` machinery already renders pages!) instead of — or
    below — the heading list.
12. **Margin-click to edit furniture.** Click in the header/footer zone to
    edit it in place (the roadmap already wants this; it would retire the
    dialog).

---

## 5. Companion PRs

Implemented from this review, each on its own branch with disjoint files so
they merge independently:

| PR | Branch | Contents |
|---|---|---|
| #8 MiniZip hardening | `claude/minizip-hardening` | Bugs 1.1, 1.2, 1.3 + malformed-archive tests (2.8) |
| #9 Updater polish | `claude/updater-semver-polish` | Bug 1.4 + tests, download timeout (2.10), "last checked" in Settings (3.7), honest unparseable-tag message (2.9) |
| #10 Editor correctness & polish | `claude/editor-polish` | Bug 1.5, relayout coalescing (2.1), spell checking (3.2), arrow-key nudge + Esc-cancel (3.5, 3.6) |
| #11 Find panel & friends | `claude/find-panel` | Find & Replace (3.1), word count (3.3), Fit Page / Fit Width zoom (3.4) |
| #12 Format safety | `claude/format-safety` | formatVersion guard (1.6), zip-slip name validation (2.7) + tests |
| #13 Ruler tab fix | `claude/ruler-tab-fix` | Bug 1.8 — verified against the code while implementing |

`PROGRESS.md`/`AGENTS.md` updates were deliberately left out of the
implementation PRs to keep them conflict-free; a follow-up housekeeping
commit can reconcile the checklists once they land.
