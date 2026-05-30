# Goldengo Plan 2 — Persistence & Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the data layer: CloudKit-safe SwiftData models, an `@ModelActor` ingestion store that dedupes/merges and auto-categorizes, and the connector protocol — so every spending source (manual, import, crypto) funnels through one verified pipeline.

**Architecture:** A `GoldengoData` package owns the SwiftData `@Model`s and the `IngestionStore` actor; a `GoldengoConnectors` package owns the `ExpenseConnector` protocol. Both depend only on `GoldengoCore`. Persistence runs entirely inside the `@ModelActor` (Swift 6 rule: only `Sendable` values cross actor boundaries — connectors emit `NormalizedTransaction`, the store returns `IngestOutcome`/`ExpenseSnapshot`). Dedup is app-code fetch-before-insert keyed on `NormalizedTransaction.dedupeKey` (CloudKit forbids `@Attribute(.unique)`).

**Tech Stack:** Swift 6, SwiftData (in-memory `ModelContainer` for tests — runs headlessly via `swift test` on macOS 14+), XCTest.

**Scope note:** Only the models the pipeline needs now — `ExpenseRecord`, `CategoryRecord`, `AccountRecord`, `MerchantRecord`. `Subscription`/`ImportBatch`/`ExchangeRate` are added by their own feature plans (YAGNI). All models follow the CloudKit-sync rules from spec §6 (optional relationships, defaulted non-optionals, no `.unique`).

---

### Task 1: Add `GoldengoData` + `GoldengoConnectors` targets

**Files:**
- Modify: `Package.swift`
- Create: `Sources/GoldengoData/GoldengoData.swift`
- Create: `Sources/GoldengoConnectors/GoldengoConnectors.swift`
- Test: `Tests/GoldengoDataTests/SmokeTests.swift`
- Test: `Tests/GoldengoConnectorsTests/SmokeTests.swift`

- [ ] **Step 1: Extend the manifest**

Replace the `products` and `targets` in `Package.swift` with:

```swift
    products: [
        .library(name: "GoldengoCore", targets: ["GoldengoCore"]),
        .library(name: "GoldengoData", targets: ["GoldengoData"]),
        .library(name: "GoldengoConnectors", targets: ["GoldengoConnectors"]),
    ],
    targets: [
        .target(name: "GoldengoCore"),
        .testTarget(name: "GoldengoCoreTests", dependencies: ["GoldengoCore"]),
        .target(name: "GoldengoConnectors", dependencies: ["GoldengoCore"]),
        .testTarget(name: "GoldengoConnectorsTests", dependencies: ["GoldengoConnectors"]),
        .target(name: "GoldengoData", dependencies: ["GoldengoCore"]),
        .testTarget(name: "GoldengoDataTests", dependencies: ["GoldengoData"]),
    ]
```

- [ ] **Step 2: Add placeholder sources**

`Sources/GoldengoData/GoldengoData.swift`:
```swift
public enum GoldengoData {}
```
`Sources/GoldengoConnectors/GoldengoConnectors.swift`:
```swift
public enum GoldengoConnectors {}
```

- [ ] **Step 3: Add smoke tests**

`Tests/GoldengoDataTests/SmokeTests.swift`:
```swift
import XCTest
@testable import GoldengoData
final class DataSmokeTests: XCTestCase {
    func test_moduleLoads() { _ = GoldengoData.self }
}
```
`Tests/GoldengoConnectorsTests/SmokeTests.swift`:
```swift
import XCTest
@testable import GoldengoConnectors
final class ConnectorsSmokeTests: XCTestCase {
    func test_moduleLoads() { _ = GoldengoConnectors.self }
}
```

- [ ] **Step 4: Build & test**

Run: `swift test`
Expected: PASS (existing 12 + 2 new smoke tests). If SwiftData import later requires a higher platform, the manifest already targets iOS 17 / macOS 14.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/GoldengoData Sources/GoldengoConnectors Tests/GoldengoDataTests Tests/GoldengoConnectorsTests
git commit -m "feat: add GoldengoData and GoldengoConnectors package targets"
```

---

### Task 2: CloudKit-safe SwiftData models

**Files:**
- Create: `Sources/GoldengoData/Models/ExpenseRecord.swift`
- Create: `Sources/GoldengoData/Models/CategoryRecord.swift`
- Create: `Sources/GoldengoData/Models/AccountRecord.swift`
- Create: `Sources/GoldengoData/Models/MerchantRecord.swift`
- Create: `Sources/GoldengoData/ModelContainer+Goldengo.swift`
- Test: `Tests/GoldengoDataTests/ModelContainerTests.swift`

CloudKit rules (spec §6): every stored property has a default; every relationship is optional; no `@Attribute(.unique)`. Enums are stored as raw `String` with typed accessors from `GoldengoCore`.

- [ ] **Step 1: Write the failing test**

`Tests/GoldengoDataTests/ModelContainerTests.swift`:
```swift
import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class ModelContainerTests: XCTestCase {
    func test_inMemoryContainer_buildsAndPersistsExpense() throws {
        let container = try ModelContainer.goldengoInMemory()
        let ctx = ModelContext(container)
        let e = ExpenseRecord(amount: 1500, currencyCode: "ALL", date: .now,
                              kind: .expense, source: .manual, dedupeKey: "cmp:x")
        ctx.insert(e)
        try ctx.save()
        let all = try ctx.fetch(FetchDescriptor<ExpenseRecord>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.kind, .expense)
        XCTAssertEqual(all.first?.money, Money(amount: 1500, currency: .all))
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter ModelContainerTests`
Expected: FAIL — `ExpenseRecord`/`ModelContainer.goldengoInMemory` not found.

- [ ] **Step 3: Implement `CategoryRecord`**

`Sources/GoldengoData/Models/CategoryRecord.swift`:
```swift
import Foundation
import SwiftData

@Model
public final class CategoryRecord {
    public var name: String = ""
    public var icon: String = "circle"
    public var colorHex: String = "#0A84FF"
    @Relationship(deleteRule: .nullify, inverse: \ExpenseRecord.category)
    public var expenses: [ExpenseRecord]? = []

    public init(name: String = "", icon: String = "circle", colorHex: String = "#0A84FF") {
        self.name = name; self.icon = icon; self.colorHex = colorHex
    }
}
```

- [ ] **Step 4: Implement `AccountRecord`**

`Sources/GoldengoData/Models/AccountRecord.swift`:
```swift
import Foundation
import SwiftData

@Model
public final class AccountRecord {
    public var name: String = "Cash"
    public var typeRaw: String = "cash"        // bankCard | cash | cryptoWallet | cryptoExchange
    public var currencyCode: String = "ALL"
    public var connectorID: String?

    public init(name: String = "Cash", typeRaw: String = "cash",
                currencyCode: String = "ALL", connectorID: String? = nil) {
        self.name = name; self.typeRaw = typeRaw
        self.currencyCode = currencyCode; self.connectorID = connectorID
    }
}
```

- [ ] **Step 5: Implement `MerchantRecord`**

`Sources/GoldengoData/Models/MerchantRecord.swift`:
```swift
import Foundation
import SwiftData

@Model
public final class MerchantRecord {
    public var displayName: String = ""
    public var normalizedName: String = ""
    public var useCount: Int = 0
    public var lastUsed: Date = Date.now
    public var defaultCategory: CategoryRecord?

    public init(displayName: String = "", normalizedName: String = "",
                useCount: Int = 0, lastUsed: Date = .now,
                defaultCategory: CategoryRecord? = nil) {
        self.displayName = displayName; self.normalizedName = normalizedName
        self.useCount = useCount; self.lastUsed = lastUsed
        self.defaultCategory = defaultCategory
    }
}
```

- [ ] **Step 6: Implement `ExpenseRecord`**

`Sources/GoldengoData/Models/ExpenseRecord.swift`:
```swift
import Foundation
import SwiftData
import GoldengoCore

@Model
public final class ExpenseRecord {
    public var amount: Decimal = 0
    public var currencyCode: String = "ALL"
    public var date: Date = Date.now
    public var merchantName: String?
    public var note: String?
    public var kindRaw: String = TransactionKind.expense.rawValue
    public var sourceRaw: String = ExpenseSource.manual.rawValue
    public var dedupeKey: String = ""
    public var isArchived: Bool = false          // soft-delete tombstone (CloudKit-friendly)
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    public var category: CategoryRecord?
    public var account: AccountRecord?

    public init(amount: Decimal = 0, currencyCode: String = "ALL", date: Date = .now,
                merchantName: String? = nil, note: String? = nil,
                kind: TransactionKind = .expense, source: ExpenseSource = .manual,
                dedupeKey: String = "", category: CategoryRecord? = nil,
                account: AccountRecord? = nil) {
        self.amount = amount; self.currencyCode = currencyCode; self.date = date
        self.merchantName = merchantName; self.note = note
        self.kindRaw = kind.rawValue; self.sourceRaw = source.rawValue
        self.dedupeKey = dedupeKey; self.category = category; self.account = account
    }

    public var kind: TransactionKind { TransactionKind(rawValue: kindRaw) ?? .expense }
    public var source: ExpenseSource { ExpenseSource(rawValue: sourceRaw) ?? .manual }
    public var money: Money { Money(amount: amount, currency: CurrencyCode(currencyCode)) }
}
```

- [ ] **Step 7: Implement the in-memory container factory**

`Sources/GoldengoData/ModelContainer+Goldengo.swift`:
```swift
import Foundation
import SwiftData

public extension ModelContainer {
    static let goldengoSchema = Schema([
        ExpenseRecord.self, CategoryRecord.self, AccountRecord.self, MerchantRecord.self,
    ])

    /// In-memory container for tests and previews (no CloudKit, no disk).
    static func goldengoInMemory() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: goldengoSchema, configurations: config)
    }
}
```

- [ ] **Step 8: Run the test**

Run: `swift test --filter ModelContainerTests`
Expected: PASS. If the SwiftData macro flags a non-optional relationship or a missing default, fix it to satisfy the CloudKit rules (optional relationship, defaulted attribute) — do not add `.unique`.

- [ ] **Step 9: Commit**

```bash
git add Sources/GoldengoData/Models Sources/GoldengoData/ModelContainer+Goldengo.swift Tests/GoldengoDataTests/ModelContainerTests.swift
git commit -m "feat: add CloudKit-safe SwiftData models (Expense/Category/Account/Merchant)"
```

---

### Task 3: `ExpenseConnector` protocol

**Files:**
- Create: `Sources/GoldengoConnectors/ExpenseConnector.swift`
- Test: `Tests/GoldengoConnectorsTests/ExpenseConnectorTests.swift`

- [ ] **Step 1: Write the failing test (a fake connector emitting Sendable transactions)**

`Tests/GoldengoConnectorsTests/ExpenseConnectorTests.swift`:
```swift
import XCTest
import GoldengoCore
@testable import GoldengoConnectors

private struct FakeConnector: ExpenseConnector {
    let id = "fake"
    let capabilities = ConnectorCapabilities(supportsBackfill: true, supportsRealtime: false, supportsBalances: false)
    func pull(since checkpoint: SyncCheckpoint?) async throws -> [NormalizedTransaction] {
        [NormalizedTransaction(externalID: "1", amount: 500, currency: .all,
                               date: .now, rawMerchant: "Spar", kind: .expense, accountRef: "cash")]
    }
}

final class ExpenseConnectorTests: XCTestCase {
    func test_connector_pullsNormalizedTransactions() async throws {
        let c = FakeConnector()
        let txns = try await c.pull(since: nil)
        XCTAssertEqual(txns.count, 1)
        XCTAssertEqual(txns.first?.dedupeKey, "ext:1")
        XCTAssertTrue(c.capabilities.supportsBackfill)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter ExpenseConnectorTests`
Expected: FAIL — `ExpenseConnector`/`ConnectorCapabilities`/`SyncCheckpoint` not found.

- [ ] **Step 3: Implement the protocol (minimal — grows when a real 2nd connector lands)**

`Sources/GoldengoConnectors/ExpenseConnector.swift`:
```swift
import Foundation
import GoldengoCore

public struct ConnectorCapabilities: Sendable, Equatable {
    public var supportsBackfill: Bool
    public var supportsRealtime: Bool
    public var supportsBalances: Bool
    public init(supportsBackfill: Bool, supportsRealtime: Bool, supportsBalances: Bool) {
        self.supportsBackfill = supportsBackfill
        self.supportsRealtime = supportsRealtime
        self.supportsBalances = supportsBalances
    }
}

public struct SyncCheckpoint: Sendable, Equatable {
    public var token: String
    public var date: Date
    public init(token: String, date: Date) { self.token = token; self.date = date }
}

public protocol ExpenseConnector: Sendable {
    var id: String { get }
    var capabilities: ConnectorCapabilities { get }
    func pull(since checkpoint: SyncCheckpoint?) async throws -> [NormalizedTransaction]
}
```

- [ ] **Step 4: Run the test**

Run: `swift test --filter ExpenseConnectorTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoConnectors/ExpenseConnector.swift Tests/GoldengoConnectorsTests/ExpenseConnectorTests.swift
git commit -m "feat: add ExpenseConnector protocol with capabilities and checkpoint"
```

---

### Task 4: `@ModelActor` ingestion store with dedupe/merge

**Files:**
- Create: `Sources/GoldengoData/IngestionStore.swift`
- Test: `Tests/GoldengoDataTests/IngestionStoreTests.swift`

The store is the ONLY place that touches `ModelContext`. It returns `Sendable` values (`IngestOutcome`, `ExpenseSnapshot`) so nothing `@Model` crosses the actor boundary (spec §7).

- [ ] **Step 1: Write the failing tests**

`Tests/GoldengoDataTests/IngestionStoreTests.swift`:
```swift
import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class IngestionStoreTests: XCTestCase {
    private func tx(ext: String?, amount: Decimal, merchant: String, source: ExpenseSource = .imported) -> NormalizedTransaction {
        NormalizedTransaction(externalID: ext, amount: amount, currency: .all,
                              date: Date(timeIntervalSince1970: 1_750_000_000),
                              rawMerchant: merchant, kind: .expense, accountRef: "cash")
    }

    func test_ingest_insertsNewExpense() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let outcome = try await store.ingest(tx(ext: "a1", amount: 500, merchant: "Spar"))
        XCTAssertEqual(outcome, .inserted)
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 1)
    }

    func test_ingest_sameDedupeKeyMerges_noDoubleCount() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        _ = try await store.ingest(tx(ext: "a1", amount: 500, merchant: "Spar"))
        let second = try await store.ingest(tx(ext: "a1", amount: 500, merchant: "Spar"))
        XCTAssertEqual(second, .merged)
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 1)
    }

    func test_ingest_manualThenImport_mergesAndUpgradesSource() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        // Manual entry with no externalID -> composite key
        let manual = NormalizedTransaction(externalID: nil, amount: 500, currency: .all,
            date: Date(timeIntervalSince1970: 1_750_000_000), rawMerchant: "Spar",
            kind: .expense, accountRef: "cash")
        _ = try await store.ingest(manual, source: .manual)
        // Imported row, same composite key
        let outcome = try await store.ingest(manual, source: .imported)
        XCTAssertEqual(outcome, .merged)
        XCTAssertEqual(try await store.expenseCount(), 1)
        let snap = try await store.snapshot(dedupeKey: manual.dedupeKey)
        XCTAssertEqual(snap?.source, .imported)   // import upgrades the record's provenance
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter IngestionStoreTests`
Expected: FAIL — `IngestionStore`, `IngestOutcome`, `snapshot`/`expenseCount` not found.

- [ ] **Step 3: Implement the store**

`Sources/GoldengoData/IngestionStore.swift`:
```swift
import Foundation
import SwiftData
import GoldengoCore

public enum IngestOutcome: String, Sendable, Equatable { case inserted, merged }

public struct ExpenseSnapshot: Sendable, Equatable {
    public var dedupeKey: String
    public var amount: Decimal
    public var currencyCode: String
    public var source: ExpenseSource
    public var categoryName: String?
}

@ModelActor
public actor IngestionStore {
    /// Insert a transaction, or merge into an existing record with the same dedupeKey.
    public func ingest(_ tx: NormalizedTransaction, source: ExpenseSource = .imported) throws -> IngestOutcome {
        let key = tx.dedupeKey
        var fd = FetchDescriptor<ExpenseRecord>(predicate: #Predicate { $0.dedupeKey == key && !$0.isArchived })
        fd.fetchLimit = 1
        if let existing = try modelContext.fetch(fd).first {
            // Merge: prefer the richer provenance and refresh mutable fields.
            existing.sourceRaw = source.rawValue
            existing.merchantName = tx.rawMerchant ?? existing.merchantName
            existing.updatedAt = .now
            try modelContext.save()
            return .merged
        }
        let rec = ExpenseRecord(amount: tx.amount, currencyCode: tx.currency.rawValue,
                                date: tx.date, merchantName: tx.rawMerchant,
                                kind: tx.kind, source: source, dedupeKey: key)
        modelContext.insert(rec)
        try modelContext.save()
        return .inserted
    }

    public func expenseCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<ExpenseRecord>(predicate: #Predicate { !$0.isArchived }))
    }

    public func snapshot(dedupeKey key: String) throws -> ExpenseSnapshot? {
        var fd = FetchDescriptor<ExpenseRecord>(predicate: #Predicate { $0.dedupeKey == key })
        fd.fetchLimit = 1
        guard let r = try modelContext.fetch(fd).first else { return nil }
        return ExpenseSnapshot(dedupeKey: r.dedupeKey, amount: r.amount,
                               currencyCode: r.currencyCode, source: r.source,
                               categoryName: r.category?.name)
    }
}
```
- [ ] **Step 4: Run the tests**

Run: `swift test --filter IngestionStoreTests`
Expected: PASS (3 tests). If `#Predicate` rejects `!$0.isArchived`, use `$0.isArchived == false`.

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoData/IngestionStore.swift Tests/GoldengoDataTests/IngestionStoreTests.swift
git commit -m "feat: add @ModelActor IngestionStore with dedupe/merge reconciliation"
```

---

### Task 5: Merchant normalization + auto-categorization

**Files:**
- Create: `Sources/GoldengoCore/MerchantNormalizer.swift`
- Modify: `Sources/GoldengoData/IngestionStore.swift`
- Test: `Tests/GoldengoCoreTests/MerchantNormalizerTests.swift`
- Test: `Tests/GoldengoDataTests/AutoCategorizeTests.swift`

- [ ] **Step 1: Write the failing normalizer test**

`Tests/GoldengoCoreTests/MerchantNormalizerTests.swift`:
```swift
import XCTest
@testable import GoldengoCore

final class MerchantNormalizerTests: XCTestCase {
    func test_normalize_uppercasesTrimsCollapsesAndStripsTrailingDigits() {
        XCTAssertEqual(MerchantNormalizer.normalize("  Spar   Tirana 4471 "), "SPAR TIRANA")
        XCTAssertEqual(MerchantNormalizer.normalize("spar"), "SPAR")
        XCTAssertEqual(MerchantNormalizer.normalize(nil), "")
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter MerchantNormalizerTests`
Expected: FAIL — `MerchantNormalizer` not found.

- [ ] **Step 3: Implement the normalizer**

`Sources/GoldengoCore/MerchantNormalizer.swift`:
```swift
import Foundation

public enum MerchantNormalizer {
    /// Uppercases, trims, collapses whitespace, and drops trailing numeric tokens
    /// (e.g. store/terminal numbers) so "Spar" and "SPAR TIRANA 4471" normalize closer.
    public static func normalize(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        let upper = raw.uppercased()
        let tokens = upper.split(whereSeparator: { $0 == " " || $0 == "\t" })
        let kept = tokens.filter { !$0.allSatisfy(\.isNumber) }
        return kept.joined(separator: " ")
    }
}
```

- [ ] **Step 4: Run it**

Run: `swift test --filter MerchantNormalizerTests`
Expected: PASS.

- [ ] **Step 5: Write the failing auto-categorize test**

`Tests/GoldengoDataTests/AutoCategorizeTests.swift`:
```swift
import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class AutoCategorizeTests: XCTestCase {
    func test_ingest_appliesMerchantDefaultCategory() async throws {
        let container = try ModelContainer.goldengoInMemory()
        // Seed a merchant->category memory
        let seed = ModelContext(container)
        let groceries = CategoryRecord(name: "Groceries", icon: "cart", colorHex: "#34C759")
        let merchant = MerchantRecord(displayName: "Spar", normalizedName: "SPAR",
                                      defaultCategory: groceries)
        seed.insert(groceries); seed.insert(merchant); try seed.save()

        let store = IngestionStore(modelContainer: container)
        let tx = NormalizedTransaction(externalID: "z1", amount: 800, currency: .all,
            date: .now, rawMerchant: "SPAR 12", kind: .expense, accountRef: "cash")
        _ = try await store.ingest(tx, source: .imported)

        let snap = try await store.snapshot(dedupeKey: "ext:z1")
        XCTAssertEqual(snap?.categoryName, "Groceries")
    }
}
```

- [ ] **Step 6: Run it to verify it fails**

Run: `swift test --filter AutoCategorizeTests`
Expected: FAIL — ingest does not yet attach a category.

- [ ] **Step 7: Extend `ingest` to auto-categorize via merchant memory**

In `Sources/GoldengoData/IngestionStore.swift`, before inserting a new record (in the non-merge branch), look up a merchant by normalized name and apply its default category:

```swift
        // (inside ingest, replacing the new-record creation block)
        let rec = ExpenseRecord(amount: tx.amount, currencyCode: tx.currency.rawValue,
                                date: tx.date, merchantName: tx.rawMerchant,
                                kind: tx.kind, source: source, dedupeKey: key)
        if let raw = tx.rawMerchant {
            let norm = MerchantNormalizer.normalize(raw)
            var mf = FetchDescriptor<MerchantRecord>(predicate: #Predicate { $0.normalizedName == norm })
            mf.fetchLimit = 1
            if let merchant = try modelContext.fetch(mf).first {
                rec.category = merchant.defaultCategory
                merchant.useCount += 1
                merchant.lastUsed = .now
            }
        }
        modelContext.insert(rec)
        try modelContext.save()
        return .inserted
```

- [ ] **Step 8: Run the test (and the full suite)**

Run: `swift test --filter AutoCategorizeTests` then `swift test`
Expected: PASS; full suite green.

- [ ] **Step 9: Commit**

```bash
git add Sources/GoldengoCore/MerchantNormalizer.swift Sources/GoldengoData/IngestionStore.swift Tests/GoldengoCoreTests/MerchantNormalizerTests.swift Tests/GoldengoDataTests/AutoCategorizeTests.swift
git commit -m "feat: normalize merchants and auto-apply default category on ingest"
```

---

## Done criteria

- `swift test` green from a clean checkout (foundation + data + connectors).
- `GoldengoData` exposes CloudKit-safe `@Model`s and an `@ModelActor IngestionStore` that dedupes/merges (no double-count) and auto-categorizes via merchant memory, returning only `Sendable` values.
- `GoldengoConnectors` exposes the `ExpenseConnector` protocol.
- Addresses the Plan 1 review follow-ups: merchant normalization for reconciliation, and dedupe stability is exercised by the merge tests.
- This is the verified data layer Plan 3 (frictionless capture) builds its Quick-Add + App Intent on.
