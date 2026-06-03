import SwiftUI
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

/// Searchable currency picker: a "Suggested" group (popular ∩ available) then all currencies sorted
/// by name, or a single filtered list while searching. Writes the chosen ISO code to `selectedCode`
/// and pops. Styled to the Goldengo language — gold-tinted symbols, a gold selected-state — and kept
/// cross-platform so it compiles on the macOS CI test build.
struct CurrencyPickerView: View {
    let available: [CurrencyCode]
    @Binding var selectedCode: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private func name(_ c: CurrencyCode) -> String {
        Locale.current.localizedString(forCurrencyCode: c.rawValue) ?? c.rawValue
    }
    private func byName(_ a: CurrencyCode, _ b: CurrencyCode) -> Bool {
        name(a).localizedCaseInsensitiveCompare(name(b)) == .orderedAscending
    }

    private var suggested: [CurrencyCode] {
        let have = Set(available.map(\.rawValue))
        return CurrencyCode.popular.filter { have.contains($0.rawValue) }
    }
    private var others: [CurrencyCode] {
        let pop = Set(CurrencyCode.popular.map(\.rawValue))
        return available.filter { !pop.contains($0.rawValue) }.sorted(by: byName)
    }
    private var results: [CurrencyCode] {
        CurrencyCatalog.filter(available, query: query, name: name).sorted(by: byName)
    }

    var body: some View {
        List {
            if query.isEmpty {
                if !suggested.isEmpty {
                    Section("Suggested") { ForEach(suggested, id: \.rawValue, content: row) }
                }
                Section("All currencies") { ForEach(others, id: \.rawValue, content: row) }
            } else {
                ForEach(results, id: \.rawValue, content: row)
            }
        }
        .searchable(text: $query, prompt: "Search by name or code")
        .navigationTitle("Currency")
    }

    private func row(_ c: CurrencyCode) -> some View {
        let selected = c.rawValue == selectedCode
        return Button {
            selectedCode = c.rawValue
            dismiss()
        } label: {
            HStack(spacing: GoldengoTheme.Spacing.m) {
                Text(c.symbol)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(GoldengoTheme.accent)
                    .frame(width: 34, alignment: .center)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name(c)).foregroundStyle(.primary)
                    Text(c.rawValue).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: GoldengoTheme.Spacing.s)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(GoldengoTheme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
