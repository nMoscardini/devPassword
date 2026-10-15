import XCTest
@testable import VaultCore

/// Decision 0007 amendment: per-login master, second secret, "Pick characters". Synthetic data only.
final class BankingTests: XCTestCase {
    func testParsesCommonForms() throws {
        XCTAssertEqual(try CharacterPicker.positions("2 5 7"), [2, 5, 7])
        XCTAssertEqual(try CharacterPicker.positions("2,5,7"), [2, 5, 7])
        XCTAssertEqual(try CharacterPicker.positions(" 7, 2 and 5 "), [7, 2, 5])
        XCTAssertEqual(try CharacterPicker.positions("2nd, 3rd, 1st and 11th"), [2, 3, 1, 11])
        XCTAssertEqual(try CharacterPicker.positions("2 2 5"), [2, 5])
    }

    func testRejectsBadPositions() {
        XCTAssertThrowsError(try CharacterPicker.positions("")) {
            XCTAssertEqual($0 as? CharacterPicker.PickError, .noPositions)
        }
        XCTAssertThrowsError(try CharacterPicker.positions("two")) {
            XCTAssertEqual($0 as? CharacterPicker.PickError, .notAPosition("two"))
        }
        XCTAssertThrowsError(try CharacterPicker.pick("abc", positionsText: "4")) {
            XCTAssertEqual($0 as? CharacterPicker.PickError, .outOfRange(position: 4, length: 3))
        }
        XCTAssertThrowsError(try CharacterPicker.pick("abc", positionsText: "0"))
    }

    func testPicksOneBasedPositionsOnly() throws {
        let picks = try CharacterPicker.pick("Memorable1", positionsText: "1, 4, 10")
        XCTAssertEqual(picks, [.init(position: 1, character: "M"),
                               .init(position: 4, character: "o"),
                               .init(position: 10, character: "1")])
    }

    func testCountsCharactersNotBytes() throws {
        let picks = try CharacterPicker.pick("ñé日 x", positions: [1, 3, 4])
        XCTAssertEqual(picks.map(\.character), ["ñ", "日", " "])
    }

    func testMasterAndSecondSecretSurviveVault() throws {
        let dir = tempDir()
        let (vault, _) = try makeVault(in: dir)
        var bank = Entry(type: .login, title: "Example Bank online")
        bank[field: "password"] = "first-test-secret"
        bank[field: "secondSecret"] = "testmemorable"
        bank.master = .devPassword
        var shop = Entry(type: .login, title: "Example shop")
        shop.master = .apple
        let unset = Entry(type: .login, title: "Example unset")
        try vault.saveAll([bank, shop, unset])
        let loaded = try vault.loadAll().entries
        XCTAssertEqual(loaded.first { $0.id == bank.id }?.master, .devPassword)
        XCTAssertEqual(loaded.first { $0.id == bank.id }?[field: "secondSecret"], "testmemorable")
        XCTAssertEqual(loaded.first { $0.id == shop.id }?.master, .apple)
        XCTAssertNil(loaded.first { $0.id == unset.id }?.master)
    }

    func testRecordsSavedBeforeMasterStillDecode() throws {
        let e = Entry(type: .login, title: "Old record")
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(e)) as! [String: Any]
        json.removeValue(forKey: "master")
        let decoded = try JSONDecoder().decode(Entry.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.master)
        XCTAssertEqual(decoded.title, "Old record")
    }

    func testSecondSecretIsConcealedAndNotSearchable() {
        var e = Entry(type: .login, title: "Example Bank online")
        e[field: "secondSecret"] = "testmemorable"
        XCTAssertEqual(RecordType.allFieldDefs["secondSecret"]?.kind, .concealed)
        XCTAssertFalse(e.searchableText.contains("testmemorable"))
    }
}
