# Receipt Scanning (GOL-80) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scan a paper receipt with the camera and auto-fill a confirmable expense (amount + merchant + date), fully on-device, no backend, no photo kept.

**Architecture:** A pure, fully-tested parser in `GoldengoCore` turns OCR lines into `(amount, merchant, date)`. `GoldengoFeatures/Receipt/` holds the on-device OCR (`Vision`), the iOS document-scanner wrapper (`VisionKit`), an `@Observable` orchestrator, and a confirm sheet; the Add screen gets a scan button. The only app-target change is one `Info.plist` key, so no `project.rb` regen.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, `Vision` (`VNRecognizeTextRequest`, on-device, macOS+iOS), `VisionKit` (`VNDocumentCameraViewController`, iOS-only), XCTest. Spec: `docs/superpowers/specs/2026-06-06-receipt-scan-design.md`.

**Cross-platform note:** the SPM package builds for macOS too (tests run there). `Vision` OCR and the parser are cross-platform; `VisionKit.VNDocumentCameraViewController` is **iOS-only**, so `DocumentScannerView` and its call sites are wrapped in `#if os(iOS)`. The parser and `ReceiptScanModel` take a `CGImage`/`[RecognizedLine]` (cross-platform) and are unit-tested on macOS.

**SwiftData rule (from memory):** never compare `Decimal` inside a `#Predicate` — not relevant here (no new predicates), but keep `Decimal` math in plain Swift.

---

## File Structure

**Create:**
- `Sources/GoldengoCore/ReceiptParser.swift` — `RecognizedLine`, `ParsedReceipt`, `ReceiptParser.parse` + amount/merchant/date heuristics (pure).
- `Sources/GoldengoFeatures/Receipt/ReceiptOCR.swift` — `Vision` OCR: `CGImage → [RecognizedLine]`.
- `Sources/GoldengoFeatures/Receipt/ReceiptScanModel.swift` — `@MainActor @Observable` orchestrator + save.
- `Sources/GoldengoFeatures/Receipt/DocumentScannerView.swift` — iOS-only `UIViewControllerRepresentable` over `VNDocumentCameraViewController`.
- `Sources/GoldengoFeatures/Receipt/ReceiptReviewView.swift` — pre-filled confirm sheet.
- `Tests/GoldengoCoreTests/ReceiptParserTests.swift`
- `Tests/GoldengoFeaturesTests/ReceiptScanModelTests.swift`

**Modify:**
- `Sources/GoldengoData/IngestionStore.swift` — add `date: Date = .now` to `logManual`/`logEntry`.
- `Tests/GoldengoDataTests/LogManualTests.swift` — back-dated `logManual` test.
- `Sources/GoldengoFeatures/QuickAdd/QuickAddView.swift` — iOS-only scan button + scanner/review presentation.
- `AppProject/Goldengo/Info.plist` — `NSCameraUsageDescription`.

---

## Task 1: `logManual` accepts an explicit date

**Files:**
- Modify: `Sources/GoldengoData/IngestionStore.swift`
- Test: `Tests/GoldengoDataTests/LogManualTests.swift`

- [ ] **Step 1: Write the failing test** — append inside the `LogManualTests` class:

```swift
    func test_logManual_persistsExplicitDate() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let past = Date(timeIntervalSince1970: 1_700_000_000)   // 2023-11-14
        _ = try await store.logManual(amount: 500, currency: .all, merchant: "Spar",
                                      categoryName: nil, date: past)
        let recents = try await store.recentExpenses(limit: 1)
        XCTAssertEqual(recents.first?.date, past, "A scanned/back-dated receipt must keep its own date, not now.")
    }
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter 'LogManualTests/test_logManual_persistsExplicitDate'`
Expected: FAIL — extra argument `date` in call.

- [ ] **Step 3: Add the `date` parameter** — in `Sources/GoldengoData/IngestionStore.swift`, change `logManual` and `logEntry`:

```swift
    @discardableResult
    public func logManual(amount: Decimal, currency: CurrencyCode,
                          merchant: String?, note: String? = nil, categoryName: String?,
                          date: Date = .now) throws -> String {
        try logEntry(amount: amount, currency: currency, merchant: merchant, note: note,
                     categoryName: categoryName, source: .manual, keyPrefix: "manual", date: date)
    }
```

And update `logAutomatic` + `logEntry` to thread the date (default `.now`):

```swift
    @discardableResult
    public func logAutomatic(amount: Decimal, currency: CurrencyCode,
                             merchant: String?, categoryName: String? = nil) throws -> String {
        try logEntry(amount: amount, currency: currency, merchant: merchant, note: nil,
                     categoryName: categoryName, source: .automatic, keyPrefix: "auto", date: .now)
    }

    @discardableResult
    private func logEntry(amount: Decimal, currency: CurrencyCode, merchant: String?, note: String?,
                          categoryName: String?, source: ExpenseSource, keyPrefix: String,
                          date: Date = .now) throws -> String {
        let key = "\(keyPrefix):\(UUID().uuidString)"
        let cleanNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rec = ExpenseRecord(amount: amount, currencyCode: currency.rawValue, date: date,
                                merchantName: merchant, note: (cleanNote?.isEmpty ?? true) ? nil : cleanNote,
                                kind: .expense, source: source, dedupeKey: key)
        if let categoryName, !categoryName.isEmpty {
            rec.category = try findOrCreateCategory(named: categoryName)
        } else {
            rec.category = try defaultCategory(forMerchant: merchant) ?? findOrCreateCategory(named: "Other")
        }
        modelContext.insert(rec)
        try linkToConfirmedSubscription(rec)
        try modelContext.save()
        try refreshSharedTodayTotal()
        return key
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter 'LogManualTests'`
Expected: PASS (existing logManual tests + the new one).

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoData/IngestionStore.swift Tests/GoldengoDataTests/LogManualTests.swift
git commit -m "feat(gol-80): logManual accepts an explicit date (back-dated receipts)"
```

---

## Task 2: ReceiptParser — amount extraction

**Files:**
- Create: `Sources/GoldengoCore/ReceiptParser.swift`
- Test: `Tests/GoldengoCoreTests/ReceiptParserTests.swift`

- [ ] **Step 1: Write the failing tests** — create `Tests/GoldengoCoreTests/ReceiptParserTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import GoldengoCore

final class ReceiptParserTests: XCTestCase {
    /// Helper: a line at vertical position `y` (0 = bottom of receipt, 1 = top).
    private func line(_ text: String, y: Double) -> RecognizedLine {
        RecognizedLine(text: text, boundingBox: CGRect(x: 0.1, y: y, width: 0.8, height: 0.03))
    }

    func test_amount_prefersTotalKeywordLine_overSubtotalAndTax() {
        let lines = [
            line("SPAR TIRANA", y: 0.95),
            line("Subtotal 1000", y: 0.40),
            line("TVSH 200", y: 0.30),
            line("TOTALI 1200 L", y: 0.20),
        ]
        let parsed = ReceiptParser.parse(lines, currency: .all)
        XCTAssertEqual(parsed.amount, 1200, "Must pick the TOTAL line, not the subtotal or tax.")
    }

    func test_amount_lek_stripsThousandsSeparator_noDecimals() {
        let lines = [line("TOTALI 1.250 L", y: 0.2)]
        XCTAssertEqual(ReceiptParser.parse(lines, currency: .all).amount, 1250)
    }

    func test_amount_twoDecimalCurrency_dotDecimal() {
        let lines = [line("TOTAL $12.50", y: 0.2)]
        XCTAssertEqual(ReceiptParser.parse(lines, currency: .usd).amount, Decimal(string: "12.50"))
    }

    func test_amount_twoDecimalCurrency_commaDecimal() {
        let lines = [line("TOTAL 12,50", y: 0.2)]
        XCTAssertEqual(ReceiptParser.parse(lines, currency: .eur).amount, Decimal(string: "12.50"))
    }

    func test_amount_fallsBackToLargestInLowerHalf_whenNoKeyword() {
        let lines = [
            line("ITEM A 300", y: 0.6),
            line("ITEM B 250", y: 0.5),
            line("900", y: 0.2),          // the (unlabeled) total, near the bottom
        ]
        XCTAssertEqual(ReceiptParser.parse(lines, currency: .all).amount, 900)
    }

    func test_amount_nilWhenNoNumbers() {
        let lines = [line("THANK YOU", y: 0.2), line("SPAR", y: 0.9)]
        XCTAssertNil(ReceiptParser.parse(lines, currency: .all).amount)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter 'ReceiptParserTests'`
Expected: FAIL — `cannot find 'ReceiptParser' / 'RecognizedLine' in scope`.

- [ ] **Step 3: Create the parser with amount extraction** — create `Sources/GoldengoCore/ReceiptParser.swift`:

```swift
import Foundation
import CoreGraphics

/// One OCR text line with its normalized position (origin bottom-left, so larger y = higher on the receipt).
public struct RecognizedLine: Sendable, Equatable {
    public let text: String
    public let boundingBox: CGRect
    public init(text: String, boundingBox: CGRect) {
        self.text = text
        self.boundingBox = boundingBox
    }
}

/// Best-effort fields pulled from a receipt. Any field may be nil — the user confirms before saving.
public struct ParsedReceipt: Sendable, Equatable {
    public let amount: Decimal?
    public let merchant: String?
    public let date: Date?
    public init(amount: Decimal?, merchant: String?, date: Date?) {
        self.amount = amount; self.merchant = merchant; self.date = date
    }
}

public enum ReceiptParser {
    private static let totalKeywords = ["TOTALI", "TOTAL", "AMOUNT DUE", "SHUMA", "VLERA"]

    public static func parse(_ lines: [RecognizedLine], currency: CurrencyCode) -> ParsedReceipt {
        ParsedReceipt(amount: extractAmount(lines, currency: currency),
                      merchant: nil,   // Task 3
                      date: nil)       // Task 4
    }

    // MARK: Amount

    static func extractAmount(_ lines: [RecognizedLine], currency: CurrencyCode) -> Decimal? {
        let digits = currency.fractionDigits
        // 1) Prefer lines that name a total; among those, the bottom-most (final total sits near the bottom).
        let keywordLines = lines
            .filter { line in
                let upper = line.text.uppercased()
                return totalKeywords.contains { upper.contains($0) } && !amounts(in: line.text, digits: digits).isEmpty
            }
            .sorted { $0.boundingBox.midY < $1.boundingBox.midY }   // bottom-most first
        if let best = keywordLines.first {
            return amounts(in: best.text, digits: digits).max()
        }
        // 2) Fallback: the largest amount in the lower half of the receipt.
        let lowerHalf = lines.filter { $0.boundingBox.midY < 0.5 }
        let candidates = lowerHalf.flatMap { amounts(in: $0.text, digits: digits) }
        return candidates.max()
    }

    /// Every parseable money amount in a string (currency symbols/letters ignored).
    static func amounts(in text: String, digits: Int) -> [Decimal] {
        guard let re = try? NSRegularExpression(pattern: #"\d[\d.,]*\d|\d"#) else { return [] }
        let ns = text as NSString
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { parseAmount(ns.substring(with: $0.range), fractionDigits: digits) }
    }

    /// Parse one numeric token into a Decimal, resolving `,`/`.` as decimal vs. thousands separators.
    static func parseAmount(_ raw: String, fractionDigits: Int) -> Decimal? {
        let filtered = raw.filter { $0.isNumber || $0 == "." || $0 == "," }
        guard filtered.contains(where: \.isNumber) else { return nil }
        if fractionDigits == 0 {
            return Decimal(string: String(filtered.filter(\.isNumber)))
        }
        if let lastSep = filtered.lastIndex(where: { $0 == "." || $0 == "," }) {
            let after = filtered[filtered.index(after: lastSep)...].filter(\.isNumber)
            if after.count >= 1 && after.count <= fractionDigits {
                let intPart = filtered[..<lastSep].filter(\.isNumber)
                return Decimal(string: "\(intPart).\(after)")
            }
        }
        return Decimal(string: String(filtered.filter(\.isNumber)))   // all separators are grouping
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter 'ReceiptParserTests'`
Expected: PASS (all 5 amount tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoCore/ReceiptParser.swift Tests/GoldengoCoreTests/ReceiptParserTests.swift
git commit -m "feat(gol-80): ReceiptParser amount extraction (total-keyword + lower-half fallback)"
```

---

## Task 3: ReceiptParser — merchant extraction

**Files:**
- Modify: `Sources/GoldengoCore/ReceiptParser.swift`
- Test: `Tests/GoldengoCoreTests/ReceiptParserTests.swift`

- [ ] **Step 1: Write the failing tests** — append inside `ReceiptParserTests`:

```swift
    func test_merchant_isTopMostNonNumericLine() {
        let lines = [
            line("SPAR TIRANA", y: 0.95),
            line("Rruga Myslym Shyri", y: 0.88),
            line("TOTALI 1200", y: 0.2),
        ]
        XCTAssertEqual(ReceiptParser.parse(lines, currency: .all).merchant, "SPAR TIRANA")
    }

    func test_merchant_skipsNumericAndDateTopLines() {
        let lines = [
            line("2026-05-30", y: 0.97),
            line("0696 4471", y: 0.95),
            line("Cafe Bar Elida", y: 0.90),
            line("TOTALI 300", y: 0.2),
        ]
        XCTAssertEqual(ReceiptParser.parse(lines, currency: .all).merchant, "Cafe Bar Elida")
    }

    func test_merchant_nilWhenNothingSuitable() {
        let lines = [line("1200", y: 0.9), line("2026-05-30", y: 0.8)]
        XCTAssertNil(ReceiptParser.parse(lines, currency: .all).merchant)
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter 'ReceiptParserTests/test_merchant'`
Expected: FAIL — merchant is nil (not yet implemented).

- [ ] **Step 3: Implement merchant extraction** — in `ReceiptParser.swift`, update `parse` and add the helpers:

```swift
    public static func parse(_ lines: [RecognizedLine], currency: CurrencyCode) -> ParsedReceipt {
        ParsedReceipt(amount: extractAmount(lines, currency: currency),
                      merchant: extractMerchant(lines),
                      date: nil)       // Task 4
    }

    // MARK: Merchant

    static func extractMerchant(_ lines: [RecognizedLine]) -> String? {
        let topFirst = lines.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        for line in topFirst {
            let t = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.count >= 2 else { continue }
            if isMostlyNumeric(t) { continue }
            if dateString(in: t) != nil { continue }
            return t
        }
        return nil
    }

    private static func isMostlyNumeric(_ s: String) -> Bool {
        let letters = s.filter(\.isLetter).count
        let numbers = s.filter(\.isNumber).count
        return numbers > letters   // "0696 4471" -> numeric; "SPAR TIRANA" -> not
    }
```

(`dateString(in:)` is added in Task 4; for now add this stub above `extractMerchant` so the file compiles — Task 4 replaces it with the real implementation:)

```swift
    static func dateString(in text: String) -> String? { nil }   // replaced in Task 4
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter 'ReceiptParserTests'`
Expected: PASS (amount + merchant tests; the date-skip case passes because "2026-05-30" is mostly numeric).

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoCore/ReceiptParser.swift Tests/GoldengoCoreTests/ReceiptParserTests.swift
git commit -m "feat(gol-80): ReceiptParser merchant extraction (top-most non-numeric line)"
```

---

## Task 4: ReceiptParser — date extraction

**Files:**
- Modify: `Sources/GoldengoCore/ReceiptParser.swift`
- Test: `Tests/GoldengoCoreTests/ReceiptParserTests.swift`

- [ ] **Step 1: Write the failing tests** — append inside `ReceiptParserTests`:

```swift
    private func ymd(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    func test_date_parsesISOFormat() {
        let lines = [line("Date: 2025-05-30", y: 0.8), line("TOTALI 1200", y: 0.2)]
        XCTAssertEqual(ReceiptParser.parse(lines, currency: .all).date, ymd(2025, 5, 30))
    }

    func test_date_parsesDayFirstDotFormat() {
        let lines = [line("30.05.2025 14:22", y: 0.8), line("TOTALI 1200", y: 0.2)]
        XCTAssertEqual(ReceiptParser.parse(lines, currency: .all).date, ymd(2025, 5, 30))
    }

    func test_date_nilWhenAbsent() {
        let lines = [line("SPAR", y: 0.9), line("TOTALI 1200", y: 0.2)]
        XCTAssertNil(ReceiptParser.parse(lines, currency: .all).date)
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter 'ReceiptParserTests/test_date'`
Expected: FAIL — date is nil (only the stub exists).

- [ ] **Step 3: Implement date extraction** — in `ReceiptParser.swift`, update `parse`, **replace** the `dateString(in:)` stub, and add `extractDate`:

```swift
    public static func parse(_ lines: [RecognizedLine], currency: CurrencyCode) -> ParsedReceipt {
        ParsedReceipt(amount: extractAmount(lines, currency: currency),
                      merchant: extractMerchant(lines),
                      date: extractDate(lines))
    }

    // MARK: Date

    private static let dateFormats = ["yyyy-MM-dd", "dd.MM.yyyy", "dd/MM/yyyy", "dd-MM-yyyy"]

    static func extractDate(_ lines: [RecognizedLine], now: Date = .now) -> Date? {
        let cal = Calendar(identifier: .gregorian)
        let twoYearsAgo = cal.date(byAdding: .year, value: -2, to: now) ?? now
        for line in lines {
            guard let token = dateString(in: line.text) else { continue }
            for fmt in dateFormats {
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.timeZone = TimeZone(identifier: "UTC")
                df.dateFormat = fmt
                if let d = df.date(from: token), d <= now, d >= twoYearsAgo { return d }
            }
        }
        return nil
    }

    /// The first date-shaped substring in a line, or nil.
    static func dateString(in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: #"\d{1,4}[./-]\d{1,2}[./-]\d{1,4}"#) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range)
    }
```

(Delete the Task 3 `dateString(in:)` stub — this is its real implementation.)

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter 'ReceiptParserTests'`
Expected: PASS (all amount + merchant + date tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoCore/ReceiptParser.swift Tests/GoldengoCoreTests/ReceiptParserTests.swift
git commit -m "feat(gol-80): ReceiptParser date extraction (multi-format, sanity-bounded)"
```

---

## Task 5: ReceiptOCR (Vision, on-device)

**Files:**
- Create: `Sources/GoldengoFeatures/Receipt/ReceiptOCR.swift`

- [ ] **Step 1: Implement the OCR wrapper** — create the file:

```swift
import Foundation
import Vision
import CoreGraphics
import GoldengoCore

/// On-device OCR: a receipt page image → recognized text lines with positions.
/// Vision processes entirely on-device. `nonisolated` so callers run it off the main actor.
public enum ReceiptOCR {
    public static func recognizeLines(in cgImage: CGImage) throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        return (request.results ?? []).compactMap { obs in
            guard let text = obs.topCandidates(1).first?.string else { return nil }
            return RecognizedLine(text: text, boundingBox: obs.boundingBox)
        }
    }
}
```

- [ ] **Step 2: Verify it builds (no unit test — OCR accuracy is verified on device)**

Run: `swift build`
Expected: build succeeds. (Vision is available on macOS, so the package compiles; real OCR quality is validated on-device in Task 11.)

- [ ] **Step 3: Commit**

```bash
git add Sources/GoldengoFeatures/Receipt/ReceiptOCR.swift
git commit -m "feat(gol-80): ReceiptOCR — on-device Vision text recognition"
```

---

## Task 6: ReceiptScanModel (orchestrator)

**Files:**
- Create: `Sources/GoldengoFeatures/Receipt/ReceiptScanModel.swift`
- Test: `Tests/GoldengoFeaturesTests/ReceiptScanModelTests.swift`

- [ ] **Step 1: Write the failing tests** — create `Tests/GoldengoFeaturesTests/ReceiptScanModelTests.swift`:

```swift
import XCTest
import CoreGraphics
import GoldengoCore
import GoldengoData
@testable import GoldengoFeatures

@MainActor
final class ReceiptScanModelTests: XCTestCase {
    private func line(_ text: String, y: Double) -> RecognizedLine {
        RecognizedLine(text: text, boundingBox: CGRect(x: 0.1, y: y, width: 0.8, height: 0.03))
    }

    func test_populate_fillsDraftFromLines() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let model = ReceiptScanModel(store: store, currency: .all)
        model.populate(from: [line("SPAR TIRANA", y: 0.95),
                              line("30.05.2025", y: 0.88),
                              line("TOTALI 1.250 L", y: 0.2)])
        XCTAssertEqual(model.amountString, "1250")
        XCTAssertEqual(model.merchant, "SPAR TIRANA")
        XCTAssertNotNil(model.date)
    }

    func test_save_logsExpenseWithParsedDate() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let model = ReceiptScanModel(store: store, currency: .all)
        model.populate(from: [line("Cafe Elida", y: 0.95), line("TOTALI 300", y: 0.2)])
        await model.save()
        let recents = try await store.recentExpenses(limit: 1)
        XCTAssertEqual(recents.first?.amount, 300)
        XCTAssertEqual(recents.first?.merchantName, "Cafe Elida")
        XCTAssertEqual(recents.first?.source, .manual)
    }

    func test_canSave_falseWhenNoAmount() throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let model = ReceiptScanModel(store: store, currency: .all)
        model.populate(from: [line("THANK YOU", y: 0.2)])
        XCTAssertFalse(model.canSave)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter 'ReceiptScanModelTests'`
Expected: FAIL — `cannot find 'ReceiptScanModel' in scope`.

- [ ] **Step 3: Implement the model** — create `Sources/GoldengoFeatures/Receipt/ReceiptScanModel.swift`:

```swift
import Foundation
import Observation
import CoreGraphics
import GoldengoCore
import GoldengoData

@MainActor
@Observable
public final class ReceiptScanModel {
    public let store: IngestionStore
    public var currency: CurrencyCode
    public var amountString: String = ""
    public var merchant: String = ""
    public var selectedCategory: String?
    public var date: Date?
    public private(set) var savedCount: Int = 0
    public var errorText: String?
    /// True after a scan whose OCR yielded no usable total (drives the "enter it" hint in the review).
    public private(set) var amountWasUnreadable = false

    public init(store: IngestionStore, currency: CurrencyCode = .all) {
        self.store = store
        self.currency = currency
    }

    public var amountDecimal: Decimal { Decimal(string: amountString) ?? 0 }
    public var canSave: Bool { amountDecimal > 0 }

    /// Run OCR on a scanned page image, then fill the draft. Off the main actor for OCR.
    public func handle(cgImage: CGImage) async {
        let lines = (try? await Task.detached { try ReceiptOCR.recognizeLines(in: cgImage) }.value) ?? []
        populate(from: lines)
    }

    /// Pure draft population from recognized lines (unit-tested without a camera).
    public func populate(from lines: [RecognizedLine]) {
        let parsed = ReceiptParser.parse(lines, currency: currency)
        if let amount = parsed.amount {
            amountString = NSDecimalNumber(decimal: amount).stringValue
            amountWasUnreadable = false
        } else {
            amountString = ""
            amountWasUnreadable = true
        }
        merchant = parsed.merchant ?? ""
        date = parsed.date
        selectedCategory = nil
    }

    public func save() async {
        guard canSave else { return }
        do {
            try await store.logManual(amount: amountDecimal, currency: currency,
                                      merchant: merchant.isEmpty ? nil : merchant,
                                      categoryName: selectedCategory,
                                      date: date ?? .now)
            savedCount += 1
        } catch {
            errorText = error.localizedDescription
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter 'ReceiptScanModelTests'`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoFeatures/Receipt/ReceiptScanModel.swift Tests/GoldengoFeaturesTests/ReceiptScanModelTests.swift
git commit -m "feat(gol-80): ReceiptScanModel orchestrates OCR -> parse -> draft -> logManual"
```

---

## Task 7: DocumentScannerView (iOS document camera)

**Files:**
- Create: `Sources/GoldengoFeatures/Receipt/DocumentScannerView.swift`

- [ ] **Step 1: Implement the scanner wrapper** — create the file (iOS-only; the package also builds for macOS):

```swift
#if os(iOS)
import SwiftUI
import VisionKit
import CoreGraphics

/// Wraps the system document scanner (live edge-detect + deskew + crop). Hands back the first
/// page's image as a CGImage, or a cancel. The host presents this and dismisses on either callback.
struct DocumentScannerView: UIViewControllerRepresentable {
    let onScan: (CGImage) -> Void
    let onCancel: () -> Void

    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView
        init(_ parent: DocumentScannerView) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            guard scan.pageCount > 0, let cg = scan.imageOfPage(at: 0).cgImage else {
                parent.onCancel(); return
            }
            parent.onScan(cg)
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            parent.onCancel()
        }
    }
}
#endif
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: build succeeds (the `#if os(iOS)` block is skipped on macOS).

- [ ] **Step 3: Commit**

```bash
git add Sources/GoldengoFeatures/Receipt/DocumentScannerView.swift
git commit -m "feat(gol-80): DocumentScannerView wraps VNDocumentCameraViewController (iOS)"
```

---

## Task 8: ReceiptReviewView (confirm sheet)

**Files:**
- Create: `Sources/GoldengoFeatures/Receipt/ReceiptReviewView.swift`

- [ ] **Step 1: Implement the review sheet** — create the file (functional baseline; visual polish via the frontend-design skill is welcome but the behavior must match):

```swift
import SwiftUI
import GoldengoDesignSystem
import GoldengoCore

/// Pre-filled confirm sheet for a scanned receipt. The user verifies/edits, then saves.
public struct ReceiptReviewView: View {
    @State private var model: ReceiptScanModel
    let onDone: () -> Void
    @FocusState private var amountFocused: Bool
    @FocusState private var merchantFocused: Bool

    public init(model: ReceiptScanModel, onDone: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onDone = onDone
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Amount") {
                    HStack {
                        Text(model.currency.symbol).foregroundStyle(.secondary)
                        TextField("0", text: $model.amountString)
#if os(iOS)
                            .keyboardType(.decimalPad)
#endif
                            .focused($amountFocused)
                            .font(.title2.weight(.semibold))
                    }
                    if model.amountWasUnreadable {
                        Text("Couldn't read the total — enter it.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Merchant") {
                    TextField("Merchant", text: $model.merchant)
                        .focused($merchantFocused)
                }
                Section("Date") {
                    DatePicker("Date",
                               selection: Binding(get: { model.date ?? .now },
                                                  set: { model.date = $0 }),
                               displayedComponents: .date)
                }
                Section("Category") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: GoldengoTheme.Spacing.s) {
                            ForEach(["Groceries", "Food", "Transport", "Coffee", "Bills", "Shopping", "Other"], id: \.self) { cat in
                                let selected = model.selectedCategory == cat
                                Button {
                                    model.selectedCategory = selected ? nil : cat
                                } label: {
                                    Label(cat, systemImage: GoldengoCategoryIcon.symbol(for: cat))
                                        .font(.subheadline.weight(.medium))
                                        .padding(.horizontal, GoldengoTheme.Spacing.m)
                                        .padding(.vertical, 8)
                                        .background(selected ? GoldengoTheme.accent : Color.goldengoSurface)
                                        .foregroundStyle(selected ? .black : .primary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Review receipt")
            .scrollContentBackground(.hidden)
            .background(Color.goldengoBackground.ignoresSafeArea())
            .contentShape(Rectangle())
            .onTapGesture { amountFocused = false; merchantFocused = false }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDone() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        amountFocused = false; merchantFocused = false
                        Task { await model.save(); onDone() }
                    }
                    .disabled(!model.canSave)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: build succeeds (SwiftUI is cross-platform).

- [ ] **Step 3: Commit**

```bash
git add Sources/GoldengoFeatures/Receipt/ReceiptReviewView.swift
git commit -m "feat(gol-80): ReceiptReviewView — pre-filled confirm sheet"
```

---

## Task 9: Wire the scan button into the Add screen

**Files:**
- Modify: `Sources/GoldengoFeatures/QuickAdd/QuickAddView.swift`

- [ ] **Step 1: Add scan state + button + presentation** — in `QuickAddView`:

(a) Add state properties next to the existing `@State`s:

```swift
#if os(iOS)
    @State private var showScanner = false
    @State private var scanModel: ReceiptScanModel?
#endif
```

(b) Add the scan button into the layout — change the `keypad` / `addButton` area by inserting a scan button above `addButton` in the main `VStack` (after `keypad`):

```swift
            keypad
#if os(iOS)
            scanReceiptButton
#endif
            addButton
```

(c) Add the button + sheets as computed/ modifiers. Add this view + attach the sheets:

```swift
#if os(iOS)
    @ViewBuilder private var scanReceiptButton: some View {
        if DocumentScannerView.isSupported {
            Button {
                showScanner = true
            } label: {
                Label("Scan receipt", systemImage: "doc.viewfinder")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(GoldengoTheme.accent)
        }
    }
#endif
```

(d) Attach the scanner + review presentation. Add these modifiers to the root `VStack` (next to the existing `.sheet`s):

```swift
#if os(iOS)
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView(
                onScan: { cg in
                    showScanner = false
                    let m = ReceiptScanModel(store: model.store, currency: model.currency)
                    scanModel = m
                    Task { await m.handle(cgImage: cg) }
                },
                onCancel: { showScanner = false }
            )
            .ignoresSafeArea()
        }
        .sheet(item: $scanModel) { m in
            ReceiptReviewView(model: m, onDone: { scanModel = nil })
        }
#endif
```

(e) For `.sheet(item:)`, `ReceiptScanModel` must be `Identifiable`. Add to `ReceiptScanModel` (in its file):

```swift
extension ReceiptScanModel: Identifiable {
    public nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}
```

- [ ] **Step 2: Build for the simulator**

Run: `xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath AppProject/.build build`
Expected: BUILD SUCCEEDED. (The scan button is hidden in the Simulator since `VNDocumentCameraViewController.isSupported` is false there — that's expected; the wiring still compiles.)

- [ ] **Step 3: Commit**

```bash
git add Sources/GoldengoFeatures/QuickAdd/QuickAddView.swift Sources/GoldengoFeatures/Receipt/ReceiptScanModel.swift
git commit -m "feat(gol-80): scan-receipt entry point on the Add screen (iOS)"
```

---

## Task 10: Camera usage permission (Info.plist)

**Files:**
- Modify: `AppProject/Goldengo/Info.plist`

- [ ] **Step 1: Add the key** — inside the top-level `<dict>` (e.g. after `LSSupportsOpeningDocumentsInPlace`):

```xml
  <key>NSCameraUsageDescription</key>
  <string>Scan a receipt to add the expense automatically.</string>
```

- [ ] **Step 2: Verify**

Run: `plutil -lint AppProject/Goldengo/Info.plist`
Expected: `OK`.
Run: `xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath AppProject/.build build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add AppProject/Goldengo/Info.plist
git commit -m "feat(gol-80): NSCameraUsageDescription for receipt scanning"
```

---

## Task 11: Full suite, device verification, ticket

- [ ] **Step 1: Full test suite** — `swift test` → all green (existing ~205 + new ReceiptParser/ReceiptScanModel/logManual-date tests). Fix anything red before proceeding; run the FULL suite (a `--filter` run hides cross-suite regressions — see GOL-79).

- [ ] **Step 2: Device build + install**

```bash
xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'generic/platform=iOS' -allowProvisioningUpdates -derivedDataPath AppProject/.build-device build
xcrun devicectl device install app --device 7B8F5F4F-B6B9-5A41-926D-31C29770064E AppProject/.build-device/Build/Products/Debug-iphoneos/Goldengo.app
```

- [ ] **Step 3: Manual device verification** — Add screen shows "Scan receipt"; scanning a real cash receipt (Albanian + English) opens the review pre-filled with a plausible total + merchant + date, category suggested where the merchant is known; Save logs it onto Recent with the right amount/merchant/currency/date; a faded/ambiguous receipt opens the review for manual amount entry (no crash, "couldn't read the total" hint).

- [ ] **Step 4: Ticket** — set GOL-80 → To Verify with a summary comment (what shipped, test counts, the device-verification checklist).

- [ ] **Step 5: Finish the branch** — second-Opus review over the diff → ff-merge to `main` → push.

---

## Self-Review

**Spec coverage:** capture (Task 7) ✓; OCR (Task 5) ✓; parser amount/merchant/date (Tasks 2–4) ✓; orchestrator + save-as-`.manual` with parsed date (Task 6 + Task 1) ✓; confirm sheet incl. unreadable-total hint (Task 8) ✓; entry point gated on `isSupported` (Task 9) ✓; `NSCameraUsageDescription`, no regen (Task 10) ✓; no photo kept / page-0 only / preferred currency / no new dedup (by construction — nothing stores an image, `handle` uses page 0, model defaults to the passed currency, save uses `.manual`) ✓; tests incl. "picks total not subtotal/tax" (Task 2) ✓.

**Placeholder scan:** none. The Task 3 `dateString` stub is explicitly created then replaced in Task 4 (called out in both), not a left-behind TODO.

**Type consistency:** `RecognizedLine`/`ParsedReceipt`/`ReceiptParser.parse(_:currency:)` consistent Tasks 2–4, 6; `ReceiptOCR.recognizeLines(in:) -> [RecognizedLine]` matches its caller in Task 6; `ReceiptScanModel(store:currency:)`, `.populate(from:)`, `.handle(cgImage:)`, `.save()`, `.amountString`, `.canSave`, `.amountWasUnreadable` consistent across Tasks 6, 8, 9; `DocumentScannerView(onScan:onCancel:)` + `.isSupported` match Task 9; `logManual(..., date:)` matches Task 1.
