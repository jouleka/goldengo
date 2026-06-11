import Foundation

/// Reserved funding-pin ids that are not `SourceRecord` ids (GOL-95 v2).
public enum FundingPin {
    /// The physical cash wallet. Expenses pinned here — or `.manual` expenses with no pin at
    /// all (cash by default) — drain the wallet ledger, not the bank-side source pools.
    /// On an INCOME row, this pin means "cash in hand": it credits the wallet and never
    /// reaches a bank-side pool.
    public static let wallet = "wallet"
}
