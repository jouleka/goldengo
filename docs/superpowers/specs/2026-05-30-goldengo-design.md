# Goldengo — Design Spec

- **Date:** 2026-05-30
- **Status:** Approved (design direction); pending spec review before implementation planning
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

## 4. Product principles — the frictionless north star (enforced rules)

1. **Only two fields are required to save: amount + category.** Merchant, note, date are optional and defaulted.
2. **A smart default category is pre-selected on open** (from last merchant / time-of-day / history), so the common path is: type amount → already categorized → one tap to save.
3. **"Repeat last"** logs the most frequent/last expense in a single tap.
4. **Save is one tap, no confirmation dialog** — haptic feedback + instant dismiss. Categorization never blocks saving; "Uncategorized" is allowed and fixable later in one tap.
5. **No onboarding wall.** The app is usable the instant it opens; connectors are optional add-ons.
6. **Performance targets (measured):** launch-to-keypad under ~1s; full entry under 2s.

## 5. Architecture

- **Native SwiftUI**, minimum iOS 17 (iOS 18-only surfaces such as the Control Center control are availability-gated). Swift 6 concurrency.
- **Local-first persistence: SwiftData**, with **CloudKit private database** sync across the user's own devices. The app is fully functional offline; CloudKit is sync, not the source of truth. No backend to operate or pay for.
- **Modular Swift Package Manager packages** to enforce boundaries and enable isolated testing (see §13).
- **Pluggable connector layer**: every spending source funnels through one ingestion pipeline, so future sources (Revolut/Wise/aggregators/Android-SMS) are additive, never a rewrite.

## 6. Data model (SwiftData `@Model`)

- **Expense** — core record: `amount: Decimal`, `currency` (ISO 4217: `ALL`, `EUR`, or a crypto symbol), `date`, `merchantName?`, `note?`, `kind` (`expense` / `income` / `transfer` — so statement imports don't choke on credits), `source` (`manual` / `imported` / `crypto`), `dedupeKey`, `createdAt`, `updatedAt`. Relationships → `Category?`, `Account?`, `Subscription?`.
- **Category** — `name`, `icon` (SF Symbol/emoji), `color`. Flat (no sub-categories in MVP). Budgets deferred.
- **Merchant** — `name`, `normalizedName`, `defaultCategory`, `useCount`, `lastUsed`. Powers one-tap categorization: choosing a merchant pre-fills the category last used for it.
- **Account** — a source of funds: `name` ("Raiffeisen Visa", "Cash", "Binance"), `type` (`bankCard` / `cash` / `cryptoWallet` / `cryptoExchange`), `currency`, `connectorId?`.
- **Subscription** — `name`, `amount`, `cadence` (weekly/monthly/quarterly/yearly), `nextChargeDate`, `isConfirmed`, `dismissed` ("not a subscription"), `detected` (auto vs manual). Relationship → `charges: [Expense]`.
- **ImportBatch** — `fileName`, `importedAt`, `rowCount`, `dedupedCount`. Makes every import reviewable and undoable.

**Reconciliation rule:** because card spend is both typed-by-the-user and later imported from a statement, every record carries a `dedupeKey` (external id/hash, or `date + amount + merchant + account`). When an import matches an existing manual entry, Goldengo **merges instead of double-counting** — this is what makes "fast manual now, import as a safety net" produce correct totals.

## 7. Capture pipeline & connectors (the future-proofing)

All sources funnel through **one ingestion pipeline**: `normalize → dedupe/reconcile → auto-categorize → persist`.

```swift
protocol ExpenseConnector {
    var id: String { get }
    var capabilities: ConnectorCapabilities { get }   // realtime? backfill? balances?
    func pull(since checkpoint: SyncCheckpoint?) async throws -> [NormalizedTransaction]
}
```

`NormalizedTransaction` is the common shape every connector emits (amount, currency, date, raw merchant, external id, kind, account ref). MVP connectors:

1. **Manual** (the star) — a *push* source: Quick-Add and App Intents write straight into the same pipeline, so dedupe/categorization apply uniformly.
2. **StatementImport** — pick a Raiffeisen **CSV** → column-mapping → backfill. Supports review/undo via `ImportBatch`. (PDF is a stretch goal.)
3. **Crypto** — read-only on-chain address watching; outflows become expenses; optional read-only exchange API keys. Lowest priority; ships after the core.

## 8. Capture entry points (all roads → one Quick-Add)

The linchpin is a single **`LogExpenseIntent`** (App Intents), built once and reused by **Siri**, **Shortcuts**, **Back Tap** (double-tap the back of the phone), and the **Action Button**. **WidgetKit** Lock-Screen + Home widgets (interactive) and an iOS 18 **Control Center** tile deep-link into Quick-Add. One code path, every surface.

## 9. Subscription detection

On-device, implemented as a **pure function over the expense set** (so it is trivially unit-testable):

- Group transactions by normalized merchant + similar amount (tolerance for variable bills like utilities).
- Detect a steady interval (~weekly / ~monthly / ~yearly) across **≥3 occurrences**; compute a confidence score.
- **Surface candidates for the user to confirm — never silently assert.** Confirmed subscriptions auto-match future charges and predict `nextChargeDate`.
- Optional local notification before the next charge. The user can mark a candidate "not a subscription" (`dismissed`).

## 10. Sync & storage

- **SwiftData + CloudKit private DB** (`ModelConfiguration(cloudKitDatabase: .private)`). Local-first, offline-capable; cross-device sync is automatic and encrypted.
- Conflicts are rare by design: the `dedupeKey` reconciliation on ingestion collapses duplicates; last-writer-wins for field edits.
- **Statement files (CSV/PDF) are never synced** — processed locally, then discarded. Only the resulting normalized records persist.
- **Secrets are never stored in SwiftData/CloudKit** (see §11) — they live in the Keychain.

## 11. Security & privacy

- **Biometric app lock** (Face ID / Touch ID via LocalAuthentication), with auto-lock when backgrounded.
- **All secrets in the Keychain** (crypto API keys, any tokens) — never in SwiftData, UserDefaults, or plaintext. Non-synced secrets use device-only accessibility.
- **iOS Data Protection (Complete)** on the store; CloudKit private DB is encrypted in transit and at rest.
- **Crypto is read-only**: public addresses + read-only API keys only. Never private keys or seed phrases; reject withdrawal-capable keys where detectable.
- **Lock-Screen widget redaction**: amounts on the lock screen are opt-in / blurred by default — a locked phone must not broadcast spending.
- **Network**: HTTPS-only (ATS enforced), minimal external calls (blockchain APIs only in MVP).
- **No third-party analytics/trackers** touching financial data. Ship the required `PrivacyInfo.xcprivacy` manifest; request least-privilege entitlements only.
- **Import parsers treat files as untrusted**: size limits, robust failure handling, fuzz-tested. Malformed CSV/PDF is the primary attack surface.

## 12. Testing strategy

Tests ship with every feature (standing workspace rule; TDD where reasonable):

- **Unit (mandatory):** CSV parser (incl. malformed fixtures), dedupe/reconciliation, subscription detection, merchant/category suggestion, Decimal-currency + date math.
- **Integration:** connector → ingestion → SwiftData persistence using an in-memory `ModelContainer`; `LogExpenseIntent` writes a correct `Expense`.
- **UI:** the Quick-Add golden path (launch → amount → category → save), asserting the tap count stays minimal.

## 13. Project structure (modular SPM)

- `GoldengoCore` — domain models, currency/value types. No UI, no persistence deps.
- `GoldengoData` — SwiftData stack, repositories, ingestion pipeline, dedupe.
- `GoldengoConnectors` — `ExpenseConnector` protocol + Manual / StatementImport / Crypto.
- `GoldengoIntents` — App Intents + Shortcuts provider (shared with the widget & Control Center extensions).
- `GoldengoDesignSystem` — Goldengo gold palette, typography, components; light + dark.
- `GoldengoFeatures` — SwiftUI features: QuickAdd, Dashboard, Subscriptions, Detail, Settings.
- App target + Widget extension + Control Center extension wire them together.

## 14. Tech & versions

- iOS 17.0 minimum (iOS 18 Control Center control availability-gated). SwiftUI, SwiftData, App Intents, WidgetKit. Swift 6.
- Currency stored as `Decimal` + ISO 4217 code; default `ALL` (lekë, displayed "L"), with `EUR` and crypto symbols supported. Crypto amounts store the native asset amount with an optional fiat snapshot.

## 15. Roadmap / phasing (maps to YouTrack epics)

- **Phase 0 — Scaffold:** `GOL-1` (modular project + CI), `GOL-9` (design system base).
- **Phase 1 — Core capture:** `GOL-2` (data model + sync), `GOL-3` (ingestion + connector framework), `GOL-4` (frictionless capture + entry points), `GOL-10`/`GOL-11` woven throughout (security + tests).
- **Phase 2 — Safety net:** `GOL-5` (CSV statement import).
- **Phase 3 — Insight:** `GOL-7` (subscription detection), `GOL-8` (dashboard & insights).
- **Phase 4 — Extras:** `GOL-6` (read-only crypto).
- `GOL-10` (security & privacy) and `GOL-11` (testing & CI) are cross-cutting and applied in every phase, not deferred to the end.

## 16. Open questions & future work

- **PDF statement parsing** (beyond CSV).
- **Always-on-Mac SMS bridge**: parse Raiffeisen SMS off a synced Mac and feed iOS — a fragile, optional power-user experiment, not MVP.
- **Android build**: the home of true automatic capture (SMS + notification parsing) — the original "it just appears when I pay" dream.
- **Aggregators / Revolut / Wise / PayPal** connectors for a future public product.
- **Budgets & limits.**
- **Public release**: original name + trademark + App Store name-availability check; privacy review.
