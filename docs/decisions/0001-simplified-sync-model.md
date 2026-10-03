# 0001 Simplified record and sync model

Date: 3 October 2026. Status: accepted. Record type: lite (Personal).

- **Decision.** One encrypted record per entry with a revision counter and a deleted flag. The previous password is one field inside the record. On a sync conflict, keep both. No revision graph, no custom outbox, no full history.
- **Why.** The spec's immutable revision graph, sibling revisions, encrypted history, tombstone ancestry and custom outbox are more machinery than one person with two devices needs. CKSyncEngine already persists pending changes, so a second outbox would be a second source of truth (principle 6). Fewer parts means fewer ways to corrupt a vault.
- **Principle affected.** 2 (keep it simple) and 6 (one source of truth). Departs from spec v1.1 sections 4 and 6.
- **Reversal point.** Real use shows lost edits or conflicts that keep-both cannot resolve, or a second regular user edits the same vault.
