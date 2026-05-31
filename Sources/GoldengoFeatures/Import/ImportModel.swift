import Foundation
import Observation
import GoldengoCore
import GoldengoData
import GoldengoImport

@MainActor
@Observable
public final class ImportModel {
    public let store: IngestionStore
    public var currency: CurrencyCode
    public private(set) var resultText: String = ""

    public init(store: IngestionStore, currency: CurrencyCode = .all) {
        self.store = store; self.currency = currency
    }

    public func setError(_ message: String) {
        resultText = message
    }

    public func importCSV(text: String, fileName: String) async throws {
        guard text.utf8.count <= 10_000_000 else {
            resultText = "File too large (max 10 MB)."
            return
        }
        try await ingest(StatementImporter.transactions(fromCSV: text, currency: currency), fileName)
    }

    public func importPDF(url: URL, fileName: String) async throws {
        guard let text = PDFTextExtractor.text(from: url) else {
            resultText = "Couldn't read the PDF."
            return
        }
        try await ingest(StatementImporter.transactions(fromPDFText: text, currency: currency), fileName)
    }

    private func ingest(_ txns: [NormalizedTransaction], _ fileName: String) async throws {
        guard !txns.isEmpty else {
            resultText = "No transactions recognized in \(fileName)."
            return
        }
        let s = try await store.importStatement(txns, fileName: fileName)
        resultText = "Imported \(s.imported), skipped \(s.deduped) duplicates"
    }
}
