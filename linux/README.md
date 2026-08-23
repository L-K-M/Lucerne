# Lucerne for Linux (Qt port)

The native Ubuntu/Linux edition of Lucerne — a Qt 6 (C++17) implementation of
the same product: a small, pleasant, ClarisWorks-style tool for writing
letters, with rulers, tabs, and **genuine free placement of images with live
text flow**. It reads and writes the same `.luce` files as the Mac app,
verified continuously against the shared conformance corpus in
[`Tests/Fixtures`](../Tests/Fixtures) (see
[`docs/ubuntu-port.md`](../docs/ubuntu-port.md) for the design rationale and
[`docs/luce-format-spec.md`](../docs/luce-format-spec.md) for the format
contract).

## How the hard feature works here

On macOS, TextKit flows text around `NSTextContainer.exclusionPaths`. Qt has
no equivalent property — but `QTextLayout`'s manual line API lets the layout
engine do the same geometry itself (`linux/src/app/PageLayout.cpp`, a
`QAbstractTextDocumentLayout`): for every line, the page's exclusion
rectangles are subtracted from the line's vertical band
(`ExclusionPathController::availableSegments`) and each remaining span gets a
`QTextLine` via `setLineWidth`/`setPosition`. Shaping, bidi, and font fallback
stay HarfBuzz/Qt's problem. Pagination, forced page breaks, hanging list
gutters, and the ClarisWorks margin-sliver rule (`minColumn`) ride on the same
pass. The exclusion-rect math itself is the same ~100 lines in both apps
(`Sources/LucerneCore/Layout` ⇄ `linux/src/core/PageMetrics.cpp`).

## Building

```sh
sudo apt install qt6-base-dev qt6-base-dev-tools libgl1-mesa-dev zlib1g-dev \
                 cmake ninja-build
cmake -S linux -B linux/build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build linux/build
./linux/build/lucerne --sample        # launch with the demo letter
ctest --test-dir linux/build          # run the test suites (headless-safe)
```

Qt ≥ 6.2 (Ubuntu 22.04's) is the floor; Ubuntu 24.04's 6.4 is what CI
exercises daily. Packaging:

```sh
cd linux/build && cpack -G DEB        # → lucerne_<version>_amd64.deb
```

CI (`.github/workflows/linux-qt.yml`) builds a `.deb` on ubuntu-24.04 and an
AppImage on ubuntu-22.04 (wider glibc reach); releases attach both.

## Layout of this directory

| Path | Responsibility |
|---|---|
| `src/core/` | The C++ mirror of Swift `LucerneCore` (Qt Core/Gui only, headless-testable): model, spec-conformant JSON coding, MiniZip, `.luce` archive, Markdown export, list numbering, history pruning, style library, page/exclusion geometry, furniture tokens |
| `src/app/PageLayout.*` | The paginated exclusion-flow layout engine |
| `src/app/DocumentBridge.*` | model ⇆ `QTextDocument` (deltas captured on read-back; Mac font/color names preserved through fontconfig substitution) |
| `src/app/Editor.*` | Controller: unified undo (text + objects), save path with history trail, image commands, style engine, page/PDF rendering |
| `src/app/PageCanvas.*` | The editing surface: caret/selection, image drag/resize with live reflow, zoom, clipboard, IME |
| `src/app/MainWindow.*` | Menus, format toolbar, find bar, navigator dock, status bar, print/PDF/Markdown export, dialogs |
| `src/app/Ruler.*` | Unit-aware ruler: indent triangles, tab stops (click/drag/double-click-cycle/drag-off-delete) |
| `tests/` | Ten Qt Test suites; `tst_fixtures` walks the same corpus as Swift's `SpecFixtureTests` |
| `resources/` | Desktop entry, AppStream metainfo, MIME type, hicolor icons |

## Parity with the Mac app

Implemented: editing/selection/undo on discrete pages, named paragraph styles
(seeded from the shared style library), fonts/size/B-I-U/color/alignment/line
spacing, indents + all four tab types with a draggable ruler, free image
placement with live wrap (both sides, standoff, wrap none/rectangular,
cross-page drag, nudge, resize), forced page breaks, headers/footers with
`{page}/{pages}/{date}/{title}` tokens and `pageNumberStart`, DIN 5008 fold
marks, nested ordered/unordered lists with all marker styles, heading
navigator, find & replace, zoom modes, print + PDF export, Markdown
export/copy, `content.md` + thinned `history/` on every save, welcome screen
with recents and the day's epigraph, `.deb`/AppImage packaging with full
desktop integration (`.luce` MIME type, icons).

Known gaps vs. the Mac (tracked, not silently dropped — cell/table metadata
is *preserved* through open/save either way): table **editing** (cell
paragraphs render as ordinary text, the spec's documented fallback), the
generated table of contents, stationery, style-library editing UI, RTF/DOCX
export, spell checking, smart quotes/dashes and Markdown typing shortcuts,
crash-draft recovery, and the update checker (Linux updates arrive via
`.deb`/AppImage releases).
