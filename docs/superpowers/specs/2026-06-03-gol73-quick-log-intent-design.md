# GOL-73 — Quick-log expense via App Intent (note + amount, no app launch)

> **Superseded during implementation.** The shipped quick-log uses a **category tap-list** (not a free-text note), the intent + `AppShortcutsProvider` live in the **app target** (App Shortcuts can't register from a package), and `perform()` returns **no dialog** (silent save). This doc captures the initial design only — see the GOL-73 commits for the final shape.

**Ticket:** [GOL-73](https://mysigner.youtrack.cloud/issue/GOL-73).
**Status:** design approved; pending spec review.
**Date:** 2026-06-03.
**Depends on:** GOL-70/71 (the `ExpenseRecord.note` field + `logManual(note:)`) — shipped.

## Goal

Let the user log an expense from anywhere **without opening the app**, via one trigger of *their own
choosing*. The trigger runs **exactly two system prompts — "What's it for?" then "Amount?" — and
nothing else** — then saves the expense in the user's preferred currency and confirms. As pain-free
as possible.

## Decision record

- **System prompts, not a custom popup.** iOS gives third-party apps no overlay/popup API, so the
  input UI is iOS's own `AppIntent` parameter prompts (an overlay that appears without launching the
  app). This is the only way to capture input "without opening the app." Accepted by the user.
- **Trigger-agnostic — the user picks the gesture, we hardcode none.** The action is exposed via the
  existing `AppShortcut`, so iOS surfaces it in Siri, Spotlight, the Shortcuts app, **Back Tap (double
  or triple), the Action Button, Control Center, and Lock/Home-Screen widgets**. The user binds it to
  whatever they like. We configure no specific trigger (the user was explicit: "gestures are decided
  by the user not us").
- **Exactly two prompts: note then amount.** No category prompt, no currency prompt, no extra step.
  The `category` parameter is removed from the intent; category auto-defaults to **"Other"** (GOL-72)
  and currency is the user's **preferred currency** (`SharedSummary`), both silent.
- **Builds on what exists.** `LogExpenseIntent` is already a background intent (no `openAppWhenRun`)
  that saves via `ExpenseLogging.log` → `logManual`. This story adds the note, drops the category
  prompt, and switches the hardcoded lek to the preferred currency.

## Components

### 1. `ExpenseLogging.log` gains a `note` (GoldengoIntents)

`ExpenseLogging.log` ([ExpenseLogging.swift:7-13](../../../Sources/GoldengoIntents/ExpenseLogging.swift))
adds `note: String?` and forwards it to `logManual(note:)`. The confirmation string appends the note
when present:

```swift
public static func log(amount: Decimal, currencyCode: String, merchant: String?,
                       note: String?, categoryName: String?, store: IngestionStore) async throws -> String {
    let currency = CurrencyCode(currencyCode)
    try await store.logManual(amount: amount, currency: currency,
                              merchant: merchant, note: note, categoryName: categoryName)
    let money = Money(amount: amount, currency: currency).formatted()
    let clean = note?.trimmingCharacters(in: .whitespacesAndNewlines)
    return (clean?.isEmpty ?? true) ? "Logged \(money)" : "Logged \(money) — \(clean!)"
}
```

### 2. `LogExpenseIntent` — note + amount only (GoldengoIntents)

`LogExpenseIntent` ([LogExpenseIntent.swift:13-31](../../../Sources/GoldengoIntents/LogExpenseIntent.swift)):

- Parameters become **`note: String`** (title "What's it for?") and **`amount: Double`** (title
  "Amount"). The `category` parameter is removed.
- A `parameterSummary` orders the prompts note-first: `Summary("Log \(\.$note) for \(\.$amount)")`.
  (The exact prompt order is an App Intents runtime behavior — **verified on device**; if iOS asks
  amount-first, adjust the summary/declaration until it's note → amount.)
- `perform()` reads the preferred currency and saves in the background, returning the confirmation:

```swift
@Parameter(title: "What's it for?") public var note: String
@Parameter(title: "Amount") public var amount: Double

public static var parameterSummary: some ParameterSummary {
    Summary("Log \(\.$note) for \(\.$amount)")
}

@MainActor
public func perform() async throws -> some IntentResult & ProvidesDialog {
    guard let store = IntentEnvironment.storeProvider?() else {
        return .result(dialog: "Goldengo isn't ready yet.")
    }
    let currency = SharedSummary().readPreferredCurrency().rawValue
    let summary = try await ExpenseLogging.log(amount: Decimal(amount), currencyCode: currency,
                                               merchant: nil, note: note, categoryName: nil, store: store)
    return .result(dialog: IntentDialog(stringLiteral: summary))
}
```

(`note` is non-optional so iOS prompts for it; a blank/whitespace note normalizes to `nil` downstream
and the row falls back to category, per GOL-71.)

### 3. `AppShortcut` (GoldengoIntents)

`GoldengoShortcuts` ([GoldengoShortcuts.swift](../../../Sources/GoldengoIntents/GoldengoShortcuts.swift))
already exposes `LogExpenseIntent` with phrases + `shortTitle: "Log Expense"`. **No change needed** —
this is what makes the action bindable to any trigger. (Kept as-is.)

### 4. README — trigger options (docs)

A short "Quick-log (one gesture)" note in the README listing where the user can bind "Log Expense"
(Back Tap, Action Button, Control Center, a widget, Siri) — examples, not a mandate.

## Data flow

```
user-chosen trigger → LogExpenseIntent (background, no app launch)
   → iOS prompts "What's it for?" (note) then "Amount?" (amount)
   → perform(): currency = SharedSummary preferred; ExpenseLogging.log(note:, currency, category: nil)
   → logManual(note:) → ExpenseRecord (category auto "Other")  → widget today-total refresh
   → dialog "Logged L 500 — coffee"
app never enters foreground
```

## Tests

- **`ExpenseLoggingTests` (GoldengoIntentsTests):** `log(amount: 500, currencyCode: "ALL", merchant:
  nil, note: "coffee", categoryName: nil, store:)` against an in-memory store → the stored expense's
  snapshot has `note == "coffee"` (round-trip), and the returned confirmation contains "coffee".
  A whitespace note → stored `nil` and the confirmation omits the dash. *Why: the whole point is that
  the note typed at the trigger reaches the saved expense; and a blank note must not produce a dangling
  "— " confirmation.* Extends the existing `ExpenseLoggingTests`.
- **Intent UI & prompt order (build + device):** the `LogExpenseIntent` parameter prompts, the
  note→amount order, the no-app-launch behavior, and the trigger binding are App-Intents/OS runtime
  behavior — verified by building to device and the user binding a trigger and running it. Not unit-
  testable (the simulator has no Back Tap / Action Button, and prompt UI is system-rendered).

## Runtime verification

Device only. Build + install. The user binds "Log Expense" to a trigger (e.g. Settings → Accessibility
→ Touch → Back Tap → Double Tap → Log Expense, or the Action Button). Trigger it: confirm iOS asks
"What's it for?" then "Amount?", the app does **not** open, the confirmation shows the amount + note,
and the expense appears in Recent (correct note, preferred currency, "Other" category) on next app
open. Second-Opus review over the diff before merge.

## Out of scope

- Any custom-designed popup/overlay (impossible for third-party apps without launching).
- Configuring the trigger for the user (we expose the action; the user binds it).
- An amount-only variant or a third prompt (the user wants exactly note + amount).
- GOL-53 CloudKit activation (deferred at the user's request).
- No `project.rb` change (all edits are in the existing GoldengoIntents package + its test target + the
  README).
