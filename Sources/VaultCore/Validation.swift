import Foundation

public enum PassphrasePolicy {
    public static let minimumLength = 12

    /// Returns a message if the passphrase is too weak, otherwise nil.
    public static func problem(_ passphrase: String) -> String? {
        if passphrase.count < minimumLength {
            return "Use at least \(minimumLength) characters. Four or more random words works well."
        }
        if Set(passphrase).count < 5 {
            return "That passphrase repeats too few characters."
        }
        return nil
    }

    public static func validate(_ passphrase: String) throws {
        if let p = problem(passphrase) { throw VaultError.weakPassphrase(p) }
    }
}

/// Warnings, not refusals (spec F02). The user can always save.
public enum EntryValidation {
    public static func warnings(for e: Entry) -> [String] {
        var out: [String] = []
        if e.title.trimmingCharacters(in: .whitespaces).isEmpty {
            out.append("Add a title.")
        }
        switch e.type {
        case .paymentCard:
            let number = e[field: "cardNumber"]
            if !number.isEmpty && !luhnValid(number) {
                out.append("The card number fails the standard check digit test. Check it.")
            }
            let exp = e[field: "cardExpiry"]
            if !exp.isEmpty && DateParsing.cardExpiry(exp) == nil {
                out.append("Expiry should look like MM/YY.")
            }
        case .identityDocument:
            for key in ["issueDate", "expiryDate"] {
                let v = e[field: key]
                if !v.isEmpty && DateParsing.isoDate(v) == nil {
                    out.append("\(RecordType.allFieldDefs[key]?.label ?? key) should look like YYYY-MM-DD.")
                }
            }
        case .bankAccount:
            let sort = e[field: "sortCode"].filter { $0.isNumber }
            if !e[field: "sortCode"].isEmpty && sort.count != 6 {
                out.append("A UK sort code has six digits.")
            }
        default:
            break
        }
        for f in e.customFields where f.kind == .date && !f.value.isEmpty && DateParsing.isoDate(f.value) == nil {
            out.append("\(f.label) should look like YYYY-MM-DD.")
        }
        return out
    }

    public static func luhnValid(_ s: String) -> Bool {
        let digits = s.filter { !$0.isWhitespace && $0 != "-" }
        guard digits.count >= 12, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
        var sum = 0
        for (i, ch) in digits.reversed().enumerated() {
            var d = Int(String(ch))!
            if i % 2 == 1 {
                d *= 2
                if d > 9 { d -= 9 }
            }
            sum += d
        }
        return sum % 10 == 0
    }
}
