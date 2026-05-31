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
        var rows = CSVParser.parse(text)
        guard let header = rows.first,
              let mapping = MappingDetector.detect(header: header, currency: currency) else {
            resultText = "Couldn't recognize the statement columns."
            return
        }
        rows.removeFirst()
        let txns = rows.compactMap { StatementRowMapper.map(row: $0, using: mapping) }
        let summary = try await store.importStatement(txns, fileName: fileName)
        resultText = "Imported \(summary.imported), skipped \(summary.deduped) duplicates"
    }
}
