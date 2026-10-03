import XCTest
@testable import VaultCore

/// The smoke test (principle 8): the main path end to end on a realistic synthetic vault.
/// Run with: scripts/smoke.sh
final class SmokeTests: XCTestCase {
    func testMainPathOnSyntheticVault() throws {
        let dir = tempDir()
        let url = dir.appendingPathComponent("vault.sqlite")
        let count = 1_000
        let start = Date()

        // 1. Create and fill.
        let (vault, code) = try makeVault(in: dir)
        var entries: [Entry] = []
        for i in 0..<count {
            var e = sampleEntries()[i % 5]
            e.id = UUID()
            e.title += " \(i)"
            if e.type == .login { e[field: "username"] += "\(i)" }
            entries.append(e)
        }
        try vault.saveAll(entries)

        // 2. Lock, reopen, unlock, load.
        vault.close()
        let v = try Vault.open(at: url)
        try v.unlock(passphrase: testPassphrase)
        let loaded = try v.loadAll()
        XCTAssertEqual(loaded.entries.count, count)
        XCTAssertTrue(loaded.failedIDs.isEmpty)

        // 3. Search in memory.
        let t0 = Date()
        let hits = loaded.entries.filter { $0.searchableText.localizedCaseInsensitiveContains("visa 997") }
        let searchMs = Date().timeIntervalSince(t0) * 1000
        XCTAssertEqual(hits.count, 1)

        // 4. Edit a password: previous kept.
        var first = loaded.entries.first(where: { $0.type == .login })!
        first.previousPassword = PreviousValue(value: first[field: "password"], changedAt: Date())
        first[field: "password"] = "new-password"
        try v.save(first)

        // 5. Backup, verify, restore to a clean location with the recovery code.
        let backup = try Backup.writeToFolder(vault: v, folder: dir.appendingPathComponent("Backups"))
        let opened = try Backup.open(try Backup.read(from: backup), recoveryCode: code)
        XCTAssertEqual(opened.preview.entryCount, count)
        let clean = tempDir().appendingPathComponent("vault.sqlite")
        try Backup.restore(opened, to: clean)
        let r = try Vault.open(at: clean)
        try r.unlock(passphrase: testPassphrase)
        XCTAssertEqual(try r.loadAll().entries.count, count)

        // 6. CSV export and import into a fresh vault.
        let csv = try CSVExport.make(try v.loadAll().entries)
        let (fresh, _) = try makeVault()
        let (headers, rows) = try Importer.table(from: csv)
        let preview = Importer.preview(headers: headers, rows: rows, mapping: Importer.guess(headers: headers), existing: [])
        try fresh.saveAll(preview.toCommit)
        XCTAssertEqual(try fresh.loadAll().entries.count, count)

        print("SMOKE ok: \(count) records, search \(Int(searchMs)) ms, total \(Int(Date().timeIntervalSince(start) * 1000)) ms")
    }

    /// Times the production key derivation on this Mac (spec: benchmark the work factor).
    func testKDFBenchmark() throws {
        let t0 = Date()
        _ = try VaultCrypto.deriveKey(passphrase: testPassphrase, salt: VaultCrypto.randomBytes(16),
                                      iterations: VaultCrypto.defaultIterations)
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        print("KDF benchmark: PBKDF2-HMAC-SHA256 \(VaultCrypto.defaultIterations) iterations took \(ms) ms")
        XCTAssertLessThan(ms, 5_000)
    }
}
