import XCTest
@testable import LucerneKit

/// The shared numeric-field parser (§1.18). Numeric style-editor/toolbar fields
/// display values with a period, so the canonical period form must parse in
/// every locale; blank input is a no-op (nil). Comma-decimal locale behavior
/// depends on the test host's `.current` locale, so it isn't asserted here.
final class UserNumberParsingTests: XCTestCase {

    func testPeriodDecimalParsesRegardlessOfLocale() {
        XCTAssertEqual(UserNumber.parse("1.5"), 1.5)
        XCTAssertEqual(UserNumber.parse("0.25"), 0.25)
        XCTAssertEqual(UserNumber.parse("12"), 12)
    }

    func testSurroundingWhitespaceIsIgnored() {
        XCTAssertEqual(UserNumber.parse("  3.25  "), 3.25)
        XCTAssertEqual(UserNumber.parse("\t14\n"), 14)
    }

    func testBlankInputIsNil() {
        XCTAssertNil(UserNumber.parse(""))
        XCTAssertNil(UserNumber.parse("   "))
    }

    func testNonNumericInputIsNil() {
        XCTAssertNil(UserNumber.parse("abc"))
    }
}
