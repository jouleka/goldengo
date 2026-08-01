import SwiftUI
import Observation
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

@MainActor
@Observable
final class MerchantRulesModel {
    let store: IngestionStore
    private(set) var rules: [MerchantRuleSnapshot] = []
    var errorText: String?

    init(store: IngestionStore) { self.store = store }

    func load() async {
        do { rules = try await store.merchantRules(); errorText = nil }
        catch { errorText = error.localizedDescription }
    }
    func save(merchant: String, category: String) async {
        do { try await store.setMerchantRule(merchantName: merchant, categoryName: category); await load() }
        catch { errorText = error.localizedDescription }
    }
    func delete(_ rule: MerchantRuleSnapshot) async {
        do { try await store.deleteMerchantRule(id: rule.id); await load() }
        catch { errorText = error.localizedDescription }
    }
}

struct MerchantRulesView: View {
    @State private var model: MerchantRulesModel
    @State private var editing: MerchantRuleSnapshot?
    @State private var showAdd = false

    init(store: IngestionStore) { _model = State(initialValue: MerchantRulesModel(store: store)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("When a familiar merchant appears again, Goldengo can choose the category for you. Every rule stays visible here.")
                    .font(.system(size: 13.5)).foregroundStyle(GoldengoTheme.inkMuted)
                    .padding(.horizontal, 2)

                Button { showAdd = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill").foregroundStyle(GoldengoTheme.accent)
                        Text("Add merchant rule").font(.system(size: 15, weight: .semibold))
                        Spacer(); Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(GoldengoTheme.inkMuted)
                    }.goldengoCard()
                }.buttonStyle(.plain)

                if model.rules.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "wand.and.stars").font(.system(size: 27)).foregroundStyle(GoldengoTheme.accent)
                        Text("No rules yet").font(.system(size: 16, weight: .semibold))
                        Text("Categorize a merchant once and choose “Remember” to make the next one automatic.")
                            .font(.system(size: 13)).foregroundStyle(GoldengoTheme.inkMuted).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity).padding(.vertical, 30).padding(.horizontal, 24).goldengoCard()
                } else {
                    ForEach(model.rules) { rule in ruleCard(rule) }
                }
            }
            .padding(.horizontal, GoldengoTheme.Spacing.m)
            .padding(.vertical, 16)
        }
        .background(Color.goldengoBackground.ignoresSafeArea())
        .navigationTitle("Merchant rules")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .task { await model.load() }
        .refreshable { await model.load() }
        .sheet(isPresented: $showAdd) { MerchantRuleEditor(model: model, existing: nil) }
        .sheet(item: $editing) { MerchantRuleEditor(model: model, existing: $0) }
        .alert("Couldn’t update rules", isPresented: Binding(
            get: { model.errorText != nil }, set: { if !$0 { model.errorText = nil } }
        )) { Button("OK") { model.errorText = nil } } message: { Text(model.errorText ?? "") }
    }

    private func ruleCard(_ rule: MerchantRuleSnapshot) -> some View {
        HStack(spacing: 13) {
            Image(systemName: "storefront.fill")
                .foregroundStyle(GoldengoTheme.accent).frame(width: 40, height: 40)
                .background(GoldengoTheme.accentSoft).clipShape(RoundedRectangle(cornerRadius: 12))
            Button { editing = rule } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.merchantName).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(GoldengoTheme.inkPrimary).lineLimit(1)
                    Label(rule.categoryName, systemImage: GoldengoCategoryIcon.symbol(for: rule.categoryName))
                        .font(.system(size: 12.5, weight: .medium)).foregroundStyle(GoldengoTheme.inkMuted)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
            Button { Task { await model.delete(rule) } } label: {
                Image(systemName: "trash").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GoldengoTheme.danger).frame(width: 38, height: 38)
                    .background(GoldengoTheme.danger.opacity(0.09)).clipShape(Circle())
            }.buttonStyle(.plain).accessibilityLabel("Delete rule for \(rule.merchantName)")
        }.goldengoCard(padding: 14)
    }
}

private struct MerchantRuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    let model: MerchantRulesModel
    let existing: MerchantRuleSnapshot?
    @State private var merchant: String
    @State private var category: String
    @State private var showCategories = false

    init(model: MerchantRulesModel, existing: MerchantRuleSnapshot?) {
        self.model = model; self.existing = existing
        _merchant = State(initialValue: existing?.merchantName ?? "")
        _category = State(initialValue: existing?.categoryName ?? "Other")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("When this appears") {
                    TextField("Merchant name", text: $merchant).disabled(existing != nil)
                }
                Section("Use this category") {
                    Button { showCategories = true } label: {
                        HStack {
                            Label(category, systemImage: GoldengoCategoryIcon.symbol(for: category)).foregroundStyle(GoldengoTheme.inkPrimary)
                            Spacer(); Image(systemName: "chevron.right").foregroundStyle(GoldengoTheme.inkMuted)
                        }
                    }
                }
                Text("This affects future imported and auto-logged transactions. Existing transactions never change silently.")
                    .font(.caption).foregroundStyle(GoldengoTheme.inkMuted)
            }
            .scrollContentBackground(.hidden).background(Color.goldengoBackground)
            .navigationTitle(existing == nil ? "New rule" : "Edit rule")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await model.save(merchant: merchant, category: category); dismiss() } }
                        .fontWeight(.semibold).disabled(merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $showCategories) {
                SpendingCategoryPicker(selectedCategory: category) { category = $0 }.presentationDetents([.large])
            }
        }.tint(GoldengoTheme.accent)
    }
}
