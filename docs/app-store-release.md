# Goldengo App Store 1.0

Store name: **Goldengo: Spending & Budgets**. Installed app name: **Goldengo**.
Bundle ID: `com.goldengo.app`; widget: `com.goldengo.app.widget`.
App Store Connect app ID: `6820573440`. Version/build: `1.0 (1)`.

The first release is free, public, and configured to release automatically after Apple approval.
Availability is all 175 current countries/regions on iPhone and iPad. Apple Silicon Mac and
Apple Vision Pro distribution are disabled for this first release.

## Store assets

- Subtitle: Track spending. Plan calmly.
- Primary category: Finance.
- Primary language: English (U.S.).
- Privacy: https://jouleka.github.io/goldengo/privacy/
- Support: https://jouleka.github.io/goldengo/support/
- Marketing: https://jouleka.github.io/goldengo/
- Support email: lekacoding@gmail.com.
- Icon source: `scripts/render-app-icon.swift`; generated asset is tracked in the app asset catalog.
- Static website: `docs/site/`, published to GitHub Pages from the `gh-pages` branch.

Store screenshots use synthetic records, captured from the actual app in the iOS 26.5 simulator.
The iPhone 17 Pro Max captures are 1320 × 2868; the iPad Pro 13-inch captures are 2064 × 2752.
Both sets show Home, Wallet, and the statement import sheet. Local images and submission proof
are retained in ignored `output/app-store/`.

Screenshot setup is compiled only in DEBUG simulator builds. Launch with
`GOLDENGO_SEED_SAMPLE=1`; `GOLDENGO_SCREENSHOT_TAB=5` opens Wallet and `=3` opens Import.
It adds synthetic sample data once and does not delete existing simulator records.
Never seed a simulator that contains personal records for a public screenshot.

## Privacy and sync

The privacy manifest and App Store label disclose Other Diagnostic Data for App Functionality,
linked to the user, with no tracking. The external exchange-rate provider can retain request IPs
and connection information for operational logs and rate limiting. Financial records, statement
parsing, and receipt recognition remain on-device or in the user's private iCloud database.

ExchangeRate-API attribution appears on the screens that display converted amounts and in
Settings. The website explains optional CloudKit synchronization, archived-record retention,
exports, support correspondence, and deletion.

All 15 current SwiftData model record types and their indexes were initialized in the CloudKit
development environment using Apple's NSPersistentCloudKitContainer schema workflow and deployed
to Production on October 8, 2026. Dashboard roles apply to the public database; the app uses the
private database. Future model additions must be initialized and deployed before release.

## Validation

- `swift test --jobs 4`: 522 tests passed across seven package suites.
- DEBUG simulator build and signed Release archive succeeded with Xcode 27.
- App Group fallback launch verified in a simulator without the App Group entitlement.
- User confirmed the signed development app opens on iPhone, adds an expense, and exports a CSV.
- Real simulator screens visually inspected on iPhone and iPad.
- Apple upload validation requires `CFBundleDisplayName` in the widget extension.
- Siri metadata uses generic transaction-automation wording; the rejected wording was removed
  and the replacement verified in the final archive's `Metadata.appintents/extract.actionsdata`.

The focused category-budget regression covers a zero-spend foreign-currency budget and its
conversion timestamp. The row-building loop avoids Swift 6 region-isolation errors.

## Build and upload

Generate the project with the desired signing team:

```sh
GOLDENGO_DEVELOPMENT_TEAM=<your-team-id> bundle exec ruby AppProject/project.rb
```

Archive the Goldengo scheme in Release for generic iOS with automatic signing. Export using
`method=app-store-connect`, `destination=upload`, `uploadSymbols=true`, and the same team ID.
Keep Apple login credentials in Xcode; never commit them or provisioning profiles.

Upload acceptance, build processing, and App Review submission are separate stages. Verify the
processed build is selected in the version and that the App Review page says Waiting for Review
before reporting submission complete.

## Submitted release

Version `1.0 (1)` was submitted on October 8, 2026 at 17:37 Europe/Tirane. Apple confirmed
**Waiting for Review** for the submission and the app version. The release remains free and
configured to publish automatically after approval.

- Submission ID: `b7f93c02-c784-47d9-a596-3cd105bdc8ba`.
- Processed build ID: `c82cca4a-95e7-4aad-bac5-04a5ebc2fdff`.
- App source commit: `6654df0` on `release/app-store-v1`.
- Review receipt: https://appstoreconnect.apple.com/apps/6820573440/distribution/reviewsubmissions/details/b7f93c02-c784-47d9-a596-3cd105bdc8ba
- Submission screenshot: ignored `output/app-store/proof/submitted-review.png`.
- Final signed archive: `Goldengo 1.0 Submission.xcarchive`, retained in Xcode's Archives folder.

Apple's approval and public availability are subsequent stages and have not yet been confirmed.
