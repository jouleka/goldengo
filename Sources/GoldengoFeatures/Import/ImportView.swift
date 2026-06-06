import SwiftUI
import UniformTypeIdentifiers
import GoldengoData
import GoldengoDesignSystem

public struct ImportView: View {
    @State private var model: ImportModel
    @State private var showingPicker = false
    @Environment(\.dismiss) private var dismiss
    public init(model: ImportModel) { _model = State(initialValue: model) }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: GoldengoTheme.Spacing.m) {
                    intro
                    VStack(spacing: GoldengoTheme.Spacing.s) {
                        actionButton("Choose a file", subtitle: "CSV or PDF statement",
                                     systemImage: "folder", prominent: true) { showingPicker = true }
                        actionButton("Try a sample", subtitle: "See how import works",
                                     systemImage: "doc.text.magnifyingglass", prominent: false) {
                            Task { await model.importCSV(text: SampleStatement.csv, fileName: "sample.csv") }
                        }
                    }
                    if !model.resultText.isEmpty { resultCard }
                }
                .padding(GoldengoTheme.Spacing.m)
            }
            .background(Color.goldengoBackground.ignoresSafeArea())
            .navigationTitle("Import")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showingPicker,
                allowedContentTypes: [.pdf, .commaSeparatedText, .plainText]
            ) { result in
                guard case let .success(url) = result else { return }
                Task { await model.importFile(url: url) }
            }
        }
    }

    private var intro: some View {
        VStack(spacing: GoldengoTheme.Spacing.s) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(GoldengoTheme.accent)
            Text("Import a bank statement")
                .font(.headline)
            Text("Bring in transactions in one step. Duplicates are skipped automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, GoldengoTheme.Spacing.s)
    }

    private func actionButton(_ title: String, subtitle: String, systemImage: String,
                              prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: GoldengoTheme.Spacing.m) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(prominent ? .black : GoldengoTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(prominent ? GoldengoTheme.accent : GoldengoTheme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.chip, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .goldengoCard()
        }
        .buttonStyle(.plain)
    }

    private var resultCard: some View {
        HStack(spacing: GoldengoTheme.Spacing.s) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(model.resultText).font(.subheadline)
            Spacer()
        }
        .goldengoCard()
    }
}
