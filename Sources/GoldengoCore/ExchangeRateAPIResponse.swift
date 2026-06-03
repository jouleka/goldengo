import Foundation

/// Decodable mapping of the ExchangeRate-API open-endpoint JSON onto a `RateTable`. Pure (no
/// networking) so it is shared by the live fetch (GoldengoData) and the bundled seed.
public struct ExchangeRateAPIResponse: Decodable, Sendable {
    public let result: String
    public let baseCode: String
    public let timeLastUpdateUnix: TimeInterval?
    public let timeLastUpdateUtc: String?
    public let rates: [String: Decimal]

    enum CodingKeys: String, CodingKey {
        case result, rates
        case baseCode = "base_code"
        case timeLastUpdateUnix = "time_last_update_unix"
        case timeLastUpdateUtc = "time_last_update_utc"
    }

    /// Builds a `RateTable`, or nil if the payload isn't a usable success response.
    public func toRateTable() -> RateTable? {
        guard result == "success", !rates.isEmpty else { return nil }
        let asOf: Date
        if let unix = timeLastUpdateUnix {
            asOf = Date(timeIntervalSince1970: unix)
        } else if let utc = timeLastUpdateUtc, let parsed = Self.rfc1123.date(from: utc) {
            asOf = parsed
        } else {
            return nil
        }
        return RateTable(base: CurrencyCode(baseCode), rates: rates, asOf: asOf)
    }

    /// e.g. "Wed, 03 Jun 2026 00:02:31 +0000". POSIX locale → locale-independent parsing.
    private static let rfc1123: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f
    }()
}
