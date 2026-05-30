import SwiftUI
import GoldengoDesignSystem

public struct QuickAddView: View {
    @State private var model: QuickAddModel
    public init(model: QuickAddModel) { _model = State(initialValue: model) }

    private let keys = ["1","2","3","4","5","6","7","8","9",".","0","⌫"]

    public var body: some View {
        VStack(spacing: GoldengoTheme.Spacing.l) {
            Text(model.amountString.isEmpty ? "0" : model.amountString)
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.top, GoldengoTheme.Spacing.l)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: GoldengoTheme.Spacing.s) {
                    ForEach(model.quickCategories, id: \.self) { cat in
                        Button(cat) { model.selectedCategory = cat }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(model.selectedCategory == cat ? GoldengoTheme.accent : secondaryBackground)
                            .foregroundStyle(model.selectedCategory == cat ? .black : .primary)
                            .clipShape(Capsule())
                    }
                }.padding(.horizontal)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: GoldengoTheme.Spacing.s) {
                ForEach(keys, id: \.self) { k in
                    Button { tap(k) } label: {
                        Text(k).font(.title2).frame(maxWidth: .infinity, minHeight: 56)
                            .background(secondaryBackground).clipShape(RoundedRectangle(cornerRadius: 12))
                    }.foregroundStyle(.primary)
                }
            }.padding(.horizontal)

            Button {
                Task { try? await model.save() }
            } label: {
                Text("Add").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
            }
            .background(model.canSave ? GoldengoTheme.accent : disabledBackground)
            .foregroundStyle(.black).clipShape(RoundedRectangle(cornerRadius: 14))
            .disabled(!model.canSave).padding(.horizontal).padding(.bottom, GoldengoTheme.Spacing.l)
        }
    }

    private func tap(_ k: String) { k == "⌫" ? model.backspace() : model.tap(k) }

    private var secondaryBackground: Color {
#if canImport(UIKit)
        Color(.secondarySystemBackground)
#else
        Color(.windowBackgroundColor)
#endif
    }

    private var disabledBackground: Color {
#if canImport(UIKit)
        Color(.systemGray4)
#else
        Color(.separatorColor)
#endif
    }
}
