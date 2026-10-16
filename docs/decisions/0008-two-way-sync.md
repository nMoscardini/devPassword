# 0008 Two-way sync between Mac and iPhone

Date: 15 October 2026. Status: accepted by Nino, build not started. Record type: lite (Personal). Supersedes the "iPhone read-only viewer" line in SPEC.md and decision 0007's iPhone section.

- **Decision.** The iPhone app edits records, and changes sync both ways between Mac and iPhone through CloudKit (private database, CKSyncEngine), using the model in decision 0001: one encrypted record per entry, a revision counter, a deleted flag, keep both on conflict.
- **Why.** Nino, 15 October: "if I am out and about and I change something on my phone I need it synced. If I can't edit then I have to write it down. UNSAFE." A read-only phone pushes changes into notes or paper. That is the "real limit" SPEC.md named as the reason to add sync.
- **Rules.**
  - Records travel sealed under the vault key, exactly as stored. CloudKit sees ciphertext, record counts and timing only.
  - Conflict: both versions kept, the newer shown, the other marked for Nino to choose. Never a silent overwrite.
  - The Mac takes a snapshot (N3) before applying a batch of incoming changes. Encrypted backups continue unchanged.
  - Amended 16 October (Nino): only Apple-imported logins that hold something of Nino's go to the iPhone: a second password, his own notes, custom fields or a pasted picture (`Entry.belongsOnPhone`). Plain Apple snapshots stay on the Mac; Passwords on the iPhone already has them. Site logos sync too (they are in backups since 16 October).
  - Apple-imported logins (0007) sync as read-only on both devices. Only the Mac imports from Apple Passwords. Nino's own fields on them (your notes, second password, tags, group) stay editable on both.
  - Groups sync as one sealed list; last change wins, with the previous list kept in the snapshot.
  - Vault key on the iPhone: Keychain, this device only, Face ID current set. First unlock with the vault password.
  - A recovery code reset changes the key: the other device must unlock with the vault password once.
- **Proof first (half a day).** CloudKit from the signed, non-sandboxed Mac app (decision 0002), with iCloud entitlement and container. If it needs App Sandbox, stop and decide before building.
- **Nino's side.** Turn on iCloud Advanced Data Protection (already an open item).
- **Reversal point.** Lost edits or conflicts keep-both cannot resolve in real use; or CloudKit proves unreliable.
