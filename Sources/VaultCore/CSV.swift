import Foundation

/// RFC 4180 CSV: quoted commas, doubled quotes, multiline fields, CRLF or LF, optional BOM.
public enum CSV {
    public static func parse(_ text: String) throws -> [[String]] {
        var scalars = Array(text.unicodeScalars)
        if scalars.first == "\u{FEFF}" { scalars.removeFirst() }

        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false
        var i = 0

        func endField() {
            row.append(String(field))
            field = String.UnicodeScalarView()
        }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }   // skip blank lines
            row = []
        }

        while i < scalars.count {
            let c = scalars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < scalars.count && scalars[i + 1] == "\"" {
                        field.append("\"")
                        i += 2
                        continue
                    }
                    inQuotes = false
                } else {
                    field.append(c)
                }
                i += 1
                continue
            }
            switch c {
            case "\"":
                if field.isEmpty { inQuotes = true } else { field.append(c) }
            case ",":
                endField()
            case "\r":
                if i + 1 < scalars.count && scalars[i + 1] == "\n" { i += 1 }
                endRow()
            case "\n":
                endRow()
            default:
                field.append(c)
            }
            i += 1
        }
        if inQuotes { throw VaultError.importFailed("The file ends inside a quoted field.") }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }

    public static func write(_ rows: [[String]]) -> String {
        rows.map { $0.map(quote).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    static func quote(_ s: String) -> String {
        // Check scalars, not Characters: Swift treats "\r\n" as one Character, so contains("\n") misses it.
        let needs = s.unicodeScalars.contains { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }
            || s.hasPrefix(" ") || s.hasSuffix(" ")
        guard needs else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// devPassword's own CSV format: one file, a type column, every field and custom field.
/// Plaintext. For migration away from this app only.
/// Internal: callers outside this module must use Vault.exportPlaintextCSV(passphrase:).
enum CSVExport {
    static let fixedColumns = ["type", "title", "urls", "tags", "favourite", "notes", "notes_concealed", "custom_fields"]

    static var fieldColumns: [String] {
        RecordType.allCases.flatMap { $0.fieldDefs.map { "field:" + $0.key } }
    }

    static func make(_ entries: [Entry]) throws -> String {
        let header = fixedColumns + fieldColumns
        var rows: [[String]] = [header]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for e in entries where !e.isDeleted {
            let custom: String
            if e.customFields.isEmpty {
                custom = ""
            } else {
                let plain = e.customFields.map { ["label": $0.label, "value": $0.value, "kind": $0.kind.rawValue] }
                custom = String(decoding: try encoder.encode(plain), as: UTF8.self)
            }
            var row = [e.type.rawValue, e.title, e.urls.joined(separator: "\n"), e.tags.joined(separator: ";"),
                       e.favourite ? "1" : "0", e.notes, e.notesConcealed ? "1" : "0", custom]
            for col in fieldColumns {
                row.append(e[field: String(col.dropFirst("field:".count))])
            }
            rows.append(row)
        }
        return CSV.write(rows)
    }
}
