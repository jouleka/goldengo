# GOL-82 — The Rhythm Ledger (daily cash-rhythm ghosts)

**Ticket:** [GOL-82](https://mysigner.youtrack.cloud/issue/GOL-82).
**Status:** design approved; pending spec review.
**Date:** 2026-06-09.
**Origin:** standout feature #2 from the post-GOL-80 ultracode ideation (after Provenance/GOL-81).
**Builds on:** the existing `TransactionOccurrence` value type, `MerchantNormalizer`, `IngestionStore.logManual` (auto-category + subscription-link + widget refresh), `RecentExpensesModel`/`RecentExpensesView` (the Home tab).

## Goal

Goldengo learns the cadence of recurring **daily** cash spends (the 200-lek coffee, daily transport) and pre-drafts greyed **"ghost"** entries in a "Today's usuals" strip on Home. The daily logging chore shrinks to a **one-tap confirm** at the learned amount. Only an app whose primary data is cash habits can predict cash habits — bank-sync incumbents only auto-detect recurring *card* data.

## Decision record (brainstorm)

- **Scope = DAILY only** (chosen over daily+weekly and all-cadences). Daily is genuinely new — the existing `SubscriptionDetector` floors at weekly (`5...9` day band) — so there is **zero overlap or pollution** with the Subscriptions tab, and daily spends are where ghost pre-drafting saves the most friction (you log them most). Weekly+ stays with Subscriptions.
- **Engine = a separate, focused `RhythmDetector`** (chosen over adding a `.daily` case to `SubscriptionCadence`, and over extracting a shared generic core). The mature, tested subscription system stays **completely untouched** (Rule 3). The Rhythm Ledger answers a different question ("what daily habit is due *today*?", not "what's the next charge forecast?") and needs its own recency + conservatism tuning. Minor logic overlap (group + median-gap) is acceptable for clean separation.
- **Ghosts are COMPUTED each read, never stored** — so unconfirmed ghosts auto-vanish at day-end, confirmed ones disappear on the next recompute, and there's nothing to desync or expire.
- **Surface = a Home "Today's usuals" strip, one-tap confirm at the median amount** (chosen over tap-opens-editor and opt-in-section). Lowest-tap, proactive. Adjust-before-add is a minimal secondary action; if a 1-tap add is the wrong amount, it's now a normal expense the user edits via the existing Edit flow.
- **`Decimal` math stays in plain Swift**, never in a `#Predicate` (segfault rule). All detection is on-device, no backend.

## Components

### 1. `RhythmDetector` — `Sources/GoldengoCore/RhythmDetector.swift` (pure, the tested core)
No SwiftData/UIKit. Reuses the existing `TransactionOccurrence`.
```
public struct RhythmPattern: Sendable, Equatable, Identifiable {
    public let id: String                 // "<normalizedMerchant>|<currencyCode>"
    public let displayName: String
    public let normalizedMerchant: String
    public let amount: Decimal             // median of recent occurrences (positive)
    public let currency: CurrencyCode
    public let occurrenceCount: Int        // distinct recent days
    public let lastSeen: Date
    public let confidence: Double          // 0...1
}
public enum RhythmDetector {
    public struct Options: Sendable {
        public var windowDays: Int = 21        // recency window
        public var minOccurrences: Int = 6     // distinct days in window
        public var maxGap: Int = 2             // a gap larger than this breaks the daily run
        public var activeWithinDays: Int = 2   // last seen must be this recent ("due today")
        public var minConfidence: Double = 0.6
        public var now: Date = .now
    }
    public static func detect(_ occurrences: [TransactionOccurrence], options: Options = .init()) -> [RhythmPattern]
}
```
**Algorithm:** group by `MerchantNormalizer.normalize(merchant) + currency` (skip empty); collapse same UTC day to one (keep larger amount); keep only occurrences with `date >= now - windowDays`; require `distinctDays >= minOccurrences`; compute consecutive day-gaps; require **median gap == 1** and the majority of gaps `<= maxGap` (an occasional skipped day is fine); require `lastSeen >= now - activeWithinDays` (active/"due today"); compute `confidence = 0.6·regularity + 0.4·occWeight` where `regularity = max(0, 1 - cv(gaps))` and `occWeight = min(1, distinctDays/8)` — the same weighting as `SubscriptionDetector` (chosen over a pure product so a perfectly regular series isn't over-penalized for having few occurrences); keep only `confidence >= minConfidence`. `amount` = median of positive amounts; `displayName` = most-recent non-empty raw merchant. Return sorted by confidence desc. **Conservative by design** — sparse/sporadic/weekly/stale patterns yield nothing.

### 2. Store layer — `Sources/GoldengoData/IngestionStore+Rhythm.swift`
- `RhythmGhost` (Sendable): `id, displayName, amount, currencyCode, categoryName?`.
- `rhythmGhosts(now: Date = .now) throws -> [RhythmGhost]` — fetch non-archived `.expense` records → `TransactionOccurrence` → `RhythmDetector.detect` → **drop any pattern whose merchant already has a non-archived expense dated *today*** (suppress already-logged) → map to `RhythmGhost` (with the learned default category for the merchant). Computed each call; nothing stored.
- `confirmRhythmGhost(_ ghost: RhythmGhost) throws` — `logManual(amount: ghost.amount, currency: CurrencyCode(ghost.currencyCode), merchant: ghost.displayName, categoryName: nil, date: .now)`. The `categoryName: nil` path already resolves the learned merchant default (or "Other"), so confirmed ghosts are categorized exactly like a manual log; reuses subscription-link + widget refresh.
- Both methods are added to the `RecentExpensesReading` protocol (so `RecentExpensesModel` stays decoupled from concrete `IngestionStore`); `IngestionStore` already conforms.

### 3. UI — `Sources/GoldengoFeatures/Recent/` (the Home tab)
- `RecentExpensesModel` gains `public private(set) var ghosts: [RhythmGhost] = []` (loaded in `load()` via `reader.rhythmGhosts(now:)`, non-fatal on error) and `func confirm(_ ghost: RhythmGhost) async` (calls `reader.confirmRhythmGhost`, then `load()`).
- `RecentExpensesView`: a greyed **"Today's usuals"** section above the recent list, shown only when `!model.ghosts.isEmpty`. Each ghost = a row (category icon, "Coffee · ~200 lek", a subtle "tap to add" affordance, reduced opacity to read as a draft). **Tap → `model.confirm(ghost)`** (logs at median, today; the row then disappears via the already-logged filter). A **context menu "Adjust amount…"** opens a minimal amount editor (reusing the QuickAdd keypad styling) to set a different amount before adding. Built with the frontend-design skill; minimalist, low-tap.

## Data flow
```
Home load → RecentExpensesModel.load()
    → reader.rhythmGhosts(now:)
        → fetch non-archived .expense → TransactionOccurrence
        → RhythmDetector.detect (pure, daily, recency-gated, conservative)
        → drop patterns already logged today
    → ghosts: [RhythmGhost]   (greyed "Today's usuals" strip)
tap a ghost → model.confirm(ghost) → reader.confirmRhythmGhost → logManual(median, today)
    → ghost disappears (already-logged filter) on reload; expense on Recent + widget refresh
day rolls over → recompute shows tomorrow's due usuals; today's unconfirmed simply weren't logged
```

## Error handling / edge cases
- Sparse/new data → `detect` returns `[]` → no strip (Home unaffected).
- A failed `rhythmGhosts` load leaves `ghosts` empty and Home still renders (non-fatal, mirrors the existing `loadFailed` philosophy).
- Already logged today (manually or via a prior ghost tap) → that pattern is suppressed, so no double-count.
- A habit that stops → falls out of the recency window / fails the active check within ~2 days → its ghost auto-disappears (no explicit dismiss needed in v1).
- Multiple same-merchant spends in one day → collapsed to one occurrence (daily means one ghost/day); the median amount represents the typical spend.
- Confirm at median when the real amount differs → it's a normal expense afterward; edit via the existing Edit flow (or use "Adjust amount…" before adding).

## Tests
- **`RhythmDetectorTests` (GoldengoCoreTests) — the bulk:** a strong daily series (≥6 recent days, gap 1) is detected with the right median amount + high confidence; **rejected**: weekly (gap 7), sporadic (irregular gaps), too few (<6 days), and **stale** (last seen > activeWithinDays — not "due today"); recency window excludes old occurrences; confidence gating drops a borderline-irregular series. *Why each matters:* a wrong ghost erodes trust — a detector that fires on weekly/sporadic/stale data must fail these (Rule 9).
- **Store tests (GoldengoDataTests):** `rhythmGhosts` surfaces a daily pattern; `rhythmGhosts` **excludes** a pattern already logged today; `confirmRhythmGhost` logs a `.manual` expense at the median with today's date and the learned category.
- **Model test (GoldengoFeaturesTests):** `RecentExpensesModel.load` populates `ghosts`; `confirm` logs and the ghost clears on reload (against an in-memory store).

## Out of scope (explicit, v1)
- Weekly / monthly rhythms (daily only; weekly+ stays with Subscriptions).
- Stored ghosts / a dedicated ghosts screen (computed, surfaced only on Home).
- An explicit "not a usual" dismiss (relies on recency auto-expiry; conservative thresholds keep false positives rare) — noted follow-up.
- A rich adjust-before-add flow (v1 = one-tap-at-median + a minimal amount editor).
- Touching `SubscriptionDetector` / `SubscriptionCadence` / the Subscriptions feature in any way.
