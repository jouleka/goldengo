import SwiftUI
import UniformTypeIdentifiers
import GoldengoData
import GoldengoCore
import GoldengoDesignSystem
#if os(iOS)
import UIKit
#endif

public struct SettingsView: View {
    private let store: IngestionStore?
    private let onAuthenticated: () -> Void
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
    @AppStorage(SharedSummary.appLockEnabledKey, store: UserDefaults(suiteName: SharedSummary.appGroupID))
    private var appLockEnabled: Bool = false
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
    @State private var exportShare: FinancialExportShare?
    @State private var exporting = false
    @State private var showingRestorePicker = false
    @State private var restoring = false
    @State private var restoreNotice: String?
    @State private var settingsError: String?
    private let storageStatus: String

    /// Minutes ↔ Date on a fixed reference day — the pickers only ever read hour+minute.
    private static func date(fromMinutes m: Int) -> Date {
        Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0,
                              of: Date(timeIntervalSinceReferenceDate: 0)) ?? .now
    }
    private static func minutes(from date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    public init(store: IngestionStore? = nil, storageStatus: String = "This device",
                onAuthenticated: @escaping () -> Void = {}) {
        self.store = store; self.storageStatus = storageStatus
        self.onAuthenticated = onAuthenticated
    }

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
                    Toggle("Require Face ID", isOn: Binding(
                        get: { appLockEnabled },
                        set: { requested in setAppLock(requested) }
                    ))
                    Toggle("Show amounts on Lock Screen", isOn: $reveal)
                } header: { GoldengoSerifSectionHeader("Privacy") }
                footer: {
                    Text("App Lock protects Goldengo whenever you leave it. Lock Screen amounts stay hidden by default.")
                }
                if let store {
                    Section {
                        NavigationLink { MerchantRulesView(store: store) } label: {
                            Label("Merchant rules", systemImage: "wand.and.stars")
                        }
                        Button { exportData(using: store) } label: {
                            HStack {
                                Label("Export financial data", systemImage: "square.and.arrow.up")
                                Spacer()
                                if exporting { ProgressView() }
                            }
                        }
                        .disabled(exporting)
                        Button { showingRestorePicker = true } label: {
                            HStack {
                                Label("Restore Goldengo backup", systemImage: "arrow.clockwise.icloud")
                                Spacer()
                                if restoring { ProgressView() }
                            }
                        }
                        .disabled(restoring)
                    } header: { GoldengoSerifSectionHeader("Your data") }
                    footer: {
                        Text("Export one complete, portable CSV. Restore merges a Goldengo backup with current data and never deletes newer entries.")
                    }
                }
                Section {
                    LabeledContent("Storage & sync", value: storageStatus)
                    LabeledContent("Entry methods", value: "Manual + statements")
                    LabeledContent("Bank connections", value: "Not connected")
                } header: { GoldengoSerifSectionHeader("Data sources") }
                  footer: {
                      Text("Bank linking is not active in this build. Goldengo never pretends a statement or balance refreshed when it did not.")
                  }
                Section {
                    NavigationLink {
                        CurrencyPickerView(available: availableCurrencies, selectedCode: $preferredCode)
                    } label: {
                        LabeledContent("Default currency", value: preferredLabel)
                    }
                } header: { GoldengoSerifSectionHeader("Preferences") }
                footer: { Text("Used for new expenses and dashboard totals.") }
                Section {
                    NavigationLink {
                        AutomationSetupView(kind: .quickLog)
                    } label: {
                        Label("Quick-log gesture", systemImage: "hand.tap")
                    }
                    NavigationLink {
                        AutomationSetupView(kind: .applePay)
                    } label: {
                        Label("Apple Pay auto-log", systemImage: "creditcard")
                    }
                } header: { GoldengoSerifSectionHeader("Automations") }
                footer: { Text("Optional shortcuts for logging without opening Goldengo.") }
                Section {
                    Toggle("Remind me before a charge", isOn: $remind)
                    if remind {
                        Stepper("Days before: \(leadDays)", value: $leadDays, in: 1...7)
                    }
                    Toggle("Remind me about money owed", isOn: $loanReminders)
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
                } header: { GoldengoSerifSectionHeader("Reminders") }
                footer: { Text("Quiet, local reminders. Turn on only what helps.") }
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
            .sheet(item: $exportShare) { FinancialExportShareSheet(item: $0) }
            .fileImporter(isPresented: $showingRestorePicker,
                          allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
                restoreBackup(result, using: store)
            }
            .alert("Backup restored", isPresented: Binding(
                get: { restoreNotice != nil }, set: { if !$0 { restoreNotice = nil } }
            )) { Button("OK") { restoreNotice = nil } } message: { Text(restoreNotice ?? "") }
            .alert("Couldn’t finish that", isPresented: Binding(
                get: { settingsError != nil }, set: { if !$0 { settingsError = nil } }
            )) { Button("OK") { settingsError = nil } } message: { Text(settingsError ?? "") }
        }
    }

    private func setAppLock(_ requested: Bool) {
        if !requested { appLockEnabled = false; return }
        Task { @MainActor in
            let success = await GoldengoDeviceAuthentication.authenticate(
                reason: "Turn on privacy protection for Goldengo")
            if success {
                appLockEnabled = true
                onAuthenticated()
            } else {
                appLockEnabled = false
                settingsError = "Face ID or device authentication wasn’t completed, so App Lock stayed off."
            }
        }
    }

    private func exportData(using store: IngestionStore) {
        guard !exporting else { return }
        exporting = true
        Task { @MainActor in
            defer { exporting = false }
            do {
                let csv = try await store.exportFinancialDataCSV()
                let stamp = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Goldengo-export-\(stamp).csv")
                try csv.write(to: url, atomically: true, encoding: .utf8)
                exportShare = FinancialExportShare(url: url)
            } catch {
                settingsError = error.localizedDescription
            }
        }
    }

    private func restoreBackup(_ result: Result<URL, Error>, using store: IngestionStore?) {
        guard let store else { return }
        switch result {
        case .failure(let error):
            // Closing the document picker is not a failure worth interrupting the user for.
            if (error as NSError).code != NSUserCancelledError { settingsError = error.localizedDescription }
        case .success(let url):
            guard !restoring else { return }
            restoring = true
            Task { @MainActor in
                defer { restoring = false }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                do {
                    let csv = try String(contentsOf: url, encoding: .utf8)
                    let summary = try await store.restoreFinancialDataCSV(csv)
                    restoreNotice = "Restored \(summary.restored) records. Kept \(summary.skippedExisting) existing records"
                        + (summary.unsupported == 0 ? "." : "; skipped \(summary.unsupported) unsupported rows.")
                } catch {
                    settingsError = error.localizedDescription
                }
            }
        }
    }
}

private enum AutomationSetupKind {
    case quickLog, applePay

    var title: String { self == .quickLog ? "Quick-log gesture" : "Apple Pay auto-log" }
    var subtitle: String {
        self == .quickLog
            ? "Log an expense from Back Tap without opening Goldengo."
            : "Log an in-store card payment automatically after you tap to pay."
    }
    var icon: String { self == .quickLog ? "hand.tap.fill" : "creditcard.fill" }
    var steps: [String] {
        switch self {
        case .quickLog:
            return [
                "In Shortcuts, tap +, choose Add Action, then add Goldengo’s Log Expense action.",
                "Name the shortcut, then open iOS Settings → Accessibility → Touch → Back Tap.",
                "Choose Double Tap or Triple Tap and select your Log Expense shortcut."
            ]
        case .applePay:
            return [
                "In Shortcuts, open Automation, tap +, then choose Transaction and select your card.",
                "Choose Run Immediately and keep Notify When Run on so you get a clear confirmation.",
                "Add Goldengo’s Log Payment action. Pass the transaction Amount and Merchant into it."
            ]
        }
    }
    var footnote: String {
        self == .quickLog
            ? "Apple requires you to choose the Back Tap gesture yourself."
            : "This works for in-store taps. Online Apple Pay payments can still be added by statement import."
    }
}

private struct AutomationSetupView: View {
    let kind: AutomationSetupKind
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: kind.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(GoldengoTheme.accent)
                        .frame(width: 52, height: 52)
                        .background(GoldengoTheme.accentSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    Text(kind.subtitle)
                        .font(.system(size: 15))
                        .foregroundStyle(GoldengoTheme.inkMuted)
                }

                VStack(spacing: 0) {
                    ForEach(Array(kind.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 13) {
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.goldengoBackground)
                                .frame(width: 26, height: 26)
                                .background(GoldengoTheme.accent)
                                .clipShape(Circle())
                            Text(step)
                                .font(.system(size: 14.5, weight: .medium))
                                .foregroundStyle(GoldengoTheme.inkPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 15)
                        if index < kind.steps.count - 1 {
                            Divider().overlay(GoldengoTheme.hairline).padding(.leading, 39)
                        }
                    }
                }
                .goldengoCard(padding: 16)

                Text(kind.footnote)
                    .font(.system(size: 12.5))
                    .foregroundStyle(GoldengoTheme.inkMuted)

                Button {
                    if let url = URL(string: "shortcuts://") { openURL(url) }
                } label: {
                    Label("Open Shortcuts", systemImage: "arrow.up.forward.app.fill")
                        .font(.system(size: 15.5, weight: .bold))
                        .foregroundStyle(Color.goldengoBackground)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(GoldengoTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, GoldengoTheme.Spacing.m)
            .padding(.vertical, 18)
        }
        .background(Color.goldengoBackground.ignoresSafeArea())
        .navigationTitle(kind.title)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}
