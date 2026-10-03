# devPassword

Nino's personal password manager for Mac and iPhone. Class: Personal. Stage 1: local vault on the Mac.

Read first: `SPEC.md` (one page), `ENGINEERING_STATE.md` (where it stands), `docs/decisions/`.
Design standards: `~/devDesign`.

## Layout

- `Sources/VaultCore` - shared core: record model, encryption, SQLite store, backup, CSV import and export, password generator. No UI.
- `Sources/DevPasswordUI` - the SwiftUI Mac interface.
- `Sources/DevPasswordMac` - `swift run` entry point. Unsigned, no Touch ID.
- `App/` - the signed Xcode app. Thin wrapper around `DevPasswordUI`. Has Touch ID.
- `Tests/VaultCoreTests` - unit tests and the smoke test. Synthetic data only.
- `scripts/smoke.sh` - build and run every test. Writes `logs/smoke-latest.log`.

## Run

Daily use, with Touch ID: open `App/devPassword/devPassword.xcodeproj` in Xcode and press Command-R.

Quick check without signing: `swift run DevPasswordMac` in this folder. No Touch ID.

Both use the same vault file.

## Stop

Quit the app (Command-Q). The vault locks on quit, sleep, screen lock, Command-L, and after 5 minutes without input.

## Test

```
scripts/smoke.sh
```

## Where the data lives

- Vault: `~/Library/Application Support/devPassword/vault.sqlite`. Encrypted records only. Never copy this file while the app is running (H2). Use Back Up Now.
- Local snapshots, taken before every destructive change: `~/Library/Application Support/devPassword/Snapshots/`. Newest ten kept. Same disk, so not a backup.
- Encrypted backups: the folder chosen in Settings > Backup. Newest four kept, each verified after writing.

## Back up

Settings > Backup > choose a folder, then Back Up Now. Weekly backups run on unlock when one is due. The folder must itself be copied to a second device and off-site (devDesign principle 3). That is not yet set up: see ENGINEERING_STATE.md.

## Recover

- Forgot the passphrase: on the lock screen choose "Use recovery code", then set a new passphrase.
- Vault file lost or damaged: Settings > Backup > Restore. Opens with the passphrase current when the backup was made, or the recovery code. The current vault is kept beside the restored one, never deleted.
- Lost both passphrase and recovery code: there is no way back. That is the design.

## Update

Pull the source, run `scripts/smoke.sh`, then run the app. Back up first (N3). Schema changes are scripted migrations that take a snapshot first.

## Rules for working on this project

- Never put a real vault, CSV export, passphrase or recovery code into an AI session, a log, a test, or git (N1).
- Synthetic data in tests only.
- Plaintext CSV exports stay out of cloud folders and get deleted after use.
