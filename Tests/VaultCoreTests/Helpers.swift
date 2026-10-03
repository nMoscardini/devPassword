import Foundation
import XCTest
@testable import VaultCore

/// Low iteration count for tests only. Production uses VaultCrypto.defaultIterations.
let testIterations = 1_000
let testPassphrase = "correct horse battery staple"

func tempDir() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("devPasswordTests-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func makeVault(in dir: URL = tempDir()) throws -> (Vault, String) {
    let r = try Vault.create(at: dir.appendingPathComponent("vault.sqlite"), passphrase: testPassphrase, iterations: testIterations)
    return (r.vault, r.recoveryCode)
}

/// Content of an entry without IDs and timestamps, for round-trip comparison.
struct Content: Equatable {
    let type: RecordType, title: String, urls: [String], fields: [String: String]
    let custom: [String], notes: String, notesConcealed: Bool, tags: [String], favourite: Bool
    init(_ e: Entry) {
        type = e.type; title = e.title; urls = e.urls; fields = e.fields
        custom = e.customFields.map { "\($0.label)|\($0.value)|\($0.kind.rawValue)" }
        notes = e.notes; notesConcealed = e.notesConcealed; tags = e.tags; favourite = e.favourite
    }
}

func sorted(_ entries: [Entry]) -> [Content] {
    entries.map(Content.init).sorted { ($0.type.rawValue, $0.title, $0.notes) < ($1.type.rawValue, $1.title, $1.notes) }
}

/// One realistic synthetic record of each type, including awkward characters.
func sampleEntries() -> [Entry] {
    var login = Entry(type: .login, title: "Example Bank")
    login.urls = ["https://www.example.com/login", "https://m.example.com"]
    login[field: "username"] = "Nino.Test@example.com"
    login[field: "password"] = " p@ss,\"word\"\nwith newline and trailing space "
    login.tags = ["finance", "uk"]
    login.favourite = true
    login.notes = "Line one\nLine two, with comma"

    var note = Entry(type: .secureNote, title: "Wi-Fi at the caravan")
    note.notes = "SSID: Test\nKey: =SUM(A1)"
    note.notesConcealed = true

    var card = Entry(type: .paymentCard, title: "Test Visa")
    card[field: "cardholder"] = "N MOSCARDINI"
    card[field: "cardNumber"] = "4111 1111 1111 1111"
    card[field: "cardExpiry"] = "09/29"
    card[field: "cardIssuer"] = "Example Bank"
    card[field: "securityCode"] = "123"
    card.customFields = [CustomField(label: "Support line", value: "0800 000 000")]

    var bank = Entry(type: .bankAccount, title: "Current account")
    bank[field: "bankName"] = "Example Bank"
    bank[field: "sortCode"] = "00-00-00"
    bank[field: "accountNumber"] = "12345678"
    bank[field: "bankPasscode"] = "ÄÖÜ-ñ-日本"

    var passport = Entry(type: .identityDocument, title: "Passport")
    passport[field: "documentType"] = "Passport"
    passport[field: "holderName"] = "Test Person"
    passport[field: "documentNumber"] = "000000000"
    passport[field: "issuingAuthority"] = "United Kingdom"
    passport[field: "issueDate"] = "2020-01-31"
    passport[field: "expiryDate"] = "2030-01-31"
    passport.customFields = [CustomField(label: "Memorable word", value: "secret", kind: .concealed)]

    return [login, note, card, bank, passport]
}

func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }
