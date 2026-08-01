import SwiftUI
import GoldengoCore
import GoldengoDesignSystem

/// Reusable category/subcategory browser. Entry screens can keep their fast recent chips while the
/// full canonical hierarchy is always reachable in two taps.
struct SpendingCategoryMenu: View {
    let selectedCategory: String?
    let onSelect: (String) -> Void

    var body: some View {
        Menu {
            ForEach(SpendingCategoryCatalog.groups) { group in
                Menu {
                    Button("General \(group.name.lowercased())") { onSelect(group.name) }
                    if !group.subcategories.isEmpty { Divider() }
                    ForEach(group.subcategories) { subcategory in
                        Button {
                            onSelect(subcategory.name)
                        } label: {
                            if selectedCategory == subcategory.name {
                                Label(subcategory.name, systemImage: "checkmark")
                            } else {
                                Text(subcategory.name)
                            }
                        }
                    }
                } label: {
                    Label(group.name, systemImage: group.icon)
                }
            }
        } label: {
            Label("Browse", systemImage: "square.grid.2x2")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GoldengoTheme.inkPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.goldengoField)
                .clipShape(Capsule())
        }
        .accessibilityLabel("Browse categories and subcategories")
    }
}
