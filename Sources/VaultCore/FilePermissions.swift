import Foundation

/// Owner-only file permissions for the vault and its SQLite side files (security review F1).
enum FilePermissions {
    /// Creates an empty file at 0600 so SQLite's -wal and -shm files, which copy the
    /// database file's mode, are owner-only from the start.
    static func createPrivateFile(_ path: String) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
    }

    /// Sets 0600 on a database file and any side files that exist.
    static func tighten(_ path: String) {
        for suffix in ["", "-wal", "-shm", "-journal"] {
            let p = path + suffix
            if FileManager.default.fileExists(atPath: p) {
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: p)
            }
        }
    }
}
