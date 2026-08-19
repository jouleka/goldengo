# Contributing to Goldengo

Thanks for helping improve Goldengo.

## Development workflow

1. Fork the repository and create a focused branch from `main`.
2. Make the smallest coherent change and add or update tests.
3. Run `swift test --quiet`.
4. If app or widget wiring changed, run `bundle install`, regenerate with `bundle exec ruby AppProject/project.rb`, and build the `Goldengo` scheme for an iOS Simulator.
5. Open a pull request that explains the user-visible behavior, validation, and any privacy or migration implications.

The generated `AppProject/Goldengo.xcodeproj` is ignored. Change `AppProject/project.rb` instead of committing generated project files.

## Privacy rules

- Never commit real statements, receipts, account numbers, personal exports, signing certificates, provisioning profiles, tokens, or `.env` files.
- Test fixtures must be synthetic and clearly labeled.
- Changes that transmit data must document exactly what leaves the device and why.
- Preserve Goldengo's local-only fallback and do not imply that bank linking exists unless a real, reviewed integration is implemented.

## Style and tests

Follow the existing Swift 6 conventions and keep domain logic in the package layer when possible. Regression fixes should include a focused test. Avoid unrelated formatting churn.

For security issues, do not open a public issue; follow [SECURITY.md](SECURITY.md).
