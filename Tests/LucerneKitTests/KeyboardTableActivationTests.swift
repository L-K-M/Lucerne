import AppKit
import XCTest
@testable import LucerneKit

@MainActor
final class KeyboardTableActivationTests: XCTestCase {

    func testNavigatorActivatesSelectedHeadingWithReturnSpaceAndKeypadEnter() throws {
        let navigator = NavigatorView(frame: NSRect(x: 0, y: 0, width: 180, height: 240))
        navigator.setItems([
            EditorController.HeadingItem(title: "Introduction", characterIndex: 42, level: 1)
        ])

        let table = try XCTUnwrap(findTableView(in: navigator))
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)

        var selections: [Int] = []
        navigator.onSelect = { selections.append($0) }

        table.keyDown(with: keyEvent(characters: "\r", keyCode: 36))
        table.keyDown(with: keyEvent(characters: " ", keyCode: 49))
        table.keyDown(with: keyEvent(characters: "\u{3}", keyCode: 76, modifiers: [.numericPad]))

        XCTAssertEqual(selections, [42, 42, 42])

        table.keyDown(with: keyEvent(characters: "\r", keyCode: 36, modifiers: [.command]))
        XCTAssertEqual(selections, [42, 42, 42], "modified shortcuts should retain normal table handling")
    }

    func testActivationIsIgnoredWhenNothingIsSelected() throws {
        let navigator = NavigatorView(frame: NSRect(x: 0, y: 0, width: 180, height: 240))
        navigator.setItems([
            EditorController.HeadingItem(title: "Introduction", characterIndex: 42, level: 1)
        ])
        let table = try XCTUnwrap(findTableView(in: navigator))
        table.deselectAll(nil)

        var selections: [Int] = []
        navigator.onSelect = { selections.append($0) }
        table.keyDown(with: keyEvent(characters: "\r", keyCode: 36))
        table.keyDown(with: keyEvent(characters: " ", keyCode: 49))

        XCTAssertTrue(selections.isEmpty)
    }

    func testProgrammaticActionUsesTheSelectedNavigatorRow() throws {
        let navigator = NavigatorView(frame: NSRect(x: 0, y: 0, width: 180, height: 240))
        navigator.setItems([
            EditorController.HeadingItem(title: "Introduction", characterIndex: 42, level: 1)
        ])
        let table = try XCTUnwrap(findTableView(in: navigator))
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        XCTAssertEqual(table.clickedRow, -1)

        var selections: [Int] = []
        navigator.onSelect = { selections.append($0) }
        XCTAssertTrue(table.sendAction(try XCTUnwrap(table.action), to: table.target))

        XCTAssertEqual(selections, [42])
    }

    private func findTableView(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        return view.subviews.lazy.compactMap(findTableView(in:)).first
    }

    private func keyEvent(
        characters: String,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}
