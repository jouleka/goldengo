import SwiftUI
import GoldengoCore
import GoldengoDesignSystem

/// A searchable, single-level category picker for entry flows.
///
/// The canonical taxonomy is still grouped for scanning, but every leaf is visible and selectable
/// in one tap. This deliberately avoids nested `Menu` controls, which turn into overlapping
/// popovers on iPhone and make the user remember which parent contains a category.
struct SpendingCategoryPicker: View {
    @Environment(\.dismiss) private var dismiss

    let selectedCategory: String?
    private let merchantName: String?
    private let onSelect: (String, Bool) -> Void

    @State private var query = ""
    @State private var customCategory = ""
    @State private var rememberMerchant = true
    @FocusState private var customFieldFocused: Bool

    init(selectedCategory: String?, onSelect: @escaping (String) -> Void) {
        self.selectedCategory = selectedCategory
        self.merchantName = nil
        self.onSelect = { category, _ in onSelect(category) }
    }

    init(selectedCategory: String?, merchantName: String?,
         onSelect: @escaping (String, Bool) -> Void) {
        self.selectedCategory = selectedCategory
        let clean = merchantName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.merchantName = (clean?.isEmpty ?? true) ? nil : clean
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    if let merchantName { rememberCard(merchantName) }
                    ForEach(visibleGroups) { group in
                        categoryGroup(group)
                    }

                    if query.isEmpty {
                        customCategoryCard
                    } else if visibleGroups.isEmpty {
                        emptySearchCard
                    }
                }
                .padding(.horizontal, GoldengoTheme.Spacing.m)
                .padding(.vertical, 14)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.goldengoBackground.ignoresSafeArea())
            .navigationTitle("Choose category")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .searchable(text: $query, prompt: "Search rent, fuel, investing…")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func rememberCard(_ merchant: String) -> some View {
        Toggle(isOn: $rememberMerchant) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Remember for \(merchant)")
                    .font(.system(size: 14.5, weight: .semibold)).foregroundStyle(GoldengoTheme.inkPrimary)
                    .lineLimit(1)
                Text("Future transactions can categorize themselves.")
                    .font(.system(size: 12.5)).foregroundStyle(GoldengoTheme.inkMuted)
            }
        }
        .tint(GoldengoTheme.accent)
        .padding(14)
        .background(GoldengoTheme.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var visibleGroups: [SpendingCategoryGroup] {
        guard !queryKey.isEmpty else { return SpendingCategoryCatalog.groups }
        return SpendingCategoryCatalog.groups.filter { group in
            normalized(group.name).contains(queryKey)
                || group.subcategories.contains { subcategory in
                    normalized(subcategory.name).contains(queryKey)
                        || subcategory.aliases.contains { normalized($0).contains(queryKey) }
                }
        }
    }

    private func visibleSubcategories(in group: SpendingCategoryGroup) -> [SpendingSubcategory] {
        guard !queryKey.isEmpty, !normalized(group.name).contains(queryKey) else {
            return group.subcategories
        }
        return group.subcategories.filter { subcategory in
            normalized(subcategory.name).contains(queryKey)
                || subcategory.aliases.contains { normalized($0).contains(queryKey) }
        }
    }

    private var queryKey: String { normalized(query) }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func categoryGroup(_ group: SpendingCategoryGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: group.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: group.colorHex))
                    .frame(width: 30, height: 30)
                    .background(Color(hex: group.colorHex).opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                Text(group.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(GoldengoTheme.inkPrimary)

                Spacer()

                Text(group.defaultPurpose.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(hex: group.defaultPurpose.colorHex))
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 2),
                spacing: 9
            ) {
                ForEach(visibleSubcategories(in: group)) { subcategory in
                    categoryButton(
                        subcategory.name,
                        color: Color(hex: group.colorHex),
                        purpose: subcategory.purpose
                    )
                }
            }
        }
        .padding(14)
        .background(Color.goldengoSurface)
        .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: GoldengoTheme.Radius.card, style: .continuous)
                .strokeBorder(GoldengoTheme.hairline, lineWidth: 1)
        }
    }

    private func categoryButton(_ name: String, color: Color, purpose: MoneyPurpose) -> some View {
        let isSelected = selectedCategory == name
        return Button {
            choose(name)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: purpose.colorHex))
                    .frame(width: 7, height: 7)

                Text(name)
                    .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(GoldengoTheme.inkPrimary)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(GoldengoTheme.accent)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(isSelected ? GoldengoTheme.accentSoft : color.opacity(0.09))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(isSelected ? GoldengoTheme.accentLine : color.opacity(0.16), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name), \(purpose.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var customCategoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Custom category", systemImage: "tag.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(GoldengoTheme.inkPrimary)

            HStack(spacing: 9) {
                TextField("e.g. Work tools", text: $customCategory)
                    .focused($customFieldFocused)
                    .submitLabel(.done)
                    .onSubmit { chooseCustomCategory() }
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 13)
                    .frame(minHeight: 44)
                    .background(Color.goldengoField)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button("Use") { chooseCustomCategory() }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(GoldengoTheme.onAccent)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(GoldengoTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .disabled(trimmedCustomCategory.isEmpty)
                    .opacity(trimmedCustomCategory.isEmpty ? 0.45 : 1)
            }
        }
        .padding(14)
        .background(Color.goldengoSurface)
        .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.card, style: .continuous))
    }

    private var emptySearchCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(GoldengoTheme.inkMuted)
            Text("No matching category")
                .font(.headline)
                .foregroundStyle(GoldengoTheme.inkPrimary)
            Button("Use “\(query.trimmingCharacters(in: .whitespacesAndNewlines))”") {
                choose(query.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(GoldengoTheme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(Color.goldengoSurface)
        .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.card, style: .continuous))
    }

    private var trimmedCustomCategory: String {
        customCategory.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func chooseCustomCategory() {
        guard !trimmedCustomCategory.isEmpty else {
            customFieldFocused = true
            return
        }
        choose(trimmedCustomCategory)
    }

    private func choose(_ name: String) {
        guard !name.isEmpty else { return }
        onSelect(name, rememberMerchant)
        dismiss()
    }
}
