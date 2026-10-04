import Foundation

/// Reads mSecure's CSV export (mSecure 3.x for Mac, as exported by Nino on 4 October 2026).
/// No header row: the first line is the title "mSecure CSV export file". Every row is
///   group, type, description, notes, then the fields of that type in a fixed order.
/// Layouts below come from a test export with every field filled with its own name.
/// Nothing is dropped: fields without a standard slot become labelled custom fields.
public enum MSecureImporter {
    public static let titleLine = "mSecure CSV export file"

    public static func isMSecureExport(_ text: String) -> Bool {
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return first.trimmingCharacters(in: CharacterSet(charactersIn: " ,\t\u{FEFF}\"")).hasPrefix(titleLine)
    }

    /// Where one mSecure field goes.
    enum Slot {
        case url, field(String), custom(String, FieldKind)
    }

    /// Per mSecure type: the devPassword type and the order of the type-specific fields.
    static let layouts: [String: (RecordType, [Slot])] = [
        "Logins": (.login, [.url, .custom("ID", .text), .custom("Policy", .text), .field("username"), .field("password")]),
        "Web Logins": (.login, [.url, .field("username"), .field("password")]),
        "Email Accounts": (.emailAccount, [.field("emailAddress"), .field("emailPassword"), .field("incomingServer"), .field("outgoingServer")]),
        "Frequent Flyer": (.login, [.custom("Membership number", .text), .url, .field("username"), .field("password"), .custom("Mileage", .text)]),
        "Credit Cards": (.paymentCard, [.field("cardNumber"), .field("cardExpiry"), .field("cardholder"), .field("cardPIN"), .field("cardIssuer"), .field("securityCode")]),
        "Bank Accounts": (.bankAccount, [.field("accountNumber"), .field("bankPasscode"), .field("accountName"), .custom("Branch", .text), .custom("Phone", .text)]),
        "Prescriptions": (.prescription, [.custom("RX number", .text), .field("medicineName"), .field("doctor"), .field("pharmacy"), .field("pharmacyPhone")]),
        "Vehicle Info": (.vehicle, [.field("registration"), .field("vin"), .field("datePurchased"), .field("tyreSize")]),
        "Note": (.secureNote, []),
        "Birthdays": (.secureNote, [.custom("Date", .text)]),
        "Combinations": (.secureNote, [.custom("Code", .concealed)]),
        "Insurance": (.insurance, [.field("policyNumber"), .field("groupNumber"), .field("insured"), .field("renewalDate"), .field("insurerPhone")]),
        "Memberships": (.secureNote, [.custom("Account number", .text), .custom("Name", .text), .custom("Date", .text)]),
        "Registration Codes": (.registrationCode, [.field("licenceKey"), .field("purchaseDate")]),
    ]

    public static func read(_ text: String) throws -> [Importer.BuiltRow] {
        guard isMSecureExport(text) else { throw VaultError.importFailed("This is not an mSecure export.") }
        // mSecure writes commas. A copy saved from a spreadsheet may use tabs: detect which.
        let body = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let sample = body.count > 1 ? String(body[1].prefix(2000)) : ""
        let delimiter: Unicode.Scalar = sample.filter({ $0 == "\t" }).count > sample.filter({ $0 == "," }).count ? "\t" : ","
        let rows = try CSV.parse(text, delimiter: delimiter)
        var out: [Importer.BuiltRow] = []
        for record in rejoin(rows) {
            do {
                out.append(Importer.BuiltRow(number: record.number, entry: try entry(from: record.fields), problem: nil))
            } catch {
                out.append(Importer.BuiltRow(number: record.number, entry: nil, problem: error.localizedDescription))
            }
        }
        return out
    }

    /// mSecure does not quote line breaks inside a field (seen in notes, 4 October 2026 export),
    /// so one item can arrive split over several lines. A line is a continuation when the
    /// line does not start a known type, follows a known type, and either that item is short
    /// of its type's fields or the line is too short to be an item (a break in the last field).
    /// A line of 3 or more fields after a complete item is kept as an item of unknown type.
    /// The break is put back, and the rest of the line becomes that item's next fields.
    /// Numbers are CSV rows counting the title line as 1, of the item's first line.
    static func rejoin(_ rows: [[String]]) -> [(number: Int, fields: [String])] {
        var out: [(number: Int, fields: [String])] = []
        for (i, row) in rows.enumerated() where i > 0 {
            if let last = out.last, isKnown(last.fields), !startsItem(row), isShort(last.fields) || row.count < 3 {
                var fields = last.fields
                fields[fields.count - 1] += "\n" + (row.first ?? "")
                fields += row.dropFirst()
                out[out.count - 1].fields = fields
            } else {
                out.append((number: i + 1, fields: row))
            }
        }
        return out
    }

    static func startsItem(_ row: [String]) -> Bool {
        row.count > 1 && layouts[row[1].trimmingCharacters(in: .whitespaces)] != nil
    }

    static func isKnown(_ fields: [String]) -> Bool {
        fields.count > 1 && layouts[fields[1].trimmingCharacters(in: .whitespaces)] != nil
    }

    static func isShort(_ fields: [String]) -> Bool {
        guard fields.count > 1, let layout = layouts[fields[1].trimmingCharacters(in: .whitespaces)] else { return false }
        return fields.count < 4 + layout.1.count
    }

    static func entry(from row: [String]) throws -> Entry {
        guard row.count >= 3 else { throw VaultError.importFailed("Too few columns for an mSecure item") }
        let cells = row + Array(repeating: "", count: max(0, 4 - row.count))
        let group = cells[0].trimmingCharacters(in: .whitespaces)
        let typeName = cells[1].trimmingCharacters(in: .whitespaces)
        let title = cells[2].trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = cells[3]
        let extra = Array(cells.dropFirst(4))

        let layout = layouts[typeName]
        var e = Entry(type: layout?.0 ?? .secureNote, title: title)
        e.notes = notes
        if !group.isEmpty && group != "Unassigned" { e.tags = [group] }

        let slots = layout?.1 ?? []
        for (i, raw) in extra.enumerated() where !raw.isEmpty {
            guard i < slots.count else {
                // Unknown type, or more fields than expected: keep them, numbered.
                e.customFields.append(CustomField(label: "Field \(i + 1)", value: raw))
                continue
            }
            switch slots[i] {
            case .url:
                e.urls.append(raw.trimmingCharacters(in: .whitespaces))
            case .field(let key):
                e.fields[key] = raw   // never trimmed, case preserved
            case .custom(let label, let kind):
                e.customFields.append(CustomField(label: label, value: raw, kind: kind))
            }
        }
        if layout == nil && !typeName.isEmpty {
            e.customFields.insert(CustomField(label: "mSecure type", value: typeName), at: 0)
        }
        if e.title.isEmpty { e.title = typeName.isEmpty ? "Untitled" : typeName }
        return e
    }
}
