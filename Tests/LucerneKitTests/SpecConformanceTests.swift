import AppKit
import XCTest
@testable import LucerneKit

/// Golden-file conformance against docs/luce-format-spec.md: documents the spec
/// declares valid MUST decode (members it calls optional really are optional),
/// a wrong `format` MUST be rejected (§3.1), color strings parse strictly
/// (§6.3), and generated ids are unambiguous (§6.4).
final class SpecConformanceTests: XCTestCase {

    private func decode(_ json: String) throws -> LucerneDocumentModel {
        try DocumentCoding.decode(Data(json.utf8))
    }

    // MARK: - Optional members really are optional

    func testTabStopWithoutTypeDefaultsToLeft() throws {
        // §6.5: `pos` required, `type` optional with default "left".
        let json = """
        {
          "format": "lucerne-document",
          "formatVersion": 1,
          "page": { "size": "A4", "width": 595.28, "height": 841.89,
                    "margins": { "top": 72, "left": 72, "bottom": 72, "right": 72 } },
          "styles": { "body": { "name": "Body", "markdown": "p" } },
          "body": [
            { "id": "p1", "style": "body",
              "tabStops": [ { "pos": 72 } ],
              "runs": [ { "text": "Hello" } ] }
          ],
          "objects": []
        }
        """
        let model = try decode(json)
        let stops = try XCTUnwrap(model.body.first?.tabStops)
        XCTAssertEqual(stops, [TabStopModel(pos: 72, type: "left")])
        XCTAssertEqual(stops.first?.kind, .left)
    }

    func testPartialFooterDecodes() throws {
        // §3.2's own worked example: zones are optional with default "".
        let json = """
        {
          "format": "lucerne-document",
          "formatVersion": 1,
          "page": { "size": "A4", "width": 595.28, "height": 841.89,
                    "margins": { "top": 72, "left": 72, "bottom": 72, "right": 72 } },
          "styles": { "body": { "name": "Body", "markdown": "p" } },
          "body": [],
          "objects": [],
          "footer": { "center": "Page {page}" }
        }
        """
        let model = try decode(json)
        let footer = try XCTUnwrap(model.footer)
        XCTAssertEqual(footer.left, "")
        XCTAssertEqual(footer.center, "Page {page}")
        XCTAssertEqual(footer.right, "")
    }

    func testMinimalSpecConformantDocumentDecodes() throws {
        // Everything the spec marks optional omitted: a style carrying only
        // name + markdown (§5.1), a paragraph with only id/style/runs (§6.1),
        // and a page-anchored object with only id/src/page/frame (§7) — the
        // defaults then come from Appendix C.
        let json = """
        {
          "format": "lucerne-document",
          "formatVersion": 1,
          "page": { "size": "A4", "width": 595.28, "height": 841.89,
                    "margins": { "top": 72, "left": 72, "bottom": 72, "right": 72 } },
          "styles": { "body": { "name": "Body", "markdown": "p" } },
          "body": [
            { "id": "p1", "style": "body", "runs": [ { "text": "Hello, lake." } ] }
          ],
          "objects": [
            { "id": "img1", "src": "images/lake.png", "page": 0,
              "frame": { "x": 320, "y": 180, "width": 200, "height": 140 } }
          ]
        }
        """
        let model = try decode(json)
        XCTAssertEqual(model.body.first?.plainText, "Hello, lake.")
        let style = try XCTUnwrap(model.styles["body"])
        XCTAssertEqual(style.name, "Body")
        XCTAssertNil(style.size)
        let object = try XCTUnwrap(model.objects.first)
        XCTAssertEqual(object.type, "image")
        XCTAssertEqual(object.anchorMode, .page)
        XCTAssertEqual(object.wrapMode, .rectangular)
        XCTAssertEqual(object.standoff, 12)
        XCTAssertEqual(object.z, 0)
    }

    func testAppendixBWorkedExampleDecodes() throws {
        // The spec's own worked example (Appendix B.2), verbatim.
        let json = """
        {
          "format": "lucerne-document",
          "formatVersion": 1,
          "page": {
            "size": "A4",
            "width": 595.28,
            "height": 841.89,
            "margins": { "top": 72, "left": 72, "bottom": 72, "right": 72 }
          },
          "styles": {
            "body":     { "name": "Body",      "font": "Helvetica", "size": 12, "lineSpacing": 1.2, "spaceAfter": 6, "markdown": "p" },
            "heading1": { "name": "Heading 1", "font": "Helvetica", "size": 24, "bold": true, "spaceBefore": 18, "spaceAfter": 8, "markdown": "h1" }
          },
          "body": [
            { "id": "p1", "style": "heading1", "runs": [ { "text": "A Letter from the Lake" } ] },
            {
              "id": "p2",
              "style": "body",
              "indent": { "firstLine": 18 },
              "runs": [
                { "text": "Thanks for the " },
                { "text": "wonderful", "italic": true },
                { "text": " afternoon — see the view below." }
              ]
            }
          ],
          "objects": [
            {
              "id": "img1",
              "type": "image",
              "src": "images/lake.png",
              "anchor": "page",
              "page": 0,
              "frame": { "x": 320, "y": 180, "width": 200, "height": 140 },
              "wrap": "rectangular",
              "standoff": 12,
              "z": 1
            }
          ]
        }
        """
        let model = try decode(json)
        XCTAssertEqual(model.body.count, 2)
        XCTAssertEqual(model.body[0].plainText, "A Letter from the Lake")
        XCTAssertEqual(model.body[1].runs[1].italic, true)
        XCTAssertEqual(model.objects.first?.frame,
                       RectModel(x: 320, y: 180, width: 200, height: 140))
    }

    // MARK: - format marker (§3.1)

    func testWrongFormatIsRejected() throws {
        let json = """
        {
          "format": "something-else",
          "formatVersion": 1,
          "page": { "size": "A4", "width": 595.28, "height": 841.89,
                    "margins": { "top": 72, "left": 72, "bottom": 72, "right": 72 } },
          "styles": { "body": { "name": "Body", "markdown": "p" } },
          "body": [],
          "objects": []
        }
        """
        XCTAssertThrowsError(try decode(json)) { error in
            guard case DocumentCoding.DocumentError.wrongFormat(let found) = error else {
                return XCTFail("expected wrongFormat, got \(error)")
            }
            XCTAssertEqual(found, "something-else")
        }
    }

    // MARK: - Color strings (§6.3)

    func testMalformedHexColorsAreRejected() {
        XCTAssertNil(NSColor(hexString: "#12345G"), "non-hex digit must not half-parse")
        XCTAssertNil(NSColor(hexString: "0xAABBCC"), "0x prefix is not a spec color form")
        XCTAssertNil(NSColor(hexString: "#1G3"), "shorthand expansion must stay strict")
    }

    func testValidHexColorsStillParse() throws {
        let full = try XCTUnwrap(NSColor(hexString: "#336699"))
        XCTAssertEqual(full.lucerneHexString, "#336699")
        let short = try XCTUnwrap(NSColor(hexString: "#ABC"))
        XCTAssertEqual(short.lucerneHexString, "#AABBCC")
    }

    // MARK: - Identifiers (§6.4)

    func testGeneratedIDsAreUniqueAndUnambiguous() {
        let ids = (0 ..< 1000).map { _ in IDGenerator.next("p") }
        XCTAssertEqual(Set(ids).count, ids.count)
        for id in ids {
            XCTAssertTrue(id.hasPrefix("p"))
            XCTAssertTrue(id.contains("-"),
                          "counter and random parts must be separated: \(id)")
        }
    }
}
