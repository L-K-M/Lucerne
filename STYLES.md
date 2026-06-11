# Styles — from a fixed stylesheet to an extensible one

Design notes for making paragraph styles user-extensible and editable, with both
app-global and document-local styles. This document surveys where styles stand
today, states the goals, makes the design decisions (S1–S7, in the spirit of the
plan's D1–D4), and lays out a phased implementation plan. Nothing here is
implemented yet; this is the thinking that should precede the code.

The brief, in one sentence: *styles should be extensible and easily editable;
people should be able to create global styles and document-specific styles; and
once a document uses a style, it must be persisted in the document so it
transfers to other computers.*

---

## 1. Where styles stand today

### The file format already does the hard part

`document.json` carries a required `styles` map — role key → definition (name,
font, size, bold/italic, line spacing, space before/after, indents, alignment,
color, and a `markdown` export hint). Every paragraph references a role key, and
the spec (`docs/luce-format-spec.md` §5) already says everything the brief needs:

- A writer **MUST** define every role referenced by any paragraph — so a
  conformant `.luce` file is *self-contained by construction*. The "persist
  styles in the document so it transfers" requirement is satisfied at the format
  level today.
- Role keys are arbitrary strings. A hand-edited file with a `"legalese"` style
  is **already a valid version-1 document**, and the app renders it correctly
  (the builder resolves any role; unknown roles fall back to `body`).
- Effective values resolve run → paragraph → style → hard default (§6.6), and on
  save `AttributedStringReader` stores only what *differs* from the style — so
  files stay small and intent-revealing.

So this feature requires **no breaking format change**. The work is UI, editing
semantics, and a global library.

### What is actually fixed is the UI

The set and order of styles is hardcoded as `DefaultDocuments.styleRoleOrder`
(`body`, `heading1`, `heading2`, `listItem`, `quote`) in four places:

| Site | Order from | Names from |
|---|---|---|
| `MainMenu.swift` (Format ▸ Paragraph Style, ⌃⌘1–5) | hardcoded | `DefaultDocuments.defaultStyles()` — *not* the open document |
| `PageTextView.swift` (context menu) | hardcoded | `DefaultDocuments.defaultStyles()` |
| `ToolbarView.swift` (style chooser) | hardcoded | document's names on sync; defaults as fallback |
| `FloatingPalette.styleItems` (palette + try-on picker) | hardcoded | document's names |

Consequences: a document that defines extra styles renders them fine but offers
no way to *apply* them; a document that renames "Heading 1" shows the new name in
the toolbar but the old name in the menus; a role the document deletes is still
listed (by raw key). There is also no UI to create, edit, or delete a style.

### A style's definition is baked into the text storage at apply time

`AttributedStringBuilder` computes concrete attributes (font, color,
`NSParagraphStyle`) from the definition when the document loads or when
`applyStyleRole` runs, and tags each character with `.lucerneStyleRole`. The
storage never consults the definition again. This has a sharp implication for
editability: **changing a definition without re-applying it does nothing visible
— and worse, the next save would faithfully pin the old look onto every
paragraph as per-paragraph/run overrides** (the diff-writer preserves what's on
screen, which now differs from the new definition). So "editable styles" is
really "redefinition must re-apply" (decision S3).

### Styles already carry semantics, and the model already grows roles

The `markdown` hint is not just an export detail: it drives `content.md`
emission, the heading navigator (`h1`/`h2`/`h3` roles become outline entries),
and the printed ToC. And `EditorController.ensureTOCStyle()` already adds a
`toc` role to `model.styles` dynamically — proof that nothing downstream chokes
on roles beyond the default five.

---

## 2. Goals and non-goals

Goals, mapped to the brief:

1. **Extensible** — users can create new paragraph styles in a document; the UI
   (toolbar chooser, palette, menus, shortcuts) is driven by the *document's*
   stylesheet, not a hardcoded list.
2. **Easily editable** — redefine a style and every paragraph using it follows;
   support both a "from scratch" editor and the classic two-second workflow:
   format a paragraph by hand, then *Redefine "Body" from Selection*.
3. **Global styles** — an app-level style library that seeds new documents and
   can be copied into existing ones.
4. **Document portability** — a `.luce` file remains fully self-contained; the
   library is never *referenced* by a document, only *copied into* it.
5. **Format stability** — everything stays `formatVersion: 1` (additive only).

Non-goals for the first iteration (see §9 for how each could come later):

- **Character styles** (named run styles). Runs already carry ad-hoc bold /
  italic / font / size / color; named character styles are an additive model
  extension for later.
- **Style inheritance** (`basedOn`). The flat optional-field definitions already
  give one inheritance layer (style over hard default); a basedOn chain adds
  real UI and resolution complexity for marginal benefit in a letter-writer.
- **Live-syncing library edits into existing documents.** Deliberately excluded
  — see S2.
- **A full template/stationery system.** The library covers the styles half;
  templates (page setup + furniture + starter content) are a separate feature.

---

## 3. Design decisions

### S1 — Keys are identity; names are labels

Paragraphs reference styles by **key** (`heading1`, `style-7`); the **`name`**
("Heading 1", "Legalese") is purely for display. Keys for user-created styles
are generated (`IDGenerator.next("style")` → `style-3`, …) and treated as opaque
— never derived from the name, never localized.

This makes **rename free**: editing `name` touches no paragraph, no text
storage, no re-apply — just UI refresh. It also keeps files honest: a German
user's "Überschrift" and an English user's "Heading 1" can be the same key with
different labels.

### S2 — The document owns its styles; the library is a shelf, not a live link

The global library participates at exactly three moments:

1. **New document** — the library is overlaid onto the built-in defaults to form
   the new document's stylesheet (library wins on key collisions, so redefining
   `body` in the library restyles all *future* letters).
2. **Explicit import** — "Add Library Style to Document" copies a definition in.
3. **Explicit export** — "Save Style to Library" copies a definition out.

A document never stores a *reference* to a library style, and editing the
library never reaches into existing documents. This is the copy-on-use model,
and it is what makes the portability requirement trivially true: the `.luce`
file you mail to another Mac contains everything, and behaves identically on a
machine with a different (or no) library. The cost — library and document copies
can drift — is accepted deliberately: silent cross-document restyling is exactly
the kind of spooky action a small, pleasant tool should not do. Re-import is the
explicit way to converge.

### S3 — Redefinition re-applies through the existing round-trip

The mechanism for "edit a definition and the document follows", reusing the
tested bridge machinery instead of inventing a second styling engine:

1. **Snapshot** — run `AttributedStringReader.paragraphs(from:styles:)` over the
   storage with the **old** stylesheet. This yields each paragraph's role plus
   only its *genuine* direct formatting (the diffs against the old definition) —
   the user's hand-applied italic word survives as an override; everything the
   old style supplied does not.
2. **Swap** — replace the definition in `model.styles`.
3. **Rebuild** — for each affected paragraph (role == the edited key), rebuild
   its attributes via `AttributedStringBuilder` with the **new** stylesheet and
   set them onto the paragraph's range. The text is untouched, so ranges line up
   exactly; because this is the normal load path, page-break flags, table
   blocks, and tabs are preserved by construction. (A whole-document attribute
   pass is an acceptable simplification — these are letters, not novels.)
4. **Undo** — one undo group: the storage's attribute changes (already covered
   by `withUndo`) plus an undo-manager registration that restores the old
   definition and re-applies in reverse. Caret and selection survive because no
   text mutates; refresh `typingAttributes` so a caret sitting in an affected
   paragraph types the new look.

The same snapshot-rebuild trick powers two more commands almost for free:

- **Redefine from Selection** — capture the caret paragraph's *effective*
  formatting into the definition (the inverse direction), then re-apply. This is
  the ClarisWorks/Word workflow that makes styles feel effortless.
- **Delete a style** — snapshot with the old stylesheet (which still defines the
  doomed role), rewrite affected paragraphs' role to `body`, rebuild. Default
  policy: a confirmation sheet stating "*N paragraphs use 'Legalese'. They will
  be restyled as Body.*" — clean reassignment, no override bloat. (A
  "keep their look" variant — folding the dead definition into overrides — falls
  out of the same machinery if QA prefers it.) `body` itself cannot be deleted;
  it is the format's fallback anchor.

### S4 — Semantics stay on the `markdown` hint, surfaced as "Exports as"

A style's behavior — Markdown block type, heading-navigator membership, ToC
inclusion — already keys off `markdown`. The style editor exposes it as a simple
popup ("Exports as: Paragraph / Heading 1 / Heading 2 / Heading 3 / List item /
Quotation"), defaulting to Paragraph for new styles. This buys a pleasant
emergent behavior: a user-created "Chapter" style with hint `h1` automatically
appears in the navigator and the generated ToC, with zero new plumbing. (Note
the spec already allows `h3`, which the default stylesheet doesn't use — custom
styles can claim it today.)

### S5 — Explicit ordering

Dictionaries are unordered and the current order lives in the hardcoded array,
so extensibility needs an explicit order. Add an optional **`order`** (number)
to the style definition — additive, ignorable by other readers, self-contained
per document (no second top-level list to keep in sync with the map). The UI
sorts by `(order, name)`; a model helper `orderedStyleRoles` encapsulates the
fallback for older files (the classic five in their traditional order, then
anything else by name). New styles get `max(order) + 1`; the style editor allows
reordering. The ⌃⌘1…⌃⌘9 shortcuts follow the first nine styles in order, so a
user can promote their favorites.

### S6 — The library is a plain JSON file, and doubles as the interchange format

Location: `~/Library/Application Support/Lucerne/styles.json`. Shape — the same
dialect as the document's `styles` block, wrapped with the usual identification:

```json
{
  "format": "lucerne-styles",
  "formatVersion": 1,
  "styles": {
    "body":    { "name": "Body", "font": "Palatino", "size": 12, "lineSpacing": 1.3, "spaceAfter": 6, "markdown": "p", "order": 0 },
    "style-1": { "name": "Legalese", "font": "Times New Roman", "size": 9, "color": "#444444", "markdown": "p", "order": 7 }
  }
}
```

Why a file and not `UserDefaults`: it matches the project's escape-hatch ethos —
inspectable, hand-editable, diffable, and trivially copied to another Mac (which
*is* the "global styles on my other computer" story until any future sync
exists). Decoding reuses `ParagraphStyleDef` as-is. A missing or corrupt file
degrades silently to the built-in defaults.

The library starts **empty**; the effective stylesheet for a new document is
*built-in defaults overlaid by the library*. The alternative — materializing the
defaults into the library on first run so users see everything in one place —
was considered and rejected: it orphans a stale copy of the defaults (app
updates to the default stylesheet would never reach existing users) and invites
"I deleted Body from the library" states that need special-casing.

Because the file shape is self-describing, the same format serves **File ▸
Export Stylesheet… / Import Stylesheet…** for sharing styles between people and
machines without inventing a second mechanism.

### S7 — Collision and merge rules, stated once

All paths that copy definitions across boundaries use the same rule, compared by
**key**:

- key absent → add.
- key present, definition identical → reuse, no-op.
- key present, definition differs →
  - *library → new document seeding:* library wins (that's the point of S6).
  - *library → existing document import:* this is a deliberate "use my version
    here", so replace **with the S3 re-apply**, behind a confirmation when the
    role is in use.
  - *document → library save:* replace, behind a confirmation ("update the
    library's 'Body'?").
  - *paste / future fragment import (§6):* keep both — assign the incoming style
    a fresh key. Generated keys are unique only per document, so two documents'
    `style-3` may be unrelated; comparing definitions, never trusting keys
    across documents, is what keeps this safe.

---

## 4. File-format changes (all additive; stays version 1)

| Change | Member | Notes |
|---|---|---|
| Style ordering | `order` (number, optional) on the style definition | Absent → legacy ordering (S5). Readers that ignore it lose only menu order. |
| Style-level underline | `underline` (boolean, optional) on the style definition | Today underline exists only at run level (§6.6 note), so an "underlined fine print" *style* isn't expressible — a real gap once styles are editable. Additive; an older reader renders such a style un-underlined (degrades, doesn't misinterpret). |
| Style-level right indent | `rightIndent` (number, optional) | Optional nicety for editor completeness; paragraphs can already override `indent.right`, styles cannot express it. Same compatibility character as `underline`. |

Per spec §9 these are additive (readers ignore unknown members), so
`formatVersion` stays `1`. No change is needed to *enable custom styles
themselves* — arbitrary keys are already conformant.

Spec touch-points when implementing: §5.1 table, Appendix A schema, Appendix C
defaults in `docs/luce-format-spec.md`; the overview in `docs/file-format.md`;
plus a short normative note that role keys are opaque identifiers and `name` is
the display label (the §6.4 spirit, said explicitly for styles).

---

## 5. UI sketch

Keeping to the classic-chrome idiom the app already has:

- **Styles palette** (`FloatingPalette`) grows a thin footer bar: **New…,
  Duplicate, Edit…, Delete** at palette scale. The list itself stays the
  specimen list it is today, sorted per S5, sourced from the active document.
- **Style editor sheet** (new `StyleEditorSheet`, sibling of
  `HeaderFooterSheet`): name field; "Exports as" popup (S4); face / size / bold
  / italic / underline / color; line spacing, space before/after; left / first /
  right indents; alignment; a live specimen line; and a **"Capture from
  selection"** button that fills the fields from the caret paragraph's effective
  formatting.
- **Menu commands** (Format ▸ Paragraph Style ▸): the dynamic style list (⌃⌘1–9
  by order), then *New Style from Selection…*, *Redefine "⟨current⟩" from
  Selection*, *Style Settings…*. The submenu and the context menu rebuild from
  the frontmost document via `menuNeedsUpdate` — which also retires the
  names-from-defaults staleness noted in §1.
- **Library commands**: *Save "⟨style⟩" to Library* (palette footer or Format
  menu), *Add Library Style to Document ▸* (submenu listing library styles not
  yet in the document), and *Import / Export Stylesheet…* (File menu) for the
  interchange file (S6).

The flagship workflow this enables, end to end: select a paragraph, make it look
right with the ordinary toolbar, *Format ▸ Paragraph Style ▸ New Style from
Selection…*, name it "Legalese" — done. It's in the palette, the menus, the
shortcuts; it saves into the `.luce`; *Save to Library* makes it available to
every future letter.

---

## 6. Edge cases and policies

- **Unknown roles** — unchanged: the spec's fallback chain (role → `body` →
  hard default) already covers malformed or future files.
- **The `toc` role** — just an ordinary style; once `ensureTOCStyle()` adds it,
  it shows up in the list and is editable like any other. One honest caveat:
  its dotted leaders are *measured at insertion*, so restyling `toc` leaves
  stale leader widths until the ToC is regenerated (already the documented
  refresh model for the ToC).
- **Cross-document copy/paste** — today the text pasteboard is RTF-based, so
  `.lucerneStyleRole` does not survive even between two Lucerne windows: pasted
  text *looks* right (concrete attributes) and is folded back as `body` +
  overrides on save. Custom styles make the proper fix worth doing eventually: a
  custom pasteboard type (`ch.lkmc.lucerne.fragment`) carrying paragraphs *plus
  the style definitions they reference*, merged on read per S7. Deferred to
  Phase 4; the degraded behavior is acceptable and unchanged in the meantime.
- **Undo** — style-table mutations live outside the text storage, so they need
  explicit `UndoManager` registration, grouped with their re-apply (S3) so one
  ⌘Z reverts both. (Today `ensureTOCStyle()` mutates `model.styles` without
  undo; the new machinery should subsume that.)
- **Caret-only documents** — `applyStyleRole` already special-cases the empty
  storage via typing attributes; redefinition must refresh typing attributes the
  same way.
- **Deleting `body`** — disallowed (disabled in the UI); it is the spec's
  fallback target and the writer SHOULD always define it.
- **Library hygiene** — the library file is read on demand (new document,
  import menu) rather than held open; concurrent edits by a second app instance
  are last-writer-wins, which is fine for a per-user preferences-grade file.

---

## 7. Implementation plan

Phased so each lands shippable and CI-verifiable on its own. Estimates follow
the roadmap's developer-day convention (implementation only; QA loop extra).

### Phase 1 — the document's stylesheet drives the UI (~1–2 days)

The prerequisite for everything else, and a user-visible fix by itself (files
with custom styles become first-class).

- `Model/DocumentModel.swift`: add `order` to `ParagraphStyleDef`; add
  `orderedStyleRoles` (S5 sort + legacy fallback) to `LucerneDocumentModel`.
- Replace the four hardcoded `DefaultDocuments.styleRoleOrder` sites
  (`MainMenu`, `PageTextView`, `ToolbarView`, `FloatingPalette.styleItems`) with
  the document's ordered roles; make the Format submenu and context menu rebuild
  from the frontmost document and assign ⌃⌘1–9 by order.
- Spec: add `order` to `luce-format-spec.md` (§5.1, Appendices A/C) and
  `file-format.md`.
- Tests: ordering round-trip; legacy fallback ordering.

### Phase 2 — editing and redefinition (~3–5 days)

- `EditorController`: the S3 engine — `redefineStyle(key:to:)`,
  `addStyle(_:)`, `renameStyle(key:to:)`, `deleteStyle(key:)` (reassign policy),
  `captureStyleFromSelection(into:)`; undo grouping; typing-attribute refresh;
  palette/status-bar sync (hooks exist: `FloatingPalette.syncOpenPalettes()`).
- `Views/StyleEditorSheet.swift` (new); palette footer buttons; menu commands.
- Add style-level `underline` (and optionally `rightIndent`) to the model,
  builder, reader, and spec while the editor is being built.
- Tests (the valuable ones, all AppKit-bridge level, CI-runnable): build →
  redefine → read back asserts that (a) roles and paragraph ids are unchanged,
  (b) a hand-italicized word survives as a run override, (c) **no spurious
  overrides** pin the old definition; delete-style reassignment; rename
  touching nothing but `name`.

### Phase 3 — the global library (~2–3 days)

- `IO/StyleLibrary.swift` (new): load/save `styles.json`, overlay rule,
  tolerant decode.
- `DefaultDocuments.empty()` (and the welcome screen's new-document path): seed
  per S6.
- Commands: Save to Library, Add Library Style to Document, Import/Export
  Stylesheet….
- Tests: overlay precedence; corrupt/missing file fallback; S7 conflict matrix.

### Phase 4 — later, in likely order of value

- **Next-paragraph style** (`next` member: Return at the end of a "Heading 1"
  paragraph starts a "Body" one) — small, classic, additive, purely behavioral.
- **Pasteboard fragment type** carrying styles across documents (§6).
- **`basedOn` inheritance** — if ever added, *flatten on save*: write resolved
  values plus an advisory `basedOn`, so version-1 readers stay correct without a
  format bump.
- **Character styles** — additive `characterStyles` map + run-level `style` key.
- **A library manager window** (until then, the library is edited through the
  save/import commands and, true to the escape hatch, any text editor).

---

## 8. Testing strategy

Consistent with the project's Linux-authored / macOS-CI reality: everything
above the sheet/palette layer is deliberately testable headlessly.

- **Model layer** (`swift test`, no GUI): Codable round-trips for `order` /
  `underline`; `orderedStyleRoles`; library decode/overlay/conflicts; Markdown
  export honoring custom styles' hints.
- **Bridge layer**: the Phase-2 redefinition invariants — these are the tests
  that make the diff-based save safe to keep, and they double as regression
  armor for `AttributedStringReader`'s override detection.
- **Needs a human on a Mac**: palette footer ergonomics, sheet layout, menu
  rebuild timing on window switches, undo *feel* (one ⌘Z per redefine), and the
  shortcuts following reorder.

---

## 9. Summary of the shape

The format was designed for this and needs only courtesy additions (`order`,
`underline`). The real work is: (1) stop hardcoding the role list — let the
document's stylesheet drive every chooser; (2) make redefinition re-apply
through the existing reader/builder round-trip so direct formatting survives and
files don't bloat with stale overrides; (3) add a copy-on-use library file that
seeds new documents and doubles as the stylesheet interchange format. Documents
stay self-contained at every step — which is the property that makes a `.luce`
file safe to mail to a stranger's Mac, and the one thing this design refuses to
trade away.
