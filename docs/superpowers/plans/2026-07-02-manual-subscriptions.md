# Manual Subscriptions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user add a subscription directly (name/amount/cadence/next charge date), feeding the existing tracked list, reminders, Upcoming, and one-tap ghost machinery.

**Architecture:** A manual add creates the same `SubscriptionRecord` detection creates — pre-confirmed, flagged `isManual`, with an immutable `manualAnchorDate` as its schedule origin. The reconcile pass spares chargeless manual subs and rolls their display `nextChargeDate` forward; the ghost planner anchors evidence-less manual subs on `manualAnchorDate` (the planner's `anchor <= now` guard keeps future dates silent). Spec: `docs/superpowers/specs/2026-07-02-manual-subscriptions-design.md`.

**Tech Stack:** Swift / SwiftData / SwiftUI, XCTest via `swift test`.

## Global Constraints

- New `@Model` properties must have literal defaults (CloudKit + lightweight migration).
- Never compare `Decimal` inside a `#Predicate` (SIGSEGV) — filter in memory.
- No silent fabrication: due charges surface as ghosts, never auto-logged.
- Full `swift test` must pass before any commit.

---

### Task 1: `isManual` flag + `addManualSubscription`

**Files:**
- Modify: `Sources/GoldengoData/Models/SubscriptionRecord.swift` (property block)
- Modify: `Sources/GoldengoData/IngestionStore+Subscriptions.swift` (new public func)
- Modify: `docs/superpowers/specs/2026-07-02-manual-subscriptions-design.md` (amend §4: anchor is `manualAnchorDate`, not the rolled `nextChargeDate`)
- Test: `Tests/GoldengoDataTests/ManualSubscriptionTests.swift` (create)

**Interfaces:**
- Produces: `SubscriptionRecord.isManual: Bool`, `SubscriptionRecord.manualAnchorDate: Date`,
  `IngestionStore.addManualSubscription(name:amount:currency:cadence:nextChargeDate:now:) throws`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
import GoldengoCore
@testable import GoldengoData

final class ManualSubscriptionTests: XCTestCase {
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }
    private func makeStore() throws -> IngestionStore { IngestionStore(modelContainer: try .goldengoInMemory()) }

    func test_addManual_surfacesAsTracked_reAddConverges() async throws {
        let store = try makeStore()
        try await store.addManualSubscription(name: "Claude", amount: 20, currency: .eur,
                                              cadence: .monthly, nextChargeDate: day(2026, 7, 20))
        var rows = try await store.subscriptionCandidates()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.displayName, "Claude")
        XCTAssertTrue(rows.first?.isConfirmed ?? false, "A manual sub is a user statement — tracked immediately, never a guess to review")
        // WHY converge: matchKey is the dedupe contract with detection — re-adding must update, not duplicate.
        try await store.addManualSubscription(name: "claude", amount: 22, currency: .eur,
                                              cadence: .monthly, nextChargeDate: day(2026, 8, 20))
        rows = try await store.subscriptionCandidates()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.amount, 22)
    }

    func test_detectedSeries_convergesOntoManualRecord_keepsConfirmed() async throws {
        let store = try makeStore()
        try await store.addManualSubscription(name: "Claude", amount: 20, currency: .eur,
                                              cadence: .monthly, nextChargeDate: day(2026, 7, 20))
        for m in 4...6 {
            _ = try await store.logManual(amount: 20, currency: .eur, merchant: "Claude",
                                          categoryName: nil, date: day(2026, m, 20))
        }
        _ = try await store.refreshSubscriptions(now: day(2026, 7, 1))
        let rows = try await store.subscriptionCandidates()
        XCTAssertEqual(rows.count, 1, "Detection and the manual record share one matchKey — one row, not two")
        XCTAssertTrue(rows.first?.isConfirmed ?? false, "Detection updates never revoke the user's confirmation")
        XCTAssertEqual(rows.first?.occurrenceCount, 3)
    }
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter ManualSubscriptionTests` → compile error: no member `addManualSubscription`.

- [ ] **Step 3: Implement**

`SubscriptionRecord.swift`, after `isArchived`:

```swift
    /// User-declared via "Add subscription" (not a detector guess). Manual subs survive the
    /// reconcile pass with zero charge history and anchor their ghost schedule on
    /// `manualAnchorDate` until real charges exist.
    public var isManual: Bool = false
    /// The schedule origin the user declared (their "next charge" at add time). Immutable —
    /// `nextChargeDate` rolls forward for display, but due-charge generation must keep the
    /// original phase and never invent dues from before this date.
    public var manualAnchorDate: Date = Date.now
```

`IngestionStore+Subscriptions.swift`, after `unDismissSubscription`:

```swift
    /// Track a subscription the user declares directly — no charge history needed. Creates the
    /// same record detection creates, pre-confirmed, so the Tracked list, reminders, Upcoming
    /// and due-date ghosts all work unchanged. The matchKey uses the detector's scheme, so a
    /// later detected series for the same merchant converges on THIS record instead of duplicating.
    public func addManualSubscription(name: String, amount: Decimal, currency: CurrencyCode,
                                      cadence: SubscriptionCadence, nextChargeDate: Date,
                                      now: Date = .now) throws {
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let norm = MerchantNormalizer.normalize(displayName)
        guard !norm.isEmpty, amount > 0 else { return }
        let key = "\(norm)|\(cadence.rawValue)|\(currency.rawValue)"
        if let rec = try fetchSubscription(matchKey: key) {
            rec.displayName = displayName
            rec.amount = amount
            rec.nextChargeDate = nextChargeDate
            rec.manualAnchorDate = nextChargeDate
            rec.isConfirmed = true; rec.isDismissed = false; rec.isManual = true
            rec.confidence = 1
            rec.updatedAt = now
        } else {
            let rec = SubscriptionRecord(matchKey: key, displayName: displayName,
                                         normalizedMerchant: norm, amount: amount,
                                         currencyCode: currency.rawValue, cadence: cadence,
                                         nextChargeDate: nextChargeDate,
                                         occurrenceCount: 0, confidence: 1)
            rec.isConfirmed = true
            rec.isManual = true
            rec.manualAnchorDate = nextChargeDate
            rec.detectedAt = now; rec.updatedAt = now
            modelContext.insert(rec)
        }
        try modelContext.save()
    }
```

Spec amendment (§4): replace "anchor their due-charge schedule on `nextChargeDate` (`anchor = notBefore = nextChargeDate`)" with "anchor their due-charge schedule on the immutable `manualAnchorDate` (`anchor = notBefore = manualAnchorDate`) — `nextChargeDate` rolls forward for display and must not move the schedule origin".

- [ ] **Step 4: Run** — `swift test --filter ManualSubscriptionTests` → PASS (2 tests).
- [ ] **Step 5: Commit** — `git add Sources/GoldengoData Tests/GoldengoDataTests/ManualSubscriptionTests.swift docs/superpowers/specs/2026-07-02-manual-subscriptions-design.md && git commit -m "feat(subs): manual subscription records — addManualSubscription + isManual/manualAnchorDate"`

---

### Task 2: Reconcile pass spares manual subs, rolls their next-charge date

**Files:**
- Modify: `Sources/GoldengoData/IngestionStore+Subscriptions.swift` (`refreshSubscriptions` reconcile loop)
- Test: `Tests/GoldengoDataTests/ManualSubscriptionTests.swift` (append)

**Interfaces:**
- Consumes: Task 1's fields. No new public API.

- [ ] **Step 1: Write failing test**

```swift
    func test_refresh_keepsChargelessManualSub_andRollsNextChargeForward() async throws {
        let store = try makeStore()
        try await store.addManualSubscription(name: "iCloud", amount: 3, currency: .eur,
                                              cadence: .monthly, nextChargeDate: day(2026, 6, 20))
        // WHY: reconcile-archive exists to drop stale detector GUESSES; a manual sub is a user
        // statement and must survive refresh with zero charges.
        _ = try await store.refreshSubscriptions(now: day(2026, 8, 1))
        let rows = try await store.subscriptionCandidates()
        XCTAssertEqual(rows.count, 1, "Chargeless manual sub survives refresh")
        // WHY roll: with no detected series to refresh it, "Next:" would assert a past date forever.
        XCTAssertEqual(rows.first?.nextChargeDate, day(2026, 8, 20))
    }
```

- [ ] **Step 2: Run** — fails: rows is empty (archived) today.

- [ ] **Step 3: Implement** — in `refreshSubscriptions`, replace the reconcile loop body:

```swift
        // Reconcile records that are no longer detected (e.g. the user deleted charges so the series
        // fell below the cadence bar) so they don't linger with a stale count: drop unconfirmed
        // guesses; keep confirmed ones but correct their charge count to reality. Dismissed records
        // are left untouched. Manual subs are user statements, not guesses — they survive with zero
        // charges, and their display date rolls forward (no detected series will do it for them).
        var rollCal = Calendar(identifier: .gregorian); rollCal.timeZone = TimeZone(identifier: "UTC")!
        let detectedIDs = Set(detected.map(\.id))
        for rec in byKey.values where !rec.isArchived && !rec.isDismissed && !detectedIDs.contains(rec.matchKey) {
            if rec.isConfirmed {
                let count = try currentChargeCount(normalizedMerchant: rec.normalizedMerchant,
                                                   currencyCode: rec.currencyCode)
                if count == 0 && !rec.isManual {
                    rec.isArchived = true          // confirmed but no charges left → nothing to track
                } else {
                    rec.occurrenceCount = count     // keep, count corrected to reality
                    if rec.isManual {
                        var next = rec.nextChargeDate
                        while next < now { next = rec.cadence.advance(next, calendar: rollCal) }
                        rec.nextChargeDate = next
                    }
                }
            } else {
                rec.isArchived = true               // drop an unconfirmed guess that no longer repeats
            }
            rec.updatedAt = now
        }
```

- [ ] **Step 4: Run** — `swift test --filter ManualSubscriptionTests` → PASS (3 tests). Also run `swift test --filter SubscriptionStoreTests` (reconcile behavior for detected subs unchanged).
- [ ] **Step 5: Commit** — `git commit -m "feat(subs): reconcile spares manual subs; rolls their next-charge date forward"`

---

### Task 3: Ghost planner anchors evidence-less manual subs on `manualAnchorDate`

**Files:**
- Modify: `Sources/GoldengoData/IngestionStore+Subscriptions.swift` (`pendingSubscriptionCharges` per-sub loop)
- Test: `Tests/GoldengoDataTests/ManualSubscriptionTests.swift` (append)

**Interfaces:**
- Consumes: Task 1's fields; `SubscriptionSettlementPlanner.dueCharges(anchor:notBefore:cadence:now:calendar:)`.

- [ ] **Step 1: Write failing test**

```swift
    func test_manualSub_ghostSurfacesOnlyOnceDue_neverBefore() async throws {
        let store = try makeStore()
        try await store.addManualSubscription(name: "Hetzner", amount: 9, currency: .eur,
                                              cadence: .monthly, nextChargeDate: day(2026, 6, 20))
        // WHY: predictions are surfaced as one-tap ghosts, never auto-logged, and never early —
        // a future declared date must stay silent.
        let before = try await store.pendingSubscriptionCharges(now: day(2026, 6, 15))
        XCTAssertTrue(before.isEmpty, "Nothing due before the declared date")
        let after = try await store.pendingSubscriptionCharges(now: day(2026, 6, 25))
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after.first?.dueDate, day(2026, 6, 20))
        XCTAssertEqual(after.first?.displayName, "Hetzner")
        XCTAssertEqual(after.first?.merchantName, "Hetzner", "No evidence row yet — the display name is the merchant string a future import will merge on")
    }
```

- [ ] **Step 2: Run** — fails: `pendingSubscriptionCharges` skips merchants with no rows (`guard let merchantRows … else { continue }`).

- [ ] **Step 3: Implement** — in `pendingSubscriptionCharges`, replace the body of the `for sub in representative.values` loop from the `groupKey` line through the `guard let anchor…earliest` lines with:

```swift
            let groupKey = "\(sub.normalizedMerchant)|\(sub.currencyCode)"
            let merchantRows = grouped[groupKey] ?? []
            let evidence = merchantRows.filter {
                !$0.isArchived
                    && SubscriptionSettlementPlanner.isBillingEvidence(amount: $0.amount,
                                                                       subscriptionAmount: sub.amount)
            }
            // Anchor = freshest billing evidence; the earliest bounds the backward grid walk so
            // backfill can never invent dues from before the subscription's known history.
            // A manual sub with NO evidence yet anchors on the user's declared schedule origin
            // instead (dueCharges' `anchor <= now` guard keeps a still-future date silent).
            let anchorDate: Date, notBefore: Date, anchorMerchant: String
            if let freshest = evidence.max(by: { $0.date < $1.date }),
               let earliest = evidence.min(by: { $0.date < $1.date }) {
                anchorDate = freshest.date
                notBefore = earliest.date
                // The anchor's REAL merchant string (not displayName): logging the ghost with it
                // keeps MerchantNormalizer equality with future statement rows so imports merge.
                anchorMerchant = freshest.merchantName ?? sub.displayName
            } else if sub.isManual {
                anchorDate = sub.manualAnchorDate
                notBefore = sub.manualAnchorDate
                anchorMerchant = sub.displayName
            } else {
                continue
            }
```

…and in the loop below it, use `anchorDate`/`notBefore` in the `dueCharges(anchor:notBefore:…)` call and `anchorMerchant` as `merchantName:` in the `PendingSubscriptionCharge` init.

- [ ] **Step 4: Run** — `swift test --filter "ManualSubscriptionTests|PendingSubscriptionChargesTests"` → all PASS (evidence-anchored behavior must be untouched).
- [ ] **Step 5: Commit** — `git commit -m "feat(subs): due ghosts for evidence-less manual subs, anchored on the declared date"`

---

### Task 4: Add-subscription UI (model wrapper, sheet, wiring)

**Files:**
- Modify: `Sources/GoldengoFeatures/Subscriptions/SubscriptionsModel.swift` (add `addManual`)
- Create: `Sources/GoldengoFeatures/Subscriptions/AddSubscriptionView.swift`
- Modify: `Sources/GoldengoFeatures/Subscriptions/SubscriptionsView.swift` (toolbar ＋, empty-state CTA, sheet)

**Interfaces:**
- Consumes: `IngestionStore.addManualSubscription` (Task 1), `SubscriptionsModel.load()`.
- Produces: `SubscriptionsModel.addManual(name:amount:currency:cadence:nextChargeDate:) async`.

- [ ] **Step 1: Model wrapper** — in `SubscriptionsModel`, after `unDismiss`:

```swift
    /// Track a subscription the user declares directly (Add subscription sheet).
    public func addManual(name: String, amount: Decimal, currency: CurrencyCode,
                          cadence: SubscriptionCadence, nextChargeDate: Date) async {
        try? await store.addManualSubscription(name: name, amount: amount, currency: currency,
                                               cadence: cadence, nextChargeDate: nextChargeDate)
        await load()
    }
```

- [ ] **Step 2: AddSubscriptionView** — new file, quiet-luxe idiom (serif name field like AdjustSourceView, strict amount parse like AdjustWalletView, one-tap currency menu like QuickAddView, cadence as SelectableChips, accent-tinted date picker, GoldButton):

```swift
import SwiftUI
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

/// Declare a subscription directly — no charge history needed. Creates a confirmed, tracked
/// record; the charge itself is never fabricated (it surfaces as a one-tap ghost when due).
struct AddSubscriptionView: View {
    @State var model: SubscriptionsModel
    @State private var name = ""
    @State private var amountText = ""
    @State private var currencyCode = SharedSummary().readPreferredCurrency().rawValue
    @State private var cadence: SubscriptionCadence = .monthly
    @State private var nextCharge = Date.now
    @State private var busy = false
    @State private var showCurrencyPicker = false
    @State private var selectableCurrencies: [CurrencyCode] = []
    @Environment(\.dismiss) private var dismiss

    /// STRICT parse (same rule as AdjustWalletView): whole string is a plain positive amount.
    private var typedAmount: Decimal? {
        let cleaned = amountText.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard cleaned.range(of: "^[0-9]+(\\.[0-9]{1,2})?$", options: .regularExpression) != nil
        else { return nil }
        return Decimal(string: cleaned)
    }
    private var canSave: Bool {
        !busy && (typedAmount ?? 0) > 0
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func cadenceLabel(_ c: SubscriptionCadence) -> String {
        switch c {
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .quarterly: return "Quarterly"
        case .yearly: return "Yearly"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.l) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Netflix, iCloud, rent…", text: $name)
                        .font(.system(.title2, design: .serif))
                        .foregroundStyle(GoldengoTheme.inkPrimary)
                    Text("Goldengo reminds you before it charges and offers the expense with one tap when it's due — nothing is logged by itself.")
                        .font(.caption)
                        .foregroundStyle(GoldengoTheme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    currencyMenu
                    TextField("0", text: $amountText)
#if os(iOS)
                        .keyboardType(.decimalPad)
#endif
                        .font(.system(size: 40, weight: .semibold).monospacedDigit())
                        .tracking(-1)
                        .foregroundStyle(amountText.isEmpty ? GoldengoTheme.inkMuted : GoldengoTheme.inkPrimary)
                }

                HStack(spacing: 8) {
                    ForEach(SubscriptionCadence.allCases, id: \.rawValue) { c in
                        SelectableChip(cadenceLabel(c), isSelected: cadence == c) { cadence = c }
                    }
                }

                DatePicker("Next charge", selection: $nextCharge, displayedComponents: .date)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GoldengoTheme.inkPrimary)
                    .tint(GoldengoTheme.accent)

                GoldButton("Track subscription", isEnabled: canSave) {
                    guard let amount = typedAmount else { return }
                    busy = true
                    GoldengoHaptics.spendLanded()
                    Task {
                        await model.addManual(name: name, amount: amount,
                                              currency: CurrencyCode(currencyCode),
                                              cadence: cadence, nextChargeDate: nextCharge)
                        dismiss()
                    }
                }
            }
            .padding(GoldengoTheme.Spacing.l)
        }
        .background(Color.goldengoBackground.ignoresSafeArea())
        .goldengoDismissKeyboard()
        .sheet(isPresented: $showCurrencyPicker) {
            NavigationStack {
                CurrencyPickerView(available: selectableCurrencies, selectedCode: $currencyCode)
            }
        }
        .onAppear { selectableCurrencies = CurrencyCatalog.selectable(from: ExchangeRateCache().load() ?? SeedRates.table) }
    }

    // One-tap popular currencies, "More…" behind it (same idiom as QuickAdd/AddIncome).
    private var currencyMenu: some View {
        Menu {
            ForEach(menuCurrencies, id: \.rawValue) { c in
                Button { currencyCode = c.rawValue } label: {
                    let label = "\(c.symbol)  \(Locale.current.localizedString(forCurrencyCode: c.rawValue) ?? c.rawValue)"
                    if c.rawValue == currencyCode { Label(label, systemImage: "checkmark") }
                    else { Text(label) }
                }
            }
            Divider()
            Button { showCurrencyPicker = true } label: {
                Label("More currencies…", systemImage: "ellipsis.circle")
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(CurrencyCode(currencyCode).symbol)
                    .font(.system(size: 30, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.top, 6)
            }
            .foregroundStyle(GoldengoTheme.inkMuted)
            .contentShape(Rectangle())
        }
    }

    private var menuCurrencies: [CurrencyCode] {
        let have = Set(selectableCurrencies.map(\.rawValue))
        var list = CurrencyCode.popular.filter { have.contains($0.rawValue) }
        if !list.contains(where: { $0.rawValue == currencyCode }) {
            list.insert(CurrencyCode(currencyCode), at: 0)
        }
        return list
    }
}
```

- [ ] **Step 3: SubscriptionsView wiring**
  - Add `@State private var showAdd = false`.
  - Toolbar: add before the Done item —

```swift
                ToolbarItem(placement: .navigation) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add subscription")
                }
```

  - Empty state: replace the `ContentUnavailableView` with one carrying an action:

```swift
                    ContentUnavailableView {
                        Label("No subscriptions yet", systemImage: "arrow.triangle.2.circlepath")
                    } description: {
                        Text("Add one yourself, or import statements — when the same charge repeats, Goldengo lists it here.")
                    } actions: {
                        Button("Add a subscription") { showAdd = true }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(GoldengoTheme.accent)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
```

  - Sheet, after the existing `.task(id:)` modifier:

```swift
            .sheet(isPresented: $showAdd) {
                AddSubscriptionView(model: model)
                    .presentationDetents([.medium, .large])
            }
```

- [ ] **Step 4: Verify** — `swift build` clean; full `swift test` green (444 + 4 new).
- [ ] **Step 5: Commit** — `git commit -m "feat(subs): Add-subscription sheet — declare name/amount/cadence/next charge"`

---

### Task 5: Device verification

- [ ] `xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'id=7B8F5F4F-B6B9-5A41-926D-31C29770064E' -allowProvisioningUpdates build` → BUILD SUCCEEDED
- [ ] `xcrun devicectl device install app --device 7B8F5F4F-B6B9-5A41-926D-31C29770064E <DerivedData>/Build/Products/Debug-iphoneos/Goldengo.app` → App installed
- [ ] User checks: ＋ on Subscriptions → add iCloud/Hetzner/Claude → rows under Tracked with "Next: …".
