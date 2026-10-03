import Foundation

public enum VaultError: Error, LocalizedError, Equatable {
    case wrongSecret
    case invalidRecoveryCode
    case locked
    case authenticationFailed
    case crypto(String)
    case corrupt(String)
    case unsupportedVersion(Int)
    case weakPassphrase(String)
    case database(String)
    case notFound
    case alreadyExists
    case importFailed(String)
    case invalid(String)
    case biometricCancelled
    case biometricUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .wrongSecret: return "That secret does not open this vault."
        case .invalidRecoveryCode: return "That recovery code is not valid. Check each group and try again."
        case .locked: return "The vault is locked."
        case .authenticationFailed: return "A record failed its integrity check and was not opened."
        case .crypto(let m): return "Encryption error: \(m)"
        case .corrupt(let m): return "The vault or backup is damaged: \(m)"
        case .unsupportedVersion(let v): return "This file uses format version \(v), which this app does not support."
        case .weakPassphrase(let m): return m
        case .database(let m): return "Storage error: \(m)"
        case .notFound: return "The vault was not found."
        case .alreadyExists: return "A vault already exists at that location."
        case .importFailed(let m): return "Import failed: \(m)"
        case .invalid(let m): return m
        case .biometricCancelled: return "Touch ID was cancelled."
        case .biometricUnavailable(let m): return m
        }
    }
}
