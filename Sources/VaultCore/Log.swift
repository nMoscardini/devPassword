import os

/// Structured logs with stable event names (principle 8).
/// Never log values, titles, usernames, numbers or passphrases. IDs and counts only.
enum Log {
    static let vault = Logger(subsystem: "com.moscardini.devpassword", category: "vault")
    static let backup = Logger(subsystem: "com.moscardini.devpassword", category: "backup")
    static let importer = Logger(subsystem: "com.moscardini.devpassword", category: "import")
}
