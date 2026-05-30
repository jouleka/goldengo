import XCTest
@testable import GoldengoCore

final class MerchantNormalizerTests: XCTestCase {
    func test_normalize_uppercasesTrimsCollapsesAndStripsTrailingDigits() {
        XCTAssertEqual(MerchantNormalizer.normalize("  Spar   Tirana 4471 "), "SPAR TIRANA")
        XCTAssertEqual(MerchantNormalizer.normalize("spar"), "SPAR")
        XCTAssertEqual(MerchantNormalizer.normalize(nil), "")
    }
}
