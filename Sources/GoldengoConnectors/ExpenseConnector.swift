import Foundation
import GoldengoCore

public struct ConnectorCapabilities: Sendable, Equatable {
    public var supportsBackfill: Bool
    public var supportsRealtime: Bool
    public var supportsBalances: Bool
    public init(supportsBackfill: Bool, supportsRealtime: Bool, supportsBalances: Bool) {
        self.supportsBackfill = supportsBackfill
        self.supportsRealtime = supportsRealtime
        self.supportsBalances = supportsBalances
    }
}

public struct SyncCheckpoint: Sendable, Equatable {
    public var token: String
    public var date: Date
    public init(token: String, date: Date) { self.token = token; self.date = date }
}

public protocol ExpenseConnector: Sendable {
    var id: String { get }
    var capabilities: ConnectorCapabilities { get }
    func pull(since checkpoint: SyncCheckpoint?) async throws -> [NormalizedTransaction]
}
