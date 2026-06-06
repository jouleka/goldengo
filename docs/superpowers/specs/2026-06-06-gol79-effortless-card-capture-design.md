# GOL-79 — Effortless card-swipe capture (Share-to-Goldengo import + cross-source dedup)

**Ticket:** [GOL-79](https://mysigner.youtrack.cloud/issue/GOL-79).
**Status:** design — pending spec review.
**Date:** 2026-06-06.
**Interacts with:** GOL-77 (Apple Pay auto-log — this spec re-points its `ExpenseSource` and dedupes against it). Reuses `GoldengoImport` (`StatementImporter`, `RaiffeisenAlbaniaParser`, `PDFTextExtractor`) and `IngestionStore.importStatement`.

## Goal

The user asked: "every time I swipe my card, automatically track it in Goldengo." Deliver the **honest, achievable** version of that: capturing physical card-swipe spend should feel near-effortless — globally, and specifically for the user in Albania (lek / ALL) — **with no backend**.

## Feasibility & decision record (researched, verified against live sources 2026-06-05)

A physical card swipe goes card → terminal → network → issuing bank; **it never touches the iPhone**, and iOS gives a third-party app **no way to read SMS or other apps' notifications**. Real-time, at-the-moment-of-swipe auto-capture of an external card is therefore **not possible on iOS**. Each candidate mechanism was checked against authoritative sources and ruled out:

- **On-device detection** — impossible; the phone isn't a party to the transaction.
- **Reading the bank's SMS/push** — this is exactly how Android expense apps work (`READ_SMS`); iOS forbids it. The one workaround (Shortcuts *Message* personal automation, sibling of the GOL-77 *Transaction* automation) **fails on three verified points**: it does not pass the message body to the shortcut ("automations work as a trigger but don't return the body" — [Apple Developer Forums](https://developer.apple.com/forums/thread/705659)), it reportedly fires only for iMessage not the SMS banks send ([Apple Community](https://discussions.apple.com/thread/255575030)), and it can't target a bank's short-code sender ([Apple Support](https://support.apple.com/guide/shortcuts/communication-triggers-apdd711f9dff/ios)). Building on it would violate the project's no-hallucinated-APIs rule.
- **FinanceKit** — US/UK only; exposes Apple Card/Cash/Savings (US) or a fixed UK open-banking bank list. Cannot read arbitrary external physical-card swipes; not available in Albania. ([developer.apple.com/financekit](https://developer.apple.com/financekit/))
- **Issuer-processor / card-network APIs** (Marqeta, Galileo, Stripe Issuing) — real-time auth webhooks exist **only for cards you issue yourself**. Cannot attach to a user's existing bank card. ([Stripe Issuing docs](https://docs.stripe.com/issuing/purchases/authorizations))
- **Open-banking aggregators** (Plaid, TrueLayer, Tink, Yodlee, MX, Finicity, GoCardless) — deliver **posted/settled** data via polling (1–4×/day, pending→posted hours-to-days), **all require a server-side backend**, and (below) do not cover Albania.

### Per-region verdict

- **Covered regions (US/CA/EU/UK):** automated *near-real-time bank sync* is feasible via an aggregator — but only with a backend, and it captures **delayed posted** transactions, never the live swipe. **Not built here** (see Out of scope).
- **Albania (the user's region): no aggregator coverage — verified, not assumed.** Salt Edge's own API returns 46 supported countries with **AL absent** (`/providers?country_code=AL` empty); GoCardless's full 2,954-bank / 31-country coverage sheet has **zero Albanian rows**; Tink, TrueLayer, Plaid, Yodlee, Finicity, MX, Yapily, Enable Banking — none cover Albania. The only automated route is direct per-bank NextGenPSD2 integration (Raiffeisen/Intesa/Union/BKT run live portals) requiring an **AISP licence + per-bank engineering** — an enterprise effort, not viable for this app. Albania's SEPA join (Oct 2025) is *payments*, not data access.
- **Therefore the capture path that works globally AND in Albania today is statement import** (the repo already ships `RaiffeisenAlbaniaParser`), made low-friction, complemented by the existing GOL-77 Apple Pay auto-log and manual quick-add.

### Backend question — resolved

**No backend.** This feature is entirely on-device (SwiftData + App Group). No API secrets, no per-user tokens, no webhook receiver. This keeps Goldengo's local-only architecture intact and sidesteps the cost/privacy/App-Review burden an aggregator would impose.

### Latency reality (set user expectation)

Capture is **near-effortless, not instantaneous**: the user performs one deliberate "Share" action; a statement reflects **posted** transactions (a day or more after the swipe). "Instant at the swipe" is not on the table for external cards on iOS — that was verified, not assumed.

## Architecture

Two independent, on-device units that meet only at `IngestionStore`. **No new app target and no `project.rb` run** (so Xcode-managed signing stays intact — see the project's signing gotcha).

- **Unit A — "Share to Goldengo" intake.** New surface area: a few `Info.plist` keys + an `.onOpenURL` handler + routing to the existing `ImportView`. All parsing/persistence is reused unchanged.
- **Unit B — cross-source reconciliation.** A conservative, attribute-based dedup so a purchase arriving via Apple Pay auto-log and via an imported statement collapses to one record — without ever hiding a hand-entered expense.

## Unit A — Share to Goldengo (one-tap statement import)

**Flow:** In the bank app / email / Files, **Share → Goldengo** (or "Open in Goldengo"). iOS hands the app the file URL → Goldengo opens, runs the existing importer, and shows the existing result card ("Imported 23, skipped 4 duplicates").

**Pieces:**
1. **`AppProject/Goldengo/Info.plist`** (a real file that `project.rb` does **not** manage → safe to edit by hand; no project regeneration): declare `CFBundleDocumentTypes` for PDF (`com.adobe.pdf`), CSV (`public.comma-separated-values-text`), and plain text (`public.plain-text`), plus `LSSupportsOpeningDocumentsInPlace`. This is what makes Goldengo appear as a statement handler in the Share Sheet / "Open in".
2. **`AppProject/Goldengo/GoldengoApp.swift`** (existing, ~39 lines → small edit): add `.onOpenURL { url in … }` to the `WindowGroup`, handing the URL to a router. Must work both cold-launch and already-open.
3. **Routing & presentation:** the router applies the same security-scoped-resource access + 10 MB guard pattern as `ImportView`'s `fileImporter`, then calls the existing `ImportModel.importPDF(url:fileName:)` / `importCSV(text:fileName:)`. It presents the existing `ImportView` as a sheet from the root and **runs the import on the shared file immediately**, so the user lands on the result card ("Imported X, skipped Y" — or a recognized error) rather than an empty picker. The lek-currency assumption stays visible, never silent. No new parsing, no new persistence.

**Trade-offs / honesty:** still user-initiated (one deliberate Share, not magic); depends on the bank providing a PDF/CSV. The only item needing on-device verification is that Goldengo appears in the Share Sheet and `onOpenURL` fires — a normal device test, not a feasibility risk.

## Unit B — cross-source reconciliation (the dedup)

**The honest core problem.** The same purchase via Apple Pay auto-log vs. via statement import has **no shared transaction ID**, a **different date** (Apple Pay logs at *swipe* time; the statement uses the *posting* date, often +1–4 days), and a **different merchant string** (automation name vs. bank text). The existing exact-composite-key merge (`NormalizedTransaction.dedupeKey`) cannot catch this; only attribute matching can, and naive matching can false-merge two genuine same-amount purchases.

**Principle (decides every tie):** in a budgeting app, *hiding* an expense (false-merge → user thinks they spent less) is far worse than a leftover *duplicate* (visible and one-swipe-deletable). **Merge only on high confidence; when unsure, keep both.**

**Mechanism:**
1. **Add `ExpenseSource.automatic`** to `GoldengoCore/ExpenseSource.swift` (the enum is `String, CaseIterable`; current cases `manual, imported, crypto`). Add a logging entry point that records source `.automatic` (e.g. `IngestionStore.logAutomatic(...)`, sharing `logManual`'s internals but with `source = .automatic` and a unique `"auto:<UUID>"` key — each tap is its own record, never key-collapsed). Re-point GOL-77's Apple Pay path (`ExpenseLogging.log` / `LogPaymentIntent` in the existing `QuickLogShortcut.swift`) at it. This makes auto-captured payments distinguishable from hand-typed ones — the prerequisite for safe dedup — and lets the UI honestly label "auto-logged" vs "added by you." GOL-77 is still "To Verify," so this is a clean moment to adjust it; any pre-existing `.manual` test entries simply stay `.manual` (no migration).
2. **Reconcile at import**, inside `IngestionStore.ingest(_:source:)` for `source == .imported`: when the existing dedupeKey lookup misses, run a cross-source lookup for a recent **`.automatic`** record matching on **all** of:
   - same `currencyCode`,
   - **exact** `amount` (no rate conversion),
   - normalized-merchant match via the existing `MerchantNormalizer.normalize` (non-empty on both sides),
   - posting date within `swipeDay ≤ postingDay ≤ swipeDay + 4` (day granularity, UTC, matching `dedupeKey`'s formatter),
   - same `kind` (expense).
   If found → **reuse the existing merge** (provenance becomes `.imported`, first-seen amount/date/currency preserved, category/subscription links kept, `updatedAt` bumped) and return `.merged`. If not → insert (a visible, deletable possible-duplicate).
3. **Hard guardrails:** only `imported → automatic` ever auto-merges. **Never** auto-merge into a `.manual` entry (user-asserted truth) and **never** merge two `.automatic` entries. A statement row merges into **at most one** `.automatic` record (the earliest in-window); a consumed record is not matched twice within the same import. The candidate fetch is bounded to `.automatic` records within the statement's date range ± the window.
4. **Resolve the stale comment:** `NormalizedTransaction.dedupeKey`'s doc comment claims a manual entry and its later-imported row "collapse to one record," but `logManual` deliberately uses a unique key so they don't (to preserve distinct same-day purchases). This spec sides with `logManual`'s behavior (the tested, intended one) and updates the comment to match — manual entries are never auto-reconciled.

**Mode:** auto-merge only. No "review duplicates" UI (medium-confidence cases remain as separate, deletable entries).

### Dedup across all three sources (explicit)

| Incoming → existing | Behavior |
|---|---|
| imported → imported | Merge on exact composite `dedupeKey` (**existing**, unchanged). |
| imported → automatic | **NEW:** merge only on high-confidence attribute match (rule above). |
| imported → manual | Never auto-merge (user truth; stays as-is). |
| automatic → automatic | Never merge (distinct taps; unique keys). |
| automatic → imported | Out of scope here (auto-log fires live, before the statement exists; the statement arrives later and reconciles via "imported → automatic"). |
| manual → anything | Never merged (unique key; unchanged). |

## Data flow

```
Unit A:  bank app/email/Files → Share → Goldengo
   → onOpenURL(url) → security-scoped access + 10 MB guard
   → ImportModel.importPDF/CSV → StatementImporter → IngestionStore.importStatement
   → per-row ingest(source: .imported)  [Unit B runs here]
   → ImportView result card ("Imported X, skipped Y") + widget today-total refresh

Unit B (inside ingest, source == .imported, after dedupeKey miss):
   find recent .automatic record: same currency + exact amount + normalized-merchant
       + postingDay in [swipeDay, swipeDay+4] + kind == expense
   → match → reuse existing merge (→ .merged)
   → no match → insert (.inserted)
```

## Error handling & edge cases

- **Unit A:** unreadable encoding, >10 MB, "no transactions recognized," and security-scoped access are already handled by `ImportView`/`ImportModel` and reused verbatim. `onOpenURL` handles cold-launch and already-open; multiple shared files are processed one at a time. The lek-default currency is shown in the confirmation.
- **Unit B:** currency must match exactly (10 EUR ≠ 10 ALL); empty/blank merchant never satisfies the match; one-to-one merge (earliest in-window); bounded candidate fetch; runs on the existing `@ModelActor IngestionStore` (same save path + widget refresh). Out-of-window or fuzzy-merchant matches deliberately fall through to a kept duplicate.

## Tests (TDD — each encodes *why*)

`GoldengoDataTests` (Unit B — the heart):
- **High-confidence merge:** `.automatic` (day D, 1500 ALL, "Spar") + import (D+2, 1500 ALL, "SPAR TIRANA") → **one** record, source `.imported`. *Why: the same purchase from two paths must not double-count.*
- **No false-merge of recurring spend:** two `.automatic` 300 ALL "Coffee" on D and D+1; import **one** 300 ALL coffee (D+2) → merges into **at most one**; the other survives; total count reflects every distinct purchase. *Why: never hide a real expense by collapsing distinct same-amount purchases.*
- **Never touch manual:** hand-typed `.manual` 1500 ALL "Spar" + matching import → **both kept**, manual untouched. *Why: user-asserted entries are truth.*
- **Currency guard:** `.automatic` 10 EUR vs import 10 ALL (same merchant/date) → **not merged**. *Why: same number, different money.*
- **Date-window guard:** `.automatic` swipe D vs import posting D+6 → **not merged** (kept duplicate). *Why: bias to a deletable duplicate over a hidden expense when timing is implausible.*
- **No regression:** existing import↔import composite-key dedup still passes.

`GoldengoFeaturesTests` / `GoldengoDataTests` (Unit A):
- URL → import routing produces the correct `ImportSummary` for a CSV and a PDF (parsing already covered by existing importer tests; Share-Sheet appearance is device-verified, not unit-tested).

## Runtime verification (device)

Build + install on device. Verify: (1) sharing a real bank PDF/CSV (incl. a Raiffeisen Albania statement) shows Goldengo in the Share Sheet, opens it, and imports with the correct result; (2) an Apple Pay auto-logged purchase that later appears on an imported statement shows as **one** entry; (3) a hand-typed entry matching a statement row stays as two. Second-Opus review over the diff.

## Out of scope

- **Open-banking bank sync / aggregators / any backend** (Plaid/TrueLayer/Tink/Salt Edge/etc.) — no Albania coverage and a server is required; deferred indefinitely.
- **FinanceKit** (US/UK + Apple cards only) and **issuing our own card** (regulated neobank product, unavailable from Albania).
- **SMS/notification-triggered auto-logging** — blocked by iOS (body not passed, iMessage-only, no notification API).
- **"Review duplicates" UI** and **medium-confidence merging** — auto-merge-only for v1.
- **Manual ↔ import auto-merge**, **cross-currency merging**, and **mixed-currency statements** — unchanged existing behavior.
- A true Share **Extension** (custom share UI / new target) — the document-types + `onOpenURL` path avoids the signing gotcha.

## Open questions / risks

- **GOL-77 coupling:** re-pointing the Apple Pay path to `.automatic` is a one-line behavior change to an unverified ticket; low risk, improves provenance. Flag in the GOL-77 verification.
- **Share-Sheet UTI coverage:** some banks export statements with generic/`public.data` types; if Goldengo doesn't appear for a given file, the in-app `fileImporter` remains the fallback. Verify with the user's actual bank export on device.
