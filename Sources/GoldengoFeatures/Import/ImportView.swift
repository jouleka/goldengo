import SwiftUI
import GoldengoData

public struct ImportView: View {
    @State private var model: ImportModel
    @State private var showingPicker = false
    public init(model: ImportModel) { _model = State(initialValue: model) }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Import a statement") {
                    Button("Choose CSV file…") { showingPicker = true }
                    Button("Try a sample statement") {
                        Task { try? await model.importCSV(text: SampleStatement.csv, fileName: "sample.csv") }
                    }
                }
                if !model.resultText.isEmpty {
                    Section("Result") { Text(model.resultText) }
                }
            }
            .navigationTitle("Import")
            .onOpenURL { url in
                if url.scheme == "goldengo", url.host == "import",
                   URLComponents(url: url, resolvingAgainstBaseURL: false)?
                       .queryItems?.first(where: { $0.name == "sample" })?.value == "1" {
                    Task { try? await model.importCSV(text: SampleStatement.csv, fileName: "sample.csv") }
                }
            }
            .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
                guard case let .success(url) = result else { return }
                Task {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if let text = try? String(contentsOf: url, encoding: .utf8) {
                        try? await model.importCSV(text: text, fileName: url.lastPathComponent)
                    }
                }
            }
        }
    }
}
