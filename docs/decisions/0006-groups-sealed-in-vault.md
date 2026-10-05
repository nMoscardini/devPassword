# 0006 Groups are stored sealed in the vault and carried by backups

Date: 5 October 2026. Status: accepted. Record type: lite (Personal).

- **Decision.** Nino can define groups (name and icon) in Settings > Groups. Each record is in at most one group (`Entry.groupID`). Groups show in the sidebar under Favourites, with a count. Favourites stay separate. The group list is one value in the `meta` table, sealed with AES-256-GCM under the vault key, bound to the vault ID and key ID (`devPassword-groups-v1`). Backups carry the sealed list, and the sealed manifest holds its SHA-256, so a changed, swapped or removed list makes the backup fail its check.
- **Why.** A group name such as "Medical" says something on its own. UserDefaults would leave it in plain text, leave it out of backups and never reach the iPhone.
- **What it does not change.** No SQL schema change: older records decode with no group. The backup format stays version 1: the new fields are optional, and backups made before groups still open. The crypto, fail-closed checks and credential handling are unchanged. Group changes are not re-encrypted on a passphrase change, because they sit under the vault key, not the passphrase.
- **Rules.** Deleting a group asks first, takes a snapshot (N3), then clears the group from its records, including ones in Deleted. Filing a record in a group does not change its "changed" date, so "Longest unchanged first" still means the content. If the stored list fails its check, groups are hidden and cannot be edited, so a damaged list is never overwritten.
- **Accepted risk.** As with records (decision 0005, finding 6), an older sealed group list from the same vault could be put back by something with write access to the vault file. Same reversal point: Stage 2.
- **Not done.** Groups are not in the plaintext CSV export.
