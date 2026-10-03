# devPassword - SPEC

One-page spec per devDesign PROJECT_TEMPLATE v3.0. The full design is `Personal_Password_Manager_Specification.docx` (v1.1). Where they disagree, this page and `docs/decisions/` win.

- **Class.** Personal. Only Nino uses it, it holds no data about other people yet, and nothing is reachable from the internet. Moves to Shared at Stage 4 (Debbie), or earlier if another person's documents are loaded into Nino's vault. See the challenge in `SPEC_REVIEW_2026-10-03.md`.
- **Problem.** Nino's credentials and personal records are split between LastPass (iPhone) and mSecure (Intel Mac app nearing end of support). He will not take on another subscription.
- **Success.** Nino imports his records, finds and copies them on Mac and iPhone, edits on either, sees changes converge, and restores the vault on a replacement device from a backup plus his passphrase or recovery code. Normal use never needs the Mac Studio running.
- **Riskiest assumption.** That a self-built vault matches the convenience of the current apps, AutoFill in his real browser above all, without becoming a security liability. Stage 0 tests AutoFill. The Mac app tests daily-use convenience. Reuse check still owed (see below).
- **Version 1 scope.** In: record types login, secure note, payment card, bank account, identity document, custom fields; search; generator; lock; CSV import; encrypted backup and restore; plaintext CSV export; iCloud sync; AutoFill for logins. Out: passkeys, one-time codes, attachments and scans, sharing, card AutoFill, Windows, Android, AI.
- **People and data.** No data about other people in Stages 0 to 3. Before Debbie joins, or before another person's passport or card goes into Nino's vault, write the N6 note: purpose, basis, who can see it, retention of deleted records, deletion. Nobody is ranked (N7).
- **Architecture in brief.** Swift package `VaultCore` (model, crypto, SQLite store, backup, CSV) shared by a SwiftUI macOS app now and an iOS app later. One encrypted SQLite file per device on local disk. iCloud private database (CloudKit) for sync from Stage 2. Nothing exposed, no Mac server, no NAS, no tunnel.
- **Reuse check.** Owed before Stage 2. Apple Passwords covers logins, sync and sharing for free but not cards or identity documents. KeePass-format apps (Strongbox, KeePassium) cover records with an open file format. Record the outcome as a decision.
- **Failure and recovery.** Every change saved locally before it is acknowledged. A local snapshot (SQLite backup API) before every destructive change. Weekly encrypted backup to a chosen folder, newest four kept, each verified by reading it back. Off-site copy and restore cadence: see the backup section of ENGINEERING_STATE.md.
- **AI use.** None in the product. AI is used to write code: no real vault, CSV export, passphrase or recovery code ever goes into an AI session (N1).
- **Verification.** `scripts/smoke.sh` builds, runs every test, and runs the end-to-end smoke test on a 1,000-record synthetic vault. Manual checks on the Mac app are listed in ENGINEERING_STATE.md.
- **Deviations.** `docs/decisions/0001` to `0003`.
