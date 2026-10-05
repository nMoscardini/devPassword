import Foundation

/// A named group with an icon. Each record is in at most one group (Entry.groupID).
/// The list is stored sealed in the vault, never in UserDefaults: a name such as
/// "Medical" says something on its own.
public struct EntryGroup: Codable, Identifiable, Hashable {
    public static let defaultIcon = "folder"
    public static let maxNameLength = 40

    public var id: UUID
    public var name: String
    /// SF Symbol name.
    public var icon: String

    public init(id: UUID = UUID(), name: String, icon: String = "folder") {
        self.id = id
        self.name = name
        self.icon = icon
    }

    /// What is wrong with a proposed name, or nil if it is fine.
    /// `except` is the group being renamed, so it does not clash with itself.
    public static func nameProblem(_ name: String, in groups: [EntryGroup], except id: UUID? = nil) -> String? {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "Give the group a name." }
        if t.count > maxNameLength { return "Keep the name to \(maxNameLength) characters or fewer." }
        if groups.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(t) == .orderedSame }) {
            return "There is already a group called \(t)."
        }
        return nil
    }

    static func validate(_ groups: [EntryGroup]) throws {
        guard Set(groups.map(\.id)).count == groups.count else { throw VaultError.invalid("Two groups share an ID.") }
        for g in groups {
            if let p = nameProblem(g.name, in: groups, except: g.id) { throw VaultError.invalid(p) }
        }
    }
}
