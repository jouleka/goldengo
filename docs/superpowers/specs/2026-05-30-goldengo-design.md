# Goldengo — Design Spec

- **Date:** 2026-05-30
- **Status:** Revised after Opus technical/security review — ready for implementation planning
- **Codename:** Goldengo (working name — to be replaced by an original, trademark-cleared name before any public App Store release)
- **Tracking:** YouTrack project `GOL` (https://mysigner.youtrack.cloud/projects/GOL)

## 1. Overview & goal

Goldengo is a **native iOS personal expense tracker** whose entire personality is **speed of capture**: log an expense in under two seconds, with as few taps as possible, so that tracking spending becomes a frictionless routine rather than a chore. It is built **for the user first**, but architected so it can grow into a public product (and an Android app) later without a rewrite.

The single success criterion: **the user never feels lazy about logging an expense, because logging is effectively free.**

## 2. Context & hard constraints

- **User is in Albania, banking with Raiffeisen.** Albania is not in the EEA, so PSD2 / Open Banking does not apply, and aggregators (Plaid, GoCardless, Tink, TrueLayer) do not meaningfully cover Albanian retail banks.
- **Raiffeisen sends SMS + push per transaction, not email.** iOS blocks third-party access to both SMS and other apps' notifications, so **there is no automatic card-capture hook on iOS** for this user. Apple Pay is the Raiffeisen card paying under the hood — its transactions land on the Raiffeisen statement and are captured the same way as any card spend.
- **Daily driver is an iPhone.** Automatic capture (SMS/notification parsing) only exists on Android; it is therefore explicitly a **future Android-build feature**, not part of this iOS MVP.
- Consequence: on iOS, **card/Apple Pay spend is captured by fast manual entry + statement import**; cash is manual; crypto is read-only auto.

## 3. Non-goals (MVP)

- No Apple Pay / Wallet interception (impossible on iOS).
- No bank aggregator integrations, and no Revolut/Wise connectors (user does not use them).
- No Android app, no automatic SMS/notification capture (future).
- No budgets/limits, no multi-user, no cloud backend or accounts.
- No PDF statement parsing in MVP (CSV first; PDF is a stretch goal).
- **Crypto is explicitly cut-able:** it is the largest security surface for the least personal value. It stays lowest-priority (Phase 4) and may be dropped from the MVP entirely without affecting the core.

## 4. Product principles — the frictionless north star (enforced rules)

1. **Only two fields are required to save: amount + category.** Merchant, note, date are optional and defaulted.
2. **A smart default category is pre-selected on open** (from last merchant / time-of-day / history), so the common path is: type amount → already categorized → one tap to save.
3. **"Repeat last"** logs the most frequent/last expense in a single tap.
4. **Save is one tap, no confirmation dialog** — haptic feedback + instant dismiss. Categorization never blocks saving; "Uncategorized" is allowed and fixable later in one tap.
5. **No onboarding wall.** The app is usable the instant it opens; connectors are optional add-ons.
6. **Performance targets (measured, not assumed):** launch-to-keypad under ~1s and full entry under 2s, measured by a UI test **on a real low-end device** (not the simulator). To hit launch budget, **CloudKit sync and `ModelContainer` setup must be off the launch path** (initialized lazily/in the background); Quick-Add must be presentable before sync completes.

## 5. Architecture

- **Native SwiftUI**, minimum iOS 17 (iOS 18-only surfaces such as the Control Center control are availability-gated). Swift 6 strict concurrency (see §7 for the SwiftData actor-isolation consequences).
- **Local-first persistence: SwiftData**, with **CloudKit private database** sync across the user's own devices. The app is fully functional offline; CloudKit is sync, not the source of truth. No backend to operate or pay for.
- **Modular Swift Package Manager packages** to enforce boundaries and enable isolated testing (see §13).
- **Pluggable connector layer**: every spending source funnels through one ingestion pipeline, so future sources (Revolut/Wise/aggregators/Android-SMS) are additive, never a rewrite.

## 6. Data model (SwiftData `@Model`)

> **CloudKit-sync compatibility (hard requirement).** With `cloudKitDatabase: .private`, SwiftData requires: **every relationship is optional**, **every non-optional attribute has a default value**, and **`@Attribute(.unique)` is NOT supported.** The models below are designed accordingly. Uniqueness/dedup is enforced in application code (see the reconciliation rule), never by a store constraint.

- **Expense** — core record: `amount: Decimal = 0`, `currency: String = "ALL"` (ISO 4217, or a crypto symbol), `date: Date = .now`, `merchantName: String?`, `note: String?`, `kind: TransactionKind = .expense` (`expense` / `income` / `transfer` — so statement imports don't choke on credits), `source: ExpenseSource = .manual` (`manual` / `imported` / `crypto`), `dedupeKey: String = ""` (indexed, **not** unique), `isDeleted: Bool = false` (soft-delete tombstone for reliable CloudKit deletion propagation), `createdAt`, `updatedAt`. Optional relationships → `Category?`, `Account?`, `Subscription?`.
- **Category** — `name`, `icon` (SF Symbol/emoji), `color`. Flat (no sub-categories in MVP). Budgets deferred.
- **Merchant** — `name`, `normalizedName`, optional `defaultCategory`, `useCount`, `lastUsed`. Powers one-tap categorization: choosing a merchant pre-fills the category last used for it.
- **Account** — a source of funds: `name` ("Raiffeisen Visa", "Cash", "Binance"), `type` (`bankCard` / `cash` / `cryptoWallet` / `cryptoExchange`), `currency`, optional `connectorId`, optional `balance` (only populated by connectors that expose balances).
- **Subscription** — `name`, `amount`, `cadence` (weekly/monthly/quarterly/yearly), `nextChargeDate`, `isConfirmed`, `dismissed`, `detected`. Optional relationship → `charges: [Expense]`.
- **ImportBatch** — `fileName`, `importedAt`, `rowCount`, `dedupedCount`. Makes every import reviewable and undoable.
- **ExchangeRate** — `base`, `quote`, `rate`, `asOf`. Lightweight FX snapshot so ALL↔EUR (and crypto→fiat) figures in reports are reproducible and timestamped, rather than computed against a moving live rate.

**Reconciliation rule (app-code dedup, not a DB constraint):** because card spend is both typed-by-the-user and later imported from a statement, every record carries an indexed `dedupeKey` (external id/hash, or `date + amount + merchant + account`). Ingestion does a **fetch-before-insert** against `dedupeKey`; when an import matches an existing manual entry, Goldengo **merges (upgrades source/metadata) instead of double-counting**. This runs inside the persistence actor (§7) so it is concurrency-safe. Subscription occurrence counting (§9) keys off the *merged* record so a manual+import pair is one occurrence, never two.

## 7. Capture pipeline & connectors (the future-proofing)

All sources funnel through **one ingestion pipeline**: `normalize → dedupe/reconcile → auto-categorize → persist`.

```swift
protocol ExpenseConnector {
    var id: String { get }
    var capabilities: ConnectorCapabilities { get }   // realtime? backfill? balances?
    func pull(since checkpoint: SyncCheckpoint?) async throws -> [NormalizedTransaction]
}
```

`NormalizedTransaction` is the common **`Sendable` value type** every connector emits (amount, currency, date, raw merchant, external id, kind, account ref).

> **Swift 6 concurrency (hard requirement).** `ModelContext` and `@Model` instances are **not `Sendable`** and are not safe to pass across actor boundaries. Therefore: connectors return `Sendable` `NormalizedTransaction` values only; **all persistence (dedupe + insert/merge) happens inside a `@ModelActor`**. No `@Model` object or `ModelContext` ever crosses an actor boundary. This shapes the pipeline and is not optional.

`ConnectorCapabilities`/`SyncCheckpoint` are kept **minimal** (only what Manual + CSV need) to avoid speculative abstraction; they grow when a real second connector arrives.

MVP connectors:
1. **Manual** (the star) — a *push* source: Quick-Add and the App Intent write straight into the same `@ModelActor` pipeline, so dedupe/categorization apply uniformly.
2. **StatementImport** — pick a Raiffeisen **CSV** → column-mapping → backfill. Supports review/undo via `ImportBatch`. (PDF is a stretch goal.)
3. **Crypto** — read-only on-chain address watching; outflows become expenses; optional read-only exchange API keys. Lowest priority; cut-able (§3).

## 8. Capture entry points (all roads → one Quick-Add)

The core is a single **`LogExpenseIntent`** (App Intents). How each surface reaches it:

- **Siri & Shortcuts** invoke the intent **directly** (exposed via an `AppShortcutsProvider`, with parameter resolution for amount/category).
- **Back Tap & the Action Button cannot bind an App Intent directly** — they bind a **Shortcut**. So the user (or a guided setup screen) wires a one-step Shortcut that calls `LogExpenseIntent`. The intent is built once; these surfaces reach it through that Shortcut indirection.
- **WidgetKit** Lock-Screen + Home widgets (interactive, iOS 17) and an iOS 18 **Control Center** control deep-link into Quick-Add. The intent that opens the capture UI uses `openAppWhenRun`.

One intent, every surface — with the Shortcut indirection made explicit so setup isn't a surprise.

## 9. Subscription detection

On-device, implemented as a **pure function over the expense set** (trivially unit-testable):

- Group transactions by normalized merchant + similar amount.
- Detect a steady interval with **explicit tolerance bands** to avoid monthly-vs-4-weekly aliasing: weekly ≈ 7±2d, monthly ≈ 28–31d, quarterly ≈ 88–93d, yearly ≈ 360–370d.
- Default threshold is **≥3 occurrences**, but **long cadences (yearly) use ≥2 occurrences** (or user confirmation), since 3 yearly charges would take ~3 years.
- **Free-trial handling:** detect trial→paid transitions where the first charge is 0 or differs from the recurring amount; don't let amount-grouping discard the series.
- **Variable amounts** (utilities) handled via an amount-tolerance flag on the candidate.
- Occurrence counting uses **merged** records (§6) so a manual+import pair counts once.
- **Surface candidates for the user to confirm — never silently assert.** Confirmed subscriptions auto-match future charges and predict `nextChargeDate`. Optional local notification before the next charge. The user can mark a candidate "not a subscription" (`dismissed`).

## 10. Sync & storage

- **SwiftData + CloudKit private DB** (`ModelConfiguration(cloudKitDatabase: .private)`). Local-first, offline-capable; cross-device sync is automatic.
- **Encryption (accurate framing):** the CloudKit private database is encrypted **in transit and at rest, Apple-managed** — it is **not end-to-end** unless the user has Advanced Data Protection enabled, and **SwiftData exposes no per-field encryption API.** We therefore do not rely on app-level field encryption for synced data; the strongest protection for true secrets is that **they are never synced** (Keychain only, §11).
- Dedup/merge is app-code fetch-before-insert in the `@ModelActor` (§6, §7); `isDeleted` tombstones make deletions propagate reliably across devices.
- **Statement files (CSV/PDF) are never synced** — processed locally, then discarded. Only the resulting normalized records persist.

## 11. Security & privacy

- **Biometric app lock** (Face ID / Touch ID via LocalAuthentication), with auto-lock when backgrounded. Requires **`NSFaceIDUsageDescription`** in Info.plist.
- **All secrets in the Keychain** (crypto API keys, any tokens) — never in SwiftData, UserDefaults, or plaintext. Non-synced secrets use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- **iOS Data Protection (Complete)** on the main store. **Consequence for widgets:** a Complete-protected store is **unreadable while the device is locked**, so Lock-Screen/Home widgets cannot read it then. Widgets therefore read a **small, non-sensitive cache in a shared App Group** (file protection `CompleteUntilFirstUserAuthentication`); amounts on the lock screen are **opt-in / blurred by default** on top of that. A locked phone must not broadcast spending.
- **Crypto is read-only**: public addresses + read-only API keys only. Never private keys or seed phrases; reject withdrawal-capable keys where detectable.
- **Network**: HTTPS-only (ATS enforced), minimal external calls (blockchain APIs only in MVP).
- **No third-party analytics/trackers** touching financial data. Ship a `PrivacyInfo.xcprivacy` manifest declaring required-reason API categories (e.g. `UserDefaults`, file-timestamp) and any added SDK's manifest. Request least-privilege entitlements only.
- **Import parsers treat files as untrusted**: size limits, robust failure handling, fuzz-tested. Malformed CSV/PDF is the primary attack surface.

## 12. Testing strategy

Tests ship with every feature (standing workspace rule; TDD where reasonable):

- **Unit (mandatory):** CSV parser (incl. malformed fixtures), dedupe/reconciliation, subscription detection (incl. trials, annual, aliasing fixtures), merchant/category suggestion, Decimal-currency + date math.
- **Integration:** connector → ingestion → SwiftData persistence using an in-memory `ModelContainer`; the `@ModelActor` dedupe/merge path; `LogExpenseIntent` writes a correct `Expense`.
- **UI:** the Quick-Add golden path (launch → amount → category → save), asserting the tap count stays minimal; the launch/entry timing assertions run on a real low-end device target.

## 13. Project structure (modular SPM)

- `GoldengoCore` — domain models + `Sendable` value types (e.g. `NormalizedTransaction`). No UI, no persistence deps.
- `GoldengoData` — SwiftData stack, the `@ModelActor` persistence/ingestion pipeline, repositories, dedupe.
- `GoldengoConnectors` — `ExpenseConnector` protocol + Manual / StatementImport / Crypto.
- `GoldengoIntents` — App Intents + Shortcuts provider (shared with the widget & Control Center extensions).
- `GoldengoDesignSystem` — Goldengo gold palette, typography, components; light + dark.
- `GoldengoFeatures` — SwiftUI features: QuickAdd, Dashboard, Subscriptions, Detail, Settings.
- App target + Widget extension + Control Center extension wire them together.

## 14. Tech & versions

- iOS 17.0 minimum (iOS 18 Control Center control availability-gated). SwiftUI, SwiftData, App Intents, WidgetKit. **Swift 6 strict concurrency** — persistence via a `@ModelActor`; only `Sendable` values cross actor boundaries (§7).
- Currency stored as `Decimal` + ISO 4217 code; default `ALL` (lekë, displayed "L"), with `EUR` and crypto symbols supported. Crypto amounts store the native asset amount; fiat figures use a timestamped `ExchangeRate` snapshot (§6).

## 15. Roadmap / phasing (maps to YouTrack epics)

- **Phase 0 — Scaffold:** `GOL-1` (modular project + CI), `GOL-9` (design system base).
- **Phase 1 — Core capture:** `GOL-2` (data model + CloudKit-safe sync), `GOL-3` (ingestion + `@ModelActor` pipeline + connector framework), `GOL-4` (frictionless capture + entry points), `GOL-10`/`GOL-11` woven throughout.
- **Phase 2 — Safety net:** `GOL-5` (CSV statement import).
- **Phase 3 — Insight:** `GOL-7` (subscription detection), `GOL-8` (dashboard & insights).
- **Phase 4 — Extras (optional/cut-able):** `GOL-6` (read-only crypto).
- `GOL-10` (security & privacy) and `GOL-11` (testing & CI) are cross-cutting and applied in every phase, not deferred to the end.

## 16. Open questions & future work

- **PDF statement parsing** (beyond CSV).
- **Always-on-Mac SMS bridge**: parse Raiffeisen SMS off a synced Mac and feed iOS — a fragile, optional power-user experiment, not MVP.
- **Android build**: the home of true automatic capture (SMS + notification parsing) — the original "it just appears when I pay" dream.
- **Aggregators / Revolut / Wise / PayPal** connectors for a future public product.
- **Budgets & limits.**
- **Public release**: original name + trademark + App Store name-availability check; privacy review.

## 17. Revisions — post-Opus review (2026-05-30)

Addressed a pre-implementation Opus technical/security review:

- **MUST-FIX:** removed reliance on `@Attribute(.unique)` (unsupported with CloudKit); made the data model CloudKit-compatible (optional relationships, defaulted non-optionals); corrected encryption framing (CloudKit private DB is Apple-managed, not E2E; SwiftData has no per-field encryption).
- **SHOULD-FIX:** made the `@ModelActor` + `Sendable`-only pipeline an explicit architectural requirement (Swift 6); clarified App Intent reach via Shortcut indirection for Back Tap/Action Button; fixed Lock-Screen widget data-protection reality (App Group cache, not just blur); added `NSFaceIDUsageDescription` and PrivacyInfo specifics; hardened subscription detection (tolerance bands, free trials, annual ≥2, merged-record occurrence counting).
- **Scope:** added `ExchangeRate` + soft-delete tombstones; kept connector capabilities minimal (YAGNI); marked crypto explicitly cut-able; defined perf targets as real-device measurements with sync off the launch path.
