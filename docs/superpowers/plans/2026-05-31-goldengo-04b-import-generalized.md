# Goldengo Plan 4b — Generalized Multi-Bank Import (PDF + CSV)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`).

**Goal:** Turn the CSV importer into a **format-agnostic, multi-bank** import system that also handles **PDF** statements (Raiffeisen Albania is the first concrete bank), without hardcoding any one bank. Then do a thorough QA/polish pass before any new feature.

**Architecture:** A `StatementProfile`/`BankStatementParser` **registry** feeding the existing map→ingest→dedupe→`ImportBatch` pipeline.
- **Tabular (CSV) path** stays data-driven: a `StatementProfile` carries date formats, decimal/grouping, multilingual header keywords, an `AmountStyle` (single signed column **or** separate debit/credit columns), and skip-row patterns. One generic profile + per-bank profiles cover any CSV-exporting bank by header detection.
- **PDF path**: `PDFTextExtractor` (PDFKit `PDFDocument` → text; works on macOS so it's `swift test`-able) feeds a `BankStatementParser` chosen from a registry by identifying text. `RaiffeisenAlbaniaPDFParser` is the first; new banks add a parser. PDF layouts vary too much to fully data-drive, so per-bank parsers are expected.
- A `StatementImporter` orchestrates: file → detect PDF/CSV → pick profile/parser → `[NormalizedTransaction]` → `IngestionStore.importStatement`.

**Real format learned from a sample (Raiffeisen Albania):** PDF; date `dd/MM/yy`; numbers `,`-grouped `.`-decimal (`311,259.86`); **separate `DEBI` (negative) / `KREDI` (positive)** columns; Albanian headers (`DATA E TRANSAKSIONIT`, `PERSHKRIMI`, `DEBI`, `KREDI`, `BALANCA`); multi-line noisy descriptions; summary rows (`Balanca…`, `Numri i veprimeve…`) to skip.

**Honest constraints:** PDFKit yields flat text (not clean columns), so the Raiffeisen parser is a best-effort line parser; merchant extraction is approximate and improves with more samples. No real statement data is committed — all fixtures are synthetic.

**Tech Stack:** Swift 6, PDFKit (iOS+macOS), SwiftData, SwiftUI. XCTest. iPhone 17 simulator.

---

### Task 1: `AmountStyle` + debit/credit mapping + multi-date-format

**Files:**
- Modify: `Sources/GoldengoImport/ColumnMapping.swift`
- Modify: `Sources/GoldengoImport/StatementRowMapper.swift`
- Test: `Tests/GoldengoImportTests/StatementRowMapperTests.swift` (extend)

- [ ] **Step 1: Add `AmountStyle` and extend `ColumnMapping`.** Replace the single `amountIndex` with an `AmountStyle`, and make `dateFormat` a list:
```swift
public enum AmountStyle: Sendable, Equatable {
    case signed(index: Int)                       // one column; sign = direction
    case debitCredit(debit: Int, credit: Int)     // separate columns (e.g. Raiffeisen DEBI/KREDI)
}

public struct ColumnMapping: Sendable, Equatable {
    public var dateIndex: Int
    public var amount: AmountStyle
    public var merchantIndex: Int
    public var externalIDIndex: Int?
    public var dateFormats: [String]              // try each in order
    public var decimalSeparator: String
    public var groupingSeparator: String
    public var currency: CurrencyCode
    public init(dateIndex: Int, amount: AmountStyle, merchantIndex: Int, externalIDIndex: Int?,
                dateFormats: [String], decimalSeparator: String, groupingSeparator: String, currency: CurrencyCode) {
        self.dateIndex = dateIndex; self.amount = amount; self.merchantIndex = merchantIndex
        self.externalIDIndex = externalIDIndex; self.dateFormats = dateFormats
        self.decimalSeparator = decimalSeparator; self.groupingSeparator = groupingSeparator; self.currency = currency
    }
}
```

- [ ] **Step 2: Write failing tests** (extend `StatementRowMapperTests`) for: debit/credit columns (debit → expense, credit → income), and a `dd/MM/yy` date with `,`-grouped `.`-decimal amount:
```swift
func test_debitCreditColumns_mapDirectionCorrectly() throws {
    let m = ColumnMapping(dateIndex: 0, amount: .debitCredit(debit: 3, credit: 4), merchantIndex: 1,
                          externalIDIndex: nil, dateFormats: ["dd/MM/yy"], decimalSeparator: ".",
                          groupingSeparator: ",", currency: .all)
    let debit = try XCTUnwrap(StatementRowMapper.map(row: ["29/05/26","BASHKIA TIRANA","29/05/26","-500.00","",""], using: m))
    XCTAssertEqual(debit.kind, .expense); XCTAssertEqual(debit.amount, 500)
    let credit = try XCTUnwrap(StatementRowMapper.map(row: ["29/05/26","SALARY","29/05/26","","260,000.00",""], using: m))
    XCTAssertEqual(credit.kind, .income); XCTAssertEqual(credit.amount, 260000)
}
```

- [ ] **Step 3: Run → fail.** `swift test --filter StatementRowMapperTests`.

- [ ] **Step 4: Implement.** Update `StatementRowMapper.map` to handle both `AmountStyle` cases and try each `dateFormat`:
```swift
public static func map(row: [String], using m: ColumnMapping) -> NormalizedTransaction? {
    func field(_ i: Int?) -> String? {
        guard let i, i >= 0, i < row.count else { return nil }
        return row[i].trimmingCharacters(in: .whitespaces)
    }
    guard let dateStr = field(m.dateIndex), let date = Self.date(dateStr, formats: m.dateFormats) else { return nil }

    let amount: Decimal, kind: TransactionKind
    switch m.amount {
    case .signed(let i):
        guard let s = field(i), let v = Self.decimal(s, decimal: m.decimalSeparator, grouping: m.groupingSeparator) else { return nil }
        kind = v < 0 ? .expense : .income; amount = abs(v)
    case .debitCredit(let di, let ci):
        let d = field(di).flatMap { Self.decimal($0, decimal: m.decimalSeparator, grouping: m.groupingSeparator) }
        let c = field(ci).flatMap { Self.decimal($0, decimal: m.decimalSeparator, grouping: m.groupingSeparator) }
        if let d, d != 0 { kind = .expense; amount = abs(d) }
        else if let c, c != 0 { kind = .income; amount = abs(c) }
        else { return nil }
    }
    let merchant = field(m.merchantIndex)
    let ext = field(m.externalIDIndex)
    return NormalizedTransaction(externalID: (ext?.isEmpty == false) ? ext : nil, amount: amount,
        currency: m.currency, date: date, rawMerchant: (merchant?.isEmpty == false) ? merchant : nil,
        kind: kind, accountRef: "statement")
}

static func date(_ s: String, formats: [String]) -> Date? {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
    for fmt in formats { f.dateFormat = fmt; if let d = f.date(from: s) { return d } }
    return nil
}
```
(Keep the existing `decimal(_:decimal:grouping:)` helper. Update existing tests/usages from `amountIndex:`/`dateFormat:` to the new `amount:`/`dateFormats:` API.)

- [ ] **Step 5: Run → pass; commit.**
```bash
git add Sources/GoldengoImport/ColumnMapping.swift Sources/GoldengoImport/StatementRowMapper.swift Tests/GoldengoImportTests/StatementRowMapperTests.swift
git commit -m "feat: support debit/credit columns and multiple date formats in the row mapper"
```

---

### Task 2: `StatementProfile` registry + profile-aware detection

**Files:**
- Create: `Sources/GoldengoImport/StatementProfile.swift`
- Modify: `Sources/GoldengoImport/MappingDetector.swift`
- Test: `Tests/GoldengoImportTests/StatementProfileTests.swift`

- [ ] **Step 1: Write failing tests** — generic English CSV resolves a signed mapping; a Raiffeisen-style Albanian header resolves a debit/credit mapping:
```swift
func test_genericCSV_resolvesSignedMapping() throws {
    let m = try XCTUnwrap(StatementProfile.detectMapping(header: ["Date","Description","Amount","Reference"], currency: .all))
    if case .signed = m.amount {} else { XCTFail("expected signed") }
}
func test_raiffeisenAlbanianHeader_resolvesDebitCredit() throws {
    let header = ["DATA E TRANSAKSIONIT","PERSHKRIMI","DATE VALUTA","DEBI","KREDI","BALANCA"]
    let m = try XCTUnwrap(StatementProfile.detectMapping(header: header, currency: .all))
    if case let .debitCredit(d,c) = m.amount { XCTAssertEqual(d,3); XCTAssertEqual(c,4) } else { XCTFail("expected debitCredit") }
    XCTAssertEqual(m.dateFormats.first, "dd/MM/yy")
}
```

- [ ] **Step 2: Run → fail.**

- [ ] **Step 3: Implement `StatementProfile`** — a data-driven set of profiles + a header→mapping resolver:
```swift
import Foundation
import GoldengoCore

public struct StatementProfile: Sendable {
    public var id: String
    public var dateFormats: [String]
    public var decimalSeparator: String
    public var groupingSeparator: String
    public var dateKeywords: [String]
    public var descriptionKeywords: [String]
    public var debitKeywords: [String]
    public var creditKeywords: [String]
    public var amountKeywords: [String]      // for single-signed-column banks
    public var idKeywords: [String]
    public var skipRowKeywords: [String]     // substrings marking non-transaction rows

    public static let all: [StatementProfile] = [.raiffeisenAlbania, .generic]

    public static let raiffeisenAlbania = StatementProfile(
        id: "raiffeisen-al", dateFormats: ["dd/MM/yy","dd/MM/yyyy"], decimalSeparator: ".", groupingSeparator: ",",
        dateKeywords: ["data e transaksionit","data","datë"], descriptionKeywords: ["pershkrimi","përshkrimi","description"],
        debitKeywords: ["debi","debit"], creditKeywords: ["kredi","credit"], amountKeywords: [],
        idKeywords: ["referenca","reference","ref"],
        skipRowKeywords: ["balanca","numri i veprimeve","limit overdraft","ledger balance","dispo balance"])

    public static let generic = StatementProfile(
        id: "generic", dateFormats: ["yyyy-MM-dd","dd/MM/yyyy","dd.MM.yyyy","MM/dd/yyyy"], decimalSeparator: ".", groupingSeparator: ",",
        dateKeywords: ["date","data"], descriptionKeywords: ["description","details","merchant","narrative","pershkrimi"],
        debitKeywords: ["debit","debi"], creditKeywords: ["credit","kredi"], amountKeywords: ["amount","value","vlera","shuma"],
        idKeywords: ["reference","ref","id","transaction"], skipRowKeywords: ["opening balance","closing balance","balanca"])

    /// Best-match mapping from a header row, trying each known profile.
    public static func detectMapping(header: [String], currency: CurrencyCode) -> ColumnMapping? {
        let lower = header.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        func idx(_ keys: [String]) -> Int? { lower.firstIndex { h in keys.contains { !$0.isEmpty && h.contains($0) } } }
        for p in all {
            guard let date = idx(p.dateKeywords), let desc = idx(p.descriptionKeywords) else { continue }
            let style: AmountStyle
            if let d = idx(p.debitKeywords), let c = idx(p.creditKeywords) { style = .debitCredit(debit: d, credit: c) }
            else if let a = idx(p.amountKeywords) { style = .signed(index: a) }
            else { continue }
            return ColumnMapping(dateIndex: date, amount: style, merchantIndex: desc, externalIDIndex: idx(p.idKeywords),
                                 dateFormats: p.dateFormats, decimalSeparator: p.decimalSeparator,
                                 groupingSeparator: p.groupingSeparator, currency: currency)
        }
        return nil
    }
}
```
Replace `MappingDetector.detect` callers with `StatementProfile.detectMapping` (or keep `MappingDetector` as a thin shim calling it). Update `StatementProfileTests` import.

- [ ] **Step 4: Run → pass; commit.**
```bash
git add Sources/GoldengoImport/StatementProfile.swift Sources/GoldengoImport/MappingDetector.swift Tests/GoldengoImportTests/StatementProfileTests.swift
git commit -m "feat: add multi-bank StatementProfile registry with header-based mapping detection"
```

---

### Task 3: PDF text extraction (PDFKit)

**Files:**
- Modify: `Package.swift` (`GoldengoImport` — PDFKit is a system framework, no SPM dep needed; it links automatically)
- Create: `Sources/GoldengoImport/PDFTextExtractor.swift`
- Create: `Tests/GoldengoImportTests/Fixtures/make_fixture.py` (generates a synthetic statement PDF — NOT real data)
- Create: `Tests/GoldengoImportTests/Fixtures/synthetic-statement.pdf` (generated, committed)
- Test: `Tests/GoldengoImportTests/PDFTextExtractorTests.swift`

- [ ] **Step 1: Generate a synthetic statement PDF fixture** (run once; commit the output). `make_fixture.py` uses reportlab in the venv at `/tmp/pdfvenv` (already has pip) — install reportlab there, write a small PDF mimicking the Raiffeisen layout with FAKE data:
```python
# Tests/GoldengoImportTests/Fixtures/make_fixture.py
from reportlab.pdfgen import canvas
import os
out = os.path.join(os.path.dirname(__file__), "synthetic-statement.pdf")
c = canvas.Canvas(out)
lines = [
 "NXJERRJE LLOGARIE   Dega Test",
 "DATA E TRANSAKSIONIT  PERSHKRIMI  DATE VALUTA  DEBI  KREDI  BALANCA",
 "Balanca e Fillimit                                   1,000.00",
 "01/05/26  TEST MARKET  01/05/26  -100.00      900.00",
 "02/05/26  TEST SALARY  02/05/26          5,000.00  5,900.00",
 "Numri i veprimeve ne debi  1  -100.00",
]
y = 800
for ln in lines:
    c.drawString(40, y, ln); y -= 18
c.save()
print("wrote", out)
```
Run: `/tmp/pdfvenv/bin/pip install -q reportlab && /tmp/pdfvenv/bin/python Tests/GoldengoImportTests/Fixtures/make_fixture.py`.

- [ ] **Step 2: Write the failing test** (uses the fixture; resolve its path via `Bundle.module`):
```swift
import XCTest
@testable import GoldengoImport

final class PDFTextExtractorTests: XCTestCase {
    func test_extractsText_fromSyntheticPDF() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "synthetic-statement", withExtension: "pdf"))
        let text = try XCTUnwrap(PDFTextExtractor.text(from: url))
        XCTAssertTrue(text.contains("TEST MARKET"))
        XCTAssertTrue(text.contains("DEBI"))
    }
}
```
Add the fixtures as a test resource in `Package.swift`: on the `GoldengoImportTests` target add `resources: [.copy("Fixtures/synthetic-statement.pdf")]`.

- [ ] **Step 3: Run → fail.**

- [ ] **Step 4: Implement `PDFTextExtractor`** (PDFKit works on macOS + iOS):
```swift
import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

public enum PDFTextExtractor {
    public static func text(from url: URL) -> String? {
        #if canImport(PDFKit)
        guard let doc = PDFDocument(url: url) else { return nil }
        var out = ""
        for i in 0..<doc.pageCount { if let p = doc.page(at: i), let s = p.string { out += s + "\n" } }
        return out.isEmpty ? nil : out
        #else
        return nil
        #endif
    }
    public static func text(from data: Data) -> String? {
        #if canImport(PDFKit)
        guard let doc = PDFDocument(data: data) else { return nil }
        var out = ""
        for i in 0..<doc.pageCount { if let p = doc.page(at: i), let s = p.string { out += s + "\n" } }
        return out.isEmpty ? nil : out
        #else
        return nil
        #endif
    }
}
```

- [ ] **Step 5: Run → pass; commit** (the generated PDF + script + extractor).
```bash
git add Package.swift Sources/GoldengoImport/PDFTextExtractor.swift Tests/GoldengoImportTests/Fixtures Tests/GoldengoImportTests/PDFTextExtractorTests.swift
git commit -m "feat: extract text from PDF statements via PDFKit (+ synthetic fixture)"
```

---

### Task 4: Raiffeisen Albania PDF parser

**Files:**
- Create: `Sources/GoldengoImport/BankStatementParser.swift` (protocol + registry)
- Create: `Sources/GoldengoImport/RaiffeisenAlbaniaParser.swift`
- Test: `Tests/GoldengoImportTests/RaiffeisenAlbaniaParserTests.swift`

- [ ] **Step 1: Write failing tests** using a SYNTHETIC flat-text fixture in the shape PDFKit produces (leading `dd/MM/yy`, a trailing balance, a debit `-NNN.NN` or credit, noisy description; plus summary lines to skip):
```swift
import XCTest
import GoldengoCore
@testable import GoldengoImport

final class RaiffeisenAlbaniaParserTests: XCTestCase {
    let text = """
    NXJERRJE LLOGARIE
    DATA E TRANSAKSIONIT PERSHKRIMI DATE VALUTA DEBI KREDI BALANCA
    Balanca e Fillimit 1,000.00
    01/05/26 TEST MARKET TIRANA 01/05/26 -100.00 900.00
    02/05/26 TEST SALARY 02/05/26 5,000.00 5,900.00
    Numri i veprimeve ne debi 1 -100.00
    """
    func test_parses_transactions_skippingSummaries() {
        let p = RaiffeisenAlbaniaParser()
        XCTAssertTrue(p.canParse(text))
        let txns = p.parse(text, currency: .all)
        XCTAssertEqual(txns.count, 2)
        XCTAssertEqual(txns[0].kind, .expense); XCTAssertEqual(txns[0].amount, 100)
        XCTAssertEqual(txns[1].kind, .income);  XCTAssertEqual(txns[1].amount, 5000)
        XCTAssertEqual(txns[0].rawMerchant, "TEST MARKET TIRANA")
    }
}
```

- [ ] **Step 2: Run → fail.**

- [ ] **Step 3: Implement the protocol + registry + parser.**

`BankStatementParser.swift`:
```swift
import Foundation
import GoldengoCore

public protocol BankStatementParser: Sendable {
    var id: String { get }
    func canParse(_ text: String) -> Bool
    func parse(_ text: String, currency: CurrencyCode) -> [NormalizedTransaction]
}

public enum PDFParserRegistry {
    public static let parsers: [BankStatementParser] = [RaiffeisenAlbaniaParser()]
    public static func parser(for text: String) -> BankStatementParser? { parsers.first { $0.canParse(text) } }
}
```

`RaiffeisenAlbaniaParser.swift` (best-effort line parser — date-led line with trailing balance and one debit/credit amount; honest about limits):
```swift
import Foundation
import GoldengoCore

public struct RaiffeisenAlbaniaParser: BankStatementParser {
    public let id = "raiffeisen-al-pdf"
    public init() {}

    private static let skip = ["balanca","numri i veprimeve","limit overdraft","ledger balance","dispo balance","nxjerrje llogarie","data e transaksionit"]
    private static let date = #"\d{2}/\d{2}/\d{2}"#
    private static let num = #"-?[\d,]+\.\d{2}"#

    public func canParse(_ text: String) -> Bool {
        let l = text.lowercased()
        return l.contains("nxjerrje llogarie") || (l.contains("debi") && l.contains("kredi") && l.contains("pershkrimi"))
    }

    public func parse(_ text: String, currency: CurrencyCode) -> [NormalizedTransaction] {
        var out: [NormalizedTransaction] = []
        // A transaction line: <txnDate> <description...> <valueDate> <amount> <balance>
        let pattern = "^(\\(Self.date))\\s+(.+?)\\s+(\\(Self.date))\\s+(\\(Self.num))\\s+(\\(Self.num))$"
        let re = try? NSRegularExpression(pattern: pattern)
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.timeZone = TimeZone(identifier: "UTC"); df.dateFormat = "dd/MM/yy"
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || Self.skip.contains(where: { line.lowercased().contains($0) }) { continue }
            guard let re, let m = re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let dR = Range(m.range(at: 1), in: line), let descR = Range(m.range(at: 2), in: line),
                  let amtR = Range(m.range(at: 4), in: line) else { continue }
            guard let date = df.date(from: String(line[dR])),
                  let amt = Self.decimal(String(line[amtR])) else { continue }
            let kind: TransactionKind = amt < 0 ? .expense : .income
            out.append(NormalizedTransaction(externalID: nil, amount: abs(amt), currency: currency, date: date,
                rawMerchant: String(line[descR]).trimmingCharacters(in: .whitespaces), kind: kind, accountRef: "statement"))
        }
        return out
    }

    static func decimal(_ s: String) -> Decimal? { Decimal(string: s.replacingOccurrences(of: ",", with: "")) }
}
```
> NOTE: the regex captures one amount before the balance; a real statement where DEBI and KREDI are both present as separate empty/filled columns may need refinement against more samples — that's expected and tracked. The synthetic test pins the intended behavior.

- [ ] **Step 4: Run → pass; commit.**
```bash
git add Sources/GoldengoImport/BankStatementParser.swift Sources/GoldengoImport/RaiffeisenAlbaniaParser.swift Tests/GoldengoImportTests/RaiffeisenAlbaniaParserTests.swift
git commit -m "feat: add Raiffeisen Albania PDF statement parser + parser registry"
```

---

### Task 5: `StatementImporter` orchestrator (PDF + CSV)

**Files:**
- Create: `Sources/GoldengoImport/StatementImporter.swift`
- Test: `Tests/GoldengoImportTests/StatementImporterTests.swift`

- [ ] **Step 1: Write failing tests** — CSV text routes through profile detection; PDF text routes through the parser registry; both return `[NormalizedTransaction]`:
```swift
func test_csv_routesThroughProfile() {
    let csv = "Date,Description,Amount,Reference\n2026-05-01,SPAR,-100.00,r1\n"
    let txns = StatementImporter.transactions(fromCSV: csv, currency: .all)
    XCTAssertEqual(txns.count, 1); XCTAssertEqual(txns[0].kind, .expense)
}
func test_pdfText_routesThroughParser() {
    let text = "NXJERRJE LLOGARIE\nDEBI KREDI PERSHKRIMI\n01/05/26 SPAR 01/05/26 -100.00 900.00\n"
    let txns = StatementImporter.transactions(fromPDFText: text, currency: .all)
    XCTAssertEqual(txns.count, 1)
}
```

- [ ] **Step 2: Run → fail.**

- [ ] **Step 3: Implement.**
```swift
import Foundation
import GoldengoCore

public enum StatementImporter {
    public static func transactions(fromCSV text: String, currency: CurrencyCode) -> [NormalizedTransaction] {
        var rows = CSVParser.parse(text)
        guard let header = rows.first, let mapping = StatementProfile.detectMapping(header: header, currency: currency) else { return [] }
        rows.removeFirst()
        return rows.compactMap { StatementRowMapper.map(row: $0, using: mapping) }
    }
    public static func transactions(fromPDFText text: String, currency: CurrencyCode) -> [NormalizedTransaction] {
        guard let parser = PDFParserRegistry.parser(for: text) else { return [] }
        return parser.parse(text, currency: currency)
    }
}
```

- [ ] **Step 4: Run → pass; commit.**
```bash
git add Sources/GoldengoImport/StatementImporter.swift Tests/GoldengoImportTests/StatementImporterTests.swift
git commit -m "feat: StatementImporter routes CSV via profiles and PDF via parser registry"
```

---

### Task 6: Import UI accepts PDF + CSV

**Files:**
- Modify: `Sources/GoldengoFeatures/Import/ImportModel.swift`
- Modify: `Sources/GoldengoFeatures/Import/ImportView.swift`
- Test: `Tests/GoldengoFeaturesTests/ImportModelTests.swift` (extend)

- [ ] **Step 1: Extend `ImportModel`** with PDF support and a detected-format note:
```swift
public func importCSV(text: String, fileName: String) async throws { try await ingest(StatementImporter.transactions(fromCSV: text, currency: currency), fileName) }
public func importPDF(url: URL, fileName: String) async throws {
    guard let text = PDFTextExtractor.text(from: url) else { resultText = "Couldn't read the PDF."; return }
    try await ingest(StatementImporter.transactions(fromPDFText: text, currency: currency), fileName)
}
private func ingest(_ txns: [NormalizedTransaction], _ fileName: String) async throws {
    guard !txns.isEmpty else { resultText = "No transactions recognized in \(fileName)."; return }
    let s = try await store.importStatement(txns, fileName: fileName)
    resultText = "Imported \(s.imported), skipped \(s.deduped) duplicates"
}
```
Keep the 10 MB guard. (Import `GoldengoImport`.)

- [ ] **Step 2: `ImportView`** — `.fileImporter(allowedContentTypes: [.pdf, .commaSeparatedText, .plainText])`; on success, branch by `url.pathExtension.lowercased() == "pdf"` → `importPDF`, else read text → `importCSV` (with the existing size + encoding guards).

- [ ] **Step 3: Test** the model PDF path with the synthetic fixture (oversize guard already covered):
```swift
func test_importPDF_fromSyntheticFixture() async throws {
    let store = IngestionStore(modelContainer: try .goldengoInMemory())
    let m = ImportModel(store: store, currency: .all)
    let url = try XCTUnwrap(Bundle.module.url(forResource: "synthetic-statement", withExtension: "pdf"))
    try await m.importPDF(url: url, fileName: "synthetic-statement.pdf")
    let count = try await store.expenseCount()
    XCTAssertGreaterThanOrEqual(count, 1)
}
```
(Requires the fixture also available to `GoldengoFeaturesTests` — add it as a resource there too, or move the fixture to a shared test resource.)

- [ ] **Step 4: Run → pass; commit.**
```bash
git add Sources/GoldengoFeatures/Import Tests/GoldengoFeaturesTests/ImportModelTests.swift Package.swift
git commit -m "feat: Import UI accepts PDF and CSV via StatementImporter"
```

---

### Task 7: Thorough QA + polish pass

- [ ] **Step 1: Full suite** — `swift test` → all green; note the count.
- [ ] **Step 2: Strict-concurrency build** — `swift build` clean (no warnings).
- [ ] **Step 3: App build + simulator smoke of EVERY surface** — build for iPhone 17; launch; screenshot and read each: **Add** (tap digits, save), **Recent** (the saved expense + an imported row), **Import** (run the bundled CSV sample → result), **Settings** (toggle renders). Confirm no regressions across the app.
- [ ] **Step 4: Real-PDF dry run (local only, NOT committed)** — if a real statement path is provided, run `PDFTextExtractor` + `RaiffeisenAlbaniaParser` over it locally and report how many transactions parsed vs the statement's stated debit/credit counts; tune the regex/skip-list as needed. Do not commit any real data.
- [ ] **Step 5: Fix anything found; commit.** Then this branch is ready for the final Opus review + merge.

---

## Done criteria
- Import is **format- and bank-agnostic**: `AmountStyle` (signed/debit-credit), multi-date-format, multilingual `StatementProfile` registry for CSV, and a `BankStatementParser` registry for PDF (Raiffeisen Albania first).
- **PDF import works** (PDFKit extraction → Raiffeisen parser → ingest), verified against a synthetic fixture in `swift test` and end-to-end in the simulator.
- `swift test` fully green; app build clean; every screen smoke-tested in the simulator with no regressions.
- No real statement data committed. Adding a new bank = adding a profile (CSV) or a parser (PDF), no core changes.
- Closes new GOL-5 stories for the generalized importer; real-format tuning continues against user-provided samples.
```
