import Foundation

public struct PasswordOptions: Equatable {
    public var length: Int = 20
    public var lowercase = true
    public var uppercase = true
    public var digits = true
    public var symbols = true
    public var avoidLookAlikes = false
    /// Characters the user never wants, for sites that reject them.
    public var excluded = ""

    public init() {}
}

/// Spec F04. Apple cryptographic random source, unbiased selection, at least one of each chosen set.
public enum PasswordGenerator {
    static let lower = "abcdefghijklmnopqrstuvwxyz"
    static let upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    static let digitSet = "0123456789"
    static let symbolSet = "!@#$%^&*()-_=+[]{};:,.?/~"
    static let lookAlikes = Set("Il1O0o|`'\"")

    public static func generate(_ o: PasswordOptions) throws -> String {
        var sets: [[Character]] = []
        let banned = Set(o.excluded).union(o.avoidLookAlikes ? lookAlikes : [])
        func add(_ enabled: Bool, _ chars: String) {
            guard enabled else { return }
            let filtered = chars.filter { !banned.contains($0) }
            if !filtered.isEmpty { sets.append(Array(filtered)) }
        }
        add(o.lowercase, lower)
        add(o.uppercase, upper)
        add(o.digits, digitSet)
        add(o.symbols, symbolSet)
        guard !sets.isEmpty else { throw VaultError.invalid("Choose at least one character set.") }
        let length = max(o.length, sets.count, 4)

        var rng = SecureRandom()
        var chars: [Character] = sets.map { $0[Int.random(in: 0..<$0.count, using: &rng)] }
        let pool = sets.flatMap { $0 }
        while chars.count < length {
            chars.append(pool[Int.random(in: 0..<pool.count, using: &rng)])
        }
        chars.shuffle(using: &rng)
        return String(chars)
    }
}
