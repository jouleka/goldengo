import SwiftUI
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

/// The "assign a category" sheet for a single "Other" expense — a minimal reuse of QuickAdd's
/// category-chip pattern: existing names as one-tap chips, plus a "New" chip that reveals an inline
/// name field. Presented from `CategoryDetailView`.
struct CategorizeExpenseView: View {
    let expense: ExpenseSnapshot
    let existingCategoryNames: [String]
    let onAssign: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var newCategoryFocused: Bool
    @State private var newCategoryMode = false
    @State private var newCategoryText = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.l) {
                VStack(alignment: .leading, spacing: 2) {
                    GoldengoSectionLabel("Assign a category")
                    Text(expense.displayTitle)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(GoldengoTheme.inkPrimary)
                }

                categoryChips

                if newCategoryMode {
                    newCategoryField
                }

                Spacer(minLength: 0)
            }
            .padding(GoldengoTheme.Spacing.m)
            .background(Color.goldengoBackground.ignoresSafeArea())
            // Tap anywhere outside the field clears focus (house rule — never a keyboard toolbar).
            .contentShape(Rectangle())
            .onTapGesture { newCategoryFocused = false }
#if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(existingCategoryNames.filter { $0 != "Other" }, id: \.self) { name in
                    SelectableChip(name, systemImage: GoldengoCategoryIcon.symbol(for: name), isSelected: false) {
                        assign(name)
                    }
                }
                SelectableChip("New", systemImage: "plus", isSelected: newCategoryMode) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        newCategoryMode.toggle()
                        if newCategoryMode { newCategoryFocused = true } else { newCategoryText = "" }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var newCategoryField: some View {
        TextField("Name a category — e.g. Cigarettes", text: $newCategoryText)
            .focused($newCategoryFocused)
            .submitLabel(.done)
            .onSubmit { commitNewCategory() }
            .font(.system(size: 14.5, weight: .semibold))
            .foregroundStyle(GoldengoTheme.inkPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.goldengoField)
            .clipShape(Capsule())
    }

    private func commitNewCategory() {
        let trimmed = newCategoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        newCategoryFocused = false
        guard !trimmed.isEmpty else { return }
        assign(trimmed)
    }

    private func assign(_ name: String) {
        onAssign(name)
        dismiss()
    }
}
