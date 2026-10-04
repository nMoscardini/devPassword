import Foundation
import CryptoKit
import CommonCrypto
import Security

/// Random number generator backed by Apple's cryptographic random source.
public struct SecureRandom: RandomNumberGenerator {
    public init() {}
    public mutating func next() -> UInt64 {
        var value: UInt64 = 0
        let status = withUnsafeMutableBytes(of: &value) { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        precondition(status == errSecSuccess, "System random source failed")
        return value
    }
}

public enum VaultCrypto {
    /// OWASP baseline for PBKDF2-HMAC-SHA256. Stage 0 benchmarks and confirms it.
    public static let defaultIterations = 600_000
    /// Upper bound accepted from any vault or backup header. Stops a hostile or damaged file
    /// from hanging the app (security review finding 2).
    public static let maximumIterations = 10_000_000

    public static func randomBytes(_ count: Int) -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        precondition(status == errSecSuccess, "System random source failed")
        return data
    }

    /// PBKDF2-HMAC-SHA256 through CommonCrypto. The passphrase is normalised to Unicode NFC first,
    /// so the same passphrase typed on different devices derives the same key.
    public static func deriveKey(passphrase: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        let password = Array(passphrase.precomposedStringWithCanonicalMapping.utf8)
        guard !password.isEmpty else { throw VaultError.wrongSecret }
        guard iterations > 0, iterations <= maximumIterations, !salt.isEmpty else {
            throw VaultError.corrupt("Key derivation settings are out of range")
        }
        let saltBytes = [UInt8](salt)
        var derived = [UInt8](repeating: 0, count: 32)
        let status: Int32 = password.withUnsafeBufferPointer { pw in
            saltBytes.withUnsafeBufferPointer { s in
                derived.withUnsafeMutableBufferPointer { out in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        UnsafeRawPointer(pw.baseAddress!).assumingMemoryBound(to: CChar.self),
                        pw.count,
                        s.baseAddress,
                        s.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        out.baseAddress,
                        out.count
                    )
                }
            }
        }
        guard Int(status) == kCCSuccess else { throw VaultError.crypto("Key derivation failed") }
        let key = SymmetricKey(data: derived)
        for i in derived.indices { derived[i] = 0 }
        return key
    }

    /// AES-256-GCM with a fresh random 96-bit nonce. Returns nonce || ciphertext || tag.
    public static func seal(_ plaintext: Data, key: SymmetricKey, context: Data) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key, nonce: AES.GCM.Nonce(), authenticating: context)
        guard let combined = box.combined else { throw VaultError.crypto("Seal failed") }
        return combined
    }

    /// Opens a sealed value. Any change to ciphertext, tag, nonce or context fails closed.
    public static func open(_ combined: Data, key: SymmetricKey, context: Data) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(box, using: key, authenticating: context)
        } catch {
            throw VaultError.authenticationFailed
        }
    }

    static func keyData(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }
}
