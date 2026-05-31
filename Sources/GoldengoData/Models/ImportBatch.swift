import Foundation
import SwiftData

@Model
public final class ImportBatch {
    public var fileName: String = ""
    public var importedAt: Date = Date.now
    public var rowCount: Int = 0
    public var importedCount: Int = 0
    public var dedupedCount: Int = 0

    public init(fileName: String = "", importedAt: Date = .now,
                rowCount: Int = 0, importedCount: Int = 0, dedupedCount: Int = 0) {
        self.fileName = fileName; self.importedAt = importedAt
        self.rowCount = rowCount; self.importedCount = importedCount; self.dedupedCount = dedupedCount
    }
}
