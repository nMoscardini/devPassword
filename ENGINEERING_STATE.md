# devPassword - Engineering State

Authoritative state document (devDesign principle 9). Update at the end of every session.

## Status

Class: Personal. Version: 0.1. Stage 1 (local vault, Mac) working and in daily trial with test data: Touch ID, import, backup, appearance settings. Not yet trusted with real records (see Open items).

## What it is

A password and personal-records manager for Nino's Mac and iPhone, with an encrypted vault he owns and no subscription. Stage 1 is a local-only Mac app over a shared Swift core.

## Current architecture

- `VaultCore` Swift package library. CryptoKit AES-256-GCM per record, fresh 96-bit nonce, context binds vault ID, record ID, revision, payload version and key ID. Random 256-bit vault key wrapped twice: under PBKDF2-HMAC-SHA256 (600,000 iterations, 128-bit salt, CommonCrypto) of the NFC-normalised passphrase, and under HKDF of a 256-bit recovery secret.
- Store: one SQLite file, local disk, WAL, secure_delete on. Tables `meta` (header JSON), `entries` (encrypted records), `audit` (action names and times only).
- Mac interface: `DevPasswordUI` library in the package. Two ways to run it: the signed Xcode app in `App/` (Touch ID), or `swift run DevPasswordMac` (unsigned, no Touch ID). Same vault file. No sandbox, no network.
- Touch ID: vault key in the data protection Keychain, this device only, biometryCurrentSet. Passphrase and recovery code always work. Decision 0004.
- Nothing listens on a port. Nothing is exposed. Not a Server Manager service.

## Decisions

| Date | Decision | Why | Record |
|---|---|---|---|
| 2026-10-03 | Build Stage 1 (local vault) before Stage 0 proof | Nino's choice. Core is platform-proof independent | - |
| 2026-10-03 | Simplified record and sync model | Principles 2 and 6 | 0001 |
| 2026-10-03 | Stage 1 app runs from the package, passphrase unlock only | Stage 0 has not proved signing or Keychain | 0002 |
| 2026-10-03 | Stage 1 restore keeps the vault ID | No cloud copy yet | 0003 |
| 2026-10-04 | Act on ChatGPT security review; AI review accepted in place of a human expert | No human reviewer available | 0005 |
| 2026-10-03 | Touch ID via signed Xcode app, Keychain-held key | Nino asked; spec F10 | 0004 |
| 2026-10-03 | Record types: login, secure note, payment card, bank account, identity document, plus custom fields | Spec v1.1 | - |

## Open items

- Change the master passphrase before real data goes in: the current test passphrase was shown in a screenshot during the restore test on 4 October (N1).

- Reuse check against Apple Passwords and KeePass-format apps. Waits on Nino. Due before Stage 2.
- Stage 0 proof: signing, Keychain access control, Touch ID keyboard, CloudKit records, AutoFill in Nino's browser.
- Off-site copy of the backup folder and a written loss and downtime tolerance (N4). Waits on Nino choosing the destination.
- Backup register row in `~/devDesign/REFERENCE_ARCHITECTURE.md`. Add once the destination is known.
- Sample CSV exports from LastPass and mSecure (synthetic or a few dummy records) to tune the importer's column guesses.
- KDF work factor confirmed against the benchmark on the slowest device (iPhone) in Stage 0.
- Security review: done by ChatGPT on 4 October (decision 0005), fixes applied. Still to do: a second AI pass on the fixed code, and a review of the UI layer.
- N6 note before any other person's documents enter the vault.

## Known problems

- Old record versions could be swapped back in by something with write access to the vault as Nino's user (review finding 6). Accepted for Stage 1.
- Encrypted backups made before a passphrase or recovery code change still open with the old secret. The app says so. Delete old backups if a secret is compromised.

- Swift `String` values cannot be zeroed. Decrypted records sit in memory while unlocked and are released on lock. As the spec says, no guarantee of erasure.
- No sandbox (decision 0002). The vault file is readable by any process running as Nino. It holds ciphertext only.
- Importer column guesses are untested against real LastPass and mSecure files.
- Running from the package, macOS may show the app with a generic icon.

## Run, stop, recover, back up

See README.md.

## Backup register (this project)

| Dataset | Working copy | Second device | Off-site | Last restore test |
|---|---|---|---|---|
| devPassword vault (Nino) | Mac Studio, Application Support | Weekly encrypted backup to the folder set in Settings (OneDrive) | OneDrive (cloud) | 2026-10-04: restore drill passed in the app (backup, move items to Deleted, restore, items back) |

## Last verified

2026-10-04: `scripts/smoke.sh` printed SMOKE PASSED with 13 record types, the mSecure importer (every field of Nino's 14-type test export), UK dates, MOT and renewal expiry, per-item icons, restore with Touch ID, and the security review fixes. Restore drill passed in the app. Signed app built and run by Nino; Touch ID enable, unlock, cancel and wrong finger checked.

Not verified: Touch ID after a fingerprint change; full import of Nino's real mSecure export (in progress); LastPass import; restore from a copy downloaded from the OneDrive website onto a clean account.

## Session log

- 2026-10-04: Types Email Account, Insurance (renewal date in Expiring Soon; mSecure 'Date' read as renewal date, to be confirmed by Nino) and Registration Code added; mSecure mapping updated. Generator and previous-password history now also apply to email passwords.
- 2026-10-04: New record types Prescription and Vehicle (mSecure Prescriptions and Vehicle Info mapped; RX number kept as custom field). Vehicle next MOT (last MOT + 1 year) appears in Expiring Soon. Dates accept DD/MM/YYYY. Sort by name, recently changed or longest unchanged. Emergency sheet (print, no secrets printed; code written by hand). Setup screen can now restore from a backup on a new Mac: a gap against the spec's clean-device restore requirement.
- 2026-10-04: Per-item icon choice (Entry.icon, optional, encrypted with the record; old records decode unchanged; tested).
- 2026-10-04: mSecure importer added (MSecureImporter.swift), built from Nino's test export with every field named; all 12 mSecure types mapped, unknown types kept as secure notes with numbered fields; comma or tab files. Tests in MSecureImporterTests. Fixed: selecting a type in the sidebar did not filter.
- 2026-10-04: Restore no longer shows an alert over the Touch ID prompt (green note on the lock screen instead); Settings closes after restore. Restore window offers Touch ID for backups of the same vault (Backup.open withUnlockedVault, tested). App is brought forward before the automatic Touch ID prompt. Touch ID is never used to reset the vault password (by design).
- 2026-10-04: Restore drill passed. UI now says vault password, not passphrase or master password (code and file format unchanged). Fixed: cancelling the Touch ID prompt brought it straight back; the system prompt's cancel button now reads Use Vault Password.
- 2026-10-04: Restore moved to its own step-by-step sheet (Vault > Restore from Backup…). Passphrase and recovery code fields are now hidden by default with a show button; recovery code entry shows a character count and warns when the input is not a code.
- 2026-10-04: Restore test confusion: items removed with Delete go to the Deleted list, so a backup restore found nothing missing and was not run. Renamed Delete to Move to Deleted and Restore to Put Back, added Vault > Restore from Backup…, logged move and put back in the activity log. scripts/diagnose.sh added (read-only counts and log).
- 2026-10-04: Security review (ChatGPT) received. Fixed findings 1 to 4 and file permissions; 5 and 6 accepted. Decision 0005. New tests: hostile work factor, export needs passphrase, owner-only files, snapshots removed after credential change.
- 2026-10-03: Project in git (github.com/nMoscardini/devPassword, first commit pushed). Picked up automatically by devGitStatus and devProjectStatus. Version set to 0.1.
- 2026-10-03: Settings moved from SwiftUI Settings scene (fixed size) to a normal resizable window, 760 by 680 default, 600 by 480 minimum. Command-comma unchanged.
- 2026-10-03: Lock screen colour added to Appearance. Padlock app icon (original design, generated) added to the signed app.
- 2026-10-03: Settings > Appearance: colour for each of the three panes, or System. Stored per Mac in UserDefaults.
- 2026-10-03: Touch ID prompts automatically on app activation, Mac wake or unlock, launch and idle lock. Not straight after Command-L or the Lock button. Automatic attempts fail quietly; the button shows errors.
- 2026-10-03: Touch ID added. Package split into VaultCore, DevPasswordUI, DevPasswordMac. Signed app project to be created in App/ by Nino. Touch ID not unit-testable; manual checks: enable, unlock, cancel, wrong finger, passphrase fallback, fingerprint change, swift run error message.
- 2026-10-03: Fix: local snapshots were written in WAL mode and failed their read-only check, blocking passphrase change, recovery code replacement and purge. Snapshots now finalised as single files. Fix: CSV writer did not quote CRLF. smoke.sh now ends with SMOKE PASSED or SMOKE FAILED.
- 2026-10-03: Fix: Replace Recovery Code changed the code before it was confirmed, and the idle lock could close the screen while it was being written down, leaving no known code. Now two steps (prepare, then commit after typing it back), Cancel changes nothing, idle lock paused while a code is shown. Recovery unlock shows a live character count and tells a typo apart from an old code. Row numbers removed from the code display.
- 2026-10-03: Smoke test passed. Recovery code screen made taller and scrollable, code shown in numbered rows of four groups.
- 2026-10-03: Spec reviewed against devDesign. Spec v1.1 adds cards, bank accounts and identity documents. Stage 1 core and Mac app written. Decisions 0001 to 0003 recorded.
- 2026-10-04: Sidebar click-again-to-deselect reverted (a tap gesture fought List selection). All sidebar rows now built by one ForEach over SidebarFilter?, after hand-written rows stopped responding. Clear a filter by clicking All Items.
- 2026-10-04: mSecure export writes unquoted line breaks in notes. Reader rejoins split items (MSecureImporter.rejoin). Website-less logins now matched on title plus username (false conflicts, skipped rows). Import preview lists problems first and names the item before a rejected row. scripts/csvshape.py prints a CSV's shape with no contents. Smoke passed.
