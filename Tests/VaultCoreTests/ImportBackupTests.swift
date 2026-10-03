import XCTest
@testable import VaultCore

final class CSVTests: XCTestCase {
    func testParsesAwkwardCSV() throws {
        let text = "\u{FEFF}name,url,password,extra\r\n"
            + "\"Comma, Inc\",https://a.example,\"pa\"\"ss\",\"line1\nline2\"\r\n"
            + "\r\n"
            + "Plain,https://b.example, spaced ,\n"
        let rows = try CSV.parse(text)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0], ["name", "url", "password", "extra"])
        XCTAssertEqual(rows[1], ["Comma, Inc", "https://a.example", "pa\"ss", "line1\nline2"])
        XCTAssertEqual(rows[2], ["Plain", "https://b.example", " spaced ", ""])
    }

    func testUnterminatedQuoteFails() {
        XCTAssertThrowsError(try CSV.parse("a,b\n\"open,1\n"))
    }

    func testWriteParseRoundTrip() throws {
        let rows = [["a", " lead", "trail ", "q\"uote", "multi\r\nline", "=SUM(A1)", "日本語", ""]]
        XCTAssertEqual(try CSV.parse(CSV.write(rows)), rows)
    }
}

final class ImportTests: XCTestCase {
    let lastPass = """
        url,username,password,totp,extra,name,grouping,fav
        https://www.example.com,nino@example.com,Secret1!,,note here,Example,Personal,1
        https://shop.example,nino,Pass,word,,,Shop,Shopping,0
        https://www.example.com,nino@example.com,Different2!,,,Example again,Personal,0
        https://www.example.com,nino@example.com,Secret1!,,note here,Example,Personal,1
        http://bad.example,only,three
        """

    func testLastPassStyleImport() throws {
        let (headers, rows) = try Importer.table(from: lastPass)
        let mapping = Importer.guess(headers: headers)
        XCTAssertEqual(mapping.targets[0], .urls)
        XCTAssertEqual(mapping.targets[1], .field("username"))
        XCTAssertEqual(mapping.targets[2], .field("password"))
        XCTAssertEqual(mapping.targets[3], .custom)   // TOTP secret kept, never dropped
        XCTAssertEqual(mapping.targets[5], .title)

        let p = Importer.preview(headers: headers, rows: rows, mapping: mapping, existing: [])
        XCTAssertEqual(p.rows.map(\.status), [.new, .rejected, .conflict, .duplicate, .rejected])
        XCTAssertEqual(p.rows[1].id, 3)
        XCTAssertEqual(p.rows[1].reason, "Has 9 fields, expected 8")
        XCTAssertEqual(p.toCommit.count, 2)
        let first = p.toCommit[0]
        XCTAssertEqual(first[field: "password"], "Secret1!")
        XCTAssertTrue(first.favourite)
        XCTAssertEqual(first.tags, ["Personal"])
        XCTAssertTrue(p.toCommit[1].tags.contains(Importer.reviewTag))
    }

    func testReimportCreatesNoDuplicates() throws {
        let (vault, _) = try makeVault()
        let (headers, rows) = try Importer.table(from: lastPass)
        let mapping = Importer.guess(headers: headers)
        try vault.saveAll(Importer.preview(headers: headers, rows: rows, mapping: mapping, existing: []).toCommit)
        let existing = try vault.loadAll().entries
        let again = Importer.preview(headers: headers, rows: rows, mapping: mapping, existing: existing)
        XCTAssertTrue(again.toCommit.isEmpty)
    }

    func testMixedTypesWithTypeColumn() throws {
        let csv = """
            Type,Name,Number,Expiry,CVV,Username,Password
            Credit Card,Visa,4111111111111111,09/29,123,,
            Login,Site,,,,me,pw
            Passport,UK Passport,123456789,2030-01-01,,,
            Loyalty Card,Shop card,999,,,,
            Gym Locker,Locker,,,,,
            """
        let (headers, rows) = try Importer.table(from: csv)
        let mapping = Importer.guess(headers: headers)
        let p = Importer.preview(headers: headers, rows: rows, mapping: mapping, existing: [])
        let e = p.toCommit
        XCTAssertEqual(e.map(\.type), [.paymentCard, .login, .identityDocument, .paymentCard, .login])
        XCTAssertEqual(e[0][field: "cardNumber"], "4111111111111111")
        XCTAssertEqual(e[0][field: "cardExpiry"], "09/29")
        XCTAssertEqual(e[0][field: "securityCode"], "123")
        // Columns follow each row's type.
        XCTAssertEqual(e[2][field: "documentNumber"], "123456789")
        XCTAssertEqual(e[2][field: "expiryDate"], "2030-01-01")
        XCTAssertEqual(e[3][field: "cardNumber"], "999")
        XCTAssertTrue(e[4].customFields.contains { $0.label == "Original type" && $0.value == "Gym Locker" })
    }

    func testOwnExportRoundTripsEveryType() throws {
        let originals = sampleEntries()
        let csv = try CSVExport.make(originals)
        let (headers, rows) = try Importer.table(from: csv)
        let p = Importer.preview(headers: headers, rows: rows, mapping: Importer.guess(headers: headers), existing: [])
        XCTAssertEqual(p.count(.new), originals.count)
        XCTAssertEqual(sorted(p.toCommit), sorted(originals))
    }
}

final class BackupTests: XCTestCase {
    func testBackupVerifyWithBothSecrets() throws {
        let dir = tempDir()
        let (vault, code) = try makeVault(in: dir)
        try vault.saveAll(sampleEntries())
        let url = try Backup.writeToFolder(vault: vault, folder: dir.appendingPathComponent("Backups"))
        let archive = try Backup.read(from: url)
        let a = try Backup.open(archive, passphrase: testPassphrase)
        XCTAssertEqual(a.preview.entryCount, 5)
        XCTAssertEqual(a.preview.countsByType[.paymentCard], 1)
        _ = try Backup.open(archive, recoveryCode: code)
        XCTAssertThrowsError(try Backup.open(archive, passphrase: "wrong wrong wrong"))
    }

    func testTamperedBackupRejected() throws {
        let (vault, _) = try makeVault()
        try vault.saveAll(sampleEntries())
        var archive = try Backup.makeArchive(from: vault)
        archive.entries[1].sealed[15] ^= 0x01
        XCTAssertThrowsError(try Backup.open(archive, passphrase: testPassphrase))

        var dropped = try Backup.makeArchive(from: vault)
        dropped.entries.removeLast()
        XCTAssertThrowsError(try Backup.open(dropped, passphrase: testPassphrase))
    }

    func testRestoreOnCleanDeviceAndOverExistingVault() throws {
        let source = tempDir()
        let (vault, code) = try makeVault(in: source)
        try vault.saveAll(sampleEntries())
        let backupURL = try Backup.writeToFolder(vault: vault, folder: source.appendingPathComponent("Backups"))
        vault.close()

        // Clean device: nothing but the backup file and the recovery code.
        let clean = tempDir().appendingPathComponent("vault.sqlite")
        let opened = try Backup.open(try Backup.read(from: backupURL), recoveryCode: code)
        try Backup.restore(opened, to: clean)
        let restored = try Vault.open(at: clean)
        try restored.unlock(passphrase: testPassphrase)
        XCTAssertEqual(sorted(try restored.loadAll().entries), sorted(sampleEntries()))
        restored.close()

        // Existing vault: kept aside, not overwritten.
        let otherDir = tempDir()
        let (other, _) = try makeVault(in: otherDir)
        try other.save(Entry(type: .secureNote, title: "Keep me"))
        other.close()
        try Backup.restore(opened, to: otherDir.appendingPathComponent("vault.sqlite"))
        let names = try FileManager.default.contentsOfDirectory(atPath: otherDir.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("vault.before-restore-") })
    }

    func testPruneKeepsOnlyOurNewestFour() throws {
        let dir = tempDir()
        let (vault, _) = try makeVault(in: dir)
        let folder = dir.appendingPathComponent("Backups")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: folder.appendingPathComponent("unrelated.txt"))
        for _ in 0..<6 {
            try Backup.writeToFolder(vault: vault, folder: folder, keep: 4)
            Thread.sleep(forTimeInterval: 0.01)
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertEqual(names.filter { $0.hasSuffix(".dpbackup") }.count, 4)
        XCTAssertTrue(names.contains("unrelated.txt"))
    }
}
