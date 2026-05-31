import Foundation
import Observation
import GoldengoCore
import GoldengoData
import GoldengoImport
#if canImport(WidgetKit)
import WidgetKit
#endif

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

    public func importCSV(text: String, fileName: String) async {
        guard text.utf8.count <= 10_000_000 else {
            resultText = "File too large (max 10 MB)."
            return
        }
        do {
            try await ingest(StatementImporter.transactions(fromCSV: text, currency: currency), fileName)
        } catch {
            resultText = "Import failed: \(error.localizedDescription)"
        }
    }

    public func importPDF(url: URL, fileName: String) async {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= 10_000_000 else { resultText = "File too large (max 10 MB)."; return }
        guard let text = PDFTextExtractor.text(from: url) else {
            resultText = "Couldn't read the PDF."
            return
        }
        do {
            try await ingest(StatementImporter.transactions(fromPDFText: text, currency: currency), fileName)
        } catch {
            resultText = "Import failed: \(error.localizedDescription)"
        }
    }

    private func ingest(_ txns: [NormalizedTransaction], _ fileName: String) async throws {
        guard !txns.isEmpty else {
            resultText = "No transactions recognized in \(fileName)."
            return
        }
        let s = try await store.importStatement(txns, fileName: fileName)
        resultText = "Imported \(s.imported), skipped \(s.deduped) duplicates"
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
#endif
    }
}
