# devPassword - CLAUDE.md

Nino's password and personal-records manager for Mac and iPhone. Class: Personal. Follows `~/devDesign` (read DESIGN_PRINCIPLES.md and REFERENCE_ARCHITECTURE.md first).

Read in this order: `ENGINEERING_STATE.md` (authoritative state), `SPEC.md` (one page), `docs/decisions/`. The full design is `Personal_Password_Manager_Specification.docx`.

## Layout

- `Sources/VaultCore` - model, encryption, SQLite store, backup, CSV, Touch ID Keychain code. No UI. Shared with the future iPhone app.
- `Sources/DevPasswordUI` - SwiftUI Mac screens.
- `Sources/DevPasswordMac` - `swift run` entry point. Unsigned, no Touch ID.
- `App/devPassword` - signed Xcode app (Touch ID). A thin wrapper: keep logic in the package.
- `Tests/VaultCoreTests` - unit tests and the smoke test. Synthetic data only.

## Verify

`scripts/smoke.sh`. The last line of `logs/smoke-latest.log` is SMOKE PASSED or SMOKE FAILED. Read that line, not the tail of the test output. Touch ID and Keychain code cannot run in `swift test`: check by hand and say so.

## Rules

- Never put a real vault, CSV export, backup, passphrase or recovery code into an AI session, a log, a test or git (N1).
- Any change that rewrites vault data takes a snapshot first (N3). Schema changes are scripted migrations.
- Do not weaken the crypto, the fail-closed checks or the two-step recovery code replacement without a decision record.
- Small changes, one purpose each. Update ENGINEERING_STATE.md (session log, last verified) in the same change.
- Short sentences, plain words, hyphens not em dashes.
