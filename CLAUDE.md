# devPassword - CLAUDE.md

Nino's password and personal-records manager for Mac and iPhone. Class: Personal. Follows `~/devDesign` (read DESIGN_PRINCIPLES.md and REFERENCE_ARCHITECTURE.md first).

Read in this order: `ENGINEERING_STATE.md` (authoritative state), `SPEC.md` (one page), `docs/decisions/`. The full design is `Personal_Password_Manager_Specification.docx`.

## Current status (16 October 2026)

Stage 1 Mac app working and in daily use by Nino.

- Encrypted vault, vault password and recovery code, Touch ID unlock (signed Xcode app), idle lock.
- 13 record types, including prescriptions, vehicles, email accounts, insurance and registration codes. Expiry dates, favourites, icons, sort, emergency sheet.
- Encrypted backup and restore, restore drill passed, backup folder copied to OneDrive. Restore works with password, recovery code or Touch ID.
- CSV import with an mSecure reader: rejoins items split by mSecure's unquoted line breaks. Real import being checked: expect 248 new, 0 rejected.
- Settings: Security, Backup, Export, Activity, Appearance.
- Security review by ChatGPT accepted in place of a human expert (decision 0005).

Groups (decision 0006), caravan and guitar icons, coloured icons, dark mode and text colours added 5 October: smoke passed (56 tests), checked by hand by Nino, all working.

Recent fixes not yet confirmed by Nino on his Mac: sidebar rows all built one way (top rows were not clickable), darker favourite star.

## Direction (11 October 2026): decision 0007

Decisions 0008 (two-way sync) and 0009 (site logos, the only network use) were added on 15 October.

Apple Passwords holds live logins and passkeys. devPassword is the system of record: master for all other records, plus a read-only, dated snapshot and history of logins, imported one way from Apple. No editing of Apple-mastered logins (devPassword-mastered logins, for sites Apple cannot fill, stay editable), no generator, no AutoFill, no passkey keys, no write-back to Apple after the one-off migration. Read `docs/decisions/0007-apple-passwords-for-logins.md` before touching logins or the iPhone app.

Done 15 October: Apple snapshot import (CSV route), banking second secrets, LastPass move through Apple, Hide Apple Logins, your notes on Apple logins, inline Touch ID.

Today (16 October, half a day before Nino travels), in order:
1. Site logos (decision 0009): Fetch Logos on request, direct from each site, sealed cache, letter tile fallback. About 2 hours.
2. Double-click a list row opens the item in its own window. All such windows close on lock.
3. Shorter titles for Apple logins: drop leading www., account., login. (display only).
4. Check the Apple row count (787) against Passwords (702 plus 61 Wi-Fi): removed logins probably counted; show them separately.
5. Last hour, always: scripts/smoke.sh, Nino checks by hand, commit, scripts/deploy.sh, so he travels with an installed app.

Monday 19 October: Clean-up (see docs/CLEANUP.md). One screen, rules in order, a tick box per item, nothing deleted automatically.

After that:
- Detail pane as cards; item actions (star, group, edit, delete) beside the title; remove the generator button (0007).
- Two-way sync, decision 0008: CloudKit proof first (half a day), then rewrite docs/IPHONE_PLAN.md, then the iPhone app.
- Credential exchange test (0007), stale-snapshot flag on bank logins, refresh-limit setting.

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
