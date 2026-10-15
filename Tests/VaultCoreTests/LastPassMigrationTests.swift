import XCTest
@testable import VaultCore

/// Decision 0007: LastPass logins go to Apple Passwords; notes become devPassword records. Synthetic data only.
final class LastPassMigrationTests: XCTestCase {
    let header = "url,username,password,totp,extra,name,grouping,fav\n"

    func appleLogin(_ url: String, _ user: String, _ pw: String) -> Entry {
        var e = Entry(type: .login, title: AppleImport.host(url))
        e.urls = [url]
        e[field: "username"] = user
        e[field: "password"] = pw
        e.master = .apple
        e.appleSeenAt = Date()
        return e
    }

    func testSortsLastPassRows() throws {
        let text = header + [
            "https://a.test/,u1,same,,,a.test,Shopping,0",          // already in Apple
            "https://www.b.test/login,u2,lastpass-pw,,,b.test,,0",  // password differs
            "https://c.test/,u3,pw-c,JBSWY3DPEHPK3PXP,note c,c.test,,0", // new to Apple, with TOTP
            "https://c.test/,u3,pw-c,,,c.test copy,,0",             // duplicate in file
            "https://bank.test/,u9,pw-bank,,,Bank,,0",              // devPassword master
            "http://sn,,,,\"Card 1234\nCode 000\",Spare card,Money,0", // secure note
            ",wifi-user,wifi-pw,,,Home wifi,,0",                    // no website
            ",,,,,,,0",                                              // nothing
        ].joined(separator: "\n") + "\n"
        var bank = Entry(type: .login, title: "Bank")
        bank.urls = ["https://bank.test/"]
        bank[field: "username"] = "u9"
        bank.master = .devPassword
        let existing = [appleLogin("https://a.test/", "u1", "same"), appleLogin("https://b.test/", "u2", "apple-pw"), bank]

        let plan = LastPassMigration.plan(try LastPassMigration.parse(text), existing: existing)
        XCTAssertEqual(plan.total, 8)
        XCTAssertEqual(plan.alreadyInApple, 1)
        XCTAssertEqual(plan.passwordDiffers.count, 1)
        XCTAssertEqual(plan.toApple.map(\.username), ["u3"])
        XCTAssertEqual(plan.duplicatesInFile, 1)
        XCTAssertEqual(plan.devPasswordMastered.count, 1)
        XCTAssertEqual(plan.newRecords.count, 2)
        XCTAssertEqual(plan.skipped, 1)

        let note = plan.newRecords.first { $0.type == .secureNote }!
        XCTAssertTrue(note.notesConcealed)
        XCTAssertEqual(note.tags, ["lastpass", "Money"])
        let wifi = plan.newRecords.first { $0.type == .login }!
        XCTAssertEqual(wifi.master, .devPassword)
    }

    func testPlaceholderURLStaysInDevPassword() throws {
        let text = header + [
            "http://,wifi-user,synthetic1,,,Home wifi,,0",
            "https://,app-user,synthetic2,,,Some app,,0",
            "https://real.test/,u,synthetic3,,,Real,,0",
        ].joined(separator: "\n") + "\n"
        let plan = LastPassMigration.plan(try LastPassMigration.parse(text), existing: [])
        XCTAssertEqual(plan.toApple.map(\.username), ["u"])
        XCTAssertEqual(plan.newRecords.count, 2)
        XCTAssertTrue(plan.newRecords.allSatisfy { $0.urls.isEmpty && $0.master == .devPassword })
    }

    func testAppleFileReadsBackAsAppleExport() throws {
        let items = [LastPassItem(url: "https://c.test/", username: "u3", password: "p,\"w", totp: "JBSWY3DPEHPK3PXP", extra: "line1\nline2")]
        let csv = LastPassMigration.appleCSV(items)
        let back = try AppleImport.parse(csv).logins
        XCTAssertEqual(back.count, 1)
        XCTAssertEqual(back[0].password, "p,\"w")
        XCTAssertEqual(back[0].notes, "line1\nline2")
        XCTAssertEqual(back[0].title, "c.test (u3)")
        XCTAssertTrue(back[0].otpAuth.hasPrefix("otpauth://totp/"))
        XCTAssertTrue(back[0].otpAuth.contains("secret=JBSWY3DPEHPK3PXP"))
    }

    func testFileIsOwnerOnlyAndNeverOverwritten() throws {
        let dir = tempDir()
        let now = Date()
        let url = try LastPassMigration.writeForApple("x\n", in: dir, now: now)
        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
        XCTAssertThrowsError(try LastPassMigration.writeForApple("y\n", in: dir, now: now))
        try AppleImport.destroyExport(at: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testHeaderCaseAndSpacesAsInNinosExport() throws {
        // Nino's export, 15 October 2026: "URL, username, password, totp, extra, name, grouping, fav".
        let text = "URL, username, password, totp, extra, name, grouping, fav\nhttps://a.test/,u,pw,,,a,,0\n"
        let items = try LastPassMigration.parse(text)
        XCTAssertEqual(items.first?.url, "https://a.test/")
        XCTAssertEqual(items.first?.name, "a")
    }

    func testRefusesOtherCSV() {
        XCTAssertThrowsError(try LastPassMigration.parse("Title,URL,Login\nx,y,z\n"))
    }

    func testSavesRecordsAndSkipsThemNextTime() throws {
        let (vault, _) = try makeVault()
        let text = header + "http://sn,,,,secret text,My note,,0\n"
        let plan = LastPassMigration.plan(try LastPassMigration.parse(text), existing: [])
        XCTAssertEqual(try LastPassMigration.saveRecords(plan, to: vault), 1)
        let again = LastPassMigration.plan(try LastPassMigration.parse(text), existing: try vault.loadAll().entries)
        XCTAssertEqual(again.newRecords.count, 0)
        XCTAssertEqual(again.alreadyInDevPassword, 1)
    }
}
