import Foundation
import SQLite3

enum SQLValue: Equatable {
    case int(Int64)
    case text(String)
    case blob(Data)
    case null

    var int: Int64? { if case .int(let v) = self { return v }; return nil }
    var text: String? { if case .text(let v) = self { return v }; return nil }
    var blob: Data? { if case .blob(let v) = self { return v }; return nil }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Thin wrapper over the system SQLite. Local disk only (H1).
final class SQLiteDB {
    private var handle: OpaquePointer?
    let path: String

    init(path: String, readOnly: Bool = false) throws {
        self.path = path
        let flags = readOnly
            ? SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
            : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(handle)
            handle = nil
            throw VaultError.database(msg)
        }
        sqlite3_busy_timeout(handle, 3000)
        if !readOnly {
            try exec("PRAGMA journal_mode=WAL; PRAGMA secure_delete=ON; PRAGMA foreign_keys=ON;")
        }
    }

    deinit { close() }

    func close() {
        if let h = handle {
            sqlite3_close_v2(h)
            handle = nil
        }
    }

    private var errorMessage: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "database closed"
    }

    func exec(_ sql: String) throws {
        guard let h = handle else { throw VaultError.database("database closed") }
        guard sqlite3_exec(h, sql, nil, nil, nil) == SQLITE_OK else { throw VaultError.database(errorMessage) }
    }

    private func prepare(_ sql: String, _ args: [SQLValue]) throws -> OpaquePointer {
        guard let h = handle else { throw VaultError.database("database closed") }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(h, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
            throw VaultError.database(errorMessage)
        }
        for (i, arg) in args.enumerated() {
            let idx = Int32(i + 1)
            let rc: Int32
            switch arg {
            case .int(let v): rc = sqlite3_bind_int64(s, idx, v)
            case .text(let v): rc = sqlite3_bind_text(s, idx, v, -1, SQLITE_TRANSIENT)
            case .blob(let v):
                rc = v.withUnsafeBytes { buf in
                    sqlite3_bind_blob(s, idx, buf.baseAddress, Int32(buf.count), SQLITE_TRANSIENT)
                }
            case .null: rc = sqlite3_bind_null(s, idx)
            }
            guard rc == SQLITE_OK else {
                sqlite3_finalize(s)
                throw VaultError.database(errorMessage)
            }
        }
        return s
    }

    func run(_ sql: String, _ args: [SQLValue] = []) throws {
        let s = try prepare(sql, args)
        defer { sqlite3_finalize(s) }
        let rc = sqlite3_step(s)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw VaultError.database(errorMessage) }
    }

    func query(_ sql: String, _ args: [SQLValue] = []) throws -> [[SQLValue]] {
        let s = try prepare(sql, args)
        defer { sqlite3_finalize(s) }
        var rows: [[SQLValue]] = []
        while true {
            let rc = sqlite3_step(s)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw VaultError.database(errorMessage) }
            var row: [SQLValue] = []
            for c in 0..<sqlite3_column_count(s) {
                switch sqlite3_column_type(s, c) {
                case SQLITE_INTEGER: row.append(.int(sqlite3_column_int64(s, c)))
                case SQLITE_TEXT: row.append(.text(String(cString: sqlite3_column_text(s, c)!)))
                case SQLITE_BLOB:
                    let n = Int(sqlite3_column_bytes(s, c))
                    if n == 0 {
                        row.append(.blob(Data()))
                    } else {
                        row.append(.blob(Data(bytes: sqlite3_column_blob(s, c)!, count: n)))
                    }
                default: row.append(.null)
                }
            }
            rows.append(row)
        }
        return rows
    }

    /// Runs body in one transaction. Rolls back on any error.
    func transaction<T>(_ body: () throws -> T) throws -> T {
        try exec("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try exec("COMMIT")
            return result
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    /// Online backup with SQLite's own backup API (H2). Never copy a live file.
    func backup(to destination: String) throws {
        guard let src = handle else { throw VaultError.database("database closed") }
        var dest: OpaquePointer?
        guard sqlite3_open(destination, &dest) == SQLITE_OK, let d = dest else {
            sqlite3_close(dest)
            throw VaultError.database("Could not create snapshot file")
        }
        defer { sqlite3_close(d) }
        guard let b = sqlite3_backup_init(d, "main", src, "main") else {
            throw VaultError.database(String(cString: sqlite3_errmsg(d)))
        }
        let rc = sqlite3_backup_step(b, -1)
        sqlite3_backup_finish(b)
        guard rc == SQLITE_DONE else { throw VaultError.database("Snapshot failed with code \(rc)") }
        // Make the copy one self-contained file (no WAL), so it opens read-only anywhere.
        guard sqlite3_exec(d, "PRAGMA journal_mode=DELETE", nil, nil, nil) == SQLITE_OK else {
            throw VaultError.database("Snapshot could not be finalised: \(String(cString: sqlite3_errmsg(d)))")
        }
    }

    var userVersion: Int {
        let rows = (try? query("PRAGMA user_version")) ?? []
        return Int(rows.first?.first?.int ?? 0)
    }

    func setUserVersion(_ v: Int) throws { try exec("PRAGMA user_version = \(v)") }
}
