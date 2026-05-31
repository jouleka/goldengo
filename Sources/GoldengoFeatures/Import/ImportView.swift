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
            .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
                guard case let .success(url) = result else { return }
                Task {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                       size > 10_000_000 {
                        model.setError("File too large (max 10 MB).")
                        return
                    }
                    if let text = try? String(contentsOf: url, encoding: .utf8) {
                        try? await model.importCSV(text: text, fileName: url.lastPathComponent)
                    } else if let text = try? String(contentsOf: url, encoding: .isoLatin1) {
                        try? await model.importCSV(text: text, fileName: url.lastPathComponent)
                    } else {
                        model.setError("Couldn't read the file (unsupported encoding).")
                    }
                }
            }
        }
    }
}
