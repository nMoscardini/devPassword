import Foundation

/// One event in an Apple-imported login's history. Dates and kinds only, never a secret.
public struct AppleLoginEvent: Codable, Hashable {
    public enum Kind: String, Codable, Hashable {
        case added, passwordChanged, detailsChanged, removed, returned
    }
    public var at: Date
    public var kind: Kind

    public init(at: Date, kind: Kind) {
        self.at = at
        self.kind = kind
    }

    public var text: String {
        switch kind {
        case .added: return "First seen in Apple Passwords"
        case .passwordChanged: return "Password changed in Apple Passwords"
        case .detailsChanged: return "Website, username, notes or one-time code changed"
        case .removed: return "No longer in Apple Passwords"
        case .returned: return "Back in Apple Passwords"
        }
    }
}

/// One row of an Apple Passwords export (Passwords > File > Export All Passwords).
public struct AppleLogin: Hashable {
    public var title: String
    public var url: String
    public var username: String
    public var password: String
    public var notes: String
    public var otpAuth: String

    public init(title: String = "", url: String, username: String, password: String, notes: String = "", otpAuth: String = "") {
        self.title = title
        self.url = url
        self.username = username
        self.password = password
        self.notes = notes
        self.otpAuth = otpAuth
    }
}

/// A login in the export paired with the devPassword record it matched.
public struct AppleMatch: Hashable {
    public var entry: Entry
    public var login: AppleLogin
    public var key: String
}

/// What an import would do. Built first and shown to Nino. Nothing is written until `apply`.
public struct AppleImportPlan {
    public var added: [(key: String, login: AppleLogin)] = []
    public var changed: [AppleMatch] = []
    public var unchanged: [AppleMatch] = []
    public var returned: [AppleMatch] = []
    /// Apple snapshot logins missing from this export. Kept, marked removed.
    public var removed: [Entry] = []
    /// In Apple, but devPassword is this login's master (decision 0007). Not imported: Nino chooses.
    public var masterClashes: [AppleMatch] = []
    /// New Apple logins that match an editable devPassword login (from mSecure). Both are kept.
    public var alsoInDevPassword: [AppleMatch] = []
    /// Rows with neither a website nor a username. Not imported.
    public var skipped = 0
    public var total = 0

    /// Records the import writes, for the summary line.
    public var writes: Int { added.count + changed.count + unchanged.count + returned.count + removed.count }
}

/// Decision 0007: Apple Passwords is the master for logins. devPassword keeps a read-only,
/// dated snapshot and a history of changes. One way only: nothing goes back to Apple.
public enum AppleImport {
    /// Columns in Apple's export, checked against Nino's export on 15 October 2026.
    public static let columns = ["Title", "URL", "Username", "Password", "Notes", "OTPAuth"]

    // MARK: Read the file

    public static func parse(_ text: String) throws -> (logins: [AppleLogin], skipped: Int) {
        let rows = try CSV.parse(text)
        guard let head = rows.first else { throw VaultError.importFailed("The file is empty.") }
        let names = head.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        func col(_ n: String) -> Int? { names.firstIndex { $0.caseInsensitiveCompare(n) == .orderedSame } }
        guard let t = col("Title"), let u = col("URL"), let n = col("Username"), let p = col("Password") else {
            throw VaultError.importFailed("This is not an Apple Passwords export. It needs the columns Title, URL, Username and Password.")
        }
        let notes = col("Notes"), otp = col("OTPAuth")
        func cell(_ r: [String], _ i: Int?) -> String {
            guard let i, i < r.count else { return "" }
            return r[i]
        }
        var logins: [AppleLogin] = []
        var skipped = 0
        for r in rows.dropFirst() {
            let login = AppleLogin(title: cell(r, t).trimmingCharacters(in: .whitespaces),
                                   url: cell(r, u).trimmingCharacters(in: .whitespaces),
                                   username: cell(r, n).trimmingCharacters(in: .whitespaces),
                                   password: cell(r, p),
                                   notes: cell(r, notes),
                                   otpAuth: cell(r, otp).trimmingCharacters(in: .whitespaces))
            if login.url.isEmpty && login.username.isEmpty { skipped += 1; continue }
            logins.append(login)
        }
        return (logins, skipped)
    }

    // MARK: Matching

    /// "https://www.Example.com/login" -> "example.com". Falls back to the trimmed text.
    public static func host(_ url: String) -> String {
        let s = url.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return "" }
        let withScheme = s.contains("://") ? s : "https://" + s
        if var h = URLComponents(string: withScheme)?.host, !h.isEmpty {
            if h.hasPrefix("www.") { h.removeFirst(4) }
            return h
        }
        return s
    }

    /// Website host and username. The same site and username can appear more than once in an
    /// export, so `key` adds the occurrence number.
    public static func place(url: String, username: String) -> String {
        host(url) + "\u{1F}" + username.lowercased()
    }

    static func place(_ e: Entry) -> String { place(url: e.urls.first ?? "", username: e[field: "username"]) }

    /// Title for a new record: Apple writes "site (username)"; keep the site part.
    public static func displayTitle(_ l: AppleLogin) -> String {
        var t = l.title
        let suffix = " (\(l.username))"
        if !l.username.isEmpty, t.hasSuffix(suffix) { t.removeLast(suffix.count) }
        if t.isEmpty { t = host(l.url) }
        return t.isEmpty ? l.username : t
    }

    // MARK: Plan

    public static func plan(_ logins: [AppleLogin], skipped: Int = 0, existing: [Entry]) -> AppleImportPlan {
        var plan = AppleImportPlan()
        plan.skipped = skipped
        plan.total = logins.count
        let live = existing.filter { !$0.isDeleted && $0.type == .login }

        var snapshots: [String: Entry] = [:]
        for e in live where e.isAppleSnapshot { snapshots[e.appleKey ?? (place(e) + "\u{1F}1")] = e }
        var devMastered: [String: Entry] = [:]
        var editable: [String: Entry] = [:]
        for e in live where !e.isAppleSnapshot {
            if e.master == .devPassword { devMastered[place(e)] = e } else { editable[place(e)] = e }
        }

        var seen: [String: Int] = [:]
        for l in logins {
            let p = place(url: l.url, username: l.username)
            seen[p, default: 0] += 1
            let key = p + "\u{1F}" + String(seen[p]!)
            if let snap = snapshots.removeValue(forKey: key) {
                let m = AppleMatch(entry: snap, login: l, key: key)
                if snap.appleRemovedAt != nil { plan.returned.append(m) }
                else if differs(snap, l) { plan.changed.append(m) }
                else { plan.unchanged.append(m) }
            } else if let dev = devMastered[p] {
                plan.masterClashes.append(AppleMatch(entry: dev, login: l, key: key))
            } else {
                plan.added.append((key, l))
                if let old = editable[p] { plan.alsoInDevPassword.append(AppleMatch(entry: old, login: l, key: key)) }
            }
        }
        plan.removed = snapshots.values.filter { $0.appleRemovedAt == nil }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return plan
    }

    static func differs(_ e: Entry, _ l: AppleLogin) -> Bool {
        e[field: "password"] != l.password || detailsDiffer(e, l)
    }

    static func detailsDiffer(_ e: Entry, _ l: AppleLogin) -> Bool {
        (e.urls.first ?? "") != l.url || e[field: "username"] != l.username
            || e.notes != l.notes || e[field: "otpAuth"] != l.otpAuth
    }

    // MARK: Apply

    /// Writes the plan in one transaction, after a snapshot (N3). Returns the records written.
    @discardableResult
    public static func apply(_ plan: AppleImportPlan, to vault: Vault, now: Date = Date()) throws -> Int {
        var out: [Entry] = []
        for (key, l) in plan.added {
            var e = Entry(type: .login, title: displayTitle(l))
            e.created = now
            e.modified = now
            e.master = .apple
            e.appleKey = key
            e.appleHistory = [AppleLoginEvent(at: now, kind: .added)]
            fill(&e, from: l)
            e.appleSeenAt = now
            out.append(e)
        }
        for m in plan.changed + plan.returned {
            var e = m.entry
            var events = e.appleHistory ?? []
            if e.appleRemovedAt != nil {
                events.append(AppleLoginEvent(at: now, kind: .returned))
                e.appleRemovedAt = nil
            }
            if e[field: "password"] != m.login.password {
                if !e[field: "password"].isEmpty {
                    e.previousPassword = PreviousValue(value: e[field: "password"], changedAt: now)
                }
                events.append(AppleLoginEvent(at: now, kind: .passwordChanged))
            }
            if detailsDiffer(e, m.login) { events.append(AppleLoginEvent(at: now, kind: .detailsChanged)) }
            fill(&e, from: m.login)
            e.appleHistory = events
            e.appleSeenAt = now
            e.modified = now
            out.append(e)
        }
        for m in plan.unchanged {
            var e = m.entry
            e.appleSeenAt = now
            out.append(e)
        }
        for var e in plan.removed {
            e.appleRemovedAt = now
            e.appleHistory = (e.appleHistory ?? []) + [AppleLoginEvent(at: now, kind: .removed)]
            out.append(e)
        }
        guard !out.isEmpty else { return 0 }
        try vault.snapshot(reason: "apple-import")
        try vault.saveAll(out, touchModified: false)
        vault.audit("apple.import")
        Log.vault.info("event=apple.import added=\(plan.added.count, privacy: .public) changed=\(plan.changed.count, privacy: .public) removed=\(plan.removed.count, privacy: .public)")
        return out.count
    }

    /// Apple owns these fields on a snapshot login.
    static func fill(_ e: inout Entry, from l: AppleLogin) {
        e.urls = l.url.isEmpty ? [] : [l.url]
        e[field: "username"] = l.username
        e[field: "password"] = l.password
        e[field: "otpAuth"] = l.otpAuth
        e.notes = l.notes
        e.notesConcealed = false
        e.master = .apple
    }

    // MARK: Read-only rule

    /// An edit to a snapshot login keeps Apple's fields as they were. devPassword's own fields
    /// (title, second password, custom fields, tags, group, icon, favourite) can still change.
    public static func keepAppleFields(_ edited: Entry, from original: Entry) -> Entry {
        guard original.isAppleSnapshot else { return edited }
        var e = edited
        e.urls = original.urls
        for k in ["username", "password", "otpAuth"] { e[field: k] = original[field: k] }
        e.notes = original.notes
        e.notesConcealed = original.notesConcealed
        e.master = .apple
        e.previousPassword = original.previousPassword
        e.appleSeenAt = original.appleSeenAt
        e.appleRemovedAt = original.appleRemovedAt
        e.appleKey = original.appleKey
        e.appleHistory = original.appleHistory
        return e
    }

    // MARK: Snapshot age

    /// Date of the latest Apple import, or nil if there has never been one.
    public static func lastImport(_ entries: [Entry]) -> Date? {
        entries.compactMap(\.appleSeenAt).max()
    }

    /// Whole days since the latest import.
    public static func ageInDays(_ entries: [Entry], now: Date = Date()) -> Int? {
        guard let last = lastImport(entries) else { return nil }
        return Calendar.current.dateComponents([.day], from: last, to: now).day
    }

    // MARK: The plaintext file

    /// Overwrites the export with zeros, deletes it and checks it is gone. Throws if it is still there.
    /// On an SSD the overwrite is best effort; FileVault keeps the old blocks encrypted.
    public static func destroyExport(at url: URL) throws {
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 0,
           let h = try? FileHandle(forWritingTo: url) {
            try? h.write(contentsOf: Data(count: size))
            try? h.synchronize()
            try? h.close()
        }
        try? fm.removeItem(at: url)
        if fm.fileExists(atPath: url.path) {
            throw VaultError.importFailed("The export file could not be deleted. Delete \(url.lastPathComponent) yourself now, and empty the Bin.")
        }
    }

    /// True for folders that sync to the cloud, where a plaintext export must never sit.
    public static func isSyncedFolder(_ url: URL) -> Bool {
        let p = url.path
        return ["/Library/Mobile Documents/", "/Library/CloudStorage/", "/OneDrive", "/Dropbox", "/Google Drive"]
            .contains { p.contains($0) }
    }
}
