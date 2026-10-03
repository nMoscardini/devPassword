# devPassword - Spec Review

Reviewed 3 October 2026 against devDesign v3.0 (DESIGN_PRINCIPLES.md, REFERENCE_ARCHITECTURE.md, PROJECT_TEMPLATE.md, REVIEW_PROCESS.md).
Subject: Personal_Password_Manager_Specification.docx, version 1.0, 3 October 2026.

## 1. Bottom line

The security and recovery thinking is strong. Better than most commercial specs. But the spec skips the reuse check (principle 2), and that is the question that decides whether to build at all. It also over-builds sync, leaves the backup minimum half-written, and has no exit route that works if the app stops launching. At risk, not unsafe. Fix before Stage 0, not after.

## 2. Class

Not declared. The class questions give:

- Q1 Does anyone other than Nino use it? Yes, from Stage 4 (Debbie). **Shared.**
- Q3 Internet reachable? No. CloudKit is Apple's service, not an endpoint Nino exposes.

So Personal for Stages 0 to 3, Shared from Stage 4. "A project moves up the moment an answer becomes yes." Shared means full deviation records and a data protection review before Debbie uses it. See the challenge in section 9.

## 3. Gates

| Gate | Score | Evidence |
|---|---|---|
| N1 Secrets | Pass, one gap | Logs, crash data, analytics, Spotlight, snapshots and repo all excluded. Gap: no rule keeping real CSV exports, vault files or passphrases out of AI sessions. Development will be AI-assisted. Add it. |
| N2 Narrow exposure | Pass | Nothing exposed. No tunnel, NAS or Mac server in the runtime path. |
| N3 Backup before destructive change | Unverified | Import is atomic and restore goes to a fresh vault ID. Good. But no stated rule to take and open a fresh backup before a schema migration, bulk import, dedupe, passphrase change or future tombstone compaction. |
| N4 Restore is proven | Unverified | Restore drill before full import, clean-device restore in release evidence. Good. Missing: second device and off-site copy named, loss and downtime tolerance written, retest cadence (twice yearly once Shared). "Nino's existing backup arrangements" is not a destination. The weekly backup folder could sit on the same Mac. Cite reference architecture known gap: off-site not recorded. |
| N5 AI output validated | Not applicable | No AI in the product. AI features deferred. |
| N6 People's data has a purpose | Unverified (Stage 4) | No purpose, basis, retention or deletion page for Debbie. Also: encrypted history and tombstones are kept forever ("without automatic pruning"). Deleted means not deleted. Retention must be stated before she joins. |
| N7 People not ranked | Pass | Nothing ranks people. |
| H1 SQLite on local disk | Pass | App Group container on each device. |
| H2 SQLite backed up with backup tools | Pass, one clarification | The backup of record is the exported archive, not a file copy. Say so. Time Machine or device backups copying the live container do not count as the backup. |
| H3 NAS queue | Not applicable | No NAS. |

## 4. Deviations

| Deviation | Principle | Justified | Recorded | Note |
|---|---|---|---|---|
| "Departure from Python, FastAPI, HTML stack" | Default stack | Not a deviation | n/a | Swift in Xcode **is** the default for iPhone and Mac apps. Delete the paragraph. |
| CloudKit as cloud sync, not the tunnel-to-Mac path | Principle 2 (avoid mandatory cloud), Remote access pattern | Yes. "Normal use never depends on the Mac Studio running." | No | Needs a record. Full record once Shared. |
| Direct Xcode install for Debbie, no TestFlight | Remote access: TestFlight for pilot, App Store for release; Xcode only for an app only Nino uses | Yes. TestFlight builds expire at 90 days, which is worse. | No | Needs a record. Note the key-person consequence (section 7). |
| Custom vault format and crypto, not a mature component | Principle 2 (prefer mature components) | Not yet shown | No | See section 8, change 1. |

## 5. What conforms

- Problem and success stated in observable terms (principle 1).
- Staged delivery with evidence gates. Stage 0 tests the riskiest integration first.
- Security as architecture: encrypt before upload, random IDs, AAD binding, fail-closed, honest threat boundary, no false Secure Enclave or remote-wipe claims (principle 4).
- Local-first, acknowledged edits never lost, bounded retries, idempotent import (principle 3).
- Account isolation for Debbie. No household admin role.
- Scope control and deferred features named (principle 1, add from real use).

## 6. Excess

- **Sync model.** Immutable revision DAG with parent IDs, sibling revisions, encrypted full history, tombstone ancestry, plus a custom durable outbox, plus CKSyncEngine. For one person editing a few hundred entries on two devices, this is engineering gymnastics. CKSyncEngine already persists pending changes, so the custom outbox is a second source of truth (principle 6). Simpler: one CloudKit record per entry, encrypted blob, server change tag for conditional save. On conflict, keep both and flag. Deletion is a deleted-flag record. Keep "previous password" as one encrypted field, not full history.
- **Document size.** About ten pages. The template asks for a one-page SPEC.md plus a state document. The detail is useful but belongs in a design note, not the spec.
- **Performance target** of 5,000 entries. Harmless, but sized to imagination, not use.

## 7. Missing concerns

- **Signing lapse is a lockout.** When the provisioning profile or certificate expires, the app stops launching. AutoFill goes with it. The spec says "renew and redeploy" but gives no fallback if renewal is missed while away, ill, or traveling.
- **Key-person dependency for Debbie.** Her vault opens only in an app Nino builds and signs. If Nino cannot redeploy, she loses access. She needs an exit route that does not need Xcode.
- **No open exit format.** The only non-app route out is plaintext CSV. An export to an open encrypted format (KeePass KDBX) would let any off-the-shelf app open the vault. That removes most of the two risks above.
- **mSecure record types.** The Mac UX says "different categories have different data entry fields", but F01 and F02 define only logins and secure notes. mSecure holds cards, bank accounts, identities and more. The migration does not say what happens to them. Either map them to secure notes or scope categories in. The two statements conflict.
- **SQLite in an App Group on iOS.** An app suspended while holding a SQLite lock in a shared container is killed by iOS (0xdead10cc). "Coordinate app and extension access" should name this and the mitigation.
- **Who does the security review.** It is a release gate but has no owner or cost. Crypto and sync code written with AI assistance needs an independent reviewer, not self-review.
- **Audit trail** (principle 4). Exports, plaintext CSV export, passphrase change and recovery-code use are sensitive actions. Log that they happened, never what.
- **Structured logs and a smoke test** (principle 8). Neither named. For a native app the smoke test is one XCTest scheme against a generated synthetic vault.
- **Editorial.** "Export to csv" in section 8 duplicates F07 in one line. Section 1 names mSecure and then says the name is unconfirmed. Section 10 has an unfinished sentence about developer membership.

## 8. Top three changes, ordered by harm

1. **Do the reuse check before Stage 0 (principle 2, risk to data).** The spec has none, and the template requires one. Apple Passwords (free, end-to-end encrypted iCloud Keychain, AutoFill, CSV import, Chrome extension, shared groups with Debbie) meets "no subscription, Mac and iPhone sync, Debbie later" with zero code. KeePass-format apps meet "I own the vault format" with a documented file. A home-built crypto vault and sync engine is the single largest risk to the data this project protects. If the build still wins, write down why, and adopt KDBX as an export (or the format) so recovery never depends on this app.
2. **Close N3 and N4 (risk to data).** Add the backup-before-destructive-change rule. Name the second device and off-site location. Write loss and downtime tolerance. Set the restore retest cadence. Add a backup register row. Add the signing-lapse fallback.
3. **Simplify sync (risk to data, principles 2 and 6).** Drop the revision DAG and custom outbox. Use CKSyncEngine state as the one source of pending changes, per-entry records with server change tags, keep-both on conflict. Fewer moving parts, fewer ways to corrupt a vault.

Before Stage 4: the N6 page for Debbie, including retention of deleted entries.

Housekeeping: declare the class, move to SPEC.md (one page) plus ENGINEERING_STATE.md, and put the two deviation records in docs/decisions/.

## 9. Challenges

**Class question 1, applied to household use.** Debbie makes this Shared, which triggers full deviation records and a qualified data protection review. Her data never reaches Nino or any system he runs. It sits in her own iCloud under her own keys, and household use falls under the UK GDPR domestic exemption. A qualified review here is waste.

Simplest alternative: treat a household member running their own isolated vault as Personal, with a short N6 note covering retention, deletion and her exit route.

Recommendation: make an exception for this project and record it. Revise question 1 only if a second household case appears. Nino decides.
