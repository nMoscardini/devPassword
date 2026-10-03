import XCTest
import CryptoKit
@testable import VaultCore

final class CryptoTests: XCTestCase {
    /// Published PBKDF2-HMAC-SHA256 vectors (P = "password", S = "salt", dkLen = 32).
    func testPBKDF2KnownVectors() throws {
        let k1 = try VaultCrypto.deriveKey(passphrase: "password", salt: Data("salt".utf8), iterations: 1)
        XCTAssertEqual(hex(VaultCrypto.keyData(k1)), "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
        let k4096 = try VaultCrypto.deriveKey(passphrase: "password", salt: Data("salt".utf8), iterations: 4096)
        XCTAssertEqual(hex(VaultCrypto.keyData(k4096)), "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a")
    }

    func testPassphraseIsNormalised() throws {
        let composed = "caf\u{E9} passphrase"          // é as one scalar
        let decomposed = "cafe\u{301} passphrase"      // e + combining accent
        let salt = Data("salt".utf8)
        let a = try VaultCrypto.deriveKey(passphrase: composed, salt: salt, iterations: 10)
        let b = try VaultCrypto.deriveKey(passphrase: decomposed, salt: salt, iterations: 10)
        XCTAssertEqual(VaultCrypto.keyData(a), VaultCrypto.keyData(b))
    }

    func testSealOpenAndTamperFailsClosed() throws {
        let key = SymmetricKey(size: .bits256)
        let ctx = Data("context".utf8)
        let sealed = try VaultCrypto.seal(Data("secret".utf8), key: key, context: ctx)
        XCTAssertEqual(try VaultCrypto.open(sealed, key: key, context: ctx), Data("secret".utf8))

        for index in [0, 12, sealed.count - 1] {   // nonce, ciphertext, tag
            var bad = sealed
            bad[index] ^= 0x01
            XCTAssertThrowsError(try VaultCrypto.open(bad, key: key, context: ctx))
        }
        XCTAssertThrowsError(try VaultCrypto.open(sealed, key: key, context: Data("other".utf8)))
        XCTAssertThrowsError(try VaultCrypto.open(sealed, key: SymmetricKey(size: .bits256), context: ctx))
    }

    func testNoncesAreFresh() throws {
        let key = SymmetricKey(size: .bits256)
        var nonces = Set<Data>()
        for _ in 0..<500 {
            let sealed = try VaultCrypto.seal(Data("same".utf8), key: key, context: Data())
            nonces.insert(sealed.prefix(12))
        }
        XCTAssertEqual(nonces.count, 500)
    }

    func testRecoveryCodeRoundTripAndTolerance() throws {
        let secret = Data(repeating: 7, count: 32)
        let code = RecoveryCode.format(secret)
        XCTAssertEqual(code.filter { $0 != "-" }.count, 55)
        XCTAssertEqual(try RecoveryCode.parse(code), secret)
        XCTAssertEqual(try RecoveryCode.parse(code.lowercased().replacingOccurrences(of: "-", with: " ")), secret)

        let generated = RecoveryCode.generate()
        XCTAssertEqual(try RecoveryCode.parse(generated.code), generated.secret)
    }

    func testRecoveryCodeTypoIsCaught() {
        let code = RecoveryCode.format(Data(repeating: 7, count: 32))
        var chars = Array(code)
        let i = 3
        chars[i] = chars[i] == "A" ? "B" : "A"
        XCTAssertThrowsError(try RecoveryCode.parse(String(chars)))
        XCTAssertThrowsError(try RecoveryCode.parse(String(code.dropLast(5))))
    }

    func testGeneratorRespectsOptions() throws {
        var o = PasswordOptions()
        for _ in 0..<300 {
            let p = try PasswordGenerator.generate(o)
            XCTAssertEqual(p.count, 20)
            XCTAssertTrue(p.contains { $0.isLowercase })
            XCTAssertTrue(p.contains { $0.isUppercase })
            XCTAssertTrue(p.contains { $0.isNumber })
            XCTAssertTrue(p.contains { PasswordGenerator.symbolSet.contains($0) })
        }
        o.length = 32
        o.symbols = false
        o.excluded = "aeiouAEIOU0"
        o.avoidLookAlikes = true
        for _ in 0..<300 {
            let p = try PasswordGenerator.generate(o)
            XCTAssertEqual(p.count, 32)
            XCTAssertFalse(p.contains { "aeiouAEIOU0Il1O|".contains($0) })
            XCTAssertFalse(p.contains { PasswordGenerator.symbolSet.contains($0) })
        }
        o = PasswordOptions()
        o.lowercase = false; o.uppercase = false; o.digits = false; o.symbols = false
        XCTAssertThrowsError(try PasswordGenerator.generate(o))
    }

    func testLuhnAndDates() {
        XCTAssertTrue(EntryValidation.luhnValid("4111 1111 1111 1111"))
        XCTAssertFalse(EntryValidation.luhnValid("4111 1111 1111 1112"))
        XCTAssertNotNil(DateParsing.cardExpiry("09/29"))
        XCTAssertNotNil(DateParsing.cardExpiry("09/2029"))
        XCTAssertNil(DateParsing.cardExpiry("13/29"))
        XCTAssertNotNil(DateParsing.isoDate("2030-01-31"))
        XCTAssertNil(DateParsing.isoDate("2030-02-30"))
        XCTAssertEqual(Masking.lastFour("4111 1111 1111 1234"), "•••• 1234")
    }
}
