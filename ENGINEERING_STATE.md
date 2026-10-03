# devPassword - Engineering State

Authoritative state document (devDesign principle 9). Update at the end of every session.

## Status

Class Personal. Stage 1 (local vault, Mac). Source written 3 October 2026. Build and tests: see Last verified.

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
| 2026-10-03 | Touch ID via signed Xcode app, Keychain-held key | Nino asked; spec F10 | 0004 |
| 2026-10-03 | Record types: login, secure note, payment card, bank account, identity document, plus custom fields | Spec v1.1 | - |

## Open items

- Reuse check against Apple Passwords and KeePass-format apps. Waits on Nino. Due before Stage 2.
- Stage 0 proof: signing, Keychain access control, Touch ID keyboard, CloudKit records, AutoFill in Nino's browser.
- Off-site copy of the backup folder and a written loss and downtime tolerance (N4). Waits on Nino choosing the destination.
- Backup register row in `~/devDesign/REFERENCE_ARCHITECTURE.md`. Add once the destination is known.
- Sample CSV exports from LastPass and mSecure (synthetic or a few dummy records) to tune the importer's column guesses.
- KDF work factor confirmed against the benchmark on the slowest device (iPhone) in Stage 0.
- Independent security review of `VaultCore` before real records go in. Who and when: Nino to decide.
- N6 note before any other person's documents enter the vault.
- Put the project in git. `.gitignore` is ready.

## Known problems

- Swift `String` values cannot be zeroed. Decrypted records sit in memory while unlocked and are released on lock. As the spec says, no guarantee of erasure.
- No sandbox (decision 0002). The vault file is readable by any process running as Nino. It holds ciphertext only.
- Importer column guesses are untested against real LastPass and mSecure files.
- Running from the package, macOS may show the app with a generic icon.

## Run, stop, recover, back up

See README.md.

## Backup register (this project)

| Dataset | Working copy | Second device | Off-site | Last restore test |
|---|---|---|---|---|
| devPassword vault (Nino) | Mac Studio, Application Support | Not set | Not set | Automated test only (BackupTests, smoke test). No real drill yet |

## Last verified

2026-10-03 17:24: build passed; 4 of 31 tests FAILED (snapshot check and CSV CRLF quoting). Earlier report of a pass was wrong: only the log tail was read. Both fixed, re-run pending. Smoke test on 1,000 synthetic records: search 3 ms. KDF 600,000 iterations: 84 ms on the Mac Studio.

Not verified: the Mac app's screens by a person; the importer on real export files; KDF timing on iPhone.

## Session log

- 2026-10-03: Settings moved from SwiftUI Settings scene (fixed size) to a normal resizable window, 760 by 680 default, 600 by 480 minimum. Command-comma unchanged.
- 2026-10-03: Lock screen colour added to Appearance. Padlock app icon (original design, generated) added to the signed app.
- 2026-10-03: Settings > Appearance: colour for each of the three panes, or System. Stored per Mac in UserDefaults.
- 2026-10-03: Touch ID prompts automatically on app activation, Mac wake or unlock, launch and idle lock. Not straight after Command-L or the Lock button. Automatic attempts fail quietly; the button shows errors.
- 2026-10-03: Touch ID added. Package split into VaultCore, DevPasswordUI, DevPasswordMac. Signed app project to be created in App/ by Nino. Touch ID not unit-testable; manual checks: enable, unlock, cancel, wrong finger, passphrase fallback, fingerprint change, swift run error message.
- 2026-10-03: Fix: local snapshots were written in WAL mode and failed their read-only check, blocking passphrase change, recovery code replacement and purge. Snapshots now finalised as single files. Fix: CSV writer did not quote CRLF. smoke.sh now ends with SMOKE PASSED or SMOKE FAILED.
- 2026-10-03: Fix: Replace Recovery Code changed the code before it was confirmed, and the idle lock could close the screen while it was being written down, leaving no known code. Now two steps (prepare, then commit after typing it back), Cancel changes nothing, idle lock paused while a code is shown. Recovery unlock shows a live character count and tells a typo apart from an old code. Row numbers removed from the code display.
- 2026-10-03: Smoke test passed. Recovery code screen made taller and scrollable, code shown in numbered rows of four groups.
- 2026-10-03: Spec reviewed against devDesign. Spec v1.1 adds cards, bank accounts and identity documents. Stage 1 core and Mac app written. Decisions 0001 to 0003 recorded.
