import Foundation

/// "Pick characters": banks that ask for, say, the 2nd, 5th and 7th characters of a password
/// or memorable word. Positions are 1-based, as banks state them. Decision 0007 amendment.
/// Returns only the characters asked for, never the whole secret.
public enum CharacterPicker {
    public struct Pick: Equatable, Hashable {
        public let position: Int
        public let character: String
    }

    public enum PickError: Error, Equatable, CustomStringConvertible {
        case noPositions
        case notAPosition(String)
        case outOfRange(position: Int, length: Int)

        public var description: String {
            switch self {
            case .noPositions: return "Type the positions the site asks for, such as 2 5 7."
            case .notAPosition(let t): return "\"\(t)\" is not a position."
            case .outOfRange(let p, let n): return "Position \(p) is outside the secret (\(n) characters)."
            }
        }
    }

    /// Reads "2 5 7", "2,5,7" or "2nd, 5th and 7th". Keeps the order typed and drops repeats.
    public static func positions(_ text: String) throws -> [Int] {
        let tokens = text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0 != "and" }
        var result: [Int] = []
        for token in tokens {
            var t = token
            for suffix in ["st", "nd", "rd", "th"] where t.hasSuffix(suffix) && t.count > suffix.count {
                t.removeLast(suffix.count)
                break
            }
            guard let n = Int(t) else { throw PickError.notAPosition(token) }
            if !result.contains(n) { result.append(n) }
        }
        guard !result.isEmpty else { throw PickError.noPositions }
        return result
    }

    /// Counts characters as people see them (grapheme clusters), not bytes.
    public static func pick(_ secret: String, positions: [Int]) throws -> [Pick] {
        guard !positions.isEmpty else { throw PickError.noPositions }
        let chars = Array(secret)
        return try positions.map { p in
            guard p >= 1, p <= chars.count else { throw PickError.outOfRange(position: p, length: chars.count) }
            return Pick(position: p, character: String(chars[p - 1]))
        }
    }

    public static func pick(_ secret: String, positionsText: String) throws -> [Pick] {
        try pick(secret, positions: positions(positionsText))
    }
}
