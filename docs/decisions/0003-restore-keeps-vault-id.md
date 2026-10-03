# 0003 Stage 1 restore keeps the backup's vault ID

Date: 3 October 2026. Status: accepted. Record type: lite (Personal).

- **Decision.** Restoring a backup writes its encrypted records and header byte for byte into a new vault file. The vault ID is kept. The previous vault is moved aside as `vault.before-restore-<time>.sqlite`, never deleted.
- **Why.** The spec's "restore into a fresh vault ID and reconnect sync deliberately" protects the cloud copy from being overwritten. There is no cloud copy until Stage 2. Keeping records byte for byte means a restore cannot introduce a re-encryption bug.
- **Principle affected.** None. Departs from spec v1.1 section 8 (Restore and secret changes) for Stage 1 only.
- **Reversal point.** Stage 2 sync. Restore must then issue a fresh vault ID (re-encrypting records under the new context) or require an explicit choice before reconnecting to iCloud.
