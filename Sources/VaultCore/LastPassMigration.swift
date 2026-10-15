import Foundation

/// One row of a LastPass export (Advanced Options > Export > LastPass CSV File).
public struct LastPassItem: Hashable {
    public var url: String
    public var username: String
    public var password: String
    public var totp: String
    public var extra: String
    public var name: String
    public var grouping: String

    public init(url: String, username: String = "", password: String = "", totp: String = "",
                extra: String = "", name: String = "", grouping: String = "") {
        self.url = url
        self.username = username
        self.password = password
        self.totp = totp
        self.extra = extra
        self.name = name
        self.grouping = grouping
    }

    /// LastPass marks secure notes with this URL.
    public var isSecureNote: Bool { url.trimmingCharacters(in: .whitespaces).lowercased() == "http://sn" }
    public var hasWebsite: Bool { !AppleImport.host(url).isEmpty && !isSecureNote }
}

/// A LastPass login that matches an existing devPassword login.
public struct LastPassMatch: Identifiable, Hashable {
    public let id = UUID()
    public var item: LastPassItem
    public var entry: Entry
}

/// What a LastPass move would do. Nothing is written until Nino says so.
public struct LastPassPlan {
    /// Logins Apple Passwords does not have yet. Go to the file for Passwords > File > Import Passwords.
    public var toApple: [LastPassItem] = []
    /// Same website, username and password already in the Apple snapshot. Skipped.
    public var alreadyInApple = 0
    /// Same website and username in the Apple snapshot, different password. Nino decides.
    public var passwordDiffers: [LastPassMatch] = []
    /// devPassword is the master for these (decision 0007): never sent to Apple.
    public var devPasswordMastered: [LastPassMatch] = []
    /// New devPassword records: secure notes, and logins with no website (Apple cannot fill them).
    public var newRecords: [Entry] = []
    /// Notes and website-less logins devPassword already has. Skipped.
    public var alreadyInDevPassword = 0
    /// The same login twice in the LastPass file. Counted once.
    public var duplicatesInFile = 0
    /// Rows with nothing to keep.
    public var skipped = 0
    public var total = 0
}

/// Decision 0007 migration: LastPass logins go to Apple Passwords, never straight into devPassword.
/// Everything else LastPass held (secure notes) becomes devPassword records.
public enum LastPassMigration {
    public static let tag = "lastpass"

    // MARK: Read

    public static func parse(_ text: String) throws -> [LastPassItem] {
        let rows = try CSV.parse(text)
        guard let head = rows.first else { throw VaultError.importFailed("The file is empty.") }
        let names = head.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        func col(_ n: String) -> Int? { names.firstIndex(of: n) }
        guard let u = col("url"), let n = col("username"), let p = col("password") else {
            throw VaultError.importFailed("This is not a LastPass export. It needs the columns url, username and password.")
        }
        let t = col("totp"), x = col("extra"), nm = col("name"), g = col("grouping")
        func cell(_ r: [String], _ i: Int?) -> String {
            guard let i, i < r.count else { return "" }
            return r[i]
        }
        return rows.dropFirst().map { r in
            LastPassItem(url: cell(r, u).trimmingCharacters(in: .whitespaces),
                         username: cell(r, n).trimmingCharacters(in: .whitespaces),
                         password: cell(r, p),
                         totp: cell(r, t).trimmingCharacters(in: .whitespaces),
                         extra: cell(r, x),
                         name: cell(r, nm).trimmingCharacters(in: .whitespaces),
                         grouping: cell(r, g).trimmingCharacters(in: .whitespaces))
        }
    }

    // MARK: Plan

    public static func plan(_ items: [LastPassItem], existing: [Entry]) -> LastPassPlan {
        var plan = LastPassPlan()
        plan.total = items.count
        let live = existing.filter { !$0.isDeleted }
        var apple: [String: Entry] = [:]
        var devMastered: [String: Entry] = [:]
        for e in live where e.type == .login {
            if e.isAppleSnapshot, e.appleRemovedAt == nil { apple[AppleImport.place(e)] = e }
            else if e.master == .devPassword { devMastered[AppleImport.place(e)] = e }
        }
        var existingKeys = Set(live.map(Importer.dedupKey))
        var seenLogins = Set<String>()

        for item in items {
            if item.isSecureNote || !item.hasWebsite {
                guard let e = record(from: item) else { plan.skipped += 1; continue }
                let k = Importer.dedupKey(e)
                if existingKeys.contains(k) { plan.alreadyInDevPassword += 1; continue }
                existingKeys.insert(k)
                plan.newRecords.append(e)
                continue
            }
            if item.username.isEmpty && item.password.isEmpty { plan.skipped += 1; continue }
            let place = AppleImport.place(url: item.url, username: item.username)
            let dupKey = place + "\u{1F}" + item.password
            if !seenLogins.insert(dupKey).inserted { plan.duplicatesInFile += 1; continue }
            if let dev = devMastered[place] {
                plan.devPasswordMastered.append(LastPassMatch(item: item, entry: dev))
            } else if let a = apple[place] {
                if a[field: "password"] == item.password { plan.alreadyInApple += 1 }
                else { plan.passwordDiffers.append(LastPassMatch(item: item, entry: a)) }
            } else {
                plan.toApple.append(item)
            }
        }
        return plan
    }

    /// A devPassword record for a LastPass secure note, or a login with no website.
    static func record(from item: LastPassItem) -> Entry? {
        var tags = [tag]
        if !item.grouping.isEmpty { tags.append(item.grouping) }
        if item.isSecureNote {
            guard !item.extra.isEmpty || !item.name.isEmpty else { return nil }
            var e = Entry(type: .secureNote, title: item.name.isEmpty ? "LastPass note" : item.name)
            e.notes = item.extra
            e.notesConcealed = true   // LastPass notes often hold card numbers and codes
            e.tags = tags
            return e
        }
        guard !item.username.isEmpty || !item.password.isEmpty else { return nil }
        var e = Entry(type: .login, title: item.name.isEmpty ? (item.username.isEmpty ? "LastPass login" : item.username) : item.name)
        if !AppleImport.host(item.url).isEmpty { e.urls = [item.url] }   // never keep the "http://" placeholder
        e[field: "username"] = item.username
        e[field: "password"] = item.password
        e[field: "otpAuth"] = item.totp.isEmpty ? "" : otpURL(secret: item.totp, issuer: e.title, account: item.username)
        e.notes = item.extra
        e.master = .devPassword   // no website: Apple cannot fill it
        e.tags = tags
        return e
    }

    // MARK: The file for Apple

    /// LastPass keeps the bare base32 secret; Apple wants an otpauth:// link.
    public static func otpURL(secret: String, issuer: String, account: String) -> String {
        let s = secret.replacingOccurrences(of: " ", with: "").uppercased()
        if s.lowercased().hasPrefix("otpauth://") { return secret }
        var c = URLComponents()
        c.scheme = "otpauth"
        c.host = "totp"
        c.path = "/" + (issuer.isEmpty ? account : "\(issuer):\(account)")
        c.queryItems = [URLQueryItem(name: "secret", value: s)] + (issuer.isEmpty ? [] : [URLQueryItem(name: "issuer", value: issuer)])
        return c.string ?? ""
    }

    /// Apple Passwords' own export format, which its importer reads back.
    public static func appleCSV(_ items: [LastPassItem]) -> String {
        var rows = [AppleImport.columns]
        for i in items {
            let host = AppleImport.host(i.url)
            let title = i.username.isEmpty ? host : "\(host) (\(i.username))"
            rows.append([title, i.url, i.username, i.password, i.extra,
                         i.totp.isEmpty ? "" : otpURL(secret: i.totp, issuer: host, account: i.username)])
        }
        return CSV.write(rows)
    }

    /// Writes the file owner-only and never over an existing file. Returns where it went.
    public static func writeForApple(_ csv: String, in folder: URL, now: Date = Date()) throws -> URL {
        let url = folder.appendingPathComponent("devPassword-for-Apple-\(Vault.timestamp(now)).csv")
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path),
              fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]),
              let h = try? FileHandle(forWritingTo: url) else {
            throw VaultError.importFailed("Could not create the file for Apple in \(folder.path).")
        }
        defer { try? h.close() }
        try h.write(contentsOf: Data(csv.utf8))
        return url
    }

    // MARK: Apply

    /// Saves the new devPassword records after a snapshot (N3). Returns how many.
    @discardableResult
    public static func saveRecords(_ plan: LastPassPlan, to vault: Vault) throws -> Int {
        guard !plan.newRecords.isEmpty else { return 0 }
        try vault.snapshot(reason: "lastpass")
        try vault.saveAll(plan.newRecords)
        vault.audit("lastpass.records_imported")
        return plan.newRecords.count
    }
}
