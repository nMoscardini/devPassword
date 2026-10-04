import Foundation

/// Where one CSV column goes.
public enum ImportTarget: Hashable, Identifiable {
    case ignore
    case recordType
    case title
    case urls
    case notes
    case tags
    case favourite
    case notesConcealed
    case customJSON
    case custom
    case field(String)

    public var id: String {
        switch self {
        case .field(let k): return "field:" + k
        default: return label
        }
    }

    public var label: String {
        switch self {
        case .ignore: return "Ignore"
        case .recordType: return "Record type"
        case .title: return "Title"
        case .urls: return "Website(s)"
        case .notes: return "Notes"
        case .tags: return "Tags"
        case .favourite: return "Favourite"
        case .notesConcealed: return "Notes concealed"
        case .customJSON: return "Custom fields (devPassword JSON)"
        case .custom: return "Custom field (column name as label)"
        case .field(let k):
            let def = RecordType.allFieldDefs[k]
            let owner = RecordType.allCases.first { t in t.fieldDefs.contains { $0.key == k } }
            return "\(owner?.displayName ?? "Field"): \(def?.label ?? k)"
        }
    }

    /// Every target, for the mapping picker.
    public static var all: [ImportTarget] {
        [.ignore, .custom, .title, .urls, .notes, .tags, .favourite, .recordType, .notesConcealed, .customJSON]
            + RecordType.allCases.flatMap { $0.fieldDefs.map { ImportTarget.field($0.key) } }
    }
}

public struct ImportMapping: Equatable {
    public var defaultType: RecordType
    public var targets: [ImportTarget]
    public init(defaultType: RecordType, targets: [ImportTarget]) {
        self.defaultType = defaultType
        self.targets = targets
    }
}

public enum ImportStatus: String {
    case new = "New"
    case duplicate = "Duplicate, skipped"
    case conflict = "Conflict, kept as separate entry"
    case rejected = "Rejected"
}

public struct ImportRow: Identifiable {
    /// Record number in the file, counting the header as record 1.
    public let id: Int
    public let status: ImportStatus
    public let entry: Entry?
    public let reason: String?
}

public struct ImportPreview {
    public let rows: [ImportRow]
    public var toCommit: [Entry] { rows.compactMap { $0.status == .new || $0.status == .conflict ? $0.entry : nil } }
    public func count(_ s: ImportStatus) -> Int { rows.filter { $0.status == s }.count }
}

public enum Importer {
    public static let reviewTag = "import-review"

    /// Splits CSV text into a header row and data rows.
    public static func table(from text: String) throws -> (headers: [String], rows: [[String]]) {
        let all = try CSV.parse(text)
        guard let headers = all.first, !headers.isEmpty else { throw VaultError.importFailed("The file is empty.") }
        return (headers, Array(all.dropFirst()))
    }

    // MARK: Mapping

    public static func guess(headers: [String], defaultType: RecordType = .login) -> ImportMapping {
        if headers.first == "type" && headers.contains("custom_fields") {
            // devPassword's own export.
            let targets: [ImportTarget] = headers.map { h in
                switch h {
                case "type": return .recordType
                case "title": return .title
                case "urls": return .urls
                case "tags": return .tags
                case "favourite": return .favourite
                case "notes": return .notes
                case "notes_concealed": return .notesConcealed
                case "custom_fields": return .customJSON
                default:
                    if h.hasPrefix("field:") { return .field(String(h.dropFirst("field:".count))) }
                    return .custom
                }
            }
            return ImportMapping(defaultType: defaultType, targets: targets)
        }
        return ImportMapping(defaultType: defaultType, targets: headers.map { guessTarget($0, type: defaultType) })
    }

    static func normalise(_ h: String) -> String {
        h.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func guessTarget(_ header: String, type: RecordType) -> ImportTarget {
        let h = normalise(header)
        let common: [String: ImportTarget] = [
            "name": .title, "title": .title, "itemname": .title,
            "url": .urls, "website": .urls, "websiteurl": .urls, "loginuri": .urls, "uri": .urls, "address": .urls,
            "notes": .notes, "note": .notes, "extra": .notes, "comments": .notes, "comment": .notes,
            "tags": .tags, "tag": .tags, "grouping": .tags, "group": .tags, "folder": .tags, "category": .tags,
            "fav": .favourite, "favorite": .favourite, "favourite": .favourite,
            "type": .recordType, "recordtype": .recordType, "itemtype": .recordType, "kind": .recordType,
            "username": .field("username"), "user": .field("username"), "login": .field("username"),
            "loginusername": .field("username"), "email": .field("username"),
            "password": .field("password"), "pass": .field("password"), "loginpassword": .field("password"),
            "cardholder": .field("cardholder"), "nameoncard": .field("cardholder"), "cardholdername": .field("cardholder"),
            "cardnumber": .field("cardNumber"), "ccnumber": .field("cardNumber"),
            "expiry": .field("cardExpiry"), "expiration": .field("cardExpiry"), "expirationdate": .field("cardExpiry"),
            "exp": .field("cardExpiry"), "expires": .field("cardExpiry"),
            "issuer": .field("cardIssuer"), "cardtype": .field("cardType"), "brand": .field("cardType"),
            "cvv": .field("securityCode"), "cvc": .field("securityCode"), "securitycode": .field("securityCode"),
            "cvv2": .field("securityCode"), "pin": .field("cardPIN"),
            "accountname": .field("accountName"), "bank": .field("bankName"), "bankname": .field("bankName"),
            "sortcode": .field("sortCode"), "accountnumber": .field("accountNumber"), "iban": .field("iban"),
            "bic": .field("bic"), "swift": .field("bic"), "customernumber": .field("customerNumber"),
            "documenttype": .field("documentType"), "holdername": .field("holderName"), "fullname": .field("holderName"),
            "documentnumber": .field("documentNumber"), "passportnumber": .field("documentNumber"),
            "licencenumber": .field("documentNumber"), "licensenumber": .field("documentNumber"),
            "issuingcountry": .field("issuingAuthority"), "country": .field("issuingAuthority"),
            "issuingauthority": .field("issuingAuthority"), "issuedate": .field("issueDate"), "dateofissue": .field("issueDate"),
            "expirydate": .field("expiryDate"), "dateofexpiry": .field("expiryDate"),
        ]
        var target = common[h] ?? .custom
        // Type-aware overrides for ambiguous column names.
        if h == "number" {
            switch type {
            case .paymentCard: target = .field("cardNumber")
            case .bankAccount: target = .field("accountNumber")
            case .identityDocument: target = .field("documentNumber")
            default: target = .custom
            }
        }
        if type == .identityDocument && (h == "expiry" || h == "expiration" || h == "expirationdate") {
            target = .field("expiryDate")
        }
        if type == .bankAccount && h == "pin" { target = .field("bankPasscode") }
        return target
    }

    /// Maps a type column value from another app to a record type.
    public static func recordType(from value: String) -> RecordType? {
        let v = normalise(value)
        if v.isEmpty { return nil }
        if let exact = RecordType(rawValue: value) { return exact }
        if ["login", "logins", "weblogin", "weblogins", "password", "passwords", "website"].contains(v) { return .login }
        if v.contains("note") { return .secureNote }
        if v.contains("prescription") || v.contains("medicine") { return .prescription }
        if v.contains("email") || v.contains("mail") { return .emailAccount }
        if v.contains("nationalinsurance") { return .identityDocument }
        if v.contains("insurance") || v.contains("policy") { return .insurance }
        if v.contains("registration") || v.contains("licencekey") || v.contains("licensekey") || v.contains("software") { return .registrationCode }
        if v.contains("vehicle") || v == "car" { return .vehicle }
        if v.contains("card") { return .paymentCard }
        if v.contains("bank") || v.contains("account") { return .bankAccount }
        if v.contains("passport") || v.contains("licen") || v.contains("identity") || v.contains("insurance") || v == "id" {
            return .identityDocument
        }
        return nil
    }

    static func looksSecret(_ header: String) -> Bool {
        let h = normalise(header)
        return ["password", "pin", "cvv", "cvc", "secret", "passcode", "totp", "otp", "code"].contains { h.contains($0) }
    }

    // MARK: Preview

    /// A row's outcome before duplicate checks: an entry, or the reason it was rejected.
    public struct BuiltRow {
        public let number: Int
        public let entry: Entry?
        public let problem: String?
        public init(number: Int, entry: Entry?, problem: String?) {
            self.number = number; self.entry = entry; self.problem = problem
        }
    }

    public static func preview(headers: [String], rows: [[String]], mapping: ImportMapping, existing: [Entry]) -> ImportPreview {
        var built: [BuiltRow] = []
        for (i, row) in rows.enumerated() {
            let number = i + 2
            guard row.count == headers.count else {
                built.append(BuiltRow(number: number, entry: nil, problem: "Has \(row.count) fields, expected \(headers.count)"))
                continue
            }
            do {
                built.append(BuiltRow(number: number, entry: try buildEntry(headers: headers, row: row, mapping: mapping), problem: nil))
            } catch {
                built.append(BuiltRow(number: number, entry: nil, problem: error.localizedDescription))
            }
        }
        return classify(built, existing: existing)
    }

    /// Duplicate and conflict checks against the vault and earlier rows in the same file.
    public static func classify(_ built: [BuiltRow], existing: [Entry]) -> ImportPreview {
        var existingKeys = Set(existing.filter { !$0.isDeleted }.map(dedupKey))
        var conflictKeys = Set(existing.filter { !$0.isDeleted }.compactMap(conflictKey))
        var out: [ImportRow] = []
        for b in built {
            guard var entry = b.entry else {
                out.append(ImportRow(id: b.number, status: .rejected, entry: nil, reason: b.problem))
                continue
            }
            let key = dedupKey(entry)
            if existingKeys.contains(key) {
                out.append(ImportRow(id: b.number, status: .duplicate, entry: entry, reason: nil))
                continue
            }
            existingKeys.insert(key)
            if let ck = conflictKey(entry) {
                if conflictKeys.contains(ck) {
                    if !entry.tags.contains(reviewTag) { entry.tags.append(reviewTag) }
                    out.append(ImportRow(id: b.number, status: .conflict, entry: entry,
                                         reason: "Same website and username, different password. Tagged \(reviewTag)."))
                    continue
                }
                conflictKeys.insert(ck)
            }
            out.append(ImportRow(id: b.number, status: .new, entry: entry, reason: nil))
        }
        Log.importer.info("event=import.previewed rows=\(built.count, privacy: .public)")
        return ImportPreview(rows: out)
    }

    static func buildEntry(headers: [String], row: [String], mapping: ImportMapping) throws -> Entry {
        var type = mapping.defaultType
        var unknownType: String?
        if let ti = mapping.targets.firstIndex(of: .recordType), ti < row.count {
            let raw = row[ti]
            if let t = recordType(from: raw) { type = t } else if !raw.trimmingCharacters(in: .whitespaces).isEmpty { unknownType = raw }
        }
        var e = Entry(type: type)
        let ownKeys = Set(type.fieldDefs.map(\.key))
        var notes: [String] = []

        for (i, target) in mapping.targets.enumerated() where i < row.count {
            let raw = row[i]
            let header = headers[i]
            switch target {
            case .ignore, .recordType:
                break
            case .title:
                e.title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            case .urls:
                e.urls += raw.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            case .notes:
                if !raw.isEmpty { notes.append(raw) }
            case .tags:
                e.tags += raw.split(whereSeparator: { $0 == ";" || $0 == "," || $0 == "\\" || $0 == "/" })
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            case .favourite:
                e.favourite = isTrue(raw)
            case .notesConcealed:
                e.notesConcealed = isTrue(raw)
            case .customJSON:
                guard !raw.isEmpty else { break }
                guard let data = raw.data(using: .utf8),
                      let items = try? JSONDecoder().decode([[String: String]].self, from: data) else {
                    throw VaultError.importFailed("Custom fields column is not valid devPassword JSON")
                }
                for item in items {
                    let kind = FieldKind(rawValue: item["kind"] ?? "") ?? .text
                    e.customFields.append(CustomField(label: item["label"] ?? "Field", value: item["value"] ?? "", kind: kind))
                }
            case .custom:
                if normalise(header) == "number", let key = equivalentKey("cardNumber", for: type), !raw.isEmpty, e.fields[key] == nil {
                    e.fields[key] = raw
                } else if !raw.isEmpty {
                    e.customFields.append(CustomField(label: header, value: raw, kind: looksSecret(header) ? .concealed : .text))
                }
            case .field(let key):
                guard !raw.isEmpty else { break }
                if ownKeys.contains(key) {
                    e.fields[key] = raw   // never trimmed, case preserved
                } else if let alt = equivalentKey(key, for: type), e.fields[alt] == nil {
                    e.fields[alt] = raw   // same meaning in this row's type, e.g. card expiry -> document expiry
                } else {
                    // A field that does not belong to this row's type is kept, never dropped.
                    let def = RecordType.allFieldDefs[key]
                    let kind: FieldKind = def?.kind == .concealed ? .concealed : .text
                    e.customFields.append(CustomField(label: header, value: raw, kind: kind))
                }
            }
        }
        if let unknownType {
            e.customFields.append(CustomField(label: "Original type", value: unknownType))
        }
        e.notes = notes.joined(separator: "\n")
        if e.title.isEmpty {
            e.title = e.urls.first.flatMap { URL(string: $0)?.host ?? $0 }
                ?? (e[field: "username"].isEmpty ? nil : e[field: "username"])
                ?? ""
        }
        let hasContent = !e.title.isEmpty || !e.fields.isEmpty || !e.notes.isEmpty || !e.customFields.isEmpty || !e.urls.isEmpty
        guard hasContent else { throw VaultError.importFailed("Row is empty") }
        if e.title.isEmpty { e.title = type.displayName }
        return e
    }

    /// Fields that mean the same thing across types, so a mixed-type file maps per row.
    static func equivalentKey(_ key: String, for type: RecordType) -> String? {
        let groups: [[RecordType: String]] = [
            [.paymentCard: "cardNumber", .bankAccount: "accountNumber", .identityDocument: "documentNumber"],
            [.paymentCard: "cardExpiry", .identityDocument: "expiryDate"],
            [.paymentCard: "cardPIN", .bankAccount: "bankPasscode"],
            [.paymentCard: "cardholder", .bankAccount: "accountName", .identityDocument: "holderName"],
            [.paymentCard: "cardIssuer", .bankAccount: "bankName", .identityDocument: "issuingAuthority"],
        ]
        for g in groups where g.values.contains(key) {
            return g[type]
        }
        return nil
    }

    static func isTrue(_ s: String) -> Bool {
        ["1", "true", "yes", "y"].contains(s.trimmingCharacters(in: .whitespaces).lowercased())
    }

    // MARK: Duplicates

    static func site(_ e: Entry) -> String {
        var u = (e.urls.first ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        while u.hasSuffix("/") { u.removeLast() }
        return u
    }

    /// Exact duplicate key. Logins: website, username, password. Others: type, title, main number.
    public static func dedupKey(_ e: Entry) -> String {
        switch e.type {
        case .login:
            return ["login", loginPlace(e), e[field: "username"], e[field: "password"]].joined(separator: "\u{1F}")
        case .secureNote:
            return ["note", e.title.lowercased(), e.notes].joined(separator: "\u{1F}")
        case .paymentCard:
            return ["card", e.title.lowercased(), e[field: "cardNumber"].filter(\.isNumber)].joined(separator: "\u{1F}")
        case .bankAccount:
            return ["bank", e.title.lowercased(), e[field: "accountNumber"].filter(\.isNumber), e[field: "iban"]].joined(separator: "\u{1F}")
        case .identityDocument:
            return ["id", e.title.lowercased(), e[field: "documentNumber"]].joined(separator: "\u{1F}")
        case .prescription:
            return ["rx", e.title.lowercased(), e[field: "medicineName"], e[field: "dose"]].joined(separator: "\u{1F}")
        case .vehicle:
            return ["vehicle", e.title.lowercased(), e[field: "registration"], e[field: "vin"]].joined(separator: "\u{1F}")
        case .emailAccount:
            return ["email", e.title.lowercased(), e[field: "emailAddress"], e[field: "emailPassword"]].joined(separator: "\u{1F}")
        case .insurance:
            return ["insurance", e.title.lowercased(), e[field: "policyNumber"]].joined(separator: "\u{1F}")
        case .registrationCode:
            return ["regcode", e.title.lowercased(), e[field: "licenceKey"]].joined(separator: "\u{1F}")
        }
    }

    /// Where a login belongs: its website, or its title when it has no website. Without the
    /// title fallback, every website-less login with the same username (one email address used
    /// everywhere) looked like the same account: false conflicts, and with a reused password,
    /// rows skipped as duplicates.
    static func loginPlace(_ e: Entry) -> String {
        let s = site(e)
        return s.isEmpty ? "title:" + e.title.lowercased().trimmingCharacters(in: .whitespaces) : s
    }

    /// Logins only: same website (or, without one, same title) and username.
    public static func conflictKey(_ e: Entry) -> String? {
        guard e.type == .login, !site(e).isEmpty || !e[field: "username"].isEmpty else { return nil }
        return [loginPlace(e), e[field: "username"]].joined(separator: "\u{1F}")
    }
}
