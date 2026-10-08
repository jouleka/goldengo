import SwiftUI
import GoldengoDesignSystem

/// Attribution required by the public currency-rate provider, styled to fit the app.
struct ExchangeRateAttribution: View {
    var body: some View {
        Link("Rates by ExchangeRate-API", destination: URL(string: "https://www.exchangerate-api.com")!)
            .font(.caption2)
            .foregroundStyle(GoldengoTheme.inkMuted)
            .padding(.vertical, 8)
    }
}
