import Foundation

public enum FieldKind: String, Codable, CaseIterable, Hashable {
    case text, concealed, date, expiry

    public var label: String {
        switch self {
        case .text: return "Text"
        case .concealed: return "Concealed"
        case .date: return "Date (YYYY-MM-DD)"
        case .expiry: return "Expiry (MM/YY)"
        }
    }
}

/// One field in a record type's template. Keys are unique across all types.
public struct FieldDef: Hashable {
    public let key: String
    public let label: String
    public let kind: FieldKind
    public let showsLastFour: Bool
    public let placeholder: String

    init(_ key: String, _ label: String, _ kind: FieldKind = .text, lastFour: Bool = false, placeholder: String = "") {
        self.key = key
        self.label = label
        self.kind = kind
        self.showsLastFour = lastFour
        self.placeholder = placeholder
    }
}

/// Record types R01 to R05 in the spec. R06 (custom fields) applies to every type.
public enum RecordType: String, Codable, CaseIterable, Identifiable, Hashable {
    case login, secureNote, paymentCard, bankAccount, identityDocument

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .login: return "Login"
        case .secureNote: return "Secure Note"
        case .paymentCard: return "Payment Card"
        case .bankAccount: return "Bank Account"
        case .identityDocument: return "Identity Document"
        }
    }

    public var pluralName: String {
        switch self {
        case .login: return "Logins"
        case .secureNote: return "Secure Notes"
        case .paymentCard: return "Payment Cards"
        case .bankAccount: return "Bank Accounts"
        case .identityDocument: return "Identity Documents"
        }
    }

    /// SF Symbol name.
    public var symbol: String {
        switch self {
        case .login: return "key.horizontal"
        case .secureNote: return "note.text"
        case .paymentCard: return "creditcard"
        case .bankAccount: return "building.columns"
        case .identityDocument: return "person.text.rectangle"
        }
    }

    public var fieldDefs: [FieldDef] {
        switch self {
        case .login:
            return [FieldDef("username", "Username"),
                    FieldDef("password", "Password", .concealed)]
        case .secureNote:
            return []
        case .paymentCard:
            return [FieldDef("cardholder", "Cardholder name"),
                    FieldDef("cardNumber", "Card number", .concealed, lastFour: true),
                    FieldDef("cardExpiry", "Expiry", .expiry, placeholder: "MM/YY"),
                    FieldDef("cardIssuer", "Issuer"),
                    FieldDef("cardType", "Card type", placeholder: "Visa, Mastercard, Amex"),
                    FieldDef("securityCode", "Security code", .concealed),
                    FieldDef("cardPIN", "PIN", .concealed)]
        case .bankAccount:
            return [FieldDef("accountName", "Account name"),
                    FieldDef("bankName", "Bank"),
                    FieldDef("sortCode", "Sort code", placeholder: "00-00-00"),
                    FieldDef("accountNumber", "Account number", .concealed, lastFour: true),
                    FieldDef("iban", "IBAN", .concealed, lastFour: true),
                    FieldDef("bic", "BIC"),
                    FieldDef("customerNumber", "Online banking customer number"),
                    FieldDef("bankPasscode", "Passcode", .concealed)]
        case .identityDocument:
            return [FieldDef("documentType", "Document type", placeholder: "Passport, Driving licence, National Insurance number"),
                    FieldDef("holderName", "Holder name"),
                    FieldDef("documentNumber", "Document number", .concealed, lastFour: true),
                    FieldDef("issuingAuthority", "Issuing country or authority"),
                    FieldDef("issueDate", "Issue date", .date, placeholder: "YYYY-MM-DD"),
                    FieldDef("expiryDate", "Expiry date", .date, placeholder: "YYYY-MM-DD")]
        }
    }

    /// Every field definition across all types, keyed by field key.
    public static let allFieldDefs: [String: FieldDef] = {
        var all: [String: FieldDef] = [:]
        for t in RecordType.allCases { for d in t.fieldDefs { all[d.key] = d } }
        return all
    }()
}

public struct CustomField: Codable, Hashable, Identifiable {
    public var id: UUID
    public var label: String
    public var value: String
    public var kind: FieldKind

    public init(id: UUID = UUID(), label: String, value: String, kind: FieldKind = .text) {
        self.id = id
        self.label = label
        self.value = value
        self.kind = kind
    }
}

public struct PreviousValue: Codable, Hashable {
    public var value: String
    public var changedAt: Date
    public init(value: String, changedAt: Date) {
        self.value = value
        self.changedAt = changedAt
    }
}

/// One vault record. The whole struct is encrypted as a single payload.
public struct Entry: Codable, Identifiable, Hashable {
    public static let payloadVersion = 1

    public var id: UUID
    public var type: RecordType
    public var title: String
    public var urls: [String]
    public var fields: [String: String]
    public var customFields: [CustomField]
    public var notes: String
    public var notesConcealed: Bool
    public var tags: [String]
    public var favourite: Bool
    /// The password before the last change. Kept until Nino confirms the new one works.
    public var previousPassword: PreviousValue?
    public var created: Date
    public var modified: Date
    /// Set when moved to Deleted. A deleted record can be restored or purged.
    public var deletedAt: Date?

    public init(id: UUID = UUID(), type: RecordType, title: String = "") {
        self.id = id
        self.type = type
        self.title = title
        self.urls = []
        self.fields = [:]
        self.customFields = []
        self.notes = ""
        self.notesConcealed = false
        self.tags = []
        self.favourite = false
        self.previousPassword = nil
        self.created = Date()
        self.modified = Date()
        self.deletedAt = nil
    }

    public subscript(field key: String) -> String {
        get { fields[key] ?? "" }
        set { fields[key] = newValue.isEmpty ? nil : newValue }
    }

    public var isDeleted: Bool { deletedAt != nil }

    /// Expiry for cards and identity documents, as the last day it is valid.
    public var expiryDate: Date? {
        switch type {
        case .paymentCard: return DateParsing.cardExpiry(self[field: "cardExpiry"])
        case .identityDocument: return DateParsing.isoDate(self[field: "expiryDate"])
        default: return nil
        }
    }

    public func expires(within days: Int, from now: Date = Date()) -> Bool {
        guard let exp = expiryDate else { return false }
        guard let limit = Calendar.current.date(byAdding: .day, value: days, to: now) else { return false }
        return exp <= limit
    }

    /// Text used for search. Concealed fields and concealed notes are never included.
    public var searchableText: String {
        var parts: [String] = [title, type.displayName]
        parts += urls
        for def in type.fieldDefs where def.kind != .concealed {
            parts.append(self[field: def.key])
        }
        for f in customFields where f.kind != .concealed {
            parts.append(f.label)
            parts.append(f.value)
        }
        if !notesConcealed { parts.append(notes) }
        parts += tags
        return parts.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Short line shown under the title in lists. Never shows a full concealed value.
    public var subtitle: String {
        switch type {
        case .login:
            return self[field: "username"].isEmpty ? (urls.first ?? "") : self[field: "username"]
        case .secureNote:
            return notesConcealed ? "Concealed note" : String(notes.prefix(60)).replacingOccurrences(of: "\n", with: " ")
        case .paymentCard:
            return [self[field: "cardIssuer"], Masking.lastFour(self[field: "cardNumber"])].filter { !$0.isEmpty }.joined(separator: "  ")
        case .bankAccount:
            return [self[field: "bankName"], Masking.lastFour(self[field: "accountNumber"])].filter { !$0.isEmpty }.joined(separator: "  ")
        case .identityDocument:
            return [self[field: "documentType"], self[field: "holderName"]].filter { !$0.isEmpty }.joined(separator: " - ")
        }
    }
}

public enum Masking {
    /// "•••• 1234" for numbers with at least six characters, otherwise all dots.
    public static func lastFour(_ value: String) -> String {
        let compact = value.filter { !$0.isWhitespace && $0 != "-" }
        guard !compact.isEmpty else { return "" }
        guard compact.count >= 6 else { return "••••" }
        return "•••• " + String(compact.suffix(4))
    }

    public static let dots = "••••••••"
}

public enum DateParsing {
    /// "MM/YY" or "MM/YYYY". Returns the last day of that month.
    public static func cardExpiry(_ s: String) -> Date? {
        let parts = s.trimmingCharacters(in: .whitespaces).split(separator: "/")
        guard parts.count == 2, let month = Int(parts[0]), var year = Int(parts[1]), (1...12).contains(month) else { return nil }
        if parts[1].count == 2 { year += 2000 }
        guard parts[1].count == 2 || parts[1].count == 4 else { return nil }
        var comps = DateComponents()
        comps.year = year
        comps.month = month + 1
        comps.day = 0   // day 0 of next month = last day of this month
        return Calendar(identifier: .gregorian).date(from: comps)
    }

    /// "YYYY-MM-DD".
    public static func isoDate(_ s: String) -> Date? {
        let parts = s.trimmingCharacters(in: .whitespaces).split(separator: "-")
        guard parts.count == 3, parts[0].count == 4,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        var comps = DateComponents()
        comps.year = y
        comps.month = m
        comps.day = d
        let cal = Calendar(identifier: .gregorian)
        guard let date = cal.date(from: comps), cal.component(.day, from: date) == d else { return nil }
        return date
    }
}
