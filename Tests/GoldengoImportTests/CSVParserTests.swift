import XCTest
@testable import GoldengoImport

final class CSVParserTests: XCTestCase {
    func test_parses_simpleRows() {
        let rows = CSVParser.parse("a,b,c\n1,2,3\n")
        XCTAssertEqual(rows, [["a","b","c"], ["1","2","3"]])
    }
    func test_handles_quotedFieldWithCommaAndQuotes() {
        let rows = CSVParser.parse("\"Spar, Tirana\",\"he said \"\"hi\"\"\",5\n")
        XCTAssertEqual(rows, [["Spar, Tirana", "he said \"hi\"", "5"]])
    }
    func test_handles_quotedNewlineAndTrailingNoNewline() {
        let rows = CSVParser.parse("\"line1\nline2\",x")
        XCTAssertEqual(rows, [["line1\nline2", "x"]])
    }
    func test_skips_blankLines() {
        XCTAssertEqual(CSVParser.parse("a,b\n\n c , d \n"), [["a","b"], ["c","d"]])
    }
    func test_handles_crlfLineEndings() {
        let rows = CSVParser.parse("a,b\r\n1,2\r\n")
        XCTAssertEqual(rows, [["a","b"], ["1","2"]])
    }
    func test_empty_input_returnsEmpty() {
        XCTAssertEqual(CSVParser.parse(""), [])
    }
}
