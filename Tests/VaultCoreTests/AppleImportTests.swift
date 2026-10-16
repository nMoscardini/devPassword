import XCTest
@testable import VaultCore

/// Decision 0007: one-way, read-only snapshot of Apple Passwords. Synthetic data only.
final class AppleImportTests: XCTestCase {
    let header = "Title,URL,Username,Password,Notes,OTPAuth\n"

    func csv(_ rows: [String]) -> String { header + rows.joined(separator: "\n") + "\n" }

    func testParsesAppleColumns() throws {
        let text = "\u{FEFF}" + csv([
            "example.com (test@example.com),https://www.example.com/,test@example.com,pw-one,,",
            "\"shop.test (a, b)\",http://shop.test/,\"a, b\",\"p\"\"w\",\"line1\nline2\",otpauth://totp/x?secret=TEST",
            ",,,orphan,,",
        ])
        let r = try AppleImport.parse(text)
        XCTAssertEqual(r.logins.count, 2)
        XCTAssertEqual(r.skipped, 1)
        XCTAssertEqual(r.logins[1].username, "a, b")
        XCTAssertEqual(r.logins[1].password, "p\"w")
        XCTAssertEqual(r.logins[1].notes, "line1\nline2")
        XCTAssertEqual(r.logins[1].otpAuth, "otpauth://totp/x?secret=TEST")
        XCTAssertEqual(AppleImport.displayTitle(r.logins[0]), "example.com")
    }

    func testRefusesOtherCSV() {
        XCTAssertThrowsError(try AppleImport.parse("name,url,user,pass\nx,y,z,w\n"))
    }

    func testHostMatching() {
        XCTAssertEqual(AppleImport.host("https://www.Example.com/login?x=1"), "example.com")
        XCTAssertEqual(AppleImport.host("example.com"), "example.com")
        XCTAssertEqual(AppleImport.host("https://user@www.example.com:8443/x"), "example.com")
        XCTAssertEqual(AppleImport.host("http://"), "", "LastPass placeholder for no website")
        XCTAssertEqual(AppleImport.host("https://"), "")
        XCTAssertEqual(AppleImport.host("  "), "")
        XCTAssertEqual(AppleImport.place(url: "https://example.com/", username: "Me@Test.com"),
                       AppleImport.place(url: "http://www.example.com/a", username: "me@test.com"))
    }

    func testFirstImportThenDiff() throws {
        let (vault, _) = try makeVault()
        let day1 = Date(timeIntervalSince1970: 1_790_000_000)
        let first = try AppleImport.parse(csv([
            "a.test (u1),https://a.test/,u1,pw-a,,",
            "b.test (u2),https://b.test/,u2,pw-b,,",
            "c.test (u3),https://c.test/,u3,pw-c,note,",
        ]))
        let plan1 = AppleImport.plan(first.logins, existing: [])
        XCTAssertEqual(plan1.added.count, 3)
        try AppleImport.apply(plan1, to: vault, now: day1)
        var entries = try vault.loadAll().entries
        XCTAssertEqual(entries.count, 3)
        XCTAssertTrue(entries.allSatisfy { $0.isAppleSnapshot && $0.master == .apple })
        XCTAssertEqual(AppleImport.lastImport(entries), day1)

        // Day 2: a's password changed, b removed, d new, c unchanged.
        let day2 = day1.addingTimeInterval(86_400 * 3)
        let second = try AppleImport.parse(csv([
            "a.test (u1),https://a.test/,u1,pw-a2,,",
            "c.test (u3),https://c.test/,u3,pw-c,note,",
            "d.test (u4),https://d.test/,u4,pw-d,,",
        ]))
        let plan2 = AppleImport.plan(second.logins, existing: entries)
        XCTAssertEqual(plan2.changed.count, 1)
        XCTAssertEqual(plan2.unchanged.count, 1)
        XCTAssertEqual(plan2.added.count, 1)
        XCTAssertEqual(plan2.removed.count, 1)
        try AppleImport.apply(plan2, to: vault, now: day2)
        entries = try vault.loadAll().entries
        XCTAssertEqual(entries.count, 4, "removed logins are kept")

        let a = entries.first { $0[field: "username"] == "u1" }!
        XCTAssertEqual(a[field: "password"], "pw-a2")
        XCTAssertEqual(a.previousPassword?.value, "pw-a")
        XCTAssertEqual(a.appleHistory?.map(\.kind), [.added, .passwordChanged])
        let b = entries.first { $0[field: "username"] == "u2" }!
        XCTAssertEqual(b.appleRemovedAt, day2)
        XCTAssertEqual(b[field: "password"], "pw-b", "the last known password is kept")
        XCTAssertEqual(AppleImport.ageInDays(entries, now: day2.addingTimeInterval(86_400 * 2)), 2)

        // Day 3: b is back.
        let plan3 = AppleImport.plan(try AppleImport.parse(csv([
            "a.test (u1),https://a.test/,u1,pw-a2,,",
            "b.test (u2),https://b.test/,u2,pw-b,,",
            "c.test (u3),https://c.test/,u3,pw-c,note,",
            "d.test (u4),https://d.test/,u4,pw-d,,",
        ])).logins, existing: entries)
        XCTAssertEqual(plan3.returned.count, 1)
        XCTAssertEqual(plan3.removed.count, 0)
        try AppleImport.apply(plan3, to: vault, now: day2.addingTimeInterval(86_400))
        let b2 = try vault.loadAll().entries.first { $0[field: "username"] == "u2" }!
        XCTAssertNil(b2.appleRemovedAt)
        XCTAssertEqual(b2.appleHistory?.map(\.kind), [.added, .removed, .returned])
    }

    func testDevPasswordMasterIsNotOverwritten() throws {
        var bank = Entry(type: .login, title: "Test Bank")
        bank.urls = ["https://bank.test/"]
        bank[field: "username"] = "u9"
        bank[field: "password"] = "mine"
        bank.master = .devPassword
        var old = Entry(type: .login, title: "Old Shop")
        old.urls = ["https://shop.test"]
        old[field: "username"] = "u8"
        let logins = try AppleImport.parse(csv([
            "bank.test (u9),https://bank.test/,u9,theirs,,",
            "shop.test (u8),https://www.shop.test/,u8,pw,,",
        ])).logins
        let plan = AppleImport.plan(logins, existing: [bank, old])
        XCTAssertEqual(plan.masterClashes.count, 1)
        XCTAssertEqual(plan.added.count, 1)
        XCTAssertEqual(plan.alsoInDevPassword.count, 1)
    }

    func testSameSiteAndUsernameTwiceKeepsBoth() throws {
        let logins = try AppleImport.parse(csv([
            "x.test (u),https://x.test/,u,one,,",
            "x.test (u),https://x.test/app,u,two,,",
        ])).logins
        XCTAssertEqual(AppleImport.plan(logins, existing: []).added.count, 2)
    }

    func testAppleFieldsStayReadOnly() {
        var orig = Entry(type: .login, title: "a.test")
        orig.urls = ["https://a.test/"]
        orig[field: "username"] = "u"
        orig[field: "password"] = "apple-pw"
        orig.master = .apple
        orig.appleSeenAt = Date()
        var edited = orig
        edited[field: "password"] = "changed"
        edited.urls = ["https://evil.test/"]
        edited.master = .devPassword
        edited.title = "My bank"
        edited[field: "secondSecret"] = "testmemorable"
        edited.notes = "changed apple note"
        edited.myNotes = "my own note"
        let kept = AppleImport.keepAppleFields(edited, from: orig)
        XCTAssertEqual(kept[field: "password"], "apple-pw")
        XCTAssertEqual(kept.urls, ["https://a.test/"])
        XCTAssertEqual(kept.master, .apple)
        XCTAssertEqual(kept.title, "My bank")
        XCTAssertEqual(kept[field: "secondSecret"], "testmemorable")
        XCTAssertEqual(kept.notes, "", "Apple's notes stay as imported")
        XCTAssertEqual(kept.myNotes, "my own note")
    }

    func testImportKeepsMyNotes() throws {
        let (vault, _) = try makeVault()
        let rows = ["a.test (u),https://a.test/,u,pw,apple note,"]
        try AppleImport.apply(AppleImport.plan(try AppleImport.parse(csv(rows)).logins, existing: []), to: vault)
        var e = try vault.loadAll().entries[0]
        e.myNotes = "my own note"
        try vault.save(e)
        let changed = ["a.test (u),https://a.test/,u,pw2,new apple note,"]
        try AppleImport.apply(AppleImport.plan(try AppleImport.parse(csv(changed)).logins,
                                               existing: try vault.loadAll().entries), to: vault)
        let after = try vault.loadAll().entries[0]
        XCTAssertEqual(after.notes, "new apple note")
        XCTAssertEqual(after.myNotes, "my own note")
    }

    func testExportFileIsDestroyed() throws {
        let url = tempDir().appendingPathComponent("Passwords.csv")
        try Data(csv(["a.test (u),https://a.test/,u,synthetic,,"]).utf8).write(to: url)
        try AppleImport.destroyExport(at: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(AppleImport.isSyncedFolder(URL(fileURLWithPath: "/Users/x/Library/CloudStorage/OneDrive-Personal/p.csv")))
        XCTAssertFalse(AppleImport.isSyncedFolder(URL(fileURLWithPath: "/Users/x/Downloads/p.csv")))
    }

    func testDisplayTitleDropsAddressPrefixes() {
        func apple(_ t: String) -> Entry { var e = Entry(type: .login, title: t); e.appleSeenAt = Date(); return e }
        XCTAssertEqual(apple("account.bbc.com").displayTitle, "bbc.com")
        XCTAssertEqual(apple("www.amazon.co.uk").displayTitle, "amazon.co.uk")
        XCTAssertEqual(apple("login.nhs.uk").displayTitle, "nhs.uk")
        XCTAssertEqual(apple("www.com").displayTitle, "www.com", "never strips down to a bare suffix")
        XCTAssertEqual(apple("192.168.1.1").displayTitle, "192.168.1.1")
        XCTAssertEqual(apple("My bank").displayTitle, "My bank")
        XCTAssertEqual(Entry(type: .login, title: "www.example.com").displayTitle, "www.example.com",
                       "titles Nino typed are left alone")
    }

    func testArchiveSurvivesAnAppleImport() throws {
        let (vault, _) = try makeVault()
        let rows = ["a.test (u),https://a.test/,u,pw,,"]
        try AppleImport.apply(AppleImport.plan(try AppleImport.parse(csv(rows)).logins, existing: []), to: vault)
        var e = try vault.loadAll().entries[0]
        e.archivedAt = Date()
        try vault.save(e)
        let changed = ["a.test (u),https://a.test/,u,pw2,,"]
        try AppleImport.apply(AppleImport.plan(try AppleImport.parse(csv(changed)).logins,
                                               existing: try vault.loadAll().entries), to: vault)
        XCTAssertTrue(try vault.loadAll().entries[0].isArchived)
    }

    func testWhichRecordsGoToThePhone() {
        XCTAssertTrue(Entry(type: .secureNote, title: "note").belongsOnPhone, "devPassword records always")
        var apple = Entry(type: .login, title: "a.test")
        apple.appleSeenAt = Date()
        XCTAssertFalse(apple.belongsOnPhone, "plain Apple snapshot: Passwords already has it")
        var bank = apple
        bank[field: "secondSecret"] = "testmemorable"
        XCTAssertTrue(bank.belongsOnPhone, "second password is Nino's")
        var noted = apple; noted.myNotes = "branch sort code on the card"
        XCTAssertTrue(noted.belongsOnPhone)
        var custom = apple; custom.customFields = [CustomField(label: "PIN hint", value: "x")]
        XCTAssertTrue(custom.belongsOnPhone)
        var pic = apple; pic.customLogo = Data([1])
        XCTAssertTrue(pic.belongsOnPhone)
    }

    func testOldRecordsStillDecode() throws {
        var e = Entry(type: .login, title: "t")
        e[field: "username"] = "u"
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(e)) as! [String: Any]
        for k in ["appleSeenAt", "appleRemovedAt", "appleKey", "appleHistory"] { json.removeValue(forKey: k) }
        let back = try JSONDecoder().decode(Entry.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(back.isAppleSnapshot)
    }
}
