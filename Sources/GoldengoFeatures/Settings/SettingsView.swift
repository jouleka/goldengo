import SwiftUI
import GoldengoData
import GoldengoCore
import GoldengoDesignSystem
#if os(iOS)
import UIKit
#endif

public struct SettingsView: View {
    @AppStorage(SharedSummary.revealKey, store: UserDefaults(suiteName: SharedSummary.appGroupID))
    private var reveal: Bool = false
    @AppStorage(SharedSummary.remindBeforeChargesKey, store: UserDefaults(suiteName: SharedSummary.appGroupID))
    private var remind: Bool = false
    @AppStorage(SharedSummary.reminderLeadDaysKey, store: UserDefaults(suiteName: SharedSummary.appGroupID))
    private var leadDays: Int = 1
    @AppStorage(SharedSummary.preferredCurrencyKey, store: UserDefaults(suiteName: SharedSummary.appGroupID))
    private var preferredCode: String = "ALL"
    @AppStorage(SharedSummary.ritualEnabledKey, store: UserDefaults(suiteName: SharedSummary.appGroupID))
    private var ritualEnabled: Bool = false
    // Opt-OUT (default true): a lent debt silently forgotten is the failure mode the
    // lending feature exists to prevent. Must match SharedSummary.loanRemindersEnabled().
    @AppStorage(SharedSummary.loanRemindersKey, store: UserDefaults(suiteName: SharedSummary.appGroupID))
    private var loanReminders: Bool = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    // GOL-93: nudge-time pickers (minutes-from-midnight in SharedSummary; Dates only for the UI)
    // and the quiet "notifications are off" hint.
    @State private var morningNudge: Date = SettingsView.date(fromMinutes: SharedSummary().ritualMorningMinutes())
    @State private var eveningNudge: Date = SettingsView.date(fromMinutes: SharedSummary().ritualEveningMinutes())
    @State private var notificationsDenied = false
    /// Selectable currencies, decoded once on appear (the picker NavigationLink destination is built
    /// in body, so the computed form re-read UserDefaults + re-decoded on every Settings render).
    @State private var selectableCurrencies: [CurrencyCode] = []

    /// Minutes ↔ Date on a fixed reference day — the pickers only ever read hour+minute.
    private static func date(fromMinutes m: Int) -> Date {
        Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0,
                              of: Date(timeIntervalSinceReferenceDate: 0)) ?? .now
    }
    private static func minutes(from date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    public init() {}

    private var availableCurrencies: [CurrencyCode] { selectableCurrencies }
    private var preferredLabel: String {
        let c = CurrencyCode(preferredCode)
        let n = Locale.current.localizedString(forCurrencyCode: c.rawValue) ?? c.rawValue
        return "\(c.symbol) · \(n)"
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        CurrencyPickerView(available: availableCurrencies, selectedCode: $preferredCode)
                    } label: {
                        LabeledContent("Default currency", value: preferredLabel)
                    }
                    Text("Used as the default for new expenses and your dashboard total.")
                        .font(.caption).foregroundStyle(GoldengoTheme.inkMuted)
                } header: { GoldengoSerifSectionHeader("Currency") }
                Section {
                    Text("Log an expense without opening Goldengo — a gesture pops up a category list, then the amount. Set it up once:")
                        .font(.caption).foregroundStyle(GoldengoTheme.inkMuted)
                    Button {
                        if let url = URL(string: "shortcuts://") { openURL(url) }
                    } label: {
                        Label("Open Shortcuts", systemImage: "square.stack.3d.up.fill")
                            .foregroundStyle(GoldengoTheme.accent)
                    }
                    Label("In Shortcuts: tap ＋, **Add Action**, search **Log Expense**, add it, then name it and tap Done.", systemImage: "1.circle.fill")
                    Label("Then **Settings ▸ Accessibility ▸ Touch ▸ Back Tap ▸ Double (or Triple) Tap** → choose **Log Expense**.", systemImage: "2.circle.fill")
                    Text("Only you can assign the gesture (step 2) — iOS doesn't let apps set Back Tap.")
                        .font(.caption).foregroundStyle(GoldengoTheme.inkMuted)
                } header: { GoldengoSerifSectionHeader("Quick-log gesture") }
                Section {
                    Text("Auto-add an expense every time you tap to pay in a store — set up an iOS automation once:")
                        .font(.caption).foregroundStyle(GoldengoTheme.inkMuted)
                    Button {
                        if let url = URL(string: "shortcuts://") { openURL(url) }
                    } label: {
                        Label("Open Shortcuts", systemImage: "creditcard")
                            .foregroundStyle(GoldengoTheme.accent)
                    }
                    Label("Shortcuts → **Automation** tab → **＋** → **Transaction** → pick your card(s) → choose **Run Immediately** and turn **Notify When Run** on (that's your no-tap 'Logged' banner).", systemImage: "1.circle.fill")
                    Label("**Add Action** → search **Log Payment** → set **Amount** to the transaction's Amount (and **Merchant** to its Merchant) → Done.", systemImage: "2.circle.fill")
                    Text("In-store taps only — online/web Apple Pay can't trigger it (use Import for those). iOS won't let an app set this up for you.")
                        .font(.caption).foregroundStyle(GoldengoTheme.inkMuted)
                } header: { GoldengoSerifSectionHeader("Apple Pay auto-log") }
                Section {
                    Toggle("Show amounts on Lock Screen", isOn: $reveal)
                    Text("Off by default — your spending stays hidden on the Lock Screen widget.")
                        .font(.caption).foregroundStyle(GoldengoTheme.inkMuted)
                } header: { GoldengoSerifSectionHeader("Privacy") }
                Section {
                    Toggle("Remind me before a charge", isOn: $remind)
                    if remind {
                        Stepper("Days before: \(leadDays)", value: $leadDays, in: 1...7)
                    }
                    Text("Get a local notification before a confirmed subscription's next charge.")
                        .font(.caption).foregroundStyle(GoldengoTheme.inkMuted)
                } header: { GoldengoSerifSectionHeader("Subscriptions") }
                Section {
                    Toggle("Remind me about money owed", isOn: $loanReminders)
                    Text("A quiet nudge when someone has owed you money for a month.")
                        .font(.caption).foregroundStyle(GoldengoTheme.inkMuted)
                } header: { GoldengoSerifSectionHeader("Money owed") }
                Section {
                    Toggle("Morning + evening check-in", isOn: $ritualEnabled)
                    if ritualEnabled {
                        DatePicker("Morning nudge", selection: $morningNudge,
                                   in: Self.date(fromMinutes: 5 * 60)...Self.date(fromMinutes: 11 * 60 + 45),
                                   displayedComponents: .hourAndMinute)
                        DatePicker("Evening nudge", selection: $eveningNudge,
                                   in: Self.date(fromMinutes: 18 * 60)...Self.date(fromMinutes: 23 * 60 + 45),
                                   displayedComponents: .hourAndMinute)
                        if notificationsDenied {
                            // Quiet remediation, never a scold: the sheets still self-present on open.
                            Text("Notifications are off — check-ins won't nudge you.")
                                .font(.caption).foregroundStyle(GoldengoTheme.inkMuted)
                            Button("Open iOS Settings") {
                                #if os(iOS)
                                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                    openURL(url)
                                }
                                #endif
                            }
                            .foregroundStyle(GoldengoTheme.accent)
                            .font(.caption)
                        }
                    }
                    Text("A morning intention you set for yourself, surfaced back to you at night with a calm recap. Two gentle nudges a day.")
                        .font(.caption).foregroundStyle(GoldengoTheme.inkMuted)
                } header: { GoldengoSerifSectionHeader("Daily check-in") }
            }
            .tint(GoldengoTheme.accent)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // Enabling requests notification permission; if it isn't granted we flip the toggle back
            // off so it never claims to be on while no reminder could ever fire. Actual reminders are
            // scheduled the next time the Subscriptions tab loads (SubscriptionsModel.syncReminders).
            // Disabling clears immediately; a later load's sync([]) is a belt-and-suspenders clear.
            .onChange(of: remind) { _, on in
                Task { @MainActor in
                    if on {
                        if await LocalNotificationScheduler.requestAuthorization() == false { remind = false }
                    } else {
                        await LocalNotificationScheduler.cancelAll()
                    }
                }
            }
            // Enabling requests notification permission then schedules the two daily nudges; if
            // permission is denied we leave the toggle ON (the screens still self-present on app
            // open — notifications are just a bonus). Disabling cancels only the ritual requests.
            .onChange(of: ritualEnabled) { _, on in
                Task { @MainActor in
                    if on {
                        await LocalNotificationScheduler.requestAuthorization()
                        await LocalNotificationScheduler.scheduleRitual()
                        notificationsDenied = await LocalNotificationScheduler.authorizationDenied()
                    } else {
                        await LocalNotificationScheduler.cancelRitual()
                    }
                }
            }
            // GOL-93: persist a picked nudge time (clamped to its window) and re-register both
            // nudges — same notification ids, so re-scheduling replaces cleanly.
            .onChange(of: morningNudge) { _, picked in
                SharedSummary().setRitualMorningMinutes(RitualPolicy.clampMorningNudge(minutes: Self.minutes(from: picked)))
                Task { await LocalNotificationScheduler.scheduleRitual() }
            }
            .onChange(of: eveningNudge) { _, picked in
                SharedSummary().setRitualEveningMinutes(RitualPolicy.clampEveningNudge(minutes: Self.minutes(from: picked)))
                Task { await LocalNotificationScheduler.scheduleRitual() }
            }
            .task { notificationsDenied = await LocalNotificationScheduler.authorizationDenied() }
            .onAppear { selectableCurrencies = CurrencyCatalog.selectable(from: ExchangeRateCache().load() ?? SeedRates.table) }
        }
    }
}
