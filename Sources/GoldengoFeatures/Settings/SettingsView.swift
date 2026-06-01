import SwiftUI
import GoldengoData

public struct SettingsView: View {
    @AppStorage(SharedSummary.revealKey, store: UserDefaults(suiteName: SharedSummary.appGroupID))
    private var reveal: Bool = false
    @AppStorage(SharedSummary.remindBeforeChargesKey, store: UserDefaults(suiteName: SharedSummary.appGroupID))
    private var remind: Bool = false
    @AppStorage(SharedSummary.reminderLeadDaysKey, store: UserDefaults(suiteName: SharedSummary.appGroupID))
    private var leadDays: Int = 1

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
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
            // Enabling only requests permission here; the actual reminders are scheduled the next
            // time the Subscriptions tab loads (SubscriptionsModel.syncReminders). Disabling clears
            // immediately, and a later load's sync([]) is a belt-and-suspenders clear.
            .onChange(of: remind) { _, on in
                Task {
                    if on { await LocalNotificationScheduler.requestAuthorization() }
                    else { await LocalNotificationScheduler.cancelAll() }
                }
            }
        }
    }
}
