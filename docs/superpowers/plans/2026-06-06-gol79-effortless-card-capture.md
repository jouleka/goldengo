# Effortless Card-Swipe Capture (GOL-79) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make capturing physical card-swipe spend near-effortless on iOS with no backend — one-tap "Share to Goldengo" statement import, plus cross-source dedup so Apple Pay auto-log and statement import don't double-count.

**Architecture:** Two on-device units meeting at `IngestionStore`. **Unit A** registers the app as a PDF/CSV handler (Info.plist) and routes shared files through `RootView`'s existing `.onOpenURL` into the existing import pipeline. **Unit B** adds an `.automatic` expense source for hands-free captures and a conservative reconciler that merges an imported statement row into a recent `.automatic` entry only on high confidence. No new app target and no `project.rb` run → Xcode-managed signing stays intact.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, SwiftData (`@ModelActor IngestionStore`), App Intents, App Groups, XCTest. Spec: `docs/superpowers/specs/2026-06-06-gol79-effortless-card-capture-design.md`.

**Spec deviation (intentional):** the spec named `GoldengoApp.swift` for `onOpenURL`; in fact `RootView` (SPM module `GoldengoFeatures`) already owns `.onOpenURL` + an import sheet, so file routing goes there. This touches *fewer* app-target files (only `Info.plist`) and keeps the rest in SPM, which is strictly safer for signing.

**Merchant-match reality:** `MerchantNormalizer.normalize` uppercases and drops *purely-numeric* tokens only. So "Spar" == "SPAR 4471" (terminal number dropped) but "Spar" ≠ "SPAR TIRANA" (location word kept). Exact-normalized-equality is therefore the high-confidence bar; location-word differences intentionally remain as deletable duplicates. (Note: the doc comment in `MerchantNormalizer.swift` claims "Spar"/"SPAR TIRANA 4471" normalize equal — that is misleading; only the numeric token is dropped. Do **not** rely on the comment.)

---

## File Structure

**Modify:**
- `Sources/GoldengoCore/ExpenseSource.swift` — add `.automatic` case.
- `Sources/GoldengoData/IngestionStore.swift` — extract `logEntry`; add `logAutomatic`; extract `merge`; add `reconcileImportedAgainstAutomatic`; wire reconciliation into `ingest`.
- `Sources/GoldengoIntents/ExpenseLogging.swift` — add `automatic: Bool = false` routing to `logAutomatic`/`logManual`.
- `AppProject/Goldengo/QuickLogShortcut.swift` — `LogPaymentIntent` passes `automatic: true` (app-target edit; no new file → no regen).
- `Sources/GoldengoFeatures/Import/ImportModel.swift` — add `importFile(url:)` (DRY the file-open path).
- `Sources/GoldengoFeatures/Import/ImportView.swift` — fileImporter calls `importFile`; add `autoImport:` param that imports on appear.
- `Sources/GoldengoFeatures/RootView.swift` — add `ImportFile`, file-URL routing in `.onOpenURL`, `.sheet(item:)`, and a testable `isStatementFile(_:)`.
- `AppProject/Goldengo/Info.plist` — add `CFBundleDocumentTypes` + `LSSupportsOpeningDocumentsInPlace` (app-target edit; not managed by `project.rb` → no regen).

**Create (tests):**
- `Tests/GoldengoCoreTests/ExpenseSourceTests.swift`
- `Tests/GoldengoDataTests/LogAutomaticTests.swift`
- `Tests/GoldengoDataTests/ReconcileImportTests.swift`
- `Tests/GoldengoIntentsTests/ExpenseLoggingAutomaticTests.swift`
- `Tests/GoldengoFeaturesTests/ImportFileRoutingTests.swift`

---

## Task 1: Add `ExpenseSource.automatic`

**Files:**
- Modify: `Sources/GoldengoCore/ExpenseSource.swift`
- Test: `Tests/GoldengoCoreTests/ExpenseSourceTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/GoldengoCoreTests/ExpenseSourceTests.swift`:

```swift
import XCTest
@testable import GoldengoCore

final class ExpenseSourceTests: XCTestCase {
    func test_automatic_caseExistsWithStableRawValue() {
        XCTAssertEqual(ExpenseSource.automatic.rawValue, "automatic")
        XCTAssertTrue(ExpenseSource.allCases.contains(.automatic))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ExpenseSourceTests`
Expected: FAIL — `type 'ExpenseSource' has no member 'automatic'`.

- [ ] **Step 3: Add the case**

In `Sources/GoldengoCore/ExpenseSource.swift`:

```swift
public enum ExpenseSource: String, Sendable, Codable, CaseIterable {
    case manual
    case imported
    case crypto
    case automatic   // captured hands-free (e.g. the Apple Pay Transaction automation)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ExpenseSourceTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoCore/ExpenseSource.swift Tests/GoldengoCoreTests/ExpenseSourceTests.swift
git commit -m "feat(gol-79): add ExpenseSource.automatic for hands-free captures"
```

---

## Task 2: Add `IngestionStore.logAutomatic` (extract shared `logEntry`)

**Files:**
- Modify: `Sources/GoldengoData/IngestionStore.swift`
- Test: `Tests/GoldengoDataTests/LogAutomaticTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/GoldengoDataTests/LogAutomaticTests.swift`:

```swift
import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class LogAutomaticTests: XCTestCase {
    func test_logAutomatic_createsAutomaticSourcedExpense_withMerchant() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        _ = try await store.logAutomatic(amount: 1500, currency: .all, merchant: "Spar", categoryName: nil)
        let recents = try await store.recentExpenses(limit: 10)
        XCTAssertEqual(recents.count, 1)
        XCTAssertEqual(recents.first?.source, .automatic)
        XCTAssertEqual(recents.first?.merchantName, "Spar")
        XCTAssertEqual(recents.first?.amount, 1500)
        // Unknown merchant with no category → the "Other" fallback (never silently uncategorized).
        XCTAssertEqual(recents.first?.categoryName, "Other")
    }

    func test_logAutomatic_twoIdenticalCalls_neverCollapse() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        _ = try await store.logAutomatic(amount: 300, currency: .all, merchant: "Coffee", categoryName: nil)
        _ = try await store.logAutomatic(amount: 300, currency: .all, merchant: "Coffee", categoryName: nil)
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 2, "Each tap is a distinct purchase — unique keys, never merged.")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LogAutomaticTests`
Expected: FAIL — `value of type 'IngestionStore' has no member 'logAutomatic'`.

- [ ] **Step 3: Refactor `logManual` to a shared `logEntry`, add `logAutomatic`**

In `Sources/GoldengoData/IngestionStore.swift`, replace the existing `logManual(...)` method with:

```swift
    /// Logs a user-entered expense. Always a distinct insert (unique key) so identical
    /// same-day purchases are never collapsed. Returns the new record's dedupeKey.
    @discardableResult
    public func logManual(amount: Decimal, currency: CurrencyCode,
                          merchant: String?, note: String? = nil, categoryName: String?) throws -> String {
        try logEntry(amount: amount, currency: currency, merchant: merchant, note: note,
                     categoryName: categoryName, source: .manual, keyPrefix: "manual")
    }

    /// Logs a hands-free auto-captured payment (e.g. the Apple Pay Transaction automation).
    /// Same behavior as `logManual` but tagged `.automatic` so import reconciliation can safely
    /// merge a later statement row into it, and the UI can label it "auto-logged". Distinct insert.
    @discardableResult
    public func logAutomatic(amount: Decimal, currency: CurrencyCode,
                             merchant: String?, categoryName: String? = nil) throws -> String {
        try logEntry(amount: amount, currency: currency, merchant: merchant, note: nil,
                     categoryName: categoryName, source: .automatic, keyPrefix: "auto")
    }

    @discardableResult
    private func logEntry(amount: Decimal, currency: CurrencyCode, merchant: String?, note: String?,
                          categoryName: String?, source: ExpenseSource, keyPrefix: String) throws -> String {
        let key = "\(keyPrefix):\(UUID().uuidString)"
        let cleanNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rec = ExpenseRecord(amount: amount, currencyCode: currency.rawValue, date: .now,
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

- [ ] **Step 4: Run tests to verify they pass (incl. no regression)**

Run: `swift test --filter LogAutomaticTests` → Expected: PASS.
Run: `swift test --filter LogManualTests` → Expected: PASS (behavior preserved).

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoData/IngestionStore.swift Tests/GoldengoDataTests/LogAutomaticTests.swift
git commit -m "feat(gol-79): IngestionStore.logAutomatic for .automatic captures (shared logEntry)"
```

---

## Task 3: Route the Apple Pay path to `.automatic`

**Files:**
- Modify: `Sources/GoldengoIntents/ExpenseLogging.swift`
- Modify: `AppProject/Goldengo/QuickLogShortcut.swift:95-96` (app-target edit; no new file → no `project.rb` regen)
- Test: `Tests/GoldengoIntentsTests/ExpenseLoggingAutomaticTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/GoldengoIntentsTests/ExpenseLoggingAutomaticTests.swift`:

```swift
import XCTest
import GoldengoCore
import GoldengoData
@testable import GoldengoIntents

final class ExpenseLoggingAutomaticTests: XCTestCase {
    func test_log_automaticTrue_recordsAutomaticSource() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        _ = try await ExpenseLogging.log(amount: 1500, currencyCode: "ALL", merchant: "Spar",
                                         categoryName: nil, store: store, automatic: true)
        let recents = try await store.recentExpenses(limit: 5)
        XCTAssertEqual(recents.first?.source, .automatic)
    }

    func test_log_defaultStaysManual() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        _ = try await ExpenseLogging.log(amount: 1500, currencyCode: "ALL", merchant: "Spar",
                                         categoryName: nil, store: store)
        let recents = try await store.recentExpenses(limit: 5)
        XCTAssertEqual(recents.first?.source, .manual)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ExpenseLoggingAutomaticTests`
Expected: FAIL — extra argument `automatic` in call (and source assertion would be `.manual`).

- [ ] **Step 3: Add the `automatic` parameter**

Replace the body of `Sources/GoldengoIntents/ExpenseLogging.swift` with:

```swift
import Foundation
import GoldengoCore
import GoldengoData

public enum ExpenseLogging {
    /// Shared logging path for every capture surface. `automatic` tags hands-free captures
    /// (e.g. the Apple Pay Transaction automation) so import reconciliation can dedupe them.
    /// Returns a short confirmation string.
    public static func log(amount: Decimal, currencyCode: String, merchant: String?,
                           categoryName: String?, store: IngestionStore,
                           automatic: Bool = false) async throws -> String {
        let currency = CurrencyCode(currencyCode)
        if automatic {
            try await store.logAutomatic(amount: amount, currency: currency,
                                         merchant: merchant, categoryName: categoryName)
        } else {
            try await store.logManual(amount: amount, currency: currency,
                                      merchant: merchant, categoryName: categoryName)
        }
        return "Logged \(Money(amount: amount, currency: currency).formatted())"
    }
}
```

- [ ] **Step 4: Point `LogPaymentIntent` at it**

In `AppProject/Goldengo/QuickLogShortcut.swift`, in `LogPaymentIntent.perform()`, change the `ExpenseLogging.log(...)` call to pass `automatic: true`:

```swift
        let summary = try await ExpenseLogging.log(amount: amt, currencyCode: preferred.rawValue,
                                                   merchant: clean, categoryName: nil, store: store,
                                                   automatic: true)
```

(Leave `LogExpenseIntent` unchanged — the Siri/Back-Tap quick-log is a genuine manual entry.)

- [ ] **Step 5: Run tests + build the app target**

Run: `swift test --filter ExpenseLoggingAutomaticTests` → Expected: PASS.
Run (verify the app target still compiles after the QuickLogShortcut edit):
`xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath AppProject/.build build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add Sources/GoldengoIntents/ExpenseLogging.swift AppProject/Goldengo/QuickLogShortcut.swift Tests/GoldengoIntentsTests/ExpenseLoggingAutomaticTests.swift
git commit -m "feat(gol-79): Apple Pay auto-log records .automatic source (GOL-77 path)"
```

---

## Task 4: Cross-source reconciliation in `ingest`

**Files:**
- Modify: `Sources/GoldengoData/IngestionStore.swift` (extract `merge`; add `reconcileImportedAgainstAutomatic`; wire into `ingest`)
- Test: `Tests/GoldengoDataTests/ReconcileImportTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/GoldengoDataTests/ReconcileImportTests.swift`:

```swift
import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class ReconcileImportTests: XCTestCase {
    /// An imported statement row, posting `daysAfterNow` days from now.
    private func importedRow(amount: Decimal, merchant: String, currency: CurrencyCode = .all,
                             daysAfterNow: Int) -> NormalizedTransaction {
        NormalizedTransaction(externalID: nil, amount: amount, currency: currency,
                              date: Date().addingTimeInterval(Double(daysAfterNow) * 86_400),
                              rawMerchant: merchant, kind: .expense, accountRef: nil)
    }

    func test_highConfidence_importMergesIntoAutomatic_noDoubleCount() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        _ = try await store.logAutomatic(amount: 1500, currency: .all, merchant: "Spar")   // swipe ~ now
        // Statement row: "SPAR 4471" → numeric token dropped → normalizes to "SPAR" → matches "Spar".
        let outcome = try await store.ingest(importedRow(amount: 1500, merchant: "SPAR 4471", daysAfterNow: 2),
                                             source: .imported)
        XCTAssertEqual(outcome, .merged)
        XCTAssertEqual(try await store.expenseCount(), 1, "Same purchase from two paths must collapse to one.")
    }

    func test_locationWordDifference_staysDuplicate() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        _ = try await store.logAutomatic(amount: 1500, currency: .all, merchant: "Spar")
        // "SPAR TIRANA" keeps the location word → "SPAR TIRANA" != "SPAR" → not high-confidence.
        let outcome = try await store.ingest(importedRow(amount: 1500, merchant: "SPAR TIRANA", daysAfterNow: 1),
                                             source: .imported)
        XCTAssertEqual(outcome, .inserted)
        XCTAssertEqual(try await store.expenseCount(), 2, "A deletable duplicate beats a wrong merge.")
    }

    func test_recurringSameAmount_neverHidesAnExpense() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        _ = try await store.logAutomatic(amount: 300, currency: .all, merchant: "Coffee")
        _ = try await store.logAutomatic(amount: 300, currency: .all, merchant: "Coffee")
        // One coffee on the statement merges into AT MOST one automatic entry; the other survives.
        _ = try await store.ingest(importedRow(amount: 300, merchant: "Coffee", daysAfterNow: 1), source: .imported)
        XCTAssertEqual(try await store.expenseCount(), 2,
                       "Two distinct taps + one statement row = two records; never collapse a real expense away.")
    }

    func test_neverMergesIntoManual() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        _ = try await store.logManual(amount: 1500, currency: .all, merchant: "Spar", categoryName: nil)
        let outcome = try await store.ingest(importedRow(amount: 1500, merchant: "SPAR 4471", daysAfterNow: 1),
                                             source: .imported)
        XCTAssertEqual(outcome, .inserted)
        XCTAssertEqual(try await store.expenseCount(), 2, "Hand-typed entries are user truth; never reconciled away.")
    }

    func test_currencyMismatch_doesNotMerge() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        _ = try await store.logAutomatic(amount: 10, currency: .eur, merchant: "Spar")
        let outcome = try await store.ingest(importedRow(amount: 10, merchant: "SPAR 4471", currency: .all, daysAfterNow: 1),
                                             source: .imported)
        XCTAssertEqual(outcome, .inserted)
        XCTAssertEqual(try await store.expenseCount(), 2, "Same number, different currency = different money.")
    }

    func test_outsideDateWindow_doesNotMerge() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        _ = try await store.logAutomatic(amount: 1500, currency: .all, merchant: "Spar")   // swipe ~ now
        // Posting 6 days after swipe (> swipe+4) → implausible same purchase → kept duplicate.
        let outcome = try await store.ingest(importedRow(amount: 1500, merchant: "SPAR 4471", daysAfterNow: 6),
                                             source: .imported)
        XCTAssertEqual(outcome, .inserted)
        XCTAssertEqual(try await store.expenseCount(), 2)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ReconcileImportTests`
Expected: FAIL — the high-confidence/recurring cases return `.inserted` and counts are off, because no reconciliation exists yet.

- [ ] **Step 3: Extract `merge`, add the reconciler, wire into `ingest`**

In `Sources/GoldengoData/IngestionStore.swift`, replace the existing `ingest(_:source:)` method with the version below (it extracts the merge block into `merge(_:with:source:)`, then adds the cross-source step):

```swift
    public func ingest(_ tx: NormalizedTransaction, source: ExpenseSource = .imported) throws -> IngestOutcome {
        let key = tx.dedupeKey
        var fd = FetchDescriptor<ExpenseRecord>(predicate: #Predicate { $0.dedupeKey == key && $0.isArchived == false })
        fd.fetchLimit = 1
        if let existing = try modelContext.fetch(fd).first {
            try merge(existing, with: tx, source: source)
            return .merged
        }
        // Cross-source reconciliation: an imported statement row that is very likely the same
        // purchase as a recent hands-free (.automatic) capture merges into it rather than
        // double-counting. Conservative on purpose — see reconcileImportedAgainstAutomatic.
        if source == .imported, let auto = try reconcileImportedAgainstAutomatic(tx) {
            try merge(auto, with: tx, source: source)
            return .merged
        }
        let rec = ExpenseRecord(amount: tx.amount, currencyCode: tx.currency.rawValue,
                                date: tx.date, merchantName: tx.rawMerchant,
                                kind: tx.kind, source: source, dedupeKey: key)
        rec.category = try defaultCategory(forMerchant: tx.rawMerchant)
        modelContext.insert(rec)
        try linkToConfirmedSubscription(rec)
        try modelContext.save()
        return .inserted
    }

    /// Merge an incoming transaction into an existing record: refresh provenance/merchant but keep
    /// the first-seen amount/date/currency — an import confirming an earlier entry must not silently
    /// rewrite it. Used by both the exact-dedupeKey path and cross-source reconciliation.
    private func merge(_ existing: ExpenseRecord, with tx: NormalizedTransaction, source: ExpenseSource) throws {
        existing.sourceRaw = source.rawValue
        existing.merchantName = tx.rawMerchant ?? existing.merchantName
        existing.updatedAt = .now
        if existing.category == nil {
            existing.category = try defaultCategory(forMerchant: tx.rawMerchant)
        }
        try linkToConfirmedSubscription(existing)
        try modelContext.save()
    }

    /// Find a recent `.automatic` capture that is high-confidence the SAME purchase as an imported
    /// row, or nil. High-confidence = same currency + exact amount + same kind + exact normalized
    /// merchant (`MerchantNormalizer`, which drops numeric terminal tokens) + the swipe day within
    /// `[postingDay - 4, postingDay]` (posting follows the swipe). Returns the earliest match so a
    /// second imported row in the same statement reconciles against a different capture. Bias:
    /// anything short of this stays a separate, deletable record — never hide a real expense.
    private func reconcileImportedAgainstAutomatic(_ tx: NormalizedTransaction) throws -> ExpenseRecord? {
        let merchantNorm = MerchantNormalizer.normalize(tx.rawMerchant)
        guard !merchantNorm.isEmpty else { return nil }
        let cal = Calendar.current
        let postingDay = cal.startOfDay(for: tx.date)
        guard let lower = cal.date(byAdding: .day, value: -4, to: postingDay),
              let upper = cal.date(byAdding: .day, value: 1, to: postingDay) else { return nil }
        let amt = tx.amount
        let cur = tx.currency.rawValue
        let kindRaw = tx.kind.rawValue
        let autoRaw = ExpenseSource.automatic.rawValue
        let fd = FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate {
                $0.isArchived == false && $0.sourceRaw == autoRaw && $0.kindRaw == kindRaw
                    && $0.currencyCode == cur && $0.amount == amt
                    && $0.date >= lower && $0.date < upper
            },
            sortBy: [SortDescriptor(\.date, order: .forward)])
        let candidates = try modelContext.fetch(fd)
        return candidates.first { MerchantNormalizer.normalize($0.merchantName) == merchantNorm }
    }
```

- [ ] **Step 4: Run tests to verify they pass (incl. full data suite for no regression)**

Run: `swift test --filter ReconcileImportTests` → Expected: PASS (all six).
Run: `swift test --filter GoldengoDataTests` → Expected: PASS (incl. `IngestionStoreTests`, `ImportStatementTests` — exact-key dedup unaffected).

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoData/IngestionStore.swift Tests/GoldengoDataTests/ReconcileImportTests.swift
git commit -m "feat(gol-79): reconcile imported rows into recent .automatic captures (conservative dedup)"
```

---

## Task 5: `ImportModel.importFile(url:)` (DRY the file-open path)

**Files:**
- Modify: `Sources/GoldengoFeatures/Import/ImportModel.swift`
- Modify: `Sources/GoldengoFeatures/Import/ImportView.swift:36-61`
- Test: `Tests/GoldengoFeaturesTests/ImportFileRoutingTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/GoldengoFeaturesTests/ImportFileRoutingTests.swift`:

```swift
import XCTest
import GoldengoCore
import GoldengoData
@testable import GoldengoFeatures

@MainActor
final class ImportFileRoutingTests: XCTestCase {
    func test_importFile_csv_importsRows() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let model = ImportModel(store: store)
        // Write a small CSV to a temp file and import it through the file path.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gol79-\(UUID().uuidString).csv")
        try SampleStatement.csv.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        await model.importFile(url: url)

        XCTAssertTrue(model.resultText.hasPrefix("Imported "), "Got: \(model.resultText)")
        XCTAssertGreaterThan(try await store.expenseCount(), 0)
    }

    func test_importFile_tooLarge_reportsError() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let model = ImportModel(store: store)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gol79-big-\(UUID().uuidString).csv")
        try Data(count: 10_000_001).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await model.importFile(url: url)

        XCTAssertEqual(model.resultText, "File too large (max 10 MB).")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ImportFileRoutingTests`
Expected: FAIL — `value of type 'ImportModel' has no member 'importFile'`.

- [ ] **Step 3: Add `importFile(url:)` to `ImportModel`**

In `Sources/GoldengoFeatures/Import/ImportModel.swift`, add this method to `ImportModel`:

```swift
    /// Single entry point for importing a file URL — used by both the in-app file picker and the
    /// "Share to Goldengo" / "Open in" path. Handles security-scoped access, the size guard, and
    /// PDF-vs-text selection, then delegates to the existing CSV/PDF importers.
    public func importFile(url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 10_000_000 {
            resultText = "File too large (max 10 MB)."
            return
        }
        let name = url.lastPathComponent
        if url.pathExtension.lowercased() == "pdf" {
            await importPDF(url: url, fileName: name)
        } else if let text = try? String(contentsOf: url, encoding: .utf8) {
            await importCSV(text: text, fileName: name)
        } else if let text = try? String(contentsOf: url, encoding: .isoLatin1) {
            await importCSV(text: text, fileName: name)
        } else {
            resultText = "Couldn't read the file (unsupported encoding)."
        }
    }
```

- [ ] **Step 4: Route the picker through it**

In `Sources/GoldengoFeatures/Import/ImportView.swift`, replace the `.fileImporter` completion closure (currently lines ~39-60) with:

```swift
            ) { result in
                guard case let .success(url) = result else { return }
                Task { await model.importFile(url: url) }
            }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter ImportFileRoutingTests` → Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/GoldengoFeatures/Import/ImportModel.swift Sources/GoldengoFeatures/Import/ImportView.swift Tests/GoldengoFeaturesTests/ImportFileRoutingTests.swift
git commit -m "refactor(gol-79): ImportModel.importFile(url:) single file-open path (DRY)"
```

---

## Task 6: RootView file-URL routing + ImportView auto-import

**Files:**
- Modify: `Sources/GoldengoFeatures/RootView.swift`
- Modify: `Sources/GoldengoFeatures/Import/ImportView.swift`
- Test: `Tests/GoldengoFeaturesTests/ImportFileRoutingTests.swift` (extend)

- [ ] **Step 1: Write the failing tests**

Append to `Tests/GoldengoFeaturesTests/ImportFileRoutingTests.swift` (inside the class):

```swift
    func test_fileURL_isRecognizedAsStatementFile() {
        let fileURL = URL(fileURLWithPath: "/tmp/statement.pdf")
        XCTAssertTrue(RootView.isStatementFile(fileURL))
        XCTAssertNil(RootView.tab(forDeepLink: fileURL), "A file URL must not be mis-routed as a deep link.")
    }

    func test_deepLinkURL_isNotAStatementFile() {
        let deepLink = URL(string: "goldengo://import")!
        XCTAssertFalse(RootView.isStatementFile(deepLink))
        XCTAssertEqual(RootView.tab(forDeepLink: deepLink), 3)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ImportFileRoutingTests`
Expected: FAIL — `type 'RootView' has no member 'isStatementFile'`.

- [ ] **Step 3: Add the classifier + file routing to `RootView`**

In `Sources/GoldengoFeatures/RootView.swift`:

(a) Add this `Identifiable` wrapper above `public struct RootView` (file scope):

```swift
/// A statement file handed to the app via the Share Sheet / "Open in" → presented as the import
/// sheet. Identifiable so `.sheet(item:)` re-presents for each distinct shared file.
public struct ImportFile: Identifiable, Hashable {
    public let id: String
    public let url: URL
    public init(url: URL) { self.url = url; self.id = url.absoluteString }
}
```

(b) Add state next to the other `@State` properties:

```swift
    @State private var importFile: ImportFile?
```

(c) Add the testable classifier next to `tab(forDeepLink:)`:

```swift
    /// A shared statement arrives as a `file://` URL (vs a `goldengo://` deep link). Extracted so
    /// the routing branch is unit-testable and can't silently regress.
    public nonisolated static func isStatementFile(_ url: URL) -> Bool { url.isFileURL }
```

(d) Replace the existing `.onOpenURL` modifier with:

```swift
        .onOpenURL { url in
            if Self.isStatementFile(url) {
                importFile = ImportFile(url: url)            // Share-to-Goldengo: import the file
            } else if let tab = Self.tab(forDeepLink: url) {
                route(toTab: tab)
            }
        }
```

(e) Add a sheet for the shared file (next to the existing `.sheet(isPresented: $showImport)`):

```swift
        .sheet(item: $importFile, onDismiss: {
            Task { await recentModel.load() }
            Task { await subsModel.load() }
        }) { file in
            ImportView(model: ImportModel(store: store), autoImport: file.url)
        }
```

- [ ] **Step 4: Add `autoImport` to `ImportView`**

In `Sources/GoldengoFeatures/Import/ImportView.swift`, update the stored properties + init and add the auto-import `.task`:

```swift
public struct ImportView: View {
    @State private var model: ImportModel
    @State private var showingPicker = false
    @State private var didAutoImport = false
    private let autoImport: URL?
    @Environment(\.dismiss) private var dismiss
    public init(model: ImportModel, autoImport: URL? = nil) {
        _model = State(initialValue: model)
        self.autoImport = autoImport
    }
```

Then add this modifier to the `NavigationStack { ... }` (e.g. right after `.navigationTitle("Import")`):

```swift
            .task {
                guard let autoImport, !didAutoImport else { return }
                didAutoImport = true
                await model.importFile(url: autoImport)
            }
```

- [ ] **Step 5: Run tests + build the app target**

Run: `swift test --filter ImportFileRoutingTests` → Expected: PASS.
Run: `swift build` → Expected: build succeeds (all SPM modules).
Run: `xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath AppProject/.build build` → Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add Sources/GoldengoFeatures/RootView.swift Sources/GoldengoFeatures/Import/ImportView.swift Tests/GoldengoFeaturesTests/ImportFileRoutingTests.swift
git commit -m "feat(gol-79): route shared statement files through RootView into the import sheet"
```

---

## Task 7: Register Goldengo as a PDF/CSV handler (Info.plist)

**Files:**
- Modify: `AppProject/Goldengo/Info.plist` (app-target edit; `project.rb` does not manage this file → no regeneration, signing intact)

- [ ] **Step 1: Add document types**

In `AppProject/Goldengo/Info.plist`, add these two keys inside the top-level `<dict>` (e.g. right after the `CFBundleURLTypes` array):

```xml
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Bank statement</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>com.adobe.pdf</string>
        <string>public.comma-separated-values-text</string>
        <string>public.plain-text</string>
      </array>
    </dict>
  </array>
  <key>LSSupportsOpeningDocumentsInPlace</key><true/>
```

- [ ] **Step 2: Verify the plist is valid and the app builds**

Run: `plutil -lint AppProject/Goldengo/Info.plist`
Expected: `AppProject/Goldengo/Info.plist: OK`.
Run: `xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath AppProject/.build build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add AppProject/Goldengo/Info.plist
git commit -m "feat(gol-79): register Goldengo as PDF/CSV handler for Share-to-Goldengo import"
```

---

## Task 8: Full suite, device verification, ticket update

**Files:** none (verification + ticket).

- [ ] **Step 1: Run the full test suite**

Run: `swift test`
Expected: all ~200 tests PASS (the ~195 existing + the new ExpenseSource/LogAutomatic/Reconcile/ExpenseLogging/ImportFile tests). If anything fails, fix before proceeding — do not claim done with skips.

- [ ] **Step 2: Device build + install**

```bash
xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'generic/platform=iOS' -allowProvisioningUpdates -derivedDataPath AppProject/.build-device build
xcrun devicectl device install app --device 7B8F5F4F-B6B9-5A41-926D-31C29770064E AppProject/.build-device/Build/Products/Debug-iphoneos/Goldengo.app
```

Expected: BUILD SUCCEEDED + app installed. (If signing fails with "No profiles", the project was regenerated — recover by opening Xcode and letting Automatic signing re-mint profiles for both targets. This plan does **not** run `project.rb`.)

- [ ] **Step 3: Manual device verification (per spec "Runtime verification")**

1. Export/download a statement (CSV or PDF; ideally a real Raiffeisen Albania statement) → from Files or the bank app tap **Share** → confirm **Goldengo** appears → tap it → the Import sheet opens and shows "Imported X, skipped Y".
2. Wire/confirm the GOL-77 Apple Pay automation, make an in-store Apple Pay tap (e.g. 1500 ALL at a merchant), then import a statement that includes that purchase (same amount, merchant differing only by a terminal number, within 4 days) → confirm it appears as **one** entry, not two.
3. Hand-type an expense, then import a statement row matching it → confirm **two** entries (manual untouched).

- [ ] **Step 4: Set the ticket to To Verify**

Use the youtrack MCP: set GOL-79 State → "To Verify" and add a comment summarizing what shipped (Share-to-Goldengo import, `.automatic` source, conservative reconciliation), the test counts, and the device-verification checklist above for the user to confirm.

- [ ] **Step 5: Finish the branch**

Follow the project flow: second-Opus review over the diff → ff-merge to `main` → push.

---

## Self-Review

**Spec coverage:**
- Unit A (Share-to-Goldengo) → Tasks 5, 6, 7. ✓
- Unit B (`.automatic` + reconciliation) → Tasks 1, 2, 3, 4. ✓
- Dedup-across-three-sources table → Task 4 tests (import↔automatic merge; import↔manual kept; recurring automatic↔automatic preserved; import↔import via existing exact-key path, regression-checked). ✓
- "Never hide an expense" principle → `test_recurringSameAmount_neverHidesAnExpense`, `test_locationWordDifference_staysDuplicate`, `test_outsideDateWindow_doesNotMerge`. ✓
- Backend = none → no networking introduced anywhere. ✓
- Edge cases (currency exact, merchant non-empty, one-to-one via source-flip, bounded fetch) → Task 4 implementation + tests. ✓
- No-new-target / no-`project.rb` constraint → only `Info.plist` (Task 7) and `QuickLogShortcut.swift` (Task 3) are app-target edits, both edits to existing files. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code; every run step shows the command + expected result. ✓

**Type consistency:** `logAutomatic`/`logManual`/`logEntry` signatures match across Tasks 2–4; `ExpenseLogging.log(..., automatic:)` matches its caller in Task 3; `ImportModel.importFile(url:)` matches its callers in Tasks 5–6; `ImportView(model:autoImport:)` matches its call in Task 6; `RootView.isStatementFile(_:)`/`ImportFile` match their tests. ✓
