import XCTest
@testable import GoldengoImport

final class PDFTextExtractorTests: XCTestCase {
    func test_extractsText_fromSyntheticPDF() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "synthetic-statement", withExtension: "pdf"))
        let text = try XCTUnwrap(PDFTextExtractor.text(from: url))
        XCTAssertTrue(text.contains("TEST MARKET"), "expected TEST MARKET in extracted text")
        XCTAssertTrue(text.contains("DEBI"), "expected DEBI header in extracted text")
    }
}
