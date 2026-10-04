# VaultCore Security Review

**Reviewed path:** `/Users/ninomoscardini/devUtils/devPassword/Sources/VaultCore`  
**Review date:** 4 October 2026  
**Review type:** Read-only source-code security assessment

## Executive summary

No hard-coded passwords, secret logging, network transmission, analytics, or obvious plaintext database storage were found in `VaultCore`.

The principal encryption design is sound. Vault records use AES-256-GCM, cryptographically secure randomness, authenticated metadata, and PBKDF2-HMAC-SHA256 with a production default of 600,000 iterations. Backups contain encrypted records, and biometric unlocking stores the vault key in the device-only Keychain behind the current biometric set.

However, several areas should be hardened. The most important are enforcing safe PBKDF2 iteration limits and addressing historical snapshots that remain decryptable using old credentials after a passphrase or recovery-code change.

This review found no direct password-exfiltration path in the reviewed folder. An end-to-end conclusion would also require reviewing the user interface, clipboard behaviour, export destination handling, application entitlements, release configuration, and any code that calls `VaultCore`.

## Findings

### 1. Callers can reduce the passphrase derivation strength

**Severity:** Medium  
**Relevant files:**

- `Vault.swift`, lines 43-45
- `Crypto.swift`, lines 34-37 and 50

`Vault.create` publicly accepts an iteration count. Although the default is 600,000, the validation in `deriveKey` only requires the value to be greater than zero. A caller could therefore create a vault using one PBKDF2 iteration, making an offline passphrase-guessing attack dramatically cheaper.

**Recommendation:** Enforce a secure production minimum during vault creation. If tests need reduced iteration counts, expose that capability only through an internal or test-only path. Do not permit ordinary application code to override the security baseline.

### 2. Unbounded KDF parameters can cause denial of service

**Severity:** Low  
**Relevant files:**

- `Crypto.swift`, lines 34-37 and 50
- `VaultHeader.swift`, lines 62-64

The iteration count stored in the vault header is not constrained by a maximum. A malicious or corrupted vault could request excessive processing. A value outside the range of `UInt32` can also fail during conversion.

This does not disclose passwords, but it may make the application hang or terminate when opening a hostile vault.

**Recommendation:** Validate the iteration count before key derivation using explicit minimum and maximum values. Reject unsupported values with a controlled error.

### 3. Old snapshots remain accessible with old credentials

**Severity:** Medium  
**Relevant file:** `Vault.swift`, lines 273-315 and 324-357

Before changing a passphrase or recovery code, the vault creates a snapshot containing the existing encrypted vault and its existing wrapped key. This is useful for accidental-change recovery, but it means credential rotation does not revoke access to historical snapshots.

If an attacker obtains an older snapshot and knows the old passphrase or recovery code, they can decrypt the passwords stored in that snapshot.

Portable backups have the same expected historical property: an old backup remains accessible using the credential with which its vault key was wrapped.

**Recommendation:**

- Clearly explain this behaviour when credentials are changed.
- Provide a separate “credential compromised” workflow that securely removes, rewraps, or quarantines historical snapshots.
- Help users identify portable backups that must be replaced.
- Consider whether a snapshot should be created before emergency credential rotation.

### 4. Plaintext export protection is enforced outside VaultCore

**Severity:** Low to Medium  
**Relevant file:** `CSV.swift`, lines 74-104

`CSVExport.make` accepts an array of entries and returns a `String` containing all exported values, including passwords and other concealed fields. The export function does not require recent authentication itself.

The current application UI appears to verify the passphrase before invoking export. However, another caller of `VaultCore` could bypass that convention.

**Recommendation:** Place plaintext export behind an authenticated `Vault` operation, or require a short-lived authorization object created after successful credential verification. Keep the resulting plaintext in memory for as little time as possible.

### 5. Sensitive values are not consistently cleared from memory

**Severity:** Low  
**Relevant files:**

- `Crypto.swift`, lines 34-60 and 80-82
- `VaultHeader.swift`, lines 50-76
- `RecoveryCode.swift`, lines 11-18 and 31-47
- `CSV.swift`, lines 83-104

The derived-key byte array is explicitly wiped, which is good. Other sensitive values rely on normal Swift memory management, including passphrase bytes, unwrapped key data, recovery secrets, decrypted JSON data, and plaintext CSV strings.

This is primarily defence-in-depth against process-memory inspection, crash dumps, and swap exposure. Swift does not make guaranteed zeroisation straightforward, especially for `String`, but exposure can still be reduced.

**Recommendation:**

- Keep sensitive temporary values tightly scoped.
- Prefer mutable byte buffers that can be cleared for key material and recovery secrets.
- Avoid unnecessary `Data` and `String` copies.
- Disable or tightly control diagnostic crash collection for production builds containing unlocked-vault data.

### 6. Valid older record versions can be replayed

**Severity:** Low  
**Relevant files:**

- `Vault.swift`, lines 245-269
- `VaultHeader.swift`, lines 42-44

AES-GCM prevents undetected alteration of a record. Its authenticated context includes the entry identifier, revision, payload version, and key identifier. However, an attacker with filesystem access could replace both a record’s ciphertext and its associated database metadata with an older valid version.

This does not reveal the password directly, but it could restore an obsolete password, an older note, or a previously deleted record without detection.

**Recommendation:** Add authenticated vault-wide state, such as a sealed manifest, monotonic revision root, or authenticated chain linking the current record set to the expected vault state.

## Positive security controls

The reviewed code already contains several strong controls:

- AES-256-GCM protects vault records and wrapped keys.
- Fresh nonces are generated for encryption operations.
- Record identity and metadata are authenticated as associated data.
- Random values come from Apple’s cryptographic random source.
- The default PBKDF2-HMAC-SHA256 work factor is 600,000 iterations.
- Passphrases are normalised consistently before derivation.
- Recovery codes contain 256 bits of random secret material.
- Recovery-code transcription errors are detected using a checksum.
- Backups contain encrypted records rather than plaintext entries.
- Backup manifests and record digests are authenticated.
- Biometric key material uses the data-protection Keychain.
- Keychain items are device-only and explicitly non-synchronising.
- Biometric enrollment changes invalidate stored biometric access.
- SQL values are passed through bound parameters.
- SQLite secure deletion is enabled.
- Vault, snapshot, and backup files are normally restricted to owner-only permissions.
- Logs contain event names, counts, and identifiers rather than passwords or stored field values.
- No networking, cloud upload, telemetry, or analytics code was found in `VaultCore`.

## Recommended priority

1. Enforce safe minimum and maximum PBKDF2 iteration counts.
2. Define and implement the security policy for snapshots after compromised credential rotation.
3. Bind plaintext export to recent authentication within the core API.
4. Add tests covering hostile KDF parameters and weak production configuration.
5. Review sensitive-data lifetime in memory.
6. Consider vault-wide rollback detection.

## Scope and limitations

This was a source-code review of `Sources/VaultCore` only. It was not a formal cryptographic audit, penetration test, runtime memory analysis, or verification of the compiled application.

The following areas should be reviewed separately:

- Password and recovery-code text fields
- Clipboard copying and automatic clearing
- Screen capture and application-switcher visibility
- Plaintext CSV file creation, permissions, cleanup, and destination selection
- Import-file lifecycle and temporary-file handling
- Automatic locking and application background behaviour
- macOS sandbox and Keychain entitlements
- Crash reporting and diagnostic collection
- Release-build logging
- FileVault expectations and local backup policy
- All external callers of the `VaultCore` API

## Conclusion

The reviewed code does not contain an obvious mechanism that directly exposes stored passwords. Its encryption, randomness, Keychain configuration, and logging practices are generally well designed.

The two most important improvements are to prevent creation of weakly derived vaults and to handle old snapshots carefully when credentials may have been compromised. Once those are addressed, an end-to-end review of the UI and plaintext export workflow would provide much stronger assurance about the complete application.
