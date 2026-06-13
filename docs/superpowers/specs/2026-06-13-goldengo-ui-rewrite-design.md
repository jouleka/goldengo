# Goldengo UI Rewrite — Design Spec

**Direction:** "Quiet luxe" · **Date:** 2026-06-13 · **Status:** Draft for review

A full rewrite of the **look and the flows** of the Goldengo iOS app, keeping the SwiftUI / native-iOS feel while raising the visual quality to "premium-calm." This document is the single source of truth for the redesign. Implementation is **phased** (§9); each phase gets its own implementation plan and a `swift test`-green checkpoint before the next begins.

---

## 1. Vision & principles

Goldengo should feel like a quiet private-banking app: serene, confident, expensive-feeling, and low-tap. The money is the hero; chrome recedes. We keep every existing behavior and flow — this is a visual + information-architecture rewrite, **not** a behavior change.

Guiding principles (carried from the product's existing philosophy):
- **Money moves through.** One sum, one place, drains once (bank → ATM → wallet → spend). The Wallet visualizes this as draining source pools.
- **Type, don't count. No ceremony.** Logging a spend stays the fastest path in the app.
- **Never fabricate data.** No auto-created records; surface one-tap "ghosts" instead.
- **Calm over flashy.** Restraint reads as premium. Gold is rationed.

---

## 2. Visual identity (locked)

### 2.1 Color

All tokens are `Color(light:dark:)` pairs. The dark theme is a true warm-charcoal counterpart, **not** a dimmed light theme.

| Token | Light | Dark | Use |
|---|---|---|---|
| `canvas` (background) | `#F7F3EA` warm bone | `#17140F` warm charcoal | App background |
| `surface` | `#FCFAF4` warm white | `#211D16` espresso | Elevated cards/rows |
| `field` | `#EFE7D6` warm sand | `#2B261D` | Input fills, keypad keys, chips (unselected) |
| `inkPrimary` | `#2A2620` | `#F3ECDD` cream | Primary text/amounts |
| `inkMuted` | `#8C8373` | `#A89E89` | Secondary text, captions |
| `hairline` | `#E7DECE` | `#322C22` | 1px separators, card strokes |
| `accent` (gold) | `#B68A2E` | `#E0AE4A` | The one brand accent |
| `accentSoft` | gold @ 0.12α | gold @ 0.16α | Selected washes, soft chips |
| `onAccent` | `#2A2620` | `#2A2620` | Label/glyph color on a gold fill (single value; reads on both golds) |
| `danger` | system red | system red | Destructive/delete (semantic, kept) |
| income green | system green | system green | Income inflow amounts in lists (semantic exception, kept) |
| source palette | existing 8-color cycle | existing | Per-source dots & draining bars |

### 2.2 Typography — hybrid

- **Serif voice** — `Font.system(design: .serif)` (SF Serif / "New York"): the **wordmark**, **large screen titles**, and **section headers**. This carries the brand personality.
- **Sans UI** — SF Pro for all body, labels, controls.
- **Amounts** — *every* number renders through one component, `GoldengoAmountText` (see §3): SF Pro, `.monospacedDigit()` (tabular figures), `.weight(.semibold)`, tight tracking, `.contentTransition(.numericText())`. Roles set size: `.hero` (~44pt), `.title` (~28–32pt), `.row` (~17pt), `.micro` (~13pt).

Serif fonts scale with Dynamic Type via `Font.system(design:.serif)` and degrade gracefully where New York is unavailable.

### 2.3 Gold discipline — the one-accent rule (+ semantic exceptions)

Gold is the **only brand/decorative accent**, used sparingly:
- The active tab tint + the center Add FAB.
- The single primary CTA per screen (Save / Add / Done), as a solid gold fill with `onAccent` label.
- Small accent glyphs, the `accentSoft` selected wash, and the toast action label.
- **Never** a gold fill behind large areas.

**Semantic colors are not "accents" and are kept** (they carry meaning, not decoration): `danger` = system red (delete/destructive), income inflow = system green in transaction rows, transfers = `inkMuted`. Affirmative one-shot moments (Import success glyph, Subscriptions "Confirm") use **gold**, since they are brand affirmations, not recurring semantic states.

### 2.4 Motion & haptics

- Springs from the `.snappy` family; never bouncy.
- Amounts animate in place via `.contentTransition(.numericText())`.
- `GoldengoHaptics.spendLanded()` (the two-beat "drop") is preserved byte-for-byte and stays on spend confirms only — **not** added to tab/FAB taps.
- Gentle easing on sheet presentation/dismissal.

---

## 3. Design system foundation (gating layer)

This is **Phase 1** and **gates everything**: no screen reskin begins until the token + component substrate lands and tests are green. File: `Sources/GoldengoDesignSystem/GoldengoTheme.swift` (+ siblings `GoldengoToast.swift`, `GoldengoHaptics.swift`).

### 3.1 New / changed tokens & helpers
- **`Color(light:dark:)` resolver** — does **not** exist in the codebase today (zero usage of `colorScheme`/trait-based color). Build it as an internal `UITraitCollection`-based initializer. This is a prerequisite for the entire dark-mode story.
- Migrate `Color.goldengoBackground` / `goldengoSurface` / `goldengoField` from system-grouped colors to the explicit warm-hex `Color(light:dark:)` pairs above (same public names — no call site breaks).
- Add new tokens on `GoldengoTheme`: `inkPrimary`, `inkMuted`, `hairline`, `onAccent`.
- `accent` becomes `Color(light:#B68A2E, dark:#E0AE4A)`; `accentSoft` becomes `Color(light: gold@0.12, dark: gold@0.16)` — replacing the current single `accent.opacity(0.16)`.
- `Spacing`: keep `xs/s/m/l/xl`; add `xs4/s8/m16/l24/xl32` as **additive aliases** (preserve monotonic ordering the test relies on).
- `Radius.chip(12)/control(16)/card(22)` unchanged.

### 3.2 New shared components (build once, used everywhere)
- **`GoldengoAmountText(_ value, role:)`** — the *single* amount renderer (tabular, semibold, numericText). Mandated app-wide; no screen invents its own amount view.
- **`GoldengoSerifSectionHeader`** — serif `title3` regular, `inkPrimary`. **Do NOT mutate `GoldengoSectionLabel`** — it stays uppercase-caption (QuickAdd "Paid from", Import depend on it). New screens that need the serif voice use this new header.
- **`GoldButton`** — full-width primary CTA: gold fill + `onAccent` label when enabled; `field` fill + `inkMuted` when disabled; `Radius.control`. Replaces the per-screen ad-hoc gold buttons (Morning Save, Evening Done, ReEntry CTA, QuickAdd Add, Wallet Save, AddIncome Add).
- **`AddFAB`** — gold circular center action (~60pt, `accent` fill, `onAccent` plus glyph, soft shadow). Used by the nav shell.
- **`SelectableChip`** — one selected treatment app-wide: `accentSoft` bg + 1px gold hairline + gold label when selected; `field` bg + `inkPrimary` when not. (See decision D4 — this **deviates from the north-star mockup's solid-gold chip**, deliberately, to keep gold rationed.)
- **`DrainingPoolBar`** — `field` capsule track + source-color fill capsule sized by fraction (clamped 0…1), `.animation(.snappy)`. Replaces `ProgressView` on Sources.
- **`GoldGlyphBadge`** — 72pt circle, `accentSoft` fill + hairline stroke, thin gold SF Symbol. Shared by empty/landing covers (Morning, Evening, ReEntry).
- **`GoldengoCardStyle`** — gains a 1px `hairline` stroke over `surface` at `Radius.card`.
- **`View.goldengoDismissKeyboard()`** — shared tap-outside / focus-clear helper. **Never** a keyboard "Done" toolbar (per user rule).
- **`GoldengoToast`** — unchanged behavior; action/icon tint routes through dynamic `accent`. Audit `.regularMaterial` against the flat dark canvas.

### 3.3 Cross-cutting decisions (resolved from critic findings)

| # | Decision |
|---|---|
| D1 | **On-gold color:** one `onAccent` token (`#2A2620`) for every gold-filled CTA/glyph app-wide. |
| D2 | **Subscriptions routing:** present `SubscriptionsView` as a **sheet from Home**. `goldengo://subscriptions`, `onOpenSubscriptions`, and pending-tab `4` all resolve to `selectedTab = 1` (Home) + present the subs sheet. (See §4.2, §4.3.) |
| D3 | **Section headers:** do not mutate `GoldengoSectionLabel`; add `GoldengoSerifSectionHeader`. |
| D4 | **Selected chip:** `accentSoft` + gold hairline + gold label everywhere (QuickAdd, Receipt, EditExpense). Solid gold reserved for primary CTA + FAB + active tab. |
| D5 | **Amounts:** one `GoldengoAmountText(role:)`, used by every screen. |
| D6 | **`accentSoft`:** `Color(light:0.12, dark:0.16)`. |
| D7 | **Sequencing:** land the gold + palette migration and `Color(light:dark:)` resolver **before** any screen reskin. |
| D8 | **Material audit:** verify `GoldengoToast` + tab-bar materials read against dark canvas `#17140F`. |
| D9 | **Semantic colors kept:** red = destructive, green = income inflow, gold = brand/affirmative. Documented so the one-accent rule isn't misapplied to semantic signals. |
| D10 | **Privacy parity:** the in-app pocket hero always shows the real figure (no in-app lock-screen redaction); reuse `PocketFog` phrasing for the non-even fog sublabel. Lock-screen widget keeps `.privacySensitive`. |
| D11 | **`GoldengoControl` glyph:** `plus.circle.fill` → `plus` (visual only); `OpenQuickAddIntent` behavior untouched. |
| D12 | **Test strategy:** replace the single-hex pin with resolved-`cgColor` assertions under fixed light/dark trait collections (see §8). |

### 3.4 Testing impact (Phase 1)
- `test_goldAccentHex_isStable` ([ThemeTests.swift:7](Tests/GoldengoDesignSystemTests/ThemeTests.swift:7)) pins `"#E8B341"` → **must change** to assert the resolved light (`#B68A2E`) / dark (`#E0AE4A`) values. This is a deliberate, surfaced change (Rule 9/12), not silent.
- `test_spacingScale_isMonotonic` — keep passing; new aliases are additive and order-preserving.
- `test_dangerColor_isDistinctFromGoldAccent` — keep passing; compare **resolved** colors under a fixed trait collection.

---

## 4. Information architecture (nav shell)

This is **Phase 2**. File: `Sources/GoldengoFeatures/RootView.swift`.

### 4.1 The 3-tab bar
- **Home** (was tag 1, stays the orienting landing screen) · **Add** (center FAB) · **Wallet**.
- `TabView` cannot natively render a prominent center FAB, so: render a native 2-tab bar (Home, Wallet) and overlay the gold `AddFAB`. **QuickAdd stays a real selectable destination at tag 0** so its `onChange(selectedTab==0) → quickAddModel.loadSources()` contract is preserved; the FAB sets `selectedTab = 0` (or presents the Add sheet) — its `tabItem` is hidden, not removed.
- Active tab tinted gold; inactive `inkMuted`.

### 4.2 Subscriptions folds into Home
- The Subscriptions feature leaves the tab bar and becomes an **"Upcoming" section in Home** (next to "Due" and "today usuals") plus a **full management sheet** (`SubscriptionsView`, with its review/tracked/dismissed states) presented from an Upcoming entry row.
- **Empty state:** the Upcoming serif header is omitted entirely when there are zero confirmed/tracked rows **and** zero review candidates (matches today's hide-when-nil).

### 4.3 Routing & model ownership (critical — prevents silent reminder breakage)
- `route(toTab:)` is updated: the old tag `4` (Subscriptions) and tag `5` (Sources) map into the 3-tab world — `5` → Wallet, `4` → Home + present subs sheet. Deep links (`goldengo://subscriptions`, `goldengo://wallet`), widget taps, and Siri/Control-Center `pendingTab` paths all continue to resolve (no silent no-ops). Existing routing tests' mappings are honored.
- **`SubscriptionsModel` stays owned at root.** Today `load()` → `syncReminders()` is triggered by `onChange(selectedTab==4)`. With tag 4 gone, reminder scheduling would silently stop. Fix: trigger `subsModel.load()` on the cold `.task` **and** on Home appearance (and when the subs sheet opens), so reminder sync keeps firing.

---

## 5. Per-screen specs

Each screen is a visual + structural reskin in the locked system; **all behaviors/flows preserved**. Phases noted.

### Home — `RecentExpensesView` (Phase 3)
- **Composition (top→bottom):** serif "Goldengo" wordmark (gold) → "In your pocket" muted eyebrow → **pocket-balance hero** (`GoldengoAmountText(.hero)`) with currency `Menu` + fog sublabel → today/month figures → serif "Today" section + recent rows → serif "Upcoming" section (Due charges, confirmed subscriptions, review candidates) → recent expenses list.
- **New read path:** pocket balance is not in `RecentExpensesModel`/`HomeData` today (only `pocketSnapshot()` on the store for the widget). Add **read-only** pocket fields to `HomeData` + the `RecentExpensesReading` protocol; Home never writes wallet. Reuse the widget's snapshot path.
- **Components:** `PocketHeroCard`, `GoldengoAmountText`, `GoldengoSerifSectionHeader`, `CurrencyMenuControl` (extracted reusable), `UpcomingRow`, existing `GhostRow`/`expenseRow`/`categoryBar`/`GoldengoToast` (undo).
- **States:** empty (calm panel), loading (pre-fetch placeholder for hero/upcoming), error, redacted N/A in-app (D10). Income amounts stay green; transfers `inkMuted`.
- **Privacy:** hero shows real figure; fog caption reuses `PocketFog` phrasing.

### Subscriptions management sheet — `SubscriptionsView` (Phase 3, with Home)
- Reborn as a sheet from Home's Upcoming entry. Serif section headers via `GoldengoSerifSectionHeader`; `SubscriptionRow` on `goldengoCard`; `GoldengoAmountText` for amounts; `MetaTag` (caption2, muted) for "Not sure yet / Free trial / Amount varies"; existing undo toast unchanged. Sheet detents must let long lists scroll and keep the undo toast floating above the grabber.

### Add (QuickAdd) — `QuickAddView` (Phase 4)
- Opened from the center FAB. Serif "New expense" title → **amount hero** (`GoldengoAmountText(.hero)` ~44pt, replacing today's SF Rounded 64pt — verify long values fit) → currency `Menu` → `SelectableChip` category row (D4 gold-soft selected) → `PaidFromMenu` pill (source-color dot / wallet glyph) → numpad (`field` tiles, `Radius.control`) → `ScanReceiptButton` (iOS + supported only) → `GoldButton` "Add expense". "Added" toast + `spendLanded()` haptic. "Paid from" label keeps `GoldengoSectionLabel` (uppercase).

### Receipt review — `ReceiptReviewView` (Phase 4)
- Serif title + muted subtitle → editable amount hero card (mirrors QuickAdd, editable `TextField` with monospacedDigit) → `FieldRow`s (merchant, date) → `SelectableChip` categories (D4) → gold confirmation Save. "Reading receipt…" hint state. Camera chrome (`DocumentScannerView`) visual only.

### Wallet — `WalletView` + nested `AdjustWalletView` (Phase 5)
- Serif "Wallet" title (as a List row, since `navigationTitle` can't take serif — verify no double title on push). Per-currency `SourceRow` (eyebrow + label / `GoldengoAmountText` + chevron). `TrackCurrencyRow` quiet add-affordance. AdjustWallet: `HeroAmountField` (centered monospacedDigit `TextField`) + `NoteCounterDisclosure` (denomination steppers) + `ResultLine` feedback + `GoldButton` Save. Clearing `List` row chrome carefully so cards don't fight grouped insets.

### Sources — `SourcesView` (Phase 5)
- "In your wallet" entry card + serif "Sources" header + per-source `goldengoCard` with `DrainingPoolBar` + `GoldengoAmountText` remaining + "Unaccounted" card. `ContentUnavailableView` empty state wrapped in a calm card.
- **Add error state (gap fix):** render `SourcesModel.loadFailed` ([SourcesModel.swift:14](Sources/GoldengoFeatures/Provenance/SourcesModel.swift:14)) as a quiet error card distinct from empty, with pull-to-refresh retry. Same for `WalletView`.

### Add income — `AddIncomeView` (Phase 5)
- Serif title → amount hero (`TextField`, gold caret) → `CurrencyPill` (gold-soft; **clear amount focus before navigating** to `CurrencyPickerView`) → two-row selectable cash-in-hand vs bank choice (keeps identical `cashInHand` Bool semantics, bank=false default) → `SuggestionChip`s → gold Add. Moving off `Form` needs bottom `xl32` padding + `.scrollDismissesKeyboard(.interactively)`.

### Edit/Delete expense — `EditExpenseView` (Phase 6)
- Serif title → editable amount hero → currency pill → category & paid-from `SelectableChip` (D4) → date → destructive delete. Keep merchant + note bindings (whether one "Details" card or two — confirm; bindings identical either way). Constrain hero with `minimumScaleFactor` for long/ALL-currency values.

### Statement import — `ImportView` (Phase 6)
- Serif title → `ImportActionRow`s (icon tile + title/subtitle + chevron in `goldengoCard`): choose file / try sample → `ResultCard` (status glyph + serif outcome + tabular counts). Needs an `isImporting` view-local state (loading) and structured imported/deduped counts (extend `ImportModel` to expose ints, or render from existing `result.text` if structured counts are out of scope). Success glyph uses gold (D9). `spendLanded()` on successful landing.

### Settings — `SettingsView` (Phase 6)
- Serif large "Settings" title → warm-bone `Form` (`.scrollContentBackground(.hidden)` + `surface` `.listRowBackground` at `Radius.card`) → `GoldengoSerifSectionHeader`s → gold-tinted `Toggle`/`Stepper`/`DatePicker` (accept native control internals) → `GoldOutlineButton` (Open Shortcuts / iOS Settings) → numbered step labels with gold `N.circle.fill`. Currency row pushes existing `CurrencyPickerView`.

### Currency picker — `CurrencyPickerView` (Phase 6, shared)
- Serif section headers ("Suggested" / "All currencies"); `CurrencyRow` (gold symbol well + name/code + selected gold check); selected row uses `accentSoft` `.listRowBackground` **and** a check (selection not by color alone); `EmptyResultsView` for zero search matches. `#if os(iOS)` guards on iOS-only modifiers (file is cross-platform for macOS CI). **No fake amount** on this screen.

### Morning ritual — `MorningView` (Phase 6)
- `GoldGlyphBadge` (sun) → serif largeTitle prompt → borderless `field` capture row → `GoldButton` Save → quiet "Skip for today" text button. (Disabling Save on empty is a *new* state — confirm vs strict parity; default to keeping today's behavior unless we want the clearer affordance.)

### Evening ritual — `EveningView` + `PastNotesView` (Phase 6)
- `RitualHero` (serif eyebrow + largeTitle) → `IntentionQuoteBlock` (gold-hairline left rule + serif quote) → `UsualGhostRow`s (confirm fires `spendLanded()` then `model.confirm`) → `GoldRecapRow` (spend recap, no judgment) → `GoldButton` Done → "Past notes" quiet button. `PastNotesView`: serif title, per-note muted date + serif quote. Morning/Evening share the same `GoldButton`.

### Re-entry — `ReEntryView` (Phase 6)
- Full-screen `canvas` cover after a multi-day gap. `GoldGlyphBadge` → serif largeTitle → muted body (narrow column) → `GoldButton` "Here's today" (label `onAccent`, not literal black). Verify serif largeTitle + badge spacing on SE at largest Dynamic Type.

---

## 6. Widgets & Control Center (Phase 7)

Files under `Sources/GoldengoIntents` (`GoldengoWidget`, `PocketWidget`, `GoldengoControl`, `OpenQuickAddIntent`).
- The widget extension may not link `GoldengoDesignSystem` — mirror the **locked** tokens in a local `WidgetTheme.swift` (avoids a framework dependency). Use the locked gold values, not the old `#E8B341`.
- Lock-screen accessory + Control Center render monochrome/vibrancy-tinted: gold/ink won't show there — only the home-screen `systemSmall` tile reflects the full palette. Set expectations accordingly.
- `GoldengoControl` glyph `plus.circle.fill` → `plus` (visual only, D11). `OpenQuickAddIntent` and `displayName`/`description` untouched.
- `PocketWidget` keeps `.privacySensitive` + hidden/revealed `PocketPayload` strings + `PocketFog`.

---

## 7. Accessibility & dark mode (cross-cutting requirements)

- **Dark mode** rides entirely on the new `Color(light:dark:)` resolver (Phase 1). No raw `.black`/`.white` foregrounds — use `onAccent`/`inkPrimary`/`inkMuted`. Audit `.regularMaterial` surfaces against dark canvas (D8).
- **VoiceOver/labels:** `AddFAB` → `accessibilityLabel("Add expense")`; `DrainingPoolBar` → label (source name) + `accessibilityValue` (percent remaining); tab items labeled; selected states never color-only (D4 includes hairline+check).
- **Dynamic Type:** serif titles scale; amount heroes use `minimumScaleFactor` for long values + ALL/large currencies; test largest type on SE.

---

## 8. Testing

- Update `ThemeTests` per D12 (resolved cgColor under fixed trait collections); keep spacing-monotonic and danger≠gold green.
- New tests: routing — `goldengo://subscriptions` / `onOpenSubscriptions` / pending-tab 4 → Home + subs sheet; FAB tap → `selectedTab==0` → `loadSources` fires; pocket-hero read path returns expected snapshot; `SubscriptionsModel.syncReminders()` still fires under the new trigger.
- Preserve existing pinned test `a3992bc` (wallet-change → published-claim path).
- **SwiftData caution (project memory):** never compare `Decimal` inside a `#Predicate` (SIGSEGV under load) — filter `Decimal` in memory after the fetch. Run full `swift test` at every checkpoint.

---

## 9. Phased implementation roadmap

Each phase = its own implementation plan + a `swift test`-green checkpoint before the next.

1. **Foundation (gating)** — palette + `Color(light:dark:)` + `accentSoft`/`onAccent`/ink/hairline tokens + Spacing aliases + `GoldengoAmountText` + `GoldengoSerifSectionHeader` + `GoldButton` + `GoldGlyphBadge` + `goldengoDismissKeyboard` + `GoldengoCardStyle` stroke + ThemeTests update.
2. **Nav shell** — RootView 3-tab + `AddFAB` + routing redirects + subs-sheet host + `SubscriptionsModel` ownership/reminder-sync trigger + routing tests.
3. **Home** — pocket-hero read path, sections (Due/Upcoming/today/recents), empty/loading/error, privacy fog.
4. **Add + Receipt** — QuickAdd, Receipt review, scanner chrome.
5. **Wallet + Sources + Income** — Wallet/AdjustWallet, Sources + `DrainingPoolBar`, error states, Add income.
6. **Secondary sheets** — Edit, Import, Settings, Currency picker, Morning, Evening/PastNotes, Re-entry.
7. **Widgets + Control** — WidgetTheme mirror, glyph tweak, parity.

---

## 10. Risks & open questions

- **Hero font shrink** (QuickAdd 64pt → ~44pt): must fit long values + ALL/large currencies — verify on device.
- **`List` vs custom cards**: clearing grouped chrome (`listRowBackground`/insets/separators) without double-insets across iOS versions.
- **Serif nav titles**: faked as rows; verify scroll/pin and no duplicate inline bar title on push.
- **Material on dark canvas**: confirm toast + tab bar legibility (D8).
- **Open for confirmation (decided, flag if wrong):** (a) selected chips are gold-soft, not solid gold — deviates from the north-star mockup (D4); (b) income stays **green** as a semantic exception (D9); (c) "Goldengo" shown as a literal serif wordmark on Home.

## 11. Non-goals

- No new features; no flow/behavior changes beyond the IA folding (Subscriptions → Home) and its routing.
- No third-party fonts (system serif only).
- No data-model changes except the **read-only** pocket fields Home needs.
