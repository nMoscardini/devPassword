# 0005 Response to the VaultCore security review

Date: 4 October 2026. Status: accepted. Record type: lite (Personal).

- **Decision.** Act on the source review (`docs/reviews/2026-10-04-securityCheck.md`) and the vault file inspection (`docs/reviews/2026-10-04-vaultSecurity.md`), both dated 4 October 2026 and carried out by ChatGPT. Fixed: findings 1 to 4 and file permissions. Accepted: findings 5 and 6. The independent review gate is met by a cross-model AI review, not a human expert, because no human security reviewer is available to Nino.
- **Why.** An AI reviewer from a different vendor than the one that wrote the code is the best review available. It is materially better than self-review, and weaker than a human specialist.
- **Principle affected.** Spec section 9 ("a focused security review closes material findings").
- **Reversal point.** A human security reviewer becomes available, the app is used by anyone beyond Nino and Debbie, or sync (Stage 2) changes the threat surface. Then review again.

## What changed

| Finding | Response |
|---|---|
| 1 Callers can set weak KDF iterations | `Vault.create` no longer takes an iteration count publicly. Changing the passphrase raises any lower work factor to 600,000. |
| 2 No maximum work factor | Headers asking for more than 10,000,000 iterations are refused as damaged. |
| 3 Old snapshots open with old credentials | The new passphrase or recovery code is verified before saving, then every local snapshot is removed. The app tells the user that older encrypted backups still open with the old secret and to make a new backup. |
| 4 Plaintext export guarded only by the UI | Export is now `Vault.exportPlaintextCSV(passphrase:)`. The CSV builder is internal to the core. |
| 5 Sensitive values not cleared from memory | Accepted. Swift cannot guarantee it. Listed under Known problems. |
| 6 Older record versions can be replayed | Accepted for Stage 1: needs write access to the vault as Nino's user, outside the spec's threat boundary. Revisit with a sealed vault-wide manifest in Stage 2. |
| F1 SQLite side files at 0644 | Vault file pre-created at 0600 so -wal and -shm inherit it. Existing files tightened on open. App sets umask 077. |
| F2 Legacy WAL-mode snapshot | Leftover from the snapshot bug fixed on 3 October. Removed by the next credential change, or delete by hand. |

## Still to do

- Second cross-model review of the fixed code (a different AI, same brief).
- End-to-end review of the UI layer, as both reports recommend: clipboard, export file handling, entitlements, crash reporting.
