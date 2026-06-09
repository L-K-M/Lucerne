import XCTest
@testable import LucerneKit

final class SemanticVersionTests: XCTestCase {

    private func v(_ s: String) -> SemanticVersion {
        guard let version = SemanticVersion(s) else {
            XCTFail("\(s) should parse"); return .zero
        }
        return version
    }

    // MARK: Parsing

    func testParsesPlainAndPrefixedVersions() {
        XCTAssertEqual(v("1.2.3").components, [1, 2, 3])
        XCTAssertEqual(v("v1.2.3").components, [1, 2, 3])
        XCTAssertEqual(v("V0.2.0").components, [0, 2, 0])
        XCTAssertNil(v("1.2.3").prerelease)
    }

    func testParsesPrereleaseAndIgnoresBuildMetadata() {
        let version = v("1.4.0-beta.2+build.5")
        XCTAssertEqual(version.components, [1, 4, 0])
        XCTAssertEqual(version.prerelease, "beta.2")
    }

    func testRejectsNonVersions() {
        XCTAssertNil(SemanticVersion(""))
        XCTAssertNil(SemanticVersion("latest"))
        XCTAssertNil(SemanticVersion("1.x"))
    }

    // MARK: Numeric components

    func testShorterVersionEqualsZeroPadded() {
        XCTAssertEqual(v("1.2"), v("1.2.0"))
    }

    func testNumericComponentsCompareNumerically() {
        XCTAssertLessThan(v("0.9.0"), v("0.10.0"))
        XCTAssertLessThan(v("1.9"), v("1.10"))
        XCTAssertLessThan(v("2"), v("10"))
    }

    // MARK: Pre-release ordering (SemVer §11)

    func testPrereleaseSortsBelowFinalRelease() {
        XCTAssertLessThan(v("1.2.0-beta"), v("1.2.0"))
        XCTAssertGreaterThan(v("1.2.0"), v("1.2.0-rc.1"))
    }

    func testNumericPrereleaseIdentifiersCompareNumerically() {
        // The classic regression: lexically "10" < "2".
        XCTAssertLessThan(v("1.0.0-beta.2"), v("1.0.0-beta.10"))
        XCTAssertLessThan(v("1.0.0-2"), v("1.0.0-10"))
    }

    func testNumericIdentifierSortsBelowAlphanumeric() {
        XCTAssertLessThan(v("1.0.0-alpha.1"), v("1.0.0-alpha.beta"))
    }

    func testFewerIdentifiersSortLower() {
        XCTAssertLessThan(v("1.0.0-alpha"), v("1.0.0-alpha.1"))
    }

    func testSemverSpecExampleChain() {
        // 1.0.0-alpha < 1.0.0-alpha.1 < 1.0.0-alpha.beta < 1.0.0-beta
        //   < 1.0.0-beta.2 < 1.0.0-beta.11 < 1.0.0-rc.1 < 1.0.0
        let chain = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta",
                     "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0"].map(v)
        for (lower, higher) in zip(chain, chain.dropFirst()) {
            XCTAssertLessThan(lower, higher, "\(lower) should sort below \(higher)")
        }
    }

    func testEqualPrereleasesAreEqual() {
        XCTAssertEqual(v("1.0.0-beta.2"), v("v1.0.0-beta.2"))
        XCTAssertFalse(v("1.0.0-beta.2") < v("1.0.0-beta.2"))
    }
}
