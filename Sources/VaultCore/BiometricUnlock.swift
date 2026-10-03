import Foundation
import Security
import LocalAuthentication
import CryptoKit

/// Touch ID (Mac) or Face ID (iPhone, iPad) unlock (spec F10, section 5 "Device access").
///
/// The vault key is stored in the data protection Keychain on this device only:
/// - never synchronised to iCloud Keychain,
/// - readable only after the device is unlocked,
/// - released only after a biometric match with the fingers or face enrolled today
///   (adding or removing a fingerprint invalidates it).
/// Biometrics do not derive any key. The passphrase and recovery code always still work.
/// Needs a signed app with the Keychain Sharing capability. Unsigned builds get a clear error.
public enum BiometricUnlock {
    static let service = "com.moscardini.devpassword.vault-key"

    /// True when this Mac has Touch ID hardware with at least one finger enrolled.
    public static var isAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// "Touch ID", "Face ID" or "Biometrics".
    public static var name: String {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        switch context.biometryType {
        case .touchID: return "Touch ID"
        case .faceID: return "Face ID"
        default: return "Biometrics"
        }
    }

    static func account(_ header: VaultHeader) -> String {
        "\(header.vaultID.uuidString)/\(header.keyID.uuidString)"
    }

    static func baseQuery(_ header: VaultHeader) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(header),
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    static func store(_ key: SymmetricKey, header: VaultHeader) throws {
        remove(header: header)
        var cfError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                           .biometryCurrentSet, &cfError) else {
            throw VaultError.biometricUnavailable("Could not create the Keychain access rule.")
        }
        var query = baseQuery(header)
        query[kSecAttrSynchronizable as String] = false
        query[kSecAttrAccessControl as String] = access
        query[kSecAttrLabel as String] = "devPassword vault key"
        query[kSecValueData as String] = VaultCrypto.keyData(key)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw error(for: status) }
    }

    /// Shows the system Touch ID prompt. Blocks until it is answered: call off the main thread.
    static func load(header: VaultHeader, reason: String) throws -> SymmetricKey {
        let context = LAContext()
        context.localizedReason = reason
        var query = baseQuery(header)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { throw error(for: status) }
        guard let data = result as? Data, data.count == 32 else {
            throw VaultError.biometricUnavailable("The stored key is not valid. Unlock with your passphrase.")
        }
        return SymmetricKey(data: data)
    }

    public static func remove(header: VaultHeader) {
        SecItemDelete(baseQuery(header) as CFDictionary)
    }

    static func error(for status: OSStatus) -> VaultError {
        switch status {
        case errSecUserCanceled:
            return .biometricCancelled
        case errSecItemNotFound:
            return .biometricUnavailable("Touch ID is not set up for this vault, or your fingerprints changed. Unlock with your passphrase and it will be set up again.")
        case errSecAuthFailed:
            return .biometricUnavailable("Touch ID did not unlock the vault. Use your passphrase.")
        case errSecMissingEntitlement:
            return .biometricUnavailable("Touch ID needs the signed app. Run devPassword from the Xcode project in App/, not swift run.")
        default:
            let text = SecCopyErrorMessageString(status, nil) as String? ?? "code \(status)"
            return .biometricUnavailable("Keychain error: \(text)")
        }
    }
}
