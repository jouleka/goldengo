import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

public enum PDFTextExtractor {
    /// Extracts all text from a PDF at the given URL, or nil if unreadable or no text.
    public static func text(from url: URL) -> String? {
        #if canImport(PDFKit)
        guard let doc = PDFDocument(url: url) else { return nil }
        var out = ""
        for i in 0..<doc.pageCount {
            if let p = doc.page(at: i), let s = p.string { out += s + "\n" }
        }
        return out.isEmpty ? nil : out
        #else
        return nil
        #endif
    }

    /// Extracts all text from a PDF given raw Data, or nil if unreadable or no text.
    public static func text(from data: Data) -> String? {
        #if canImport(PDFKit)
        guard let doc = PDFDocument(data: data) else { return nil }
        var out = ""
        for i in 0..<doc.pageCount {
            if let p = doc.page(at: i), let s = p.string { out += s + "\n" }
        }
        return out.isEmpty ? nil : out
        #else
        return nil
        #endif
    }
}
