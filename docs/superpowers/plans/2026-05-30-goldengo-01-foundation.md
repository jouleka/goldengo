# Goldengo Plan 1 — Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a modular Swift Package foundation for Goldengo with a fully tested, platform-agnostic domain core (currency/money, transaction kinds, the `NormalizedTransaction` connector value type) and CI, so every later feature builds on a verified, headless-testable base.

**Architecture:** All business logic lives in local Swift Package Manager packages that compile for both iOS and macOS, so `swift test` runs the whole suite headlessly without a simulator. The Xcode app target, widgets, and App Intents (added in later plans) will depend on these packages. This plan creates the package manifest, the `GoldengoCore` module, and a CI workflow.

**Tech Stack:** Swift 6, Swift Package Manager (tools 6.0), XCTest. Pure value types (`Sendable`, `Codable`) — no SwiftData/UIKit/SwiftUI in this layer.

---

### Task 1: Package scaffold + smoke test

**Files:**
- Create: `Package.swift`
- Create: `Sources/GoldengoCore/GoldengoCore.swift`
- Test: `Tests/GoldengoCoreTests/SmokeTests.swift`

- [ ] **Step 1: Write the package manifest**

Create `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Goldengo",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GoldengoCore", targets: ["GoldengoCore"]),
    ],
    targets: [
        .target(name: "GoldengoCore"),
        .testTarget(name: "GoldengoCoreTests", dependencies: ["GoldengoCore"]),
    ]
)
```

- [ ] **Step 2: Add a placeholder source so the target compiles**

Create `Sources/GoldengoCore/GoldengoCore.swift`:

```swift
/// Goldengo domain core — platform-agnostic value types shared by every feature.
public enum GoldengoCore {
    public static let schemaVersion = 1
}
```

- [ ] **Step 3: Write the failing smoke test**

Create `Tests/GoldengoCoreTests/SmokeTests.swift`:

```swift
import XCTest
@testable import GoldengoCore

final class SmokeTests: XCTestCase {
    func test_schemaVersion_isOne() {
        XCTAssertEqual(GoldengoCore.schemaVersion, 1)
    }
}
```

- [ ] **Step 4: Run the test (verifies the toolchain + package resolve)**

Run: `swift test`
Expected: builds and PASSES (`Test Suite 'SmokeTests' passed`). If `swift test` reports an old tools version, the Swift 6 toolchain isn't selected — fix the toolchain before continuing.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat: scaffold GoldengoCore Swift package with smoke test"
```

---

### Task 2: Currency & Money value types

**Files:**
- Create: `Sources/GoldengoCore/CurrencyCode.swift`
- Create: `Sources/GoldengoCore/Money.swift`
- Test: `Tests/GoldengoCoreTests/MoneyTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/GoldengoCoreTests/MoneyTests.swift`:

```swift
import XCTest
@testable import GoldengoCore

final class MoneyTests: XCTestCase {
    func test_lek_formatsWithSymbol_noDecimals_groupingSeparator() {
        let m = Money(amount: 1500, currency: .all)
        XCTAssertEqual(m.formatted(), "L 1,500")
    }

    func test_eur_formatsWithSymbol_twoDecimals() {
        let m = Money(amount: Decimal(string: "12.5")!, currency: .eur)
        XCTAssertEqual(m.formatted(), "€ 12.50")
    }

    func test_unknownCurrency_usesRawCodeAsSymbol() {
        let m = Money(amount: 3, currency: CurrencyCode("BTC"))
        XCTAssertEqual(m.currency.symbol, "BTC")
    }

    func test_currencyCode_isUppercasedAndEquatable() {
        XCTAssertEqual(CurrencyCode("eur"), .eur)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter MoneyTests`
Expected: FAIL — `cannot find 'Money'`/`CurrencyCode' in scope`.

- [ ] **Step 3: Implement `CurrencyCode`**

Create `Sources/GoldengoCore/CurrencyCode.swift`:

```swift
public struct CurrencyCode: Hashable, Sendable, Codable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue.uppercased()
    }

    public static let all = CurrencyCode("ALL")   // Albanian lek
    public static let eur = CurrencyCode("EUR")

    /// Display symbol; falls back to the raw code (e.g. crypto tickers).
    public var symbol: String {
        switch rawValue {
        case "ALL": return "L"
        case "EUR": return "€"
        default:    return rawValue
        }
    }

    /// Currencies with no minor unit in everyday display (lek is shown without decimals).
    public var fractionDigits: Int {
        rawValue == "ALL" ? 0 : 2
    }
}
```

- [ ] **Step 4: Implement `Money`**

Create `Sources/GoldengoCore/Money.swift`:

```swift
import Foundation

public struct Money: Hashable, Sendable {
    public var amount: Decimal
    public var currency: CurrencyCode

    public init(amount: Decimal, currency: CurrencyCode) {
        self.amount = amount
        self.currency = currency
    }

    /// Deterministic formatting (explicit separators) so it is locale-independent and testable.
    public func formatted() -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.decimalSeparator = "."
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = currency.fractionDigits
        f.maximumFractionDigits = currency.fractionDigits
        let number = NSDecimalNumber(decimal: amount)
        let body = f.string(from: number) ?? "\(amount)"
        return "\(currency.symbol) \(body)"
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter MoneyTests`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/GoldengoCore/CurrencyCode.swift Sources/GoldengoCore/Money.swift Tests/GoldengoCoreTests/MoneyTests.swift
git commit -m "feat: add CurrencyCode and Money value types with deterministic formatting"
```

---

### Task 3: Transaction enums

**Files:**
- Create: `Sources/GoldengoCore/TransactionKind.swift`
- Create: `Sources/GoldengoCore/ExpenseSource.swift`
- Test: `Tests/GoldengoCoreTests/EnumsTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/GoldengoCoreTests/EnumsTests.swift`:

```swift
import XCTest
@testable import GoldengoCore

final class EnumsTests: XCTestCase {
    func test_transactionKind_rawValues() {
        XCTAssertEqual(TransactionKind.expense.rawValue, "expense")
        XCTAssertEqual(TransactionKind.allCases.count, 3)
    }

    func test_expenseSource_rawValues() {
        XCTAssertEqual(ExpenseSource.manual.rawValue, "manual")
        XCTAssertEqual(Set(ExpenseSource.allCases), [.manual, .imported, .crypto])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter EnumsTests`
Expected: FAIL — types not found.

- [ ] **Step 3: Implement the enums**

Create `Sources/GoldengoCore/TransactionKind.swift`:

```swift
public enum TransactionKind: String, Sendable, Codable, CaseIterable {
    case expense
    case income
    case transfer
}
```

Create `Sources/GoldengoCore/ExpenseSource.swift`:

```swift
public enum ExpenseSource: String, Sendable, Codable, CaseIterable {
    case manual
    case imported
    case crypto
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter EnumsTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoCore/TransactionKind.swift Sources/GoldengoCore/ExpenseSource.swift Tests/GoldengoCoreTests/EnumsTests.swift
git commit -m "feat: add TransactionKind and ExpenseSource enums"
```

---

### Task 4: `NormalizedTransaction` + dedupe key

**Files:**
- Create: `Sources/GoldengoCore/NormalizedTransaction.swift`
- Test: `Tests/GoldengoCoreTests/NormalizedTransactionTests.swift`

This is the `Sendable` value type every connector emits (spec §7). Its `dedupeKey` drives the reconciliation that prevents manual+import double-counting (spec §6).

- [ ] **Step 1: Write the failing tests**

Create `Tests/GoldengoCoreTests/NormalizedTransactionTests.swift`:

```swift
import XCTest
@testable import GoldengoCore

final class NormalizedTransactionTests: XCTestCase {
    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: iso)!
    }

    func test_externalID_takesPrecedenceInDedupeKey() {
        let tx = NormalizedTransaction(
            externalID: "abc123", amount: 1500, currency: .all,
            date: date("2026-05-30T10:00:00Z"), rawMerchant: "Spar",
            kind: .expense, accountRef: "raiffeisen-visa")
        XCTAssertEqual(tx.dedupeKey, "ext:abc123")
    }

    func test_compositeKey_isStableAcrossSameDayDifferentTime() {
        let a = NormalizedTransaction(externalID: nil, amount: 1500, currency: .all,
            date: date("2026-05-30T09:00:00Z"), rawMerchant: "Spar",
            kind: .expense, accountRef: "cash")
        let b = NormalizedTransaction(externalID: nil, amount: 1500, currency: .all,
            date: date("2026-05-30T21:30:00Z"), rawMerchant: "Spar",
            kind: .expense, accountRef: "cash")
        XCTAssertEqual(a.dedupeKey, b.dedupeKey)
    }

    func test_compositeKey_differsWhenAmountDiffers() {
        let a = NormalizedTransaction(externalID: nil, amount: 1500, currency: .all,
            date: date("2026-05-30T09:00:00Z"), rawMerchant: "Spar",
            kind: .expense, accountRef: "cash")
        let b = NormalizedTransaction(externalID: nil, amount: 1600, currency: .all,
            date: date("2026-05-30T09:00:00Z"), rawMerchant: "Spar",
            kind: .expense, accountRef: "cash")
        XCTAssertNotEqual(a.dedupeKey, b.dedupeKey)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter NormalizedTransactionTests`
Expected: FAIL — `NormalizedTransaction` not found.

- [ ] **Step 3: Implement `NormalizedTransaction`**

Create `Sources/GoldengoCore/NormalizedTransaction.swift`:

```swift
import Foundation

/// The common, `Sendable` shape every connector emits. The ingestion pipeline
/// (later plan) maps these into persisted `Expense` records, using `dedupeKey`
/// to merge rather than double-count (spec §6, §7).
public struct NormalizedTransaction: Hashable, Sendable {
    public var externalID: String?
    public var amount: Decimal
    public var currency: CurrencyCode
    public var date: Date
    public var rawMerchant: String?
    public var kind: TransactionKind
    public var accountRef: String?

    public init(externalID: String?, amount: Decimal, currency: CurrencyCode,
                date: Date, rawMerchant: String?, kind: TransactionKind,
                accountRef: String?) {
        self.externalID = externalID
        self.amount = amount
        self.currency = currency
        self.date = date
        self.rawMerchant = rawMerchant
        self.kind = kind
        self.accountRef = accountRef
    }

    /// Stable key for reconciliation. Prefers a provider id; otherwise a
    /// day-granularity composite so a manual entry and its later-imported
    /// statement row collapse to one record.
    public var dedupeKey: String {
        if let id = externalID, !id.isEmpty { return "ext:\(id)" }
        let day = Self.dayFormatter.string(from: date)
        let amt = NSDecimalNumber(decimal: amount).stringValue
        return "cmp:\(day)|\(amt)|\(rawMerchant ?? "")|\(accountRef ?? "")"
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter NormalizedTransactionTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: PASS (all tasks' tests green).

- [ ] **Step 6: Commit**

```bash
git add Sources/GoldengoCore/NormalizedTransaction.swift Tests/GoldengoCoreTests/NormalizedTransactionTests.swift
git commit -m "feat: add NormalizedTransaction with reconciliation dedupe key"
```

---

### Task 5: CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`
- Create: `README.md`

- [ ] **Step 1: Add the CI workflow**

Create `.github/workflows/ci.yml`:

```yaml
name: CI
on:
  push:
  pull_request:
jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Show Swift version
        run: swift --version
      - name: Run tests
        run: swift test
```

- [ ] **Step 2: Add a minimal README**

Create `README.md`:

```markdown
# Goldengo

Native iOS personal expense tracker focused on frictionless capture. Logic lives in Swift packages (`swift test` runs headlessly); the Xcode app target is added in a later plan. See `docs/superpowers/specs/` and `docs/superpowers/plans/`.
```

- [ ] **Step 3: Verify the suite once more, then commit**

Run: `swift test`
Expected: PASS.

```bash
git add .github/workflows/ci.yml README.md
git commit -m "ci: run swift test on push/PR; add README"
```

---

## Done criteria

- `swift test` passes from a clean checkout (smoke, Money, enums, NormalizedTransaction).
- `GoldengoCore` exposes `CurrencyCode`, `Money`, `TransactionKind`, `ExpenseSource`, `NormalizedTransaction` — all `Sendable`.
- CI is in place. This is the verified base Plan 2 (persistence & pipeline) builds on.
