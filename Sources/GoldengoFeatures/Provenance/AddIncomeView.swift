import SwiftUI
import GoldengoDesignSystem
import GoldengoCore

/// Minimal income capture: amount, currency (so a EUR remittance can be logged), source name
/// with suggestions, date.
public struct AddIncomeView: View {
    @State private var model: SourcesModel
    let existingSources: [String]
    let onDone: () -> Void
    @State private var amountString = ""
    @State private var sourceName = ""
    @State private var currencyCode: String
    @State private var date = Date.now
    @FocusState private var amountFocused: Bool

    public init(model: SourcesModel, existingSources: [String], currency: CurrencyCode, onDone: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.existingSources = existingSources
        _currencyCode = State(initialValue: currency.rawValue)
        self.onDone = onDone
    }

    private var amount: Decimal { Decimal(string: amountString) ?? 0 }
    private var canSave: Bool { amount > 0 && !sourceName.trimmingCharacters(in: .whitespaces).isEmpty }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Amount") {
                    TextField("0", text: $amountString)
#if os(iOS)
                        .keyboardType(.decimalPad)
#endif
                        .focused($amountFocused)
                        .font(.title2.weight(.semibold))
                }
                Section("Currency") {
                    Picker("Currency", selection: $currencyCode) {
                        ForEach(CurrencyCode.popular, id: \.rawValue) { c in
                            Text("\(c.symbol)  \(c.rawValue)").tag(c.rawValue)
                        }
                    }
                }
                Section("From") {
                    TextField("Source (e.g. Sister, Freelance)", text: $sourceName)
                    if !existingSources.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: GoldengoTheme.Spacing.s) {
                                ForEach(existingSources, id: \.self) { s in
                                    Button(s) { sourceName = s }
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, GoldengoTheme.Spacing.m).padding(.vertical, 6)
                                        .background(Color.goldengoSurface).clipShape(Capsule())
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                Section("Date") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
            }
            .navigationTitle("Add income")
            .scrollContentBackground(.hidden)
            .background(Color.goldengoBackground.ignoresSafeArea())
            .contentShape(Rectangle())
            .onTapGesture { amountFocused = false }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onDone() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        amountFocused = false
                        Task {
                            await model.addIncome(amount: amount, currency: CurrencyCode(currencyCode),
                                                  sourceName: sourceName)
                            onDone()
                        }
                    }.disabled(!canSave)
                }
            }
        }
    }
}
