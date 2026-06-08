#if os(iOS)
import SwiftUI
import VisionKit
import CoreGraphics

/// Wraps the system document scanner (live edge-detect + deskew + crop). Hands back the first
/// page's image as a CGImage, or a cancel. The host presents this and dismisses on either callback.
struct DocumentScannerView: UIViewControllerRepresentable {
    let onScan: (CGImage) -> Void
    let onCancel: () -> Void

    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView
        init(_ parent: DocumentScannerView) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            guard scan.pageCount > 0, let cg = scan.imageOfPage(at: 0).cgImage else {
                parent.onCancel(); return
            }
            parent.onScan(cg)
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            parent.onCancel()
        }
    }
}
#endif
