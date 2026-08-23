#!/usr/bin/env python3
"""Regenerates the shared .luce conformance corpus in Tests/Fixtures/.

The fixtures are the cross-implementation compatibility contract from
docs/ubuntu-port.md §3: every Lucerne implementation (the Swift LucerneCore
reference on macOS/Linux, the Qt port in linux/) must open these files and
round-trip them without losing modelled state. Tests/LucerneCoreTests/
SpecFixtureTests.swift and linux/tests/tst_fixtures.cpp both walk this
directory, so a fixture added here is picked up by both suites.

Deterministic on purpose: stored (uncompressed) entries, fixed DOS timestamps,
sorted keys, so regeneration produces byte-identical files and diffs stay
reviewable. deflate.luce is the one exception — its document.json is DEFLATE-
compressed to exercise the readers' inflate path (spec §2.2 SHOULD).

Run from the repo root:  python3 Scripts/make-fixtures.py
"""

import json
import os
import zipfile

ROOT = os.path.join(os.path.dirname(__file__), "..", "Tests", "Fixtures")

# 1980-01-01T00:00:00 — the same deterministic stamp MiniZip writes.
DOS_EPOCH = (1980, 1, 1, 0, 0, 0)

# A 1x1 red pixel PNG; enough for payload plumbing tests.
RED_PIXEL_PNG = bytes.fromhex(
    "89504e470d0a1a0a0000000d49484452000000010000000108020000009077"
    "53de0000000c4944415408d763f8cfc000000301010018dd8db00000000049"
    "454e44ae426082"
)


def doc(body, objects, styles=None, page=None, **extra):
    document = {
        "format": "lucerne-document",
        "formatVersion": 1,
        "page": page or {
            "size": "A4",
            "width": 595.28,
            "height": 841.89,
            "margins": {"top": 72, "left": 72, "bottom": 72, "right": 72},
        },
        "styles": styles or {"body": {"name": "Body", "markdown": "p"}},
        "body": body,
        "objects": objects,
    }
    document.update(extra)
    return document


def write_luce(name, document, entries=None, compress_document=False):
    path = os.path.join(ROOT, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with zipfile.ZipFile(path, "w") as zf:
        method = zipfile.ZIP_DEFLATED if compress_document else zipfile.ZIP_STORED
        info = zipfile.ZipInfo("document.json", date_time=DOS_EPOCH)
        info.compress_type = method
        zf.writestr(info, json.dumps(document, indent=2, sort_keys=True))
        for entry_name, data in (entries or {}).items():
            info = zipfile.ZipInfo(entry_name, date_time=DOS_EPOCH)
            info.compress_type = zipfile.ZIP_STORED
            zf.writestr(info, data)
    print("wrote", os.path.relpath(path))


def para(pid, text, style="body", **extra):
    p = {"id": pid, "style": style, "runs": [{"text": text}]}
    p.update(extra)
    return p


# ---------------------------------------------------------------- minimal.luce
write_luce("minimal.luce", doc(
    body=[para("p1", "Hello, lake.")],
    objects=[],
))

# ----------------------------------------------------------- kitchen-sink.luce
# Every spec feature outside lists/tables, plus forward-compat unknowns.
kitchen = doc(
    page={
        "size": "custom",
        "width": 500.0,
        "height": 700.0,
        "margins": {"top": 60, "left": 50, "bottom": 60, "right": 40},
        "foldMarks": True,
        "unknownPageMember": "readers must ignore me",
    },
    styles={
        "body": {
            "name": "Body", "markdown": "p", "font": "Helvetica", "size": 12,
            "lineSpacing": 1.2, "spaceAfter": 6, "order": 0,
        },
        "heading1": {
            "name": "Heading 1", "markdown": "h1", "font": "Helvetica",
            "size": 24, "bold": True, "spaceBefore": 18, "spaceAfter": 8,
            "order": 1,
        },
        "fancy": {
            "name": "Fancy", "markdown": "blockquote", "font": "Georgia",
            "size": 14, "italic": True, "underline": True,
            "leftIndent": 20, "firstLineIndent": -10, "rightIndent": 16,
            "alignment": "justified", "color": "#8000FF80", "order": 2,
        },
        "shortColor": {
            "name": "Short Color", "markdown": "p", "color": "#F0A", "order": 3,
        },
    },
    body=[
        para("p1", "A Letter from the Lake", style="heading1"),
        {
            "id": "p2", "style": "body",
            "align": "right",
            "indent": {"left": 12, "right": 8, "firstLine": 18},
            "tabStops": [
                {"pos": 72},
                {"pos": 144, "type": "center"},
                {"pos": 216, "type": "right"},
                {"pos": 288, "type": "decimal"},
            ],
            "lineSpacing": 1.5,
            "spaceBefore": 4,
            "spaceAfter": 10,
            "runs": [
                {"text": "Thanks for the "},
                {"text": "wonderful", "italic": True},
                {"text": " afternoon", "bold": True, "size": 14},
                {"text": " by the water", "underline": True,
                 "font": "Courier", "color": "#123456"},
                {"text": "."},
            ],
            "unknownParagraphMember": {"nested": [1, 2, 3]},
        },
        {"id": "p3", "style": "unknownRole",
         "runs": [{"text": "Falls back to body."}]},
        {"id": "p4", "style": "body", "runs": []},
        para("p5", "Starts a new page.", pageBreakBefore=True),
        para("p6", "Quoted and fancy.", style="fancy"),
    ],
    objects=[
        {
            "id": "img1", "type": "image", "src": "images/lake.png",
            "anchor": "page", "page": 0,
            "frame": {"x": 300, "y": 180, "width": 120, "height": 90},
            "wrap": "rectangular", "standoff": 10, "z": 2,
        },
        {
            "id": "img2", "src": "images/lake.png", "page": 1,
            "frame": {"x": 60, "y": 60, "width": 80, "height": 60},
            "wrap": "none", "z": 1,
        },
        {
            "id": "img3", "type": "image", "src": "images/missing.png",
            "anchor": "page", "page": 0,
            "frame": {"x": 60, "y": 400, "width": 50, "height": 50},
            "wrap": "irregular", "standoff": 0, "z": 0,
        },
        {
            "id": "anchored", "type": "image", "src": "images/lake.png",
            "anchor": "paragraph", "anchorParagraph": "p2",
            "offset": {"x": 10, "y": 20},
        },
        {
            "id": "future", "type": "hologram",
            "unknownObjectMember": True,
        },
    ],
    header={"left": "{title}", "center": "", "right": "{date}"},
    footer={"center": "Page {page} of {pages}"},
    pageNumberStart=2,
    unknownTopLevelMember="ignore me too",
)
write_luce("kitchen-sink.luce", kitchen, entries={
    "images/lake.png": RED_PIXEL_PNG,
    "images/missing-not-this-one.png": RED_PIXEL_PNG,  # unreferenced: legal
    "future-entry.bin": b"readers must ignore unknown entries",
})

# ------------------------------------------------------------------ lists.luce
write_luce("lists.luce", doc(
    body=[
        para("l1", "First", list={"list": "A", "ordered": True, "marker": "decimal"}),
        para("l2", "Second", list={"list": "A", "ordered": True, "marker": "decimal"}),
        para("l3", "Nested a", list={"list": "A", "ordered": True,
                                     "marker": "lower-alpha", "level": 1}),
        para("l4", "Nested b", list={"list": "A", "ordered": True,
                                     "marker": "lower-alpha", "level": 1}),
        para("l5", "Back out (3)", list={"list": "A", "ordered": True, "marker": "decimal"}),
        para("l6", "A bullet between", list={"list": "A", "ordered": False, "marker": "dash"}),
        para("l7", "Still counts (4)", list={"list": "A", "ordered": True, "marker": "decimal"}),
        para("break", "Plain paragraph breaks the run."),
        para("l8", "Restarts at ten", list={"list": "A", "ordered": True,
                                            "marker": "upper-roman", "start": 10}),
        para("l9", "Deep bullet", list={"list": "A", "ordered": False,
                                        "marker": "circle", "level": 4}),
    ],
    objects=[],
))

# ----------------------------------------------------------------- tables.luce
write_luce("tables.luce", doc(
    body=[
        para("before", "Before the table."),
        para("c00", "Header A", cell={"table": "t1", "row": 0, "column": 0, "width": 30}),
        para("c01", "Header B", cell={"table": "t1", "row": 0, "column": 1}),
        para("c02", "Header C", cell={"table": "t1", "row": 0, "column": 2}),
        para("c10", "Spans two columns",
             cell={"table": "t1", "row": 1, "column": 0, "columnSpan": 2}),
        para("c12", "Tall",
             cell={"table": "t1", "row": 1, "column": 2, "rowSpan": 2}),
        para("c20", "x", cell={"table": "t1", "row": 2, "column": 0}),
        para("c21", "y | pipe", cell={"table": "t1", "row": 2, "column": 1}),
        para("after", "After the table."),
    ],
    objects=[],
))

# ---------------------------------------------------------------- history.luce
write_luce("history.luce", doc(
    body=[para("p1", "Current prose.")],
    objects=[],
), entries={
    "content.md": "Current prose.\n",
    "history/20260101T120000Z.md": "Older prose.\n",
    "history/20260201T120000Z.md": "Newer prose.\n",
    "history/not-a-timestamp.md": "Ignored: name does not parse.\n",
})

# ---------------------------------------------------------------- deflate.luce
write_luce("deflate.luce", doc(
    body=[para("p1", "This document.json entry is DEFLATE-compressed "
                     "(spec 2.2: readers SHOULD support method 8). " * 3)],
    objects=[],
), compress_document=True)

# ------------------------------------------------------------------- invalid/*
write_luce("invalid/wrong-format.luce", {
    "format": "somebody-elses-document",
    "formatVersion": 1,
    "page": {"size": "A4", "width": 595.28, "height": 841.89,
             "margins": {"top": 72, "left": 72, "bottom": 72, "right": 72}},
    "styles": {}, "body": [], "objects": [],
})
write_luce("invalid/format-too-new.luce", doc(
    body=[para("p1", "From the future.")],
    objects=[],
) | {"formatVersion": 99})
