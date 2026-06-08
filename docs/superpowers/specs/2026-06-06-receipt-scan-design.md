# GOL-80 — Receipt scanning (on-device OCR capture)

**Ticket:** [GOL-80](https://mysigner.youtrack.cloud/issue/GOL-80).
**Status:** design approved; pending spec review.
**Date:** 2026-06-06.
**Builds on:** GOL-77 (Apple Pay auto-log), GOL-79 (statement import + `.automatic` source + dedup), the existing `QuickAddModel`/`logManual` capture path and `MerchantNormalizer`/`defaultCategory` auto-categorization.

## Goal

Point the camera at a paper receipt and get a new expense **pre-filled with amount + merchant + date**, then confirm it in one sheet. Fully on-device, no backend, no photo kept. This is the only "automatic capture" iOS actually permits for the dominant spend type in Albania — **cash** — which neither Apple Pay auto-log (GOL-77) nor bank/statement paths can ever see.

## Decision record (researched, verified against Apple docs — June 2026)

- **Capture: `VisionKit.VNDocumentCameraViewController`** (the Notes/Files document scanner): on-device, live edge-detection + perspective-correction (deskew) + auto-crop + multi-page, iOS 13+. Returns a `VNDocumentCameraScan`; we take `imageOfPage(at: 0)`. Gate the entry point on the static `VNDocumentCameraViewController.isSupported` (it does **not** run in the iOS Simulator → device-only verification). Rejected `DataScannerViewController` (built for live capture of *short* discrete items, not dense full-receipt OCR) and raw `AVCaptureSession` (reinvents deskew/crop for no benefit). Sources: developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller, .../vndocumentcamerascan.
- **OCR: Vision `VNRecognizeTextRequest`** (iOS 13+ baseline; **on-device** — "all of Vision's processing happens on the user's device"). `recognitionLevel = .accurate`, `usesLanguageCorrection = true`, `recognitionLanguages = ["en-US"]`. Each `VNRecognizedTextObservation` gives `topCandidates(1).first?.string` (+ `.confidence`) and a normalized `boundingBox` (origin bottom-left) for layout heuristics. The iOS 18 Swift `RecognizeTextRequest` is **not** required (kept out of v1 to hold the iOS 17 floor; optional behind `#available` later). Sources: developer.apple.com/documentation/vision/recognizing-text-in-images, .../vnrecognizetextrequest.
- **Albanian (`sq`) is not in Apple's documented OCR language list**, but it is **Latin script** — digits, merchant names, and the keyword "TOTALI" all OCR as Latin characters. So: keep `recognitionLanguages = ["en-US"]`, **parse amounts from the raw recognized string** (language correction can mangle digit/decimal runs), and never depend on `sq`-specific correction. Honest expectation, not a blocker.
- **Permissions/config: only `NSCameraUsageDescription`** in the app `Info.plist`. **No entitlement.** The scanner + OCR live entirely in the `GoldengoFeatures` SPM module via `UIViewControllerRepresentable`, so **no new app-target file and no `ruby project.rb` regeneration** — signing stays intact (the documented gotcha).
- **Reuse the existing save path.** A scanned receipt is a user-confirmed **manual** capture → `logManual` (source `.manual`), gaining merchant→category auto-categorization, subscription detection, preferred currency, and the widget refresh for free.
- **Confirm before save is mandatory.** OCR + "which number is the total" are heuristic; the user always reviews the pre-fill. This is a feature, not a fallback.

## Components

Small, isolated, independently testable units.

### Pure parser — `Sources/GoldengoCore/ReceiptParser.swift` (no Vision/UIKit dependency)
```
struct RecognizedLine { let text: String; let boundingBox: CGRect }   // normalized, origin bottom-left
struct ParsedReceipt  { let amount: Decimal?; let merchant: String?; let date: Date? }
enum ReceiptParser { static func parse(_ lines: [RecognizedLine], currency: CurrencyCode) -> ParsedReceipt }
```
This is the heart of the feature and the primary test target — pure, deterministic, fed synthetic line arrays (no camera). Heuristics:
- **Amount:** collect lines whose text contains a currency-amount token (number with optional `,`/`.` separators and optional currency symbol/`L`/`ALL`/`€`). Prefer a line whose normalized-uppercased text contains a **total keyword** (`TOTAL`, `TOTALI`, `SHUMA`, `VLERA`, `AMOUNT DUE`); among those pick the **bottom-most** (smallest `boundingBox.midY`). If no keyword line, fall back to the **largest** amount in the lower portion of the receipt. Parse the chosen token → `Decimal`, honouring the target currency's fraction digits (lek = 0) and `,`-vs-`.` decimal separators; strip thousands separators. `nil` if nothing plausible.
- **Merchant:** the **top-most** line (largest `boundingBox.midY`) that isn't purely numeric / a date / an address line; trimmed. Passed through `MerchantNormalizer`/`defaultCategory` for the category suggestion.
- **Date:** regex over all lines for `dd/MM/yyyy`, `dd.MM.yyyy`, `dd-MM-yyyy`, `yyyy-MM-dd`; accept the first parse that is ≤ today and within ~2 years; else `nil`.

### OCR — `Sources/GoldengoFeatures/Receipt/ReceiptOCR.swift`
`func recognizeLines(in cgImage: CGImage) async throws -> [RecognizedLine]` — runs `VNRecognizeTextRequest` (`.accurate`) via `VNImageRequestHandler`, maps observations → `RecognizedLine`. Runs off the main actor.

### Scanner — `Sources/GoldengoFeatures/Receipt/DocumentScannerView.swift`
`UIViewControllerRepresentable` over `VNDocumentCameraViewController`; an `NSObject` `Coordinator` is the `VNDocumentCameraViewControllerDelegate`; exposes `onScan(VNDocumentCameraScan)` / `onCancel`. Parent presents it via `.fullScreenCover` and dismisses on finish/cancel (the controller does not self-dismiss).

### Orchestrator — `Sources/GoldengoFeatures/Receipt/ReceiptScanModel.swift`
`@MainActor @Observable`, mirrors `QuickAddModel`. `handle(_ scan:) async`: `imageOfPage(0)` → `ReceiptOCR.recognizeLines` → `ReceiptParser.parse` → populate the editable draft (`amount`, `merchant`, `date ?? .now`, `category = defaultCategory(merchant)`, `currency = preferred`). `save() async` → `store.logManual(amount: …, currency: …, merchant: …, categoryName: …, date: …)` (`note` omitted → its default `nil`).

### Confirm sheet — `Sources/GoldengoFeatures/Receipt/ReceiptReviewView.swift`
Pre-filled, editable: prominent amount, merchant field, date picker, pre-selected category chips, currency (defaults to preferred). Minimalist/low-tap; keyboard dismissal via tap-outside / Return (no Done toolbar). Built with the frontend-design skill at implementation time. **Always** requires the user to tap Save.

### Entry point — `QuickAddView` (the Add tab)
A "Scan receipt" (camera) button, shown only when `VNDocumentCameraViewController.isSupported`. Tapping presents `DocumentScannerView`; on scan, `ReceiptScanModel.handle` runs and the `ReceiptReviewView` sheet appears pre-filled.

### Enabling change — `Sources/GoldengoData/IngestionStore.swift`
Add `date: Date = .now` to `logManual` (and the private `logEntry`) so a scanned receipt persists with the **receipt's** date, not "now". Backward-compatible (default `.now`); `EditExpense`/`updateExpense` already support per-expense dates.

### Config — `AppProject/Goldengo/Info.plist`
Add `NSCameraUsageDescription` (e.g. "Scan a receipt to add the expense automatically."). App-target edit, no regen.

## Data flow
```
Add screen "Scan receipt" (visible iff VNDocumentCameraViewController.isSupported)
  → DocumentScannerView (full-screen) → didFinishWith scan → ReceiptScanModel.handle(scan)
      → cgImage = scan.imageOfPage(0)              (off main)
      → lines  = ReceiptOCR.recognizeLines(in:)    (Vision, on-device)
      → parsed = ReceiptParser.parse(lines, currency: preferred)   (pure)
      → draft  = { amount, merchant, date ?? .now, category = defaultCategory(merchant), currency = preferred }
  → ReceiptReviewView (pre-filled) → user confirms/edits → save()
      → store.logManual(amount, currency, merchant, categoryName, date)
      → expense on Recent + widget today-total refresh
```

## Dedup with GOL-79
Scanned receipts are `.manual` (user-confirmed) and use a unique key, so they are **never** auto-merged. Rationale: receipts are primarily **cash**, which never appears on a bank statement, so there is no import overlap to reconcile. A scanned *card* receipt behaves exactly like a hand-typed entry today (could duplicate a later statement row — accepted, same as the status quo). **No new dedup logic** — surgical.

## Error handling
- **Unsupported device / Simulator:** the Scan button is hidden when `isSupported == false`.
- **Camera permission denied:** the document scanner surfaces the system prompt; if denied, cancel = no-op (the system Settings deep-link is out of scope for v1).
- **OCR finds no usable total:** open the review with an empty amount + a gentle "couldn't read the total — enter it" hint (never an error wall, never a crash).
- **User cancels the scanner:** dismiss, no-op.
- **Partial parse:** pre-fill what was found, leave the rest empty for the user.

## Tests
- **`ReceiptParserTests` (GoldengoCoreTests)** — the bulk. Synthetic `[RecognizedLine]` for real receipts (Albanian "TOTALI 1.250 L" with subtotal/TVSH lines; English "TOTAL $12.50"; comma-vs-dot decimals; lek 0-fraction; no-keyword largest-amount fallback; merchant at top; multiple date formats; `nil` when nothing parses). *Why each matters:* a parser that returns the **subtotal or tax instead of the total**, or that misreads lek decimals, silently corrupts the user's amount — these tests must fail if the heuristic regresses (Rule 9).
- **`ReceiptScanModelTests` (GoldengoFeaturesTests)** — feed stubbed `[RecognizedLine]` (inject via the parser, bypassing the camera) → assert the draft is populated and `save()` calls `logManual` with the parsed date/merchant/category against an in-memory store.
- **`logManual` date param (GoldengoDataTests)** — `logManual(..., date: pastDate)` persists `pastDate`, not `.now`; the default still uses `.now`.
- **Camera/OCR/scanner** — `ReceiptOCR`, `DocumentScannerView` aren't unit-testable (need camera + device). Verified **on device** (manual), like GOL-77's intent path. `VNDocumentCameraViewController.isSupported == false` in the Simulator, so the full pipeline is device-only.

## Runtime verification (device)
Build + install. Scan a real receipt (Albanian cash receipt + an English one): the scanner deskews/crops, the review sheet opens pre-filled with a plausible total + merchant + date, the suggested category matches the merchant mapping where known, and Save logs the expense (correct amount/merchant/currency/date) onto Recent. A receipt with a faded/ambiguous total opens the review for manual entry rather than failing. Second-Opus review over the diff.

## Out of scope (explicit)
- **Keeping the receipt photo** / a receipt gallery (decided out; possible fast-follow — would add storage + CloudKit weight + a privacy surface).
- **Richer parsing** — top-N amount candidates as tappable chips on low confidence, line-item extraction (YAGNI for v1).
- **On-device Apple Intelligence (Foundation Models) parsing** — device-gated to iOS 18.1+/Apple-Intelligence hardware; breaks the iOS 17 floor; future enhancement.
- **Receipt ↔ statement-import reconciliation** (cash receipts don't appear on statements; not worth the complexity).
- **Currency auto-detection from the receipt** — v1 uses the preferred currency; the user can change it in the review.
- **Multi-page receipts** — v1 OCRs page 0 only.
