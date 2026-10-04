import XCTest
@testable import VaultCore

final class VaultTests: XCTestCase {
    func testCreateSaveLockReopenUnlock() throws {
        let dir = tempDir()
        let (vault, _) = try makeVault(in: dir)
        try vault.saveAll(sampleEntries())
        vault.close()

        let reopened = try Vault.open(at: dir.appendingPathComponent("vault.sqlite"))
        XCTAssertFalse(reopened.isUnlocked)
        XCTAssertThrowsError(try reopened.loadAll())
        try reopened.unlock(passphrase: testPassphrase)
        let loaded = try reopened.loadAll()
        XCTAssertTrue(loaded.failedIDs.isEmpty)
        XCTAssertEqual(sorted(loaded.entries), sorted(sampleEntries()))
    }

    func testNoPlaintextOnDisk() throws {
        let dir = tempDir()
        let (vault, _) = try makeVault(in: dir)
        try vault.saveAll(sampleEntries())
        vault.close()
        var bytes = Data()
        for name in try FileManager.default.contentsOfDirectory(atPath: dir.path) {
            bytes += (try? Data(contentsOf: dir.appendingPathComponent(name))) ?? Data()
        }
        let haystack = String(decoding: bytes, as: UTF8.self)
        for needle in ["Example Bank", "4111", "Nino.Test", "Passport", "12345678", testPassphrase] {
            XCTAssertFalse(haystack.contains(needle), "Found plaintext: \(needle)")
        }
    }

    func testWrongPassphraseFails() throws {
        let dir = tempDir()
        let (vault, _) = try makeVault(in: dir)
        vault.close()
        let v = try Vault.open(at: dir.appendingPathComponent("vault.sqlite"))
        XCTAssertThrowsError(try v.unlock(passphrase: "not the passphrase at all")) { e in
            XCTAssertEqual(e as? VaultError, .wrongSecret)
        }
        XCTAssertFalse(v.isUnlocked)
    }

    func testWeakPassphraseRefused() {
        XCTAssertThrowsError(try Vault.create(at: tempDir().appendingPathComponent("v.sqlite"), passphrase: "short", iterations: testIterations))
    }

    func testRecoveryCodeUnlocksAndSetsNewPassphrase() throws {
        let dir = tempDir()
        let (vault, code) = try makeVault(in: dir)
        try vault.saveAll(sampleEntries())
        vault.close()

        let v = try Vault.open(at: dir.appendingPathComponent("vault.sqlite"))
        try v.unlock(recoveryCode: code)
        XCTAssertEqual(try v.loadAll().entries.count, 5)
        try v.setPassphraseAfterRecovery("a brand new passphrase here")
        v.close()

        let again = try Vault.open(at: dir.appendingPathComponent("vault.sqlite"))
        XCTAssertThrowsError(try again.unlock(passphrase: testPassphrase))
        try again.unlock(passphrase: "a brand new passphrase here")
        again.lock()
        try again.unlock(recoveryCode: code)   // recovery code still works
    }

    func testChangePassphraseAndReplaceRecovery() throws {
        let dir = tempDir()
        let (vault, oldCode) = try makeVault(in: dir)
        XCTAssertThrowsError(try vault.changePassphrase(current: "wrong passphrase entirely", new: "another good passphrase"))
        try vault.changePassphrase(current: testPassphrase, new: "another good passphrase")
        let newCode = try vault.replaceRecoveryCode()
        vault.close()

        let v = try Vault.open(at: dir.appendingPathComponent("vault.sqlite"))
        XCTAssertThrowsError(try v.unlock(passphrase: testPassphrase))
        XCTAssertThrowsError(try v.unlock(recoveryCode: oldCode))
        try v.unlock(recoveryCode: newCode)
        v.lock()
        try v.unlock(passphrase: "another good passphrase")

        // Snapshots hold the old wrapped key, so they are removed once a change succeeds (review finding 3).
        let snaps = (try? FileManager.default.contentsOfDirectory(atPath: v.snapshotsDirectory.path)) ?? []
        XCTAssertTrue(snaps.filter { $0.hasPrefix("vault-") }.isEmpty)
        XCTAssertTrue(v.auditLog().contains { $0.action == "vault.password_changed" })
        XCTAssertTrue(v.auditLog().contains { $0.action == "snapshots.retired_after_credential_change" })
        // A low test work factor is raised to the baseline when the passphrase changes (finding 1).
        XCTAssertEqual(v.header.kdfIterations, VaultCrypto.defaultIterations)
    }

    func testPreparedRecoveryCodeChangesNothingUntilCommitted() throws {
        let dir = tempDir()
        let (vault, oldCode) = try makeVault(in: dir)
        let pending = vault.prepareRecoveryCode()
        vault.lock()   // e.g. auto-lock while the user writes the code down
        let v1 = try Vault.open(at: dir.appendingPathComponent("vault.sqlite"))
        try v1.unlock(recoveryCode: oldCode)
        XCTAssertThrowsError(try Vault.open(at: dir.appendingPathComponent("vault.sqlite")).unlock(recoveryCode: pending.code))

        try v1.commitRecoveryCode(pending)
        let v2 = try Vault.open(at: dir.appendingPathComponent("vault.sqlite"))
        XCTAssertThrowsError(try v2.unlock(recoveryCode: oldCode))
        try v2.unlock(recoveryCode: pending.code)
    }

    func testOldSnapshotsDoNotSurviveCredentialChange() throws {
        let (vault, _) = try makeVault()
        try vault.saveAll(sampleEntries())
        try vault.purge(id: try vault.loadAll().entries[0].id)   // leaves a snapshot under the old passphrase
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: vault.snapshotsDirectory.path).isEmpty)
        try vault.changePassphrase(current: testPassphrase, new: "another good passphrase")
        let left = try FileManager.default.contentsOfDirectory(atPath: vault.snapshotsDirectory.path)
        XCTAssertTrue(left.filter { $0.hasPrefix("vault-") }.isEmpty)
    }

    func testHostileWorkFactorRejected() {
        XCTAssertThrowsError(try VaultCrypto.deriveKey(passphrase: "x", salt: Data("salt".utf8),
                                                       iterations: VaultCrypto.maximumIterations + 1))
        XCTAssertThrowsError(try VaultCrypto.deriveKey(passphrase: "x", salt: Data("salt".utf8), iterations: 0))
    }

    func testPlaintextExportNeedsPassphrase() throws {
        let (vault, _) = try makeVault()
        try vault.saveAll(sampleEntries())
        XCTAssertThrowsError(try vault.exportPlaintextCSV(passphrase: "wrong wrong wrong")) { e in
            XCTAssertEqual(e as? VaultError, .wrongSecret)
        }
        let result = try vault.exportPlaintextCSV(passphrase: testPassphrase)
        XCTAssertEqual(result.count, 5)
        XCTAssertTrue(vault.auditLog().contains { $0.action == "export.plaintext_csv" })
    }

    func testVaultFilesAreOwnerOnly() throws {
        let dir = tempDir()
        let (vault, _) = try makeVault(in: dir)
        try vault.saveAll(sampleEntries())
        let base = dir.appendingPathComponent("vault.sqlite").path
        for p in [base, base + "-wal", base + "-shm"] where FileManager.default.fileExists(atPath: p) {
            let mode = (try FileManager.default.attributesOfItem(atPath: p)[.posixPermissions] as? NSNumber)?.intValue
            XCTAssertEqual(mode, 0o600, "\(p) should be owner-only")
        }
    }

    func testTamperedRecordIsReportedNotShown() throws {
        let (vault, _) = try makeVault()
        let saved = try vault.saveAll(sampleEntries())
        let target = saved[2].id
        let row = try vault.db.query("SELECT sealed FROM entries WHERE entry_id = ?", [.text(target.uuidString)])
        var sealed = row[0][0].blob!
        sealed[20] ^= 0xFF
        try vault.db.run("UPDATE entries SET sealed = ? WHERE entry_id = ?", [.blob(sealed), .text(target.uuidString)])

        let result = try vault.loadAll()
        XCTAssertEqual(result.failedIDs, [target])
        XCTAssertEqual(result.entries.count, 4)
    }

    func testSwappedRecordsFail() throws {
        let (vault, _) = try makeVault()
        let saved = try vault.saveAll(sampleEntries())
        let a = saved[0].id.uuidString, b = saved[1].id.uuidString
        let sa = try vault.db.query("SELECT sealed FROM entries WHERE entry_id = ?", [.text(a)])[0][0]
        let sb = try vault.db.query("SELECT sealed FROM entries WHERE entry_id = ?", [.text(b)])[0][0]
        try vault.db.run("UPDATE entries SET sealed = ? WHERE entry_id = ?", [sb, .text(a)])
        try vault.db.run("UPDATE entries SET sealed = ? WHERE entry_id = ?", [sa, .text(b)])
        XCTAssertEqual(Set(try vault.loadAll().failedIDs), Set([saved[0].id, saved[1].id]))
    }

    func testSoftDeleteRestoreAndPurge() throws {
        let (vault, _) = try makeVault()
        var e = try vault.save(sampleEntries()[0])
        e.deletedAt = Date()
        try vault.save(e)
        XCTAssertTrue(try vault.loadAll().entries[0].isDeleted)
        e.deletedAt = nil
        try vault.save(e)
        XCTAssertFalse(try vault.loadAll().entries[0].isDeleted)
        try vault.purge(id: e.id)
        XCTAssertTrue(try vault.loadAll().entries.isEmpty)
    }

    func testSearchNeverUsesConcealedFields() {
        let entries = sampleEntries()
        XCTAssertTrue(entries[0].searchableText.contains("Nino.Test"))
        XCTAssertFalse(entries[0].searchableText.contains("p@ss"))
        XCTAssertFalse(entries[1].searchableText.contains("SSID"))
        XCTAssertFalse(entries[2].searchableText.contains("4111"))
        XCTAssertFalse(entries[4].searchableText.contains("000000000"))
        XCTAssertFalse(entries[4].searchableText.contains("secret"))
    }
}
