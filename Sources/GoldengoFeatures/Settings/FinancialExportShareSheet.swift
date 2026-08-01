import SwiftUI

struct FinancialExportShare: Identifiable {
    let id = UUID()
    let url: URL
}

#if os(iOS)
import UIKit

struct FinancialExportShareSheet: UIViewControllerRepresentable {
    let item: FinancialExportShare
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [item.url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
struct FinancialExportShareSheet: View {
    let item: FinancialExportShare
    var body: some View {
        VStack(spacing: 16) {
            Text("Your export is ready")
            ShareLink("Share CSV", item: item.url)
        }.padding()
    }
}
#endif
