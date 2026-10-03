import Foundation
import CryptoKit

/// A 256-bit recovery secret, shown once at setup. Encoded in Crockford base32 with a
/// 16-bit checksum so transcription errors are caught before any key work is done.
public enum RecoveryCode {
    static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    static let secretLength = 32
    static let encodedLength = 55   // (32 + 2) bytes = 272 bits -> 55 characters

    public static func generate() -> (secret: Data, code: String) {
        let secret = VaultCrypto.randomBytes(secretLength)
        return (secret, format(secret))
    }

    /// Formats a secret as groups of five characters, for example "7K3QD-…".
    public static func format(_ secret: Data) -> String {
        let encoded = encode(secret + checksum(secret))
        var groups: [String] = []
        var current = ""
        for ch in encoded {
            current.append(ch)
            if current.count == 5 { groups.append(current); current = "" }
        }
        if !current.isEmpty { groups.append(current) }
        return groups.joined(separator: "-")
    }

    /// Parses a typed code. Accepts lower case, spaces and hyphens, and the usual
    /// look-alikes (O for 0, I and L for 1). Throws if the checksum does not match.
    public static func parse(_ code: String) throws -> Data {
        var cleaned: [Character] = []
        for ch in code.uppercased() {
            switch ch {
            case "-", " ", "\t", "\n", "\r": continue
            case "O": cleaned.append("0")
            case "I", "L": cleaned.append("1")
            default: cleaned.append(ch)
            }
        }
        guard cleaned.count == encodedLength, let bytes = decode(cleaned), bytes.count >= secretLength + 2 else {
            throw VaultError.invalidRecoveryCode
        }
        let secret = Data(bytes.prefix(secretLength))
        let check = Data(bytes[secretLength..<(secretLength + 2)])
        guard check == checksum(secret) else { throw VaultError.invalidRecoveryCode }
        return secret
    }

    /// Characters typed so far, ignoring spaces and hyphens. A full code has 55.
    public static func characterCount(_ typed: String) -> Int {
        typed.filter { !"- \t\n\r".contains($0) }.count
    }

    public static let length = encodedLength

    /// Wrapping key for the recovery wrapper, derived with HKDF and its own context.
    public static func wrappingKey(secret: Data, salt: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: secret),
            salt: salt,
            info: Data("devPassword recovery wrap v1".utf8),
            outputByteCount: 32
        )
    }

    static func checksum(_ secret: Data) -> Data {
        Data(SHA256.hash(data: secret).prefix(2))
    }

    static func encode(_ data: Data) -> String {
        var out = ""
        var buffer = 0
        var bits = 0
        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                out.append(alphabet[(buffer >> bits) & 31])
            }
            buffer &= (1 << bits) - 1
        }
        if bits > 0 { out.append(alphabet[(buffer << (5 - bits)) & 31]) }
        return out
    }

    static func decode(_ chars: [Character]) -> [UInt8]? {
        var lookup: [Character: Int] = [:]
        for (i, c) in alphabet.enumerated() { lookup[c] = i }
        var out: [UInt8] = []
        var buffer = 0
        var bits = 0
        for ch in chars {
            guard let v = lookup[ch] else { return nil }
            buffer = (buffer << 5) | v
            bits += 5
            if bits >= 8 {
                bits -= 8
                out.append(UInt8((buffer >> bits) & 0xFF))
            }
            buffer &= (1 << bits) - 1
        }
        return out
    }
}
