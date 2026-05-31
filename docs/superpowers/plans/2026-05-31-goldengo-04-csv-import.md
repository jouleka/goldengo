# Goldengo Plan 4 — CSV Statement Import (GOL-5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`).

**Goal:** Import a bank-statement CSV (Raiffeisen-style) so the app covers real card spend, not just manual entries: parse → map columns → normalize → ingest (dedupe) → record an `ImportBatch`. The parsing/mapping core is fully headless-testable; a thin UI lets the user pick a file and confirm.

**Architecture:** A new pure `GoldengoImport` package (CSV parser, `ColumnMapping`, row mapper, header auto-detect — all `Sendable` value logic over `GoldengoCore`). Persistence stays in `GoldengoData`: an `ImportBatch` `@Model` plus `IngestionStore.importStatement(_:fileName:)` that ingests each `NormalizedTransaction` through the existing dedupe pipeline and returns a `Sendable` summary. A SwiftUI Import screen (`.fileImporter`) drives it; a bundled sample CSV makes the flow simulator-verifiable.

**Tech Stack:** Swift 6, SwiftData, SwiftUI (`.fileImporter`), XCTest. Xcode 26.5, iPhone 17 simulator.

**Reconciliation note (from earlier reviews):** manual entries use unique keys and do NOT auto-merge with imports — exact-key dedupe here only collapses *re-imported* rows. Fuzzy manual↔import matching is deliberately out of scope (future).

**Unknown to confirm with the user:** the exact Raiffeisen Albania CSV layout (column order, date format, decimal separator, debit/credit sign). This plan uses configurable defaults (`dd.MM.yyyy`, `,` decimal, negative = expense) and a header heuristic; when a real export is available, adjust the auto-detect + defaults and add a fixture from it.

---

### Task 1: `GoldengoImport` package + CSV parser

**Files:**
- Modify: `Package.swift` (add `GoldengoImport` target + tests, dep `GoldengoCore`)
- Create: `Sources/GoldengoImport/CSVParser.swift`
- Test: `Tests/GoldengoImportTests/CSVParserTests.swift`

- [ ] **Step 1: Add the target** to `Package.swift` products/targets:
```swift
        .library(name: "GoldengoImport", targets: ["GoldengoImport"]),
```
```swift
        .target(name: "GoldengoImport", dependencies: ["GoldengoCore"]),
        .testTarget(name: "GoldengoImportTests", dependencies: ["GoldengoImport"]),
```

- [ ] **Step 2: Write the failing tests**

`Tests/GoldengoImportTests/CSVParserTests.swift`:
```swift
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
}
```

- [ ] **Step 3: Run to verify fail** — `swift test --filter CSVParserTests` → FAIL.

- [ ] **Step 4: Implement a correct RFC-4180-ish parser**

`Sources/GoldengoImport/CSVParser.swift`:
```swift
import Foundation

public enum CSVParser {
    /// Parses CSV text into rows of fields. Handles quoted fields containing commas,
    /// escaped quotes (`""`), and newlines; trims unquoted field whitespace; skips blank lines.
    public static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        var wasQuoted = false
        let chars = Array(text)
        var i = 0

        func endField() {
            row.append(wasQuoted ? field : field.trimmingCharacters(in: .whitespaces))
            field = ""; wasQuoted = false
        }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i+1] == "\"" { field.append("\""); i += 1 }
                    else { inQuotes = false }
                } else { field.append(c) }
            } else {
                switch c {
                case "\"": inQuotes = true; wasQuoted = true
                case ",": endField()
                case "\n": endRow()
                case "\r": break
                default: field.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
}
```

- [ ] **Step 5: Run** — `swift test --filter CSVParserTests` → PASS.

- [ ] **Step 6: Commit**
```bash
git add Package.swift Sources/GoldengoImport/CSVParser.swift Tests/GoldengoImportTests/CSVParserTests.swift
git commit -m "feat: add GoldengoImport package with RFC-4180 CSV parser"
```

---

### Task 2: Column mapping + row → NormalizedTransaction

**Files:**
- Create: `Sources/GoldengoImport/ColumnMapping.swift`
- Create: `Sources/GoldengoImport/StatementRowMapper.swift`
- Test: `Tests/GoldengoImportTests/StatementRowMapperTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/GoldengoImportTests/StatementRowMapperTests.swift`:
```swift
import XCTest
import GoldengoCore
@testable import GoldengoImport

final class StatementRowMapperTests: XCTestCase {
    private let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, merchantIndex: 2,
                                        externalIDIndex: 3, dateFormat: "dd.MM.yyyy",
                                        decimalSeparator: ",", groupingSeparator: ".",
                                        currency: .all)

    func test_maps_debitRowToExpense_absAmount() throws {
        let tx = try XCTUnwrap(StatementRowMapper.map(row: ["30.05.2026","-1.500,00","SPAR TIRANA","tx1"], using: mapping))
        XCTAssertEqual(tx.kind, .expense)
        XCTAssertEqual(tx.amount, Decimal(string: "1500.00"))
        XCTAssertEqual(tx.rawMerchant, "SPAR TIRANA")
        XCTAssertEqual(tx.externalID, "tx1")
        XCTAssertEqual(tx.dedupeKey, "ext:tx1")
    }
    func test_maps_creditRowToIncome() throws {
        let tx = try XCTUnwrap(StatementRowMapper.map(row: ["01.05.2026","2.000,00","SALARY","tx2"], using: mapping))
        XCTAssertEqual(tx.kind, .income)
        XCTAssertEqual(tx.amount, 2000)
    }
    func test_returnsNil_forUnparseableDateOrAmount() {
        XCTAssertNil(StatementRowMapper.map(row: ["Date","Amount","Desc","ID"], using: mapping)) // header
        XCTAssertNil(StatementRowMapper.map(row: ["x","y","z","w"], using: mapping))
    }
}
```

- [ ] **Step 2: Run to verify fail** — `swift test --filter StatementRowMapperTests` → FAIL.

- [ ] **Step 3: Implement `ColumnMapping`**

`Sources/GoldengoImport/ColumnMapping.swift`:
```swift
import Foundation
import GoldengoCore

public struct ColumnMapping: Sendable, Equatable {
    public var dateIndex: Int
    public var amountIndex: Int
    public var merchantIndex: Int
    public var externalIDIndex: Int?
    public var dateFormat: String
    public var decimalSeparator: String
    public var groupingSeparator: String
    public var currency: CurrencyCode

    public init(dateIndex: Int, amountIndex: Int, merchantIndex: Int, externalIDIndex: Int?,
                dateFormat: String, decimalSeparator: String, groupingSeparator: String,
                currency: CurrencyCode) {
        self.dateIndex = dateIndex; self.amountIndex = amountIndex
        self.merchantIndex = merchantIndex; self.externalIDIndex = externalIDIndex
        self.dateFormat = dateFormat; self.decimalSeparator = decimalSeparator
        self.groupingSeparator = groupingSeparator; self.currency = currency
    }
}
```

- [ ] **Step 4: Implement `StatementRowMapper`**

`Sources/GoldengoImport/StatementRowMapper.swift`:
```swift
import Foundation
import GoldengoCore

public enum StatementRowMapper {
    /// Maps one parsed CSV row to a NormalizedTransaction, or nil if the row is a header /
    /// has an unparseable date or amount. Negative amount → expense (abs); positive → income.
    public static func map(row: [String], using m: ColumnMapping) -> NormalizedTransaction? {
        func field(_ i: Int?) -> String? {
            guard let i, i >= 0, i < row.count else { return nil }
            return row[i].trimmingCharacters(in: .whitespaces)
        }
        guard let dateStr = field(m.dateIndex), let amountStr = field(m.amountIndex),
              let date = Self.date(dateStr, format: m.dateFormat),
              let signed = Self.decimal(amountStr, decimal: m.decimalSeparator, grouping: m.groupingSeparator)
        else { return nil }

        let isExpense = signed < 0
        let amount = abs(signed)
        let merchant = field(m.merchantIndex)
        let ext = field(m.externalIDIndex)
        return NormalizedTransaction(
            externalID: (ext?.isEmpty == false) ? ext : nil,
            amount: amount, currency: m.currency, date: date,
            rawMerchant: (merchant?.isEmpty == false) ? merchant : nil,
            kind: isExpense ? .expense : .income, accountRef: "statement")
    }

    static func date(_ s: String, format: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = format
        return f.date(from: s)
    }

    static func decimal(_ s: String, decimal: String, grouping: String) -> Decimal? {
        var t = s.replacingOccurrences(of: grouping, with: "")
        t = t.replacingOccurrences(of: decimal, with: ".")
        t = t.replacingOccurrences(of: " ", with: "")
        return Decimal(string: t)
    }
}
```

- [ ] **Step 5: Run** — `swift test --filter StatementRowMapperTests` → PASS.

- [ ] **Step 6: Commit**
```bash
git add Sources/GoldengoImport/ColumnMapping.swift Sources/GoldengoImport/StatementRowMapper.swift Tests/GoldengoImportTests/StatementRowMapperTests.swift
git commit -m "feat: map statement CSV rows to NormalizedTransactions (date/amount/sign)"
```

---

### Task 3: Header auto-detect (Raiffeisen-style)

**Files:**
- Create: `Sources/GoldengoImport/MappingDetector.swift`
- Test: `Tests/GoldengoImportTests/MappingDetectorTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/GoldengoImportTests/MappingDetectorTests.swift`:
```swift
import XCTest
import GoldengoCore
@testable import GoldengoImport

final class MappingDetectorTests: XCTestCase {
    func test_detects_columnsFromHeaderNames() throws {
        let header = ["Date", "Amount", "Description", "Reference"]
        let m = try XCTUnwrap(MappingDetector.detect(header: header, currency: .all))
        XCTAssertEqual(m.dateIndex, 0)
        XCTAssertEqual(m.amountIndex, 1)
        XCTAssertEqual(m.merchantIndex, 2)
        XCTAssertEqual(m.externalIDIndex, 3)
    }
    func test_returnsNil_whenRequiredColumnsMissing() {
        XCTAssertNil(MappingDetector.detect(header: ["Foo","Bar"], currency: .all))
    }
}
```

- [ ] **Step 2: Run to verify fail** — `swift test --filter MappingDetectorTests` → FAIL.

- [ ] **Step 3: Implement the detector** (case-insensitive header keyword match)

`Sources/GoldengoImport/MappingDetector.swift`:
```swift
import Foundation
import GoldengoCore

public enum MappingDetector {
    public static func detect(header: [String], currency: CurrencyCode) -> ColumnMapping? {
        let lower = header.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        func firstIndex(_ keys: [String]) -> Int? {
            lower.firstIndex { h in keys.contains { h.contains($0) } }
        }
        guard let dateIdx = firstIndex(["date", "data", "datë"]),
              let amtIdx = firstIndex(["amount", "vlera", "shuma", "debit"]),
              let descIdx = firstIndex(["description", "details", "merchant", "përshkrim", "narrative"])
        else { return nil }
        let idIdx = firstIndex(["reference", "ref", "id", "transaction"])
        return ColumnMapping(dateIndex: dateIdx, amountIndex: amtIdx, merchantIndex: descIdx,
                             externalIDIndex: idIdx, dateFormat: "dd.MM.yyyy",
                             decimalSeparator: ",", groupingSeparator: ".", currency: currency)
    }
}
```
> Keyword lists include a few Albanian terms as a best guess; refine against a real Raiffeisen export.

- [ ] **Step 4: Run** — `swift test --filter MappingDetectorTests` → PASS.

- [ ] **Step 5: Commit**
```bash
git add Sources/GoldengoImport/MappingDetector.swift Tests/GoldengoImportTests/MappingDetectorTests.swift
git commit -m "feat: auto-detect statement column mapping from header names"
```

---

### Task 4: `ImportBatch` model

**Files:**
- Create: `Sources/GoldengoData/Models/ImportBatch.swift`
- Modify: `Sources/GoldengoData/ModelContainer+Goldengo.swift` (add to schema)
- Test: `Tests/GoldengoDataTests/ImportBatchTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/GoldengoDataTests/ImportBatchTests.swift`:
```swift
import XCTest
import SwiftData
@testable import GoldengoData

final class ImportBatchTests: XCTestCase {
    func test_importBatch_persists() throws {
        let container = try ModelContainer.goldengoInMemory()
        let ctx = ModelContext(container)
        ctx.insert(ImportBatch(fileName: "may.csv", rowCount: 10, importedCount: 8, dedupedCount: 2))
        try ctx.save()
        let all = try ctx.fetch(FetchDescriptor<ImportBatch>())
        XCTAssertEqual(all.first?.fileName, "may.csv")
        XCTAssertEqual(all.first?.importedCount, 8)
    }
}
```

- [ ] **Step 2: Run to verify fail** — FAIL (`ImportBatch` not in schema).

- [ ] **Step 3: Implement the model** (CloudKit-safe: defaults, no `.unique`)

`Sources/GoldengoData/Models/ImportBatch.swift`:
```swift
import Foundation
import SwiftData

@Model
public final class ImportBatch {
    public var fileName: String = ""
    public var importedAt: Date = Date.now
    public var rowCount: Int = 0
    public var importedCount: Int = 0
    public var dedupedCount: Int = 0

    public init(fileName: String = "", importedAt: Date = .now,
                rowCount: Int = 0, importedCount: Int = 0, dedupedCount: Int = 0) {
        self.fileName = fileName; self.importedAt = importedAt
        self.rowCount = rowCount; self.importedCount = importedCount; self.dedupedCount = dedupedCount
    }
}
```
Add `ImportBatch.self` to the `goldengoSchema` array in `ModelContainer+Goldengo.swift`.

- [ ] **Step 4: Run** — `swift test --filter ImportBatchTests` → PASS.

- [ ] **Step 5: Commit**
```bash
git add Sources/GoldengoData/Models/ImportBatch.swift Sources/GoldengoData/ModelContainer+Goldengo.swift Tests/GoldengoDataTests/ImportBatchTests.swift
git commit -m "feat: add ImportBatch model and register it in the schema"
```

---

### Task 5: `IngestionStore.importStatement`

**Files:**
- Modify: `Sources/GoldengoData/IngestionStore.swift`
- Test: `Tests/GoldengoDataTests/ImportStatementTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/GoldengoDataTests/ImportStatementTests.swift`:
```swift
import XCTest
import GoldengoCore
@testable import GoldengoData

final class ImportStatementTests: XCTestCase {
    private func txns() -> [NormalizedTransaction] {
        [ NormalizedTransaction(externalID: "a", amount: 100, currency: .all, date: .now,
                                rawMerchant: "Spar", kind: .expense, accountRef: "statement"),
          NormalizedTransaction(externalID: "b", amount: 200, currency: .all, date: .now,
                                rawMerchant: "Kios", kind: .expense, accountRef: "statement") ]
    }
    func test_import_insertsAll_andRecordsBatch() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let s = try await store.importStatement(txns(), fileName: "may.csv")
        XCTAssertEqual(s.imported, 2)
        XCTAssertEqual(s.deduped, 0)
        XCTAssertEqual(try await store.expenseCount(), 2)
        XCTAssertEqual(try await store.importBatchCount(), 1)
    }
    func test_reimport_sameRows_allDeduped() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        _ = try await store.importStatement(txns(), fileName: "may.csv")
        let s = try await store.importStatement(txns(), fileName: "may-again.csv")
        XCTAssertEqual(s.imported, 0)
        XCTAssertEqual(s.deduped, 2)
        XCTAssertEqual(try await store.expenseCount(), 2) // no double-count
    }
}
```

- [ ] **Step 2: Run to verify fail** — FAIL.

- [ ] **Step 3: Implement** — add to `IngestionStore`:
```swift
    public struct ImportSummary: Sendable, Equatable { public var imported: Int; public var deduped: Int }

    public func importStatement(_ transactions: [NormalizedTransaction], fileName: String) throws -> ImportSummary {
        var imported = 0, deduped = 0
        for tx in transactions {
            switch try ingest(tx, source: .imported) {
            case .inserted: imported += 1
            case .merged:   deduped += 1
            }
        }
        modelContext.insert(ImportBatch(fileName: fileName, rowCount: transactions.count,
                                        importedCount: imported, dedupedCount: deduped))
        try modelContext.save()
        return ImportSummary(imported: imported, deduped: deduped)
    }

    public func importBatchCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<ImportBatch>())
    }
```

- [ ] **Step 4: Run** — `swift test --filter ImportStatementTests` → PASS; full `swift test` green.

- [ ] **Step 5: Commit**
```bash
git add Sources/GoldengoData/IngestionStore.swift Tests/GoldengoDataTests/ImportStatementTests.swift
git commit -m "feat: importStatement ingests rows, dedupes, and records an ImportBatch"
```

---

### Task 6: Import UI + simulator verification

**Files:**
- Modify: `Package.swift` (`GoldengoFeatures` depends on `GoldengoImport`)
- Create: `Sources/GoldengoFeatures/Import/ImportModel.swift`
- Create: `Sources/GoldengoFeatures/Import/ImportView.swift`
- Create: `Sources/GoldengoFeatures/Import/SampleStatement.swift` (bundled sample text for sim verification)
- Modify: `Sources/GoldengoFeatures/Settings/SettingsView.swift` (add an "Import statement" entry) OR a toolbar button on Recent
- Test: `Tests/GoldengoFeaturesTests/ImportModelTests.swift`

- [ ] **Step 1: Failing test for the model's end-to-end (parse → detect → import)**

`Tests/GoldengoFeaturesTests/ImportModelTests.swift`:
```swift
import XCTest
import GoldengoCore
import GoldengoData
@testable import GoldengoFeatures

@MainActor
final class ImportModelTests: XCTestCase {
    func test_importCSVText_parsesDetectsAndPersists() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let m = ImportModel(store: store, currency: .all)
        let csv = """
        Date,Amount,Description,Reference
        30.05.2026,"-1.500,00",SPAR TIRANA,tx1
        29.05.2026,"-250,00",COFFEE,tx2
        """
        try await m.importCSV(text: csv, fileName: "sample.csv")
        XCTAssertEqual(m.resultText, "Imported 2, skipped 0 duplicates")
        XCTAssertEqual(try await store.expenseCount(), 2)
    }
}
```

- [ ] **Step 2: Run to verify fail** — FAIL.

- [ ] **Step 3: Implement `ImportModel`** (glue: parse → detect mapping → map rows → importStatement)

`Sources/GoldengoFeatures/Import/ImportModel.swift`:
```swift
import Foundation
import Observation
import GoldengoCore
import GoldengoData
import GoldengoImport

@MainActor
@Observable
public final class ImportModel {
    public let store: IngestionStore
    public var currency: CurrencyCode
    public private(set) var resultText: String = ""

    public init(store: IngestionStore, currency: CurrencyCode = .all) {
        self.store = store; self.currency = currency
    }

    public func importCSV(text: String, fileName: String) async throws {
        var rows = CSVParser.parse(text)
        guard let header = rows.first,
              let mapping = MappingDetector.detect(header: header, currency: currency) else {
            resultText = "Couldn't recognize the statement columns."
            return
        }
        rows.removeFirst()
        let txns = rows.compactMap { StatementRowMapper.map(row: $0, using: mapping) }
        let summary = try await store.importStatement(txns, fileName: fileName)
        resultText = "Imported \(summary.imported), skipped \(summary.deduped) duplicates"
    }
}
```

- [ ] **Step 4: Run** — `swift test --filter ImportModelTests` → PASS.

- [ ] **Step 5: Add the bundled sample + the view.**

`Sources/GoldengoFeatures/Import/SampleStatement.swift`:
```swift
public enum SampleStatement {
    public static let csv = """
    Date,Amount,Description,Reference
    30.05.2026,"-1.500,00",SPAR TIRANA,s1
    29.05.2026,"-250,00",COFFEE CORNER,s2
    28.05.2026,"-3.200,00",CONAD MARKET,s3
    27.05.2026,"45.000,00",SALARY,s4
    """
}
```

`Sources/GoldengoFeatures/Import/ImportView.swift`:
```swift
import SwiftUI
import GoldengoData

public struct ImportView: View {
    @State private var model: ImportModel
    @State private var showingPicker = false
    public init(model: ImportModel) { _model = State(initialValue: model) }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Import a statement") {
                    Button("Choose CSV file…") { showingPicker = true }
                    Button("Try a sample statement") {
                        Task { try? await model.importCSV(text: SampleStatement.csv, fileName: "sample.csv") }
                    }
                }
                if !model.resultText.isEmpty {
                    Section("Result") { Text(model.resultText) }
                }
            }
            .navigationTitle("Import")
            .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
                guard case let .success(url) = result else { return }
                Task {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if let text = try? String(contentsOf: url, encoding: .utf8) {
                        try? await model.importCSV(text: text, fileName: url.lastPathComponent)
                    }
                }
            }
        }
    }
}
```
Wire it in: add an **Import** tab (tag 3) to `RootView` (and a `case "import": return 3` deep link), or a navigation row in Settings — pick the Import tab for easy simulator verification.

- [ ] **Step 6: Build, run, verify in the simulator** — build + launch; go to the **Import** screen; tap **"Try a sample statement"**; screenshot the result (`AppProject/.build/import.png`) and read it — confirm "Imported 4, skipped 0 duplicates"; switch to **Recent** and screenshot (`AppProject/.build/recent-after-import.png`) — confirm the imported rows (SPAR/COFFEE/CONAD) appear. `swift test` → green.

- [ ] **Step 7: Commit**
```bash
git add Package.swift Sources/GoldengoFeatures/Import Sources/GoldengoFeatures/RootView.swift AppProject/Goldengo.xcodeproj/project.pbxproj Tests/GoldengoFeaturesTests/ImportModelTests.swift
git commit -m "feat: add CSV import UI (file picker + sample) wired to importStatement"
```

---

## Done criteria
- `swift test` green: CSV parser (quotes/newlines/blank lines), row mapper (date/amount/sign/header-skip), header auto-detect, ImportBatch persistence, importStatement insert+dedupe, ImportModel end-to-end.
- App builds; the **Import** screen runs the bundled sample in the simulator and the imported rows appear in **Recent** (both screenshot-verified).
- Re-importing the same rows dedupes (no double-count); each import records an `ImportBatch`.
- Closes the GOL-5 stories created from these tasks. (Real Raiffeisen format to be confirmed against a user-provided export.)
