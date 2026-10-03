import Foundation
import CryptoKit

/// Public vault parameters plus the two wrapped copies of the vault key.
/// The wrappers authenticate the vault ID, key ID and KDF parameters, so changing
/// any of them makes unwrapping fail.
public struct VaultHeader: Codable, Equatable {
    public static let currentFormat = 1

    public var formatVersion: Int
    public var vaultID: UUID
    public var keyID: UUID
    public var kdfAlgorithm: String
    public var kdfSalt: Data
    public var kdfIterations: Int
    public var passphraseWrap: Data
    public var recoverySalt: Data
    public var recoveryWrap: Data
    public var created: Date

    init(vaultID: UUID, keyID: UUID, kdfSalt: Data, kdfIterations: Int, recoverySalt: Data) {
        self.formatVersion = VaultHeader.currentFormat
        self.vaultID = vaultID
        self.keyID = keyID
        self.kdfAlgorithm = "PBKDF2-HMAC-SHA256"
        self.kdfSalt = kdfSalt
        self.kdfIterations = kdfIterations
        self.passphraseWrap = Data()
        self.recoverySalt = recoverySalt
        self.recoveryWrap = Data()
        self.created = Date()
    }

    func passphraseContext() -> Data {
        Data("devPassword-wrap-v1|passphrase|\(vaultID.uuidString)|\(keyID.uuidString)|\(kdfAlgorithm)|\(kdfIterations)|\(kdfSalt.base64EncodedString())".utf8)
    }

    func recoveryContext() -> Data {
        Data("devPassword-wrap-v1|recovery|\(vaultID.uuidString)|\(keyID.uuidString)|\(recoverySalt.base64EncodedString())".utf8)
    }

    func entryContext(entryID: UUID, revision: Int, payloadVersion: Int, keyID: UUID) -> Data {
        Data("devPassword-entry-v1|\(vaultID.uuidString)|\(entryID.uuidString)|\(revision)|\(payloadVersion)|\(keyID.uuidString)".utf8)
    }

    func manifestContext() -> Data {
        Data("devPassword-manifest-v1|\(vaultID.uuidString)|\(keyID.uuidString)".utf8)
    }

    mutating func wrap(_ vaultKey: SymmetricKey, passphrase: String, newSalt: Bool) throws {
        if newSalt { kdfSalt = VaultCrypto.randomBytes(16) }
        let kek = try VaultCrypto.deriveKey(passphrase: passphrase, salt: kdfSalt, iterations: kdfIterations)
        passphraseWrap = try VaultCrypto.seal(VaultCrypto.keyData(vaultKey), key: kek, context: passphraseContext())
    }

    mutating func wrap(_ vaultKey: SymmetricKey, recoverySecret: Data, newSalt: Bool) throws {
        if newSalt { recoverySalt = VaultCrypto.randomBytes(16) }
        let kek = RecoveryCode.wrappingKey(secret: recoverySecret, salt: recoverySalt)
        recoveryWrap = try VaultCrypto.seal(VaultCrypto.keyData(vaultKey), key: kek, context: recoveryContext())
    }

    func unwrap(passphrase: String) throws -> SymmetricKey {
        let kek = try VaultCrypto.deriveKey(passphrase: passphrase, salt: kdfSalt, iterations: kdfIterations)
        guard let raw = try? VaultCrypto.open(passphraseWrap, key: kek, context: passphraseContext()) else {
            throw VaultError.wrongSecret
        }
        return SymmetricKey(data: raw)
    }

    func unwrap(recoveryCode: String) throws -> SymmetricKey {
        let secret = try RecoveryCode.parse(recoveryCode)
        let kek = RecoveryCode.wrappingKey(secret: secret, salt: recoverySalt)
        guard let raw = try? VaultCrypto.open(recoveryWrap, key: kek, context: recoveryContext()) else {
            throw VaultError.wrongSecret
        }
        return SymmetricKey(data: raw)
    }
}

/// A recovery code that has been generated and shown but not yet made active.
public struct PendingRecoveryCode: Identifiable {
    public let code: String
    let secret: Data
    public var id: String { code }
}

/// One encrypted record as stored on disk and in backups.
public struct SealedEntry: Codable, Equatable {
    public var entryID: UUID
    public var keyID: UUID
    public var payloadVersion: Int
    public var revision: Int
    public var sealed: Data
}
