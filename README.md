# Goldengo

[![CI](https://github.com/jouleka/goldengo/actions/workflows/ci.yml/badge.svg)](https://github.com/jouleka/goldengo/actions/workflows/ci.yml)
[![Secret scan](https://github.com/jouleka/goldengo/actions/workflows/secret-scan.yml/badge.svg)](https://github.com/jouleka/goldengo/actions/workflows/secret-scan.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Goldengo is a native, privacy-minded iOS personal-finance app for capturing expenses, understanding spending, and keeping a lightweight money plan. The business logic lives in Swift packages, while the iOS app, widget, App Shortcuts, and generated Xcode project live under `AppProject/`.

> Goldengo is under active development and is not currently distributed through the App Store. It is not financial advice and is not affiliated with Apple, Raiffeisen Bank, or any other financial institution.

## Highlights

- Manual expenses, income, transfers, cash balances, budgets, goals, loans, and subscriptions
- CSV and PDF statement import with duplicate detection and synthetic test fixtures
- Search, category breakdowns, spending periods, recurring-charge detection, and multi-currency views
- App Shortcuts and a widget for quick expense capture
- Portable CSV backup and additive, idempotent restore
- Optional private CloudKit sync, with a local-only fallback when iCloud is not provisioned
- 500+ headless Swift tests covering the data, import, feature, and intent layers

## Privacy and network boundary

Financial records are stored on device. When a signed build has the included CloudKit entitlement and container provisioned, records can sync through the user's **private** iCloud database. Goldengo has no custom account service, analytics SDK, advertising SDK, or bank-login backend.

The app makes one keyless network request for current currency rates: `https://open.er-api.com/v6/latest/USD`. That request does not include transactions, account balances, imported statements, or other financial records. Statement parsing runs locally.

Exports contain sensitive financial data. Goldengo writes them as protected temporary files, removes them after the share sheet closes, and neutralizes spreadsheet-formula prefixes. Treat exported CSV files as private documents.

## Requirements

- macOS with an Xcode release that supports iOS 17 and Swift 6
- Ruby and Bundler (for the generated Xcode project)
- iOS 17 or later for the app

## Quick start

Run the package test suite:

```sh
swift test --quiet
```

Generate and open the iOS project:

```sh
bundle install
bundle exec ruby AppProject/project.rb
open AppProject/Goldengo.xcodeproj
```

`AppProject/Goldengo.xcodeproj` is intentionally ignored. [`AppProject/project.rb`](AppProject/project.rb) is the source of truth; edit the generator, not the generated `.pbxproj`.

To build for a simulator from the command line:

```sh
xcodebuild \
  -project AppProject/Goldengo.xcodeproj \
  -scheme Goldengo \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Run on a physical device

A simulator build needs no signing team. For a device build, pass your Apple Developer Team ID while generating the project:

```sh
GOLDENGO_DEVELOPMENT_TEAM=YOUR_TEAM_ID bundle exec ruby AppProject/project.rb
```

Then open the project and select your team for both `Goldengo` and `GoldengoWidgetExtension`. Forks should also replace the bundle IDs, iCloud container, and App Group in `AppProject/project.rb` with identifiers owned by their Apple Developer account.

The checked-in identifiers are:

- App: `com.goldengo.app`
- Widget: `com.goldengo.app.widget`
- CloudKit: `iCloud.com.goldengo.app`
- App Group: `group.com.goldengo.app`

CloudKit, App Groups, and push-enabled device provisioning require a paid Apple Developer Program membership. Without that provisioning, Goldengo falls back to a local store. For TestFlight or App Store distribution, deploy the CloudKit schema to production before release.

## Quick capture

Goldengo exposes a **Log Expense** App Shortcut. It can be invoked from Siri, Spotlight, the Shortcuts app, the Action Button, or a user-configured Back Tap shortcut. Goldengo does not configure physical-device triggers automatically.

## Repository layout

```text
AppProject/                 iOS app, widget, entitlements, and Xcode generator
Sources/GoldengoCore/       value types and domain logic
Sources/GoldengoData/       SwiftData models, storage, export, and exchange rates
Sources/GoldengoImport/     local CSV/PDF statement parsing
Sources/GoldengoFeatures/   SwiftUI feature screens
Sources/GoldengoIntents/    App Intents and shortcut support
Tests/                      headless unit and integration tests
docs/                       design notes and implementation plans
```

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Please report vulnerabilities privately according to [SECURITY.md](SECURITY.md), especially anything involving financial-data exposure, imported documents, CloudKit boundaries, or formula injection.

## License

Goldengo is available under the [MIT License](LICENSE).
