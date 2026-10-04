# devPassword - CLAUDE.md

Nino's password and personal-records manager for Mac and iPhone. Class: Personal. Follows `~/devDesign` (read DESIGN_PRINCIPLES.md and REFERENCE_ARCHITECTURE.md first).

Read in this order: `ENGINEERING_STATE.md` (authoritative state), `SPEC.md` (one page), `docs/decisions/`. The full design is `Personal_Password_Manager_Specification.docx`.

## Current status (4 October 2026)

Stage 1 Mac app working and in daily use by Nino.

- Encrypted vault, vault password and recovery code, Touch ID unlock (signed Xcode app), idle lock.
- 13 record types, including prescriptions, vehicles, email accounts, insurance and registration codes. Expiry dates, favourites, icons, sort, emergency sheet.
- Encrypted backup and restore, restore drill passed, backup folder copied to OneDrive. Restore works with password, recovery code or Touch ID.
- CSV import with an mSecure reader: rejoins items split by mSecure's unquoted line breaks. Real import being checked: expect 248 new, 0 rejected.
- Settings: Security, Backup, Export, Activity, Appearance.
- Security review by ChatGPT accepted in place of a human expert (decision 0005).

Recent fixes not yet confirmed by Nino on his Mac: sidebar rows all built one way (top rows were not clickable), darker favourite star.

## Next major task: AutoFill in the browser

The spec's riskiest assumption. Not started. Plan:

1. Nino uses Safari and Chrome (stated 4 October 2026). Both must be tested. Test site: a public practice login page such as https://the-internet.herokuapp.com/login (published dummy credentials), so no real account is involved.
2. Proof first (about half a day): a minimal AutoFill credential provider extension offering one hard-coded synthetic login, tested in Safari and his browser. Answers whether that browser uses macOS third-party providers.
3. If it works: decision record reversing 0002 (extension must be sandboxed), move the vault to a shared App Group container by scripted migration with a snapshot first, share the Touch ID Keychain item with the extension, publish website and username (never passwords) to the credential identity store, recorded as a decision.
4. If it does not: decide between a browser extension (large, new attack surface) and a quick-fill window with a global shortcut and clipboard clearing (small, works everywhere).

Other open items: see ENGINEERING_STATE.md.

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
