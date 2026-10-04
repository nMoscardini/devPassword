import Foundation
import CryptoKit

public struct LoadResult {
    public var entries: [Entry]
    /// Entry IDs that failed their integrity check. They stay on disk untouched.
    public var failedIDs: [UUID]
}

public struct AuditRecord: Identifiable, Hashable {
    public let id: Int64
    public let at: Date
    public let action: String
}

/// The encrypted local vault: one SQLite file holding encrypted records only.
/// Thread use: create and use from one place at a time (the app's main actor).
public final class Vault: @unchecked Sendable {
    public static let schemaVersion = 1
    public static let snapshotsToKeep = 10

    public let fileURL: URL
    let db: SQLiteDB
    public private(set) var header: VaultHeader
    private var key: SymmetricKey?

    public var isUnlocked: Bool { key != nil }
    public var vaultID: UUID { header.vaultID }

    private init(fileURL: URL, db: SQLiteDB, header: VaultHeader) {
        self.fileURL = fileURL
        self.db = db
        self.header = header
    }

    // MARK: Create and open

    public static func exists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Creates a new vault and returns it unlocked, with the recovery code to show once.
    public static func create(at url: URL, passphrase: String) throws -> (vault: Vault, recoveryCode: String) {
        try create(at: url, passphrase: passphrase, iterations: VaultCrypto.defaultIterations)
    }

    /// Internal so only this module and its tests can choose the work factor (security review finding 1).
    static func create(at url: URL, passphrase: String, iterations: Int) throws -> (vault: Vault, recoveryCode: String) {
        try PassphrasePolicy.validate(passphrase)
        guard !exists(at: url) else { throw VaultError.alreadyExists }
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])

        let vaultKey = SymmetricKey(size: .bits256)
        let recovery = RecoveryCode.generate()
        var header = VaultHeader(vaultID: UUID(), keyID: UUID(), kdfSalt: VaultCrypto.randomBytes(16),
                                 kdfIterations: iterations, recoverySalt: VaultCrypto.randomBytes(16))
        try header.wrap(vaultKey, passphrase: passphrase, newSalt: false)
        try header.wrap(vaultKey, recoverySecret: recovery.secret, newSalt: false)

        FilePermissions.createPrivateFile(url.path)
        let db = try SQLiteDB(path: url.path)
        try createSchema(db)
        try writeHeader(header, to: db)
        FilePermissions.tighten(url.path)

        let vault = Vault(fileURL: url, db: db, header: header)
        vault.key = vaultKey
        vault.audit("vault.created")
        Log.vault.info("event=vault.created")
        return (vault, recovery.code)
    }

    /// Opens an existing vault, locked.
    public static func open(at url: URL) throws -> Vault {
        guard exists(at: url) else { throw VaultError.notFound }
        FilePermissions.tighten(url.path)
        let db = try SQLiteDB(path: url.path)
        FilePermissions.tighten(url.path)
        let version = db.userVersion
        guard version != 0 else { throw VaultError.corrupt("Not a devPassword vault") }
        guard version <= schemaVersion else { throw VaultError.unsupportedVersion(version) }
        // Future schema migrations go here, each after a snapshot (N3).
        guard let header = try readHeader(from: db) else { throw VaultError.corrupt("Vault header missing") }
        guard header.formatVersion <= VaultHeader.currentFormat else {
            throw VaultError.unsupportedVersion(header.formatVersion)
        }
        return Vault(fileURL: url, db: db, header: header)
    }

    static func createSchema(_ db: SQLiteDB) throws {
        try db.exec("""
            CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value BLOB NOT NULL);
            CREATE TABLE IF NOT EXISTS entries (
                entry_id TEXT PRIMARY KEY,
                key_id TEXT NOT NULL,
                payload_version INTEGER NOT NULL,
                revision INTEGER NOT NULL,
                sealed BLOB NOT NULL
            );
            CREATE TABLE IF NOT EXISTS audit (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                at INTEGER NOT NULL,
                action TEXT NOT NULL
            );
            """)
        try db.setUserVersion(schemaVersion)
    }

    static func writeHeader(_ header: VaultHeader, to db: SQLiteDB) throws {
        let data = try JSONEncoder().encode(header)
        try db.run("INSERT OR REPLACE INTO meta (key, value) VALUES ('header', ?)", [.blob(data)])
    }

    static func readHeader(from db: SQLiteDB) throws -> VaultHeader? {
        guard let data = try db.query("SELECT value FROM meta WHERE key = 'header'").first?.first?.blob else { return nil }
        return try JSONDecoder().decode(VaultHeader.self, from: data)
    }

    public func close() {
        lock()
        db.close()
    }

    // MARK: Lock and unlock

    public func unlock(passphrase: String) throws {
        do {
            key = try header.unwrap(passphrase: passphrase)
            Log.vault.info("event=vault.unlocked method=passphrase")
        } catch {
            Log.vault.notice("event=vault.unlock_failed method=passphrase")
            throw error
        }
    }

    public func unlock(recoveryCode: String) throws {
        do {
            key = try header.unwrap(recoveryCode: recoveryCode)
            audit("vault.unlocked_with_recovery_code")
            Log.vault.info("event=vault.unlocked method=recovery")
        } catch {
            Log.vault.notice("event=vault.unlock_failed method=recovery")
            throw error
        }
    }

    public func lock() {
        key = nil
    }

    // MARK: Touch ID

    /// Stores the vault key in this device's Keychain behind Touch ID. Vault must be unlocked.
    public func enableBiometricUnlock() throws {
        try BiometricUnlock.store(try requireKey(), header: header)
        audit("vault.biometric_enabled")
        Log.vault.info("event=vault.biometric_enabled")
    }

    public func disableBiometricUnlock() {
        BiometricUnlock.remove(header: header)
        audit("vault.biometric_disabled")
        Log.vault.info("event=vault.biometric_disabled")
    }

    /// Shows the Touch ID prompt and unlocks. Blocks while the prompt is up: call off the main thread.
    public func unlockWithBiometrics(reason: String) throws {
        let candidate = try BiometricUnlock.load(header: header, reason: reason)
        // Prove the stored key really opens this vault before trusting it.
        if let first = try allSealed().first, (try? Vault.decryptEntry(first, key: candidate, header: header)) == nil {
            BiometricUnlock.remove(header: header)
            Log.vault.error("event=vault.biometric_key_mismatch")
            throw VaultError.biometricUnavailable("The key stored for Touch ID does not open this vault. It has been removed. Unlock with your passphrase.")
        }
        key = candidate
        Log.vault.info("event=vault.unlocked method=biometric")
    }

    /// Fresh authentication check, for sensitive actions such as plaintext export.
    public func verify(passphrase: String) -> Bool {
        (try? header.unwrap(passphrase: passphrase)) != nil
    }

    func requireKey() throws -> SymmetricKey {
        guard let key else { throw VaultError.locked }
        return key
    }

    // MARK: Records

    public func loadAll() throws -> LoadResult {
        let key = try requireKey()
        var entries: [Entry] = []
        var failed: [UUID] = []
        for sealed in try allSealed() {
            do {
                entries.append(try decrypt(sealed, key: key, header: header))
            } catch {
                failed.append(sealed.entryID)
                Log.vault.error("event=entry.integrity_failed entry=\(sealed.entryID.uuidString, privacy: .public)")
            }
        }
        return LoadResult(entries: entries, failedIDs: failed)
    }

    @discardableResult
    public func save(_ entry: Entry) throws -> Entry {
        try saveAll([entry])[0]
    }

    /// Saves all entries in one transaction: all or nothing.
    @discardableResult
    public func saveAll(_ entries: [Entry]) throws -> [Entry] {
        let key = try requireKey()
        let header = self.header
        let saved: [Entry] = try db.transaction {
            var out: [Entry] = []
            for var e in entries {
                e.modified = Date()
                let current = try db.query("SELECT revision FROM entries WHERE entry_id = ?",
                                           [.text(e.id.uuidString)]).first?.first?.int ?? 0
                let revision = Int(current) + 1
                let plaintext = try JSONEncoder().encode(e)
                let context = header.entryContext(entryID: e.id, revision: revision,
                                                  payloadVersion: Entry.payloadVersion, keyID: header.keyID)
                let sealed = try VaultCrypto.seal(plaintext, key: key, context: context)
                try db.run("""
                    INSERT INTO entries (entry_id, key_id, payload_version, revision, sealed) VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(entry_id) DO UPDATE SET key_id = excluded.key_id,
                        payload_version = excluded.payload_version, revision = excluded.revision, sealed = excluded.sealed
                    """, [.text(e.id.uuidString), .text(header.keyID.uuidString),
                          .int(Int64(Entry.payloadVersion)), .int(Int64(revision)), .blob(sealed)])
                out.append(e)
            }
            return out
        }
        Log.vault.info("event=entries.saved count=\(saved.count, privacy: .public)")
        return saved
    }

    /// Removes a record for good. Takes a snapshot first (N3).
    public func purge(id: UUID) throws {
        _ = try requireKey()
        try snapshot(reason: "purge")
        try db.run("DELETE FROM entries WHERE entry_id = ?", [.text(id.uuidString)])
        audit("entry.purged")
        Log.vault.info("event=entry.purged entry=\(id.uuidString, privacy: .public)")
    }

    func allSealed() throws -> [SealedEntry] {
        try db.query("SELECT entry_id, key_id, payload_version, revision, sealed FROM entries ORDER BY entry_id").map { row -> SealedEntry in
            guard row.count == 5,
                  let id = row[0].text.flatMap(UUID.init(uuidString:)),
                  let keyID = row[1].text.flatMap(UUID.init(uuidString:)),
                  let pv = row[2].int, let rev = row[3].int, let sealed = row[4].blob else {
                throw VaultError.corrupt("Malformed record row")
            }
            return SealedEntry(entryID: id, keyID: keyID, payloadVersion: Int(pv), revision: Int(rev), sealed: sealed)
        }
    }

    static func decryptEntry(_ s: SealedEntry, key: SymmetricKey, header: VaultHeader) throws -> Entry {
        guard s.payloadVersion <= Entry.payloadVersion else { throw VaultError.unsupportedVersion(s.payloadVersion) }
        let context = header.entryContext(entryID: s.entryID, revision: s.revision,
                                          payloadVersion: s.payloadVersion, keyID: s.keyID)
        let plaintext = try VaultCrypto.open(s.sealed, key: key, context: context)
        let entry = try JSONDecoder().decode(Entry.self, from: plaintext)
        guard entry.id == s.entryID else { throw VaultError.authenticationFailed }
        return entry
    }

    private func decrypt(_ s: SealedEntry, key: SymmetricKey, header: VaultHeader) throws -> Entry {
        try Vault.decryptEntry(s, key: key, header: header)
    }

    // MARK: Secrets

    /// Changes the master passphrase by rewrapping the vault key. Records are not re-encrypted.
    public func changePassphrase(current: String, new: String) throws {
        try PassphrasePolicy.validate(new)
        let vaultKey = try header.unwrap(passphrase: current)
        try rewrapPassphrase(vaultKey, new: new)
    }

    /// Sets a new passphrase after unlocking with the recovery code.
    public func setPassphraseAfterRecovery(_ new: String) throws {
        try PassphrasePolicy.validate(new)
        try rewrapPassphrase(try requireKey(), new: new)
    }

    private func rewrapPassphrase(_ vaultKey: SymmetricKey, new: String) throws {
        try snapshot(reason: "passphrase-change")
        var updated = header
        // Never keep a work factor below the current baseline once the passphrase changes.
        updated.kdfIterations = max(updated.kdfIterations, VaultCrypto.defaultIterations)
        try updated.wrap(vaultKey, passphrase: new, newSalt: true)
        // Prove the new wrapper opens the same key before saving it.
        guard VaultCrypto.keyData(try updated.unwrap(passphrase: new)) == VaultCrypto.keyData(vaultKey) else {
            throw VaultError.crypto("The new passphrase did not verify. Nothing was changed.")
        }
        try db.transaction { try Vault.writeHeader(updated, to: db) }
        header = updated
        key = vaultKey
        audit("vault.passphrase_changed")
        Log.vault.info("event=vault.passphrase_changed")
        retireSnapshotsAfterCredentialChange()
    }

    /// Step 1 of replacing the recovery code: make a new code. Changes nothing.
    /// Show it, have the user confirm it, then call commitRecoveryCode.
    public func prepareRecoveryCode() -> PendingRecoveryCode {
        let r = RecoveryCode.generate()
        return PendingRecoveryCode(code: r.code, secret: r.secret)
    }

    /// Step 2: make the confirmed code the vault's recovery code. The old code stops working.
    /// Older backups still open with the old code.
    public func commitRecoveryCode(_ pending: PendingRecoveryCode) throws {
        let vaultKey = try requireKey()
        try snapshot(reason: "recovery-change")
        var updated = header
        try updated.wrap(vaultKey, recoverySecret: pending.secret, newSalt: true)
        guard VaultCrypto.keyData(try updated.unwrap(recoveryCode: pending.code)) == VaultCrypto.keyData(vaultKey) else {
            throw VaultError.crypto("The new recovery code did not verify. Nothing was changed.")
        }
        try db.transaction { try Vault.writeHeader(updated, to: db) }
        header = updated
        audit("vault.recovery_code_replaced")
        Log.vault.info("event=vault.recovery_code_replaced")
        retireSnapshotsAfterCredentialChange()
    }

    /// Security review finding 3. Every local snapshot holds the key wrapped under the OLD
    /// passphrase or recovery code. Once the new one is saved and verified, remove them all so
    /// the old secret no longer opens anything on this Mac. The snapshot taken just before the
    /// change has done its job (N3): the change succeeded. Encrypted backups elsewhere are not
    /// touched; the app tells the user to make a fresh one.
    /// Deleting on an SSD does not guarantee erasure; FileVault covers what remains.
    private func retireSnapshotsAfterCredentialChange() {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: snapshotsDirectory.path) else { return }
        var removed = 0
        for name in names where name.hasPrefix("vault-") {
            if (try? fm.removeItem(at: snapshotsDirectory.appendingPathComponent(name))) != nil { removed += 1 }
        }
        audit("snapshots.retired_after_credential_change")
        Log.vault.info("event=snapshots.retired count=\(removed, privacy: .public)")
    }

    /// Plaintext CSV of every record, only after the passphrase is re-entered (security review finding 4).
    /// Keep the returned string for as short a time as possible.
    public func exportPlaintextCSV(passphrase: String) throws -> (csv: String, count: Int) {
        guard verify(passphrase: passphrase) else { throw VaultError.wrongSecret }
        let entries = try loadAll().entries.filter { !$0.isDeleted }
        let csv = try CSVExport.make(entries)
        audit("export.plaintext_csv")
        Log.vault.info("event=export.plaintext_csv count=\(entries.count, privacy: .public)")
        return (csv, entries.count)
    }

    /// Both steps at once. Tests only: the app must always confirm before committing.
    func replaceRecoveryCode() throws -> String {
        let pending = prepareRecoveryCode()
        try commitRecoveryCode(pending)
        return pending.code
    }

    // MARK: Snapshots (N3) and audit

    public var snapshotsDirectory: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("Snapshots", isDirectory: true)
    }

    /// Local copy taken with SQLite's backup API before any destructive change, then opened
    /// to confirm it is readable. Same device only: this is not the off-site backup.
    @discardableResult
    public func snapshot(reason: String) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: snapshotsDirectory, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        let stamp = Vault.timestamp()
        let dest = snapshotsDirectory.appendingPathComponent("vault-\(stamp)-\(reason).sqlite")
        FilePermissions.createPrivateFile(dest.path)
        try db.backup(to: dest.path)
        FilePermissions.tighten(dest.path)
        let check = try SQLiteDB(path: dest.path, readOnly: true)
        let ok = (try? Vault.readHeader(from: check)) != nil
        check.close()
        guard ok else { throw VaultError.database("Snapshot did not open. Change cancelled.") }
        pruneSnapshots()
        Log.vault.info("event=snapshot.taken reason=\(reason, privacy: .public)")
        return dest
    }

    private func pruneSnapshots() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: snapshotsDirectory.path) else { return }
        let snaps = files.filter { $0.hasPrefix("vault-") && $0.hasSuffix(".sqlite") }.sorted()
        for name in snaps.dropLast(Vault.snapshotsToKeep) {
            try? fm.removeItem(at: snapshotsDirectory.appendingPathComponent(name))
        }
    }

    /// Records that a sensitive action happened. Never what it contained.
    public func audit(_ action: String) {
        try? db.run("INSERT INTO audit (at, action) VALUES (?, ?)",
                    [.int(Int64(Date().timeIntervalSince1970)), .text(action)])
    }

    public func auditLog(limit: Int = 200) -> [AuditRecord] {
        let rows = (try? db.query("SELECT id, at, action FROM audit ORDER BY id DESC LIMIT ?", [.int(Int64(limit))])) ?? []
        return rows.compactMap { r in
            guard let id = r[0].int, let at = r[1].int, let action = r[2].text else { return nil }
            return AuditRecord(id: id, at: Date(timeIntervalSince1970: TimeInterval(at)), action: action)
        }
    }

    static func timestamp(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return f.string(from: date)
    }
}
