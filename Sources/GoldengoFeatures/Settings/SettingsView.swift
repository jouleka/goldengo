import SwiftUI
import GoldengoData
import GoldengoCore

public struct SettingsView: View {
    @AppStorage(SharedSummary.revealKey, store: UserDefaults(suiteName: SharedSummary.appGroupID))
    private var reveal: Bool = false
    @AppStorage(SharedSummary.remindBeforeChargesKey, store: UserDefaults(suiteName: SharedSummary.appGroupID))
    private var remind: Bool = false
    @AppStorage(SharedSummary.reminderLeadDaysKey, store: UserDefaults(suiteName: SharedSummary.appGroupID))
    private var leadDays: Int = 1
    @AppStorage(SharedSummary.preferredCurrencyKey, store: UserDefaults(suiteName: SharedSummary.appGroupID))
    private var preferredCode: String = "ALL"
    @Environment(\.dismiss) private var dismiss

    public init() {}

    private var availableCurrencies: [CurrencyCode] {
        CurrencyCatalog.selectable(from: ExchangeRateCache().load() ?? SeedRates.table)
    }
    private var preferredLabel: String {
        let c = CurrencyCode(preferredCode)
        let n = Locale.current.localizedString(forCurrencyCode: c.rawValue) ?? c.rawValue
        return "\(c.symbol) · \(n)"
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Currency") {
                    NavigationLink {
                        CurrencyPickerView(available: availableCurrencies, selectedCode: $preferredCode)
                    } label: {
                        LabeledContent("Default currency", value: preferredLabel)
                    }
                    Text("Used as the default for new expenses and your dashboard total.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Privacy") {
                    Toggle("Show amounts on Lock Screen", isOn: $reveal)
                    Text("Off by default — your spending stays hidden on the Lock Screen widget.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Subscriptions") {
                    Toggle("Remind me before a charge", isOn: $remind)
                    if remind {
                        Stepper("Days before: \(leadDays)", value: $leadDays, in: 1...7)
                    }
                    Text("Get a local notification before a confirmed subscription's next charge.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
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
        }
    }
}
