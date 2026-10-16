# devPassword for iPhone - plan (draft, 15 October 2026)

**16 October:** first iPhone version reads the latest encrypted backup, read-only, Face ID; editing waits for sync (Monday). It shows every devPassword record and only those Apple logins that hold something of Nino's (`Entry.belongsOnPhone`). Logos come from the backup; the iPhone never fetches.

**Superseded in part by decision 0008 (two-way sync).** The phone edits and syncs through CloudKit. The read-only and backup-route sections below are now the fallback only. Rewrite this plan at the start of the next session, after the CloudKit proof.

One page. For Nino to approve before any build. Follows decision 0007 and SPEC.md: the iPhone app is a read-only viewer over the latest encrypted backup.

## What it does

- Opens the newest devPassword backup and shows everything in it: records, Apple logins (marked, read-only), groups, favourites, Expiring Soon, search, Hide Apple Logins.
- Detail screen: reveal, copy, "Pick characters" on any hidden field, second passwords.
- Shows the backup's date at the top, and warns when it is older than a limit Nino sets (proposed 7 days).

## What it does not do

No adding or editing, no export, no AutoFill, no sync, no network use, no analytics. Changes happen on the Mac. If read-only proves a real limit, that is a later decision (0007).

## How the backup reaches the phone

The Mac already writes encrypted backups to its backup folder, which Nino copies to OneDrive. A backup is ciphertext: safe in OneDrive.

1. Once: in the iPhone app, Nino picks that backup folder through the Files app (OneDrive shows there). The app remembers the folder.
2. Each time it opens, it loads the newest `devPassword-backup-*.dpbackup` from that folder and keeps a copy inside the app, so it still works with no signal.
3. To keep the phone fresh, the Mac makes a backup automatically after changes (at most daily), not only weekly. Small Mac change.

Fallback if folder access through OneDrive proves unreliable: share the backup to the phone with AirDrop or "Save to Files". Same file, same app.

## Unlock

- First open: vault password (or recovery code). Same key derivation as the Mac.
- Then Face ID: the vault key goes into the iPhone Keychain, this phone only, current faces only, never synced. Same rule as Touch ID on the Mac (decision 0004).
- If a newer backup uses a different key (after a recovery code reset), the app asks for the vault password once more.
- Locks at once when the app goes to the background. The app switcher shows a blank cover, not the screen.
- Copy: clipboard stays on the phone (not shared to the Mac by Universal Clipboard) and clears after 30 seconds.
- Decrypted records live in memory only, dropped on lock. Nothing decrypted is ever written to the phone.

## How it is built

- `VaultCore` already opens and verifies a backup and decrypts every record. The phone needs no database. Add: one function that returns the records from an opened backup, with tests.
- New iOS target in `App/devPasswordiOS`, SwiftUI, iOS 17 or later. Screens share code with the Mac where it fits; the iPhone gets its own simple list and detail layout.
- Stage 0 checks on the real phone: key derivation time (600,000 rounds should take about a second or less), Face ID with the Keychain, folder access to OneDrive.

## Steps

1. Core: records from a backup, freshness, key-mismatch check. Tests with synthetic data. Half a day.
2. iOS app: pick folder, load newest backup, password unlock, list, search, detail. A day.
3. Face ID, lock on background, app switcher cover, clipboard rules. Half a day.
4. Mac: automatic backup after changes. An hour.
5. Nino on his iPhone: install from Xcode, check each item above by hand.

## Decisions for Nino

1. Backup route: OneDrive folder through Files (recommended) or iCloud Drive.
2. Apple developer account: paid (Nino, 15 October). The app stays installed for a year per build. Settled.
3. Freshness limit on the phone: 7 days proposed.
