# Security best-practices review

Reviewed: 2026-08-19

Scope: the current Swift/iOS source tree, generated-project configuration, privacy manifests, repository history, dependency surface, and GitHub Actions configuration.

## Executive summary

No known critical, high, or medium-severity findings remain open. The review found two medium-risk data-handling issues and one low-risk repository-portability issue; all three are remediated in the public-release changes. Gitleaks 8.30.1 found no secrets in either the current working tree or all 368 reachable commits.

Goldengo stores financial data locally and can use a user's private CloudKit database when correctly provisioned. The only application network endpoint found is the keyless exchange-rate request documented in the README. This was a source review and build verification, not a third-party penetration test or App Store privacy audit.

## Critical severity

No findings.

## High severity

No findings.

## Medium severity (remediated)

### M-1. CSV exports could trigger spreadsheet formulas

**Risk:** Merchant names, notes, and other imported text were quoted but not neutralized when they began with spreadsheet formula markers. Opening an exported financial-data CSV in a spreadsheet application could therefore evaluate attacker-controlled content.

**Resolution:** The exporter now prefixes formula-like cells before RFC-style quote escaping (`Sources/GoldengoData/IngestionStore+Export.swift:120-126`). The restore path removes the exporter-added prefix so Goldengo round trips the original value (`Sources/GoldengoData/IngestionStore+Restore.swift:22-29`). A regression test covers both neutralization and restoration (`Tests/GoldengoDataTests/ExportTests.swift:80-98`).

### M-2. Sensitive export files had default temporary-file handling

**Risk:** Financial-data exports were written to a predictable temporary filename with default file protection and were not explicitly deleted after sharing. Restore also decoded a selected file before enforcing the existing 25 MB in-memory limit.

**Resolution:** Exports now use unique names, atomic complete-file-protection writes, and explicit cleanup when sharing finishes (`Sources/GoldengoFeatures/Settings/SettingsView.swift:248-273`). Restore checks the file size before reading it into memory (`Sources/GoldengoFeatures/Settings/SettingsView.swift:275-292`); the data layer retains its independent decoded-size guard (`Sources/GoldengoData/IngestionStore+Restore.swift:15-16`).

## Low severity (remediated)

### L-1. The Xcode generator embedded one developer-team identifier

**Risk:** A checked-in Apple Developer Team ID was not a signing secret, but it exposed an organization-specific identifier and made public forks generate a project tied to the original team.

**Resolution:** The generator now reads the optional `GOLDENGO_DEVELOPMENT_TEAM` environment variable and omits the setting by default (`AppProject/project.rb:1-4`, `AppProject/project.rb:24-32`, and `AppProject/project.rb:64-71`). Simulator builds therefore remain unsigned and portable; physical-device setup is documented in the README.

## Informational and residual considerations

### I-1. Preserved Git history contains identity metadata

The preserved 351-commit `main` history includes author email metadata and older revisions containing the former developer-team identifier and a removed local absolute path. These are not authentication credentials, and the full-history secret scan is clean, but they remain publicly discoverable once the repository is public. Removing them would require a disruptive history rewrite; this review intentionally preserves repository history.

### I-2. Apple service identifiers are public configuration

The bundle IDs, iCloud container, App Group, and development push entitlement are expected public application identifiers, not secrets. Forks must replace them with identifiers owned by their Apple Developer account. Distribution still requires correct signing and promotion of the CloudKit schema.

### I-3. Export recipients control the final copy

Goldengo removes its protected temporary export after the share sheet closes, but cannot delete copies saved or transmitted by the user. The README and UI should continue treating CSV exports as sensitive financial documents.

## Existing and added controls

- App and widget privacy manifests declare no tracking or collected-data categories.
- App Transport Security does not allow arbitrary loads.
- The Swift package has no third-party package dependencies; the Xcode generator dependency is pinned in `Gemfile.lock`.
- `.gitignore` excludes environment files, signing material, local databases, and generated financial exports.
- GitHub Actions are SHA-pinned and run tests, an unsigned generated-project build, full-history secret scanning, CodeQL for Swift, and pull-request dependency review.
- `SECURITY.md` directs vulnerability reports to GitHub's private reporting channel.

## Verification performed

- `swift test --quiet`: 521 tests passed.
- Generated `AppProject/Goldengo.xcodeproj` from the checked-in Ruby source of truth.
- Unsigned `Goldengo` build for the generic iOS Simulator: succeeded.
- Gitleaks 8.30.1 directory scan: no leaks in approximately 800 MB scanned.
- Gitleaks 8.30.1 full-history scan: no leaks in 368 reachable commits.
- Workflow YAML parsing and ignored-file checks: passed.
