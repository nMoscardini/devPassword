import XCTest
@testable import VaultCore

/// Built from Nino's mSecure test export: every field holds its own name, no real data.
final class MSecureImporterTests: XCTestCase {
    static let rows: [[String]] = [
        ["Money", "Bank Accounts", "devPassword_Bank_Account_Decription", "Bank_Account_Notes", "Bank_Account_Account_Number", "Bank_Account_PIN", "Bank_Account_Name", "Bank_Account_Branch", "Bank_Account_Phone_No"],
        ["Money", "Birthdays", "devPassword_Birthdays_Description", "Birthdays_Notes", "Birthdays_Date"],
        ["Money", "Combinations", "devPassword_Combinations_Description", "Combination_Notes", "Combinations_Code"],
        ["Money", "Credit Cards", "devPassword_Credit_Cards_Description", "Credit_Cards_Notes", "Credit_Cards_Card_No", "Credit_Cards_Expiration_Date", "Credit_Cards_Name", "Credit_Cards_PIN", "Credit_Cards_Bank", "Credit_Cards_Security_Code"],
        ["Money", "Email Accounts", "devPassword_Email_Accounts_Description", "Email_Accounts_Notes", "Email_Accounts_Username", "Email_Accounts_Password", "Email_Accounts_POP3_Host", "Email_Accounts_SMTP_Host"],
        ["Money", "Frequent Flyer", "devPassword_Frequent_Flyer_Description", "Frequent_Flyer_Notes", "Frequent_Flyer_Number", "Frequent_Flyer_URL", "Frequent_Flyer_Username", "Frequent_Flyer_Password", "Frequent_Flyer_Mileage"],
        ["Money", "Insurance", "devPassword_Insurance_Description", "Insurance_Notes", "Insurance_Policy_no", "Insurance_Group_No", "Insurance_Insured", "Insurance_Date", "Insurance_Phone_No"],
        ["Money", "Logins", "devPassword_Logins_Description", "Logins_Notes", "Logins_URL", "Logins_ID", "Logins_Policy", "Logins_User_Name", "Logins_Password"],
        ["Money", "Memberships", "devPassword_Memberships_Description", "Memberships_Notes", "Memberships_Account_No", "Memberships_Nme", "Memberships_Date"],
        ["Money", "Note", "devPassword_Note_Description", "Note_Notes"],
        ["Money", "Registration Codes", "devPassword_Registration_Codes_Description", "Registration_Codes_Notes", "Registration_Codes_Number", "Registration_Codes_Date"],
        ["Money", "Prescriptions", "devPassword_Perscriptions_Description", "Perscriptions_Notes", "Perscriptions_RX_Number", "Perscriptions_Name", "Perscriptions_Doctor", "Perscriptions_Pharmacy", "Perscriptions_Phone_No"],
        ["Money", "Vehicle Info", "devPassword_Vehicle_Info_Description ", "Vehicle_Info_Notes", "Vehicle_Info_Licence_Plate", "Vehicle_Info_VIN", "Vehicle_Info_Date_Purchased", "Vehicle_Info_Tire_Size"],
        ["Money", "Web Logins", "devPassword_Web_Logins_Description", "Web_Logins_Notes", "Web_Logins_URL", "Web_Logins_Username", "Web_Logins_Password"],
        ["Unassigned", "Mystery Type", "Unknown thing", "notes, with comma and \"quotes\"\nand a second line", "Odd_1", "Odd_2"],
    ]

    func file(_ delimiter: String) -> String {
        let quote: (String) -> String = { $0.contains(",") || $0.contains("\"") || $0.contains("\n") ? "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : $0 }
        return ([MSecureImporter.titleLine] + Self.rows.map { $0.map(quote).joined(separator: delimiter) }).joined(separator: "\n") + "\n"
    }

    func entries(_ delimiter: String = ",") throws -> [String: Entry] {
        let built = try MSecureImporter.read(file(delimiter))
        XCTAssertEqual(built.count, Self.rows.count)
        XCTAssertTrue(built.allSatisfy { $0.problem == nil })
        var byTitle: [String: Entry] = [:]
        for b in built { byTitle[b.entry!.title] = b.entry! }
        return byTitle
    }

    func custom(_ e: Entry, _ label: String) -> CustomField? { e.customFields.first { $0.label == label } }

    func testDetects() {
        XCTAssertTrue(MSecureImporter.isMSecureExport(file(",")))
        XCTAssertFalse(MSecureImporter.isMSecureExport("name,url\nx,y"))
    }

    func testEveryTypeMapsAndNothingIsLost() throws {
        for delimiter in [",", "\t"] {
            let e = try entries(delimiter)

            let login = e["devPassword_Logins_Description"]!
            XCTAssertEqual(login.type, .login)
            XCTAssertEqual(login.urls, ["Logins_URL"])
            XCTAssertEqual(login[field: "username"], "Logins_User_Name")
            XCTAssertEqual(login[field: "password"], "Logins_Password")
            XCTAssertEqual(custom(login, "ID")?.value, "Logins_ID")
            XCTAssertEqual(custom(login, "Policy")?.value, "Logins_Policy")
            XCTAssertEqual(login.notes, "Logins_Notes")
            XCTAssertEqual(login.tags, ["Money"])

            let web = e["devPassword_Web_Logins_Description"]!
            XCTAssertEqual(web.urls, ["Web_Logins_URL"])
            XCTAssertEqual(web[field: "username"], "Web_Logins_Username")
            XCTAssertEqual(web[field: "password"], "Web_Logins_Password")

            let mail = e["devPassword_Email_Accounts_Description"]!
            XCTAssertEqual(mail.type, .emailAccount)
            XCTAssertEqual(mail[field: "emailAddress"], "Email_Accounts_Username")
            XCTAssertEqual(mail[field: "emailPassword"], "Email_Accounts_Password")
            XCTAssertEqual(mail[field: "incomingServer"], "Email_Accounts_POP3_Host")
            XCTAssertEqual(mail[field: "outgoingServer"], "Email_Accounts_SMTP_Host")

            let flyer = e["devPassword_Frequent_Flyer_Description"]!
            XCTAssertEqual(flyer.urls, ["Frequent_Flyer_URL"])
            XCTAssertEqual(flyer[field: "username"], "Frequent_Flyer_Username")
            XCTAssertEqual(custom(flyer, "Membership number")?.value, "Frequent_Flyer_Number")
            XCTAssertEqual(custom(flyer, "Mileage")?.value, "Frequent_Flyer_Mileage")

            let card = e["devPassword_Credit_Cards_Description"]!
            XCTAssertEqual(card.type, .paymentCard)
            XCTAssertEqual(card[field: "cardNumber"], "Credit_Cards_Card_No")
            XCTAssertEqual(card[field: "cardExpiry"], "Credit_Cards_Expiration_Date")
            XCTAssertEqual(card[field: "cardholder"], "Credit_Cards_Name")
            XCTAssertEqual(card[field: "cardPIN"], "Credit_Cards_PIN")
            XCTAssertEqual(card[field: "cardIssuer"], "Credit_Cards_Bank")
            XCTAssertEqual(card[field: "securityCode"], "Credit_Cards_Security_Code")

            let bank = e["devPassword_Bank_Account_Decription"]!
            XCTAssertEqual(bank.type, .bankAccount)
            XCTAssertEqual(bank[field: "accountNumber"], "Bank_Account_Account_Number")
            XCTAssertEqual(bank[field: "bankPasscode"], "Bank_Account_PIN")
            XCTAssertEqual(bank[field: "accountName"], "Bank_Account_Name")
            XCTAssertEqual(custom(bank, "Branch")?.value, "Bank_Account_Branch")
            XCTAssertEqual(custom(bank, "Phone")?.value, "Bank_Account_Phone_No")

            let combo = e["devPassword_Combinations_Description"]!
            XCTAssertEqual(combo.type, .secureNote)
            XCTAssertEqual(custom(combo, "Code")?.kind, .concealed)

            let ins = e["devPassword_Insurance_Description"]!
            XCTAssertEqual(ins.type, .insurance)
            XCTAssertEqual(ins[field: "policyNumber"], "Insurance_Policy_no")
            XCTAssertEqual(ins[field: "groupNumber"], "Insurance_Group_No")
            XCTAssertEqual(ins[field: "insured"], "Insurance_Insured")
            XCTAssertEqual(ins[field: "renewalDate"], "Insurance_Date")
            XCTAssertEqual(ins[field: "insurerPhone"], "Insurance_Phone_No")
            XCTAssertEqual(custom(e["devPassword_Memberships_Description"]!, "Name")?.value, "Memberships_Nme")
            let reg = e["devPassword_Registration_Codes_Description"]!
            XCTAssertEqual(reg.type, .registrationCode)
            XCTAssertEqual(reg[field: "licenceKey"], "Registration_Codes_Number")
            XCTAssertEqual(reg[field: "purchaseDate"], "Registration_Codes_Date")
            XCTAssertEqual(custom(e["devPassword_Birthdays_Description"]!, "Date")?.value, "Birthdays_Date")
            XCTAssertEqual(e["devPassword_Note_Description"]!.notes, "Note_Notes")

            let rx = e["devPassword_Perscriptions_Description"]!
            XCTAssertEqual(rx.type, .prescription)
            XCTAssertEqual(rx[field: "medicineName"], "Perscriptions_Name")
            XCTAssertEqual(rx[field: "doctor"], "Perscriptions_Doctor")
            XCTAssertEqual(rx[field: "pharmacy"], "Perscriptions_Pharmacy")
            XCTAssertEqual(rx[field: "pharmacyPhone"], "Perscriptions_Phone_No")
            XCTAssertEqual(custom(rx, "RX number")?.value, "Perscriptions_RX_Number")

            let car = e["devPassword_Vehicle_Info_Description"]!   // trailing space trimmed from title
            XCTAssertEqual(car.type, .vehicle)
            XCTAssertEqual(car[field: "registration"], "Vehicle_Info_Licence_Plate")
            XCTAssertEqual(car[field: "vin"], "Vehicle_Info_VIN")
            XCTAssertEqual(car[field: "datePurchased"], "Vehicle_Info_Date_Purchased")
            XCTAssertEqual(car[field: "tyreSize"], "Vehicle_Info_Tire_Size")

            let odd = e["Unknown thing"]!
            XCTAssertEqual(odd.type, .secureNote)
            XCTAssertEqual(custom(odd, "mSecure type")?.value, "Mystery Type")
            XCTAssertEqual(custom(odd, "Field 2")?.value, "Odd_2")
            XCTAssertEqual(odd.notes, "notes, with comma and \"quotes\"\nand a second line")
            XCTAssertTrue(odd.tags.isEmpty, "Unassigned is not a tag")
        }
    }

    func testUKDatesAndMOTDue() {
        XCTAssertEqual(DateParsing.date("14/03/2026"), DateParsing.isoDate("2026-03-14"))
        XCTAssertEqual(DateParsing.date("14-03-26"), DateParsing.isoDate("2026-03-14"))
        XCTAssertNil(DateParsing.date("31/02/2026"))
        var car = Entry(type: .vehicle, title: "Car")
        car[field: "lastMOT"] = "14/03/2026"
        XCTAssertEqual(car.expiryDate, DateParsing.isoDate("2027-03-14"))
        XCTAssertEqual(car.expiryText(car.expiryDate!, now: DateParsing.isoDate("2026-10-04")!), "MOT due")
        XCTAssertEqual(car.expiryText(car.expiryDate!, now: DateParsing.isoDate("2027-04-01")!), "MOT overdue since")
        XCTAssertTrue(EntryValidation.warnings(for: car).isEmpty)
        car[field: "lastService"] = "next week"
        XCTAssertFalse(EntryValidation.warnings(for: car).isEmpty)
    }

    func testReimportFindsDuplicates() throws {
        let built = try MSecureImporter.read(file(","))
        let first = Importer.classify(built, existing: [])
        XCTAssertEqual(first.count(.new), Self.rows.count)
        let again = Importer.classify(built, existing: first.toCommit)
        XCTAssertTrue(again.toCommit.isEmpty)
    }

    func testWebsiteLessLoginsWithSameUsernameAreDistinct() {
        // Synthetic. One email address and one reused password, no websites, different titles.
        func login(_ title: String, _ pw: String) -> Importer.BuiltRow {
            var e = Entry(type: .login, title: title)
            e[field: "username"] = "someone@example.com"
            e[field: "password"] = pw
            return Importer.BuiltRow(number: 0, entry: e, problem: nil)
        }
        let p = Importer.classify([login("Library", "same"), login("Gym", "same"), login("Club", "other")], existing: [])
        XCTAssertEqual(p.count(.new), 3)
        // Same title and username, different password: still a conflict.
        let q = Importer.classify([login("Library", "a"), login("library", "b")], existing: [])
        XCTAssertEqual(q.rows.map(\.status), [.new, .conflict])
    }

    func testRejoinsUnquotedLineBreaksInNotes() throws {
        // Synthetic. mSecure writes a line break inside notes without quoting it.
        let text = [
            MSecureImporter.titleLine,
            "Unassigned,Logins,Split Login,first line of notes",
            "second line",
            "third line,https://example.com,ID1,Policy1,someone@example.com,pw1",
            "Unassigned,Note,Split Note,note line 1",
            "note line 2",
            "Unassigned,Web Logins,Whole,notes,https://example.org,user,pw2",
        ].joined(separator: "\n") + "\n"
        let built = try MSecureImporter.read(text)
        XCTAssertEqual(built.map(\.number), [2, 5, 7])
        XCTAssertTrue(built.allSatisfy { $0.problem == nil })
        let login = built[0].entry!
        XCTAssertEqual(login.type, .login)
        XCTAssertEqual(login.notes, "first line of notes\nsecond line\nthird line")
        XCTAssertEqual(login.urls, ["https://example.com"])
        XCTAssertEqual(login[field: "username"], "someone@example.com")
        XCTAssertEqual(login[field: "password"], "pw1")
        XCTAssertEqual(built[1].entry!.notes, "note line 1\nnote line 2")
        XCTAssertEqual(built[2].entry!.title, "Whole")
    }
}
