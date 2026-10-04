# Vault File Security Inspection

**Inspected location:** `~/Library/Application Support/devPassword/`  
**Inspection date:** 4 October 2026  
**Inspection type:** Read-only filesystem and SQLite structural review

## Executive summary

The inspected vault files do not show evidence of plaintext password exposure. The live vault contains three records, all stored as encrypted binary values. SQLite integrity checks passed, and no recognisable plaintext password fields, account titles, URLs, private keys, API keys, or secrets were detected in the vault, WAL, or snapshot files.

The main vault and snapshots have owner-only file permissions. The containing directories are also owner-only, which prevents other local user accounts from reaching the files.

Two matters deserve attention:

1. SQLite WAL and SHM sidecar files have `0644` permissions rather than `0600`. The protected parent directory currently prevents access by other local users, but stricter sidecar permissions would improve defence-in-depth.
2. One older snapshot carries legacy WAL-mode state and cannot be opened through an ordinary read-only SQLite connection. Its underlying database passes an immutable integrity check, but it has reduced portability and should not be relied upon as the only recovery copy.

## Files discovered

### Live vault

- `vault.sqlite`
- `vault.sqlite-wal`
- `vault.sqlite-shm`

### Snapshots

- `Snapshots/vault-20261003-172818-346-recovery-change.sqlite`
- `Snapshots/vault-20261003-173332-922-recovery-change.sqlite`
- One snapshot SHM sidecar associated with the newer snapshot

### Previous restored vaults

No files matching `vault.before-restore-*.sqlite` were present.

## Permission review

| Item | Permissions | Assessment |
|---|---:|---|
| `devPassword/` directory | `0700` | Good - accessible only by the owner |
| `Snapshots/` directory | `0700` | Good - accessible only by the owner |
| `vault.sqlite` | `0600` | Good - readable and writable only by the owner |
| Snapshot database files | `0600` | Good - readable and writable only by the owner |
| `vault.sqlite-wal` | `0644` | Should be tightened to `0600` |
| `vault.sqlite-shm` | `0644` | Should be tightened to `0600` |
| Snapshot SHM sidecar | `0644` | Should be tightened or removed when safely obsolete |

The `0644` sidecars are not currently reachable by other local accounts because the parent directory is `0700`. However, their permissions could become significant if a sidecar is copied elsewhere or the directory permissions are weakened later.

## Live vault inspection

The live database reported:

- SQLite schema version: 1
- Journal mode: WAL
- Tables: `meta`, `entries`, `audit`, and `sqlite_sequence`
- Stored entries: 3
- Entries stored as encrypted BLOBs: 3
- Entries stored in another form: 0
- Encrypted record sizes: 292 to 383 bytes
- PBKDF2 iteration count: 600,000
- Header stored under the expected `header` metadata key
- SQLite integrity result: `ok`

The entries table contains only the expected record metadata and encrypted payload:

- Entry identifier
- Key identifier
- Payload version
- Revision number
- Sealed encrypted BLOB

No plaintext title, username, password, notes, URL, or custom-field columns exist in the database schema.

## Plaintext exposure scan

The main database, active WAL, and snapshot databases were checked for recognisable plaintext patterns associated with:

- Password and username JSON fields
- Titles, notes, and custom fields
- HTTP and HTTPS URLs
- Private-key headers
- API-key labels
- Secret labels

No matching plaintext patterns were found.

This scan is useful evidence that records are being written in encrypted form. It is not a mathematical proof that every possible secret is absent, because an arbitrary value may not match a recognisable pattern.

## WAL and SHM assessment

The WAL file contains database changes that have not necessarily been checkpointed into the main `vault.sqlite` file. The main vault file is currently only 4 KB, while the WAL is considerably larger. Therefore, much of the current database state may exist in the WAL.

The WAL contains encrypted entry BLOBs rather than plaintext record data. The SHM file is SQLite coordination and WAL-index data rather than a password store.

These files must not be removed, renamed, or copied independently while the application is open. Copying only `vault.sqlite` may produce an incomplete or unusable copy.

**Recommendation:** Use the application's backup function instead of manually copying the live SQLite files.

## Snapshot assessment

Two recovery-change snapshots were present, which is within the configured retention limit of ten.

Both snapshots passed an underlying SQLite integrity check and contained the expected tables and header metadata. They contained no saved entries at the time they were created.

The older snapshot retains WAL-mode database state and cannot be opened through an ordinary read-only SQLite connection when its associated sidecars are absent. It can be inspected in immutable mode and reports an intact database.

This aligns with the documented historical issue in which older snapshots were left in WAL mode. The newer snapshot opens normally as a self-contained database.

**Recommendation:** Create and verify a fresh application backup. Once its restoration has been tested, consider retiring the legacy snapshot through an application-supported maintenance process.

## Historical credential warning

Snapshots taken before a recovery-code or passphrase change contain the older wrapped vault key. If a snapshot contains records, someone who obtains that snapshot and knows the credential that was valid when it was created may be able to decrypt its historical contents.

In this inspection, the two discovered snapshots contained no entries. Nevertheless, future snapshots may contain records, so credential rotation should not automatically be treated as revoking access to all historical copies.

## Recommended actions

1. Ensure SQLite creates WAL and SHM files with `0600` permissions.
2. Keep the `devPassword` and `Snapshots` directories at `0700`.
3. Do not manually copy or delete live SQLite files while the application is running.
4. Use the application's encrypted backup workflow.
5. Create a fresh backup and perform a controlled restoration test.
6. Treat historical snapshots and backups as still accessible with their historical credentials.
7. Consider removing the orphaned snapshot SHM file through a safe application maintenance function.
8. Recheck file and sidecar permissions after application updates or restores.

## Conclusion

The inspected vault artefacts do not currently expose plaintext passwords. The database structure, encrypted BLOB storage, PBKDF2 configuration, integrity results, and plaintext-pattern scan are consistent with the intended encrypted-vault design.

The current `0700` parent directory protects the more permissive WAL and SHM files, but those sidecars should still be created with `0600` permissions. The older WAL-mode snapshot is intact but less portable, so a newly created and restoration-tested encrypted backup is the best next step.

## Scope and limitations

This was a read-only inspection. No passwords, recovery codes, or passphrases were requested, and no attempt was made to decrypt stored records.

The inspection does not cover runtime process memory, clipboard history, screen capture, Time Machine or other system backups, cloud synchronisation outside this directory, malware running as the same user, or the security of external backup destinations.
