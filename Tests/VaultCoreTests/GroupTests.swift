import XCTest
@testable import VaultCore

/// Groups: one per record, names and icons sealed in the vault, carried by backups.
final class GroupTests: XCTestCase {
    func testNoGroupsByDefault() throws {
        let (vault, _) = try makeVault()
        XCTAssertEqual(try vault.loadGroups(), [])
    }

    func testGroupsRoundTripInOrderAndNeedUnlock() throws {
        let dir = tempDir()
        let (vault, _) = try makeVault(in: dir)
        let groups = [EntryGroup(name: "Bank", icon: "building.columns"), EntryGroup(name: "Medical", icon: "cross.case"),
                      EntryGroup(name: "Car")]
        try vault.saveGroups(groups)
        vault.close()

        let v = try Vault.open(at: dir.appendingPathComponent("vault.sqlite"))
        XCTAssertThrowsError(try v.loadGroups())
        try v.unlock(passphrase: testPassphrase)
        XCTAssertEqual(try v.loadGroups(), groups)
        XCTAssertEqual(try v.loadGroups()[2].icon, EntryGroup.defaultIcon)
    }

    func testGroupNamesNotPlaintextOnDisk() throws {
        let dir = tempDir()
        let (vault, _) = try makeVault(in: dir)
        try vault.saveGroups([EntryGroup(name: "Zebrafinch Medical")])
        vault.close()
        var bytes = Data()
        for name in try FileManager.default.contentsOfDirectory(atPath: dir.path) {
            bytes += (try? Data(contentsOf: dir.appendingPathComponent(name))) ?? Data()
        }
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("Zebrafinch"))
    }

    func testBadNamesRefused() throws {
        let (vault, _) = try makeVault()
        XCTAssertThrowsError(try vault.saveGroups([EntryGroup(name: "   ")]))
        XCTAssertThrowsError(try vault.saveGroups([EntryGroup(name: "Bank"), EntryGroup(name: "bank")]))
        XCTAssertThrowsError(try vault.saveGroups([EntryGroup(name: String(repeating: "x", count: 41))]))
        let id = UUID()
        XCTAssertThrowsError(try vault.saveGroups([EntryGroup(id: id, name: "A"), EntryGroup(id: id, name: "B")]))
        XCTAssertEqual(try vault.loadGroups(), [])
        // Renaming a group to its own name in a different case is fine.
        let g = EntryGroup(name: "Bank")
        XCTAssertNil(EntryGroup.nameProblem("BANK", in: [g], except: g.id))
        XCTAssertNotNil(EntryGroup.nameProblem("BANK", in: [g]))
    }

    func testTamperedGroupsFailClosed() throws {
        let (vault, _) = try makeVault()
        try vault.saveGroups([EntryGroup(name: "Bank")])
        var sealed = try XCTUnwrap(try vault.sealedGroups())
        sealed[sealed.count - 1] ^= 0x01
        try vault.db.run("UPDATE meta SET value = ? WHERE key = 'groups'", [.blob(sealed)])
        XCTAssertThrowsError(try vault.loadGroups())
    }

    func testGroupsFromAnotherVaultRefused() throws {
        let (a, _) = try makeVault()
        try a.saveGroups([EntryGroup(name: "Bank")])
        let (b, _) = try makeVault()
        try b.db.run("INSERT OR REPLACE INTO meta (key, value) VALUES ('groups', ?)", [.blob(try XCTUnwrap(try a.sealedGroups()))])
        XCTAssertThrowsError(try b.loadGroups())
    }

    func testEntryGroupRoundTripsAndOldRecordsDecode() throws {
        let (vault, _) = try makeVault()
        let g = EntryGroup(name: "Bank")
        try vault.saveGroups([g])
        var e = Entry(type: .login, title: "Example")
        e.groupID = g.id
        try vault.save(e)
        XCTAssertEqual(try vault.loadAll().entries.first?.groupID, g.id)

        // A record written before groups existed has no groupID key.
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Entry(type: .login, title: "Old"))) as! [String: Any]
        json.removeValue(forKey: "groupID")
        let old = try JSONDecoder().decode(Entry.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.groupID)
    }

    func testFilingKeepsChangedDate() throws {
        let (vault, _) = try makeVault()
        let saved = try vault.save(Entry(type: .login, title: "Example"))
        Thread.sleep(forTimeInterval: 0.02)
        var e = saved
        e.groupID = UUID()
        let filed = try vault.save(e, touchModified: false)
        XCTAssertEqual(filed.modified, saved.modified)
        let edited = try vault.save(filed)
        XCTAssertGreaterThan(edited.modified, saved.modified)
    }

    func testDeleteGroupKeepsItemsAndClearsThem() throws {
        let (vault, _) = try makeVault()
        let bank = EntryGroup(name: "Bank"), car = EntryGroup(name: "Car")
        try vault.saveGroups([bank, car])
        var a = Entry(type: .login, title: "A"); a.groupID = bank.id
        var b = Entry(type: .login, title: "B"); b.groupID = bank.id; b.deletedAt = Date()
        var c = Entry(type: .login, title: "C"); c.groupID = car.id
        try vault.saveAll([a, b, c])

        XCTAssertEqual(try vault.deleteGroup(id: bank.id), 2)
        XCTAssertEqual(try vault.loadGroups(), [car])
        let all = try vault.loadAll().entries
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all.filter { $0.groupID == nil }.map(\.title).sorted(), ["A", "B"])
        XCTAssertEqual(all.first { $0.title == "C" }?.groupID, car.id)
        let snaps = try FileManager.default.contentsOfDirectory(atPath: vault.snapshotsDirectory.path)
        XCTAssertTrue(snaps.contains { $0.contains("group-delete") })
        XCTAssertEqual(try vault.deleteGroup(id: UUID()), 0)
    }

    func testBackupCarriesGroupsAndRestoresThem() throws {
        let source = tempDir()
        let (vault, code) = try makeVault(in: source)
        let g = EntryGroup(name: "Bank", icon: "building.columns")
        try vault.saveGroups([g])
        var e = Entry(type: .login, title: "Example"); e.groupID = g.id
        try vault.save(e)
        let url = try Backup.writeToFolder(vault: vault, folder: source.appendingPathComponent("Backups"))

        let clean = tempDir().appendingPathComponent("vault.sqlite")
        try Backup.restore(try Backup.open(try Backup.read(from: url), recoveryCode: code), to: clean)
        let restored = try Vault.open(at: clean)
        try restored.unlock(passphrase: testPassphrase)
        XCTAssertEqual(try restored.loadGroups(), [g])
        XCTAssertEqual(try restored.loadAll().entries.first?.groupID, g.id)
    }

    func testBackupGroupsTamperedOrStrippedRejected() throws {
        let (vault, _) = try makeVault()
        try vault.saveGroups([EntryGroup(name: "Bank")])
        try vault.save(Entry(type: .login, title: "Example"))

        var flipped = try Backup.makeArchive(from: vault)
        flipped.sealedGroups![3] ^= 0x01
        XCTAssertThrowsError(try Backup.open(flipped, passphrase: testPassphrase))

        var stripped = try Backup.makeArchive(from: vault)
        stripped.sealedGroups = nil
        XCTAssertThrowsError(try Backup.open(stripped, passphrase: testPassphrase))

        XCTAssertNoThrow(try Backup.open(try Backup.makeArchive(from: vault), passphrase: testPassphrase))
    }

    func testBackupWithoutGroupsStillOpens() throws {
        let (vault, _) = try makeVault()
        try vault.saveAll(sampleEntries())
        let archive = try Backup.makeArchive(from: vault)
        XCTAssertNil(archive.sealedGroups)
        XCTAssertEqual(try Backup.open(archive, passphrase: testPassphrase).preview.entryCount, 5)
    }
}
