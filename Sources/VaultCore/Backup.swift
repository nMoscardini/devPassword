import Foundation
import CryptoKit

/// Portable encrypted backup (spec section 8). Holds encrypted records, the header with both
/// wrapped keys, and a manifest sealed under the vault key. Opens with the passphrase or the
/// recovery code. Never depends on a device Keychain.
public struct BackupArchive: Codable {
    public static let formatName = "devPassword-backup"
    public static let fileExtension = "dpbackup"

    public var format: String
    public var formatVersion: Int
    public var createdAt: Date
    public var header: VaultHeader
    public var entries: [SealedEntry]
    public var sealedManifest: Data
}

struct BackupManifest: Codable {
    var entryCount: Int
    var digest: Data
    var createdAt: Date
}

public struct BackupPreview {
    public let createdAt: Date
    public let vaultID: UUID
    public let entryCount: Int
    public let deletedCount: Int
    public let countsByType: [RecordType: Int]
    public let sampleTitles: [String]
}

/// A backup that has been opened and fully verified. Only this can be restored.
public struct OpenedBackup {
    public let archive: BackupArchive
    public let preview: BackupPreview
    let key: SymmetricKey
}

public enum Backup {
    /// Builds an archive from the unlocked vault. Records are copied as stored, still encrypted.
    public static func makeArchive(from vault: Vault) throws -> BackupArchive {
        let key = try vault.requireKey()
        let entries = try vault.allSealed()
        let created = Date()
        let manifest = BackupManifest(entryCount: entries.count, digest: try digest(entries), createdAt: created)
        let sealedManifest = try VaultCrypto.seal(try JSONEncoder().encode(manifest), key: key,
                                                  context: vault.header.manifestContext())
        return BackupArchive(format: BackupArchive.formatName, formatVersion: 1, createdAt: created,
                             header: vault.header, entries: entries, sealedManifest: sealedManifest)
    }

    public static func write(_ archive: BackupArchive, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(archive)
        try data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public static func read(from url: URL) throws -> BackupArchive {
        let data = try Data(contentsOf: url)
        let archive: BackupArchive
        do {
            archive = try JSONDecoder().decode(BackupArchive.self, from: data)
        } catch {
            throw VaultError.corrupt("Not a devPassword backup")
        }
        guard archive.format == BackupArchive.formatName else { throw VaultError.corrupt("Not a devPassword backup") }
        guard archive.formatVersion <= 1 else { throw VaultError.unsupportedVersion(archive.formatVersion) }
        return archive
    }

    public static func open(_ archive: BackupArchive, passphrase: String) throws -> OpenedBackup {
        try verify(archive, key: try archive.header.unwrap(passphrase: passphrase))
    }

    public static func open(_ archive: BackupArchive, recoveryCode: String) throws -> OpenedBackup {
        try verify(archive, key: try archive.header.unwrap(recoveryCode: recoveryCode))
    }

    /// Checks the manifest, the digest over every record, and decrypts every record.
    static func verify(_ archive: BackupArchive, key: SymmetricKey) throws -> OpenedBackup {
        let manifestData: Data
        do {
            manifestData = try VaultCrypto.open(archive.sealedManifest, key: key, context: archive.header.manifestContext())
        } catch {
            throw VaultError.corrupt("Backup manifest failed its integrity check")
        }
        let manifest = try JSONDecoder().decode(BackupManifest.self, from: manifestData)
        guard manifest.entryCount == archive.entries.count else {
            throw VaultError.corrupt("Backup holds \(archive.entries.count) records but the manifest says \(manifest.entryCount)")
        }
        guard try digest(archive.entries) == manifest.digest else {
            throw VaultError.corrupt("Backup records do not match the manifest")
        }
        var counts: [RecordType: Int] = [:]
        var deleted = 0
        var titles: [String] = []
        for s in archive.entries {
            let e: Entry
            do {
                e = try Vault.decryptEntry(s, key: key, header: archive.header)
            } catch {
                throw VaultError.corrupt("A record in the backup failed its integrity check")
            }
            if e.isDeleted { deleted += 1 } else { counts[e.type, default: 0] += 1 }
            if !e.isDeleted && titles.count < 8 { titles.append(e.title) }
        }
        let preview = BackupPreview(createdAt: archive.createdAt, vaultID: archive.header.vaultID,
                                    entryCount: archive.entries.count, deletedCount: deleted,
                                    countsByType: counts, sampleTitles: titles.sorted())
        return OpenedBackup(archive: archive, preview: preview, key: key)
    }

    /// Writes a verified backup into a folder, reads it back to verify it, and keeps the newest `keep`.
    @discardableResult
    public static func writeToFolder(vault: Vault, folder: URL, keep: Int = 4) throws -> URL {
        let key = try vault.requireKey()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let archive = try makeArchive(from: vault)
        let url = folder.appendingPathComponent("devPassword-backup-\(Vault.timestamp()).\(BackupArchive.fileExtension)")
        try write(archive, to: url)
        _ = try verify(try read(from: url), key: key)
        prune(folder: folder, keep: keep)
        vault.audit("backup.written")
        Log.backup.info("event=backup.written count=\(archive.entries.count, privacy: .public)")
        return url
    }

    /// Deletes older backups made by this app only. Never touches other files.
    static func prune(folder: URL, keep: Int) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return }
        let ours = names.filter { $0.hasPrefix("devPassword-backup-") && $0.hasSuffix(".\(BackupArchive.fileExtension)") }.sorted()
        for name in ours.dropLast(keep) {
            try? fm.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    /// Restores a verified backup to `url`. The new vault is built beside the old one first.
    /// The current vault, if any, is kept as "vault.before-restore-<time>.sqlite".
    /// The caller must close any open Vault at `url` first.
    /// Stage 1 keeps the backup's vault ID. The spec's fresh-ID rule arrives with sync (see docs/decisions).
    public static func restore(_ opened: OpenedBackup, to url: URL) throws {
        let fm = FileManager.default
        let staging = URL(fileURLWithPath: url.path + ".restoring")
        for suffix in ["", "-wal", "-shm"] { try? fm.removeItem(atPath: staging.path + suffix) }

        let db = try SQLiteDB(path: staging.path)
        try Vault.createSchema(db)
        try db.transaction {
            try Vault.writeHeader(opened.archive.header, to: db)
            for s in opened.archive.entries {
                try db.run("INSERT INTO entries (entry_id, key_id, payload_version, revision, sealed) VALUES (?, ?, ?, ?, ?)",
                           [.text(s.entryID.uuidString), .text(s.keyID.uuidString),
                            .int(Int64(s.payloadVersion)), .int(Int64(s.revision)), .blob(s.sealed)])
            }
            try db.run("INSERT INTO audit (at, action) VALUES (?, 'vault.restored_from_backup')",
                       [.int(Int64(Date().timeIntervalSince1970))])
        }
        try db.exec("PRAGMA wal_checkpoint(TRUNCATE)")
        db.close()

        if fm.fileExists(atPath: url.path) {
            let aside = url.deletingPathExtension().path + ".before-restore-\(Vault.timestamp()).sqlite"
            for suffix in ["", "-wal", "-shm"] where fm.fileExists(atPath: url.path + suffix) {
                try fm.moveItem(atPath: url.path + suffix, toPath: aside + suffix)
            }
        }
        try fm.moveItem(at: staging, to: url)
        for suffix in ["-wal", "-shm"] { try? fm.removeItem(atPath: staging.path + suffix) }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        Log.backup.info("event=backup.restored count=\(opened.archive.entries.count, privacy: .public)")
    }

    static func digest(_ entries: [SealedEntry]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let sorted = entries.sorted { $0.entryID.uuidString < $1.entryID.uuidString }
        return Data(SHA256.hash(data: try encoder.encode(sorted)))
    }
}
