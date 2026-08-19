# Security policy

## Supported version

Security fixes are applied to the latest revision of `main`. Older commits and private forks are not maintained as separate release lines.

## Report a vulnerability

Please use [GitHub private vulnerability reporting](https://github.com/jouleka/goldengo/security/advisories/new). Do not include financial records, statements, credentials, or exploit details in a public issue.

Useful reports include clear reproduction steps, the affected commit, impact, and a minimal synthetic proof of concept. Areas of particular interest are:

- unintended disclosure of financial records or imported documents;
- CloudKit, App Group, widget, or local-store boundary failures;
- unsafe CSV/PDF parsing or spreadsheet-formula execution;
- path traversal, unsafe temporary files, or resource-exhaustion inputs;
- accidental credentials, signing material, or private data in the repository.

You should receive an acknowledgment within seven days. Please allow time to investigate and ship a coordinated fix before publishing details.

## If a secret is exposed

Revoke or rotate it first. Removing a value from the latest commit does not remove it from Git history. Repository maintainers will assess whether history rewriting and downstream coordination are necessary.
