import SwiftUI
import AppKit
import VaultCore

enum Screen: Equatable {
    case setup
    case showRecovery(String)
    case locked
    case newPassphrase
    case unlocked
}

enum SidebarFilter: Hashable {
    case all, favourites, expiring, deleted
    case type(RecordType)
}

/// App state. Main actor only. Decrypted records live in memory while unlocked and are
/// dropped on lock.
@MainActor
final class AppModel: ObservableObject {
    @Published var screen: Screen = .locked
    @Published private(set) var entries: [Entry] = []
    @Published var filter: SidebarFilter? = .all
    @Published var search = ""
    @Published var selection: UUID?
    @Published var editing: Entry?
    @Published var showGenerator = false
    @Published var showImport = false
    @Published var errorMessage: String?
    @Published var infoMessage: String?
    @Published var integrityFailures = 0
    @Published var busy = false
    /// True while a new recovery code is on screen. Pauses the idle lock so writing it down is not interrupted.
    @Published var showingRecoveryCode = false

    private(set) var vault: Vault?
    let vaultURL: URL
    private var lastActivity = Date()
    private var idleTimer: Timer?

    static let expiringDays = 90

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("devPassword", isDirectory: true)
        vaultURL = support.appendingPathComponent("vault.sqlite")
        if Vault.exists(at: vaultURL) {
            do {
                vault = try Vault.open(at: vaultURL)
                screen = .locked
            } catch {
                errorMessage = error.localizedDescription
                screen = .locked
            }
        } else {
            screen = .setup
        }
        startLockMonitors()
    }

    var isUnlocked: Bool { screen == .unlocked }

    // MARK: Settings stored per Mac (not secret)

    var autoLockMinutes: Int {
        get { let v = UserDefaults.standard.integer(forKey: "autoLockMinutes"); return v == 0 ? 5 : v }
        set { UserDefaults.standard.set(newValue, forKey: "autoLockMinutes"); objectWillChange.send() }
    }

    var backupFolder: URL? {
        get { UserDefaults.standard.string(forKey: "backupFolder").map { URL(fileURLWithPath: $0, isDirectory: true) } }
        set { UserDefaults.standard.set(newValue?.path, forKey: "backupFolder"); objectWillChange.send() }
    }

    var weeklyBackup: Bool {
        get { UserDefaults.standard.object(forKey: "weeklyBackup") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "weeklyBackup"); objectWillChange.send() }
    }

    /// Touch ID switched on for this vault on this Mac. Not secret: the key itself is in the Keychain.
    var touchIDEnabled: Bool {
        get { guard let id = vault?.vaultID else { return false }
              return UserDefaults.standard.bool(forKey: "touchID-\(id.uuidString)") }
        set { guard let id = vault?.vaultID else { return }
              UserDefaults.standard.set(newValue, forKey: "touchID-\(id.uuidString)"); objectWillChange.send() }
    }

    var touchIDAvailable: Bool { BiometricUnlock.isAvailable }
    var biometricName: String { BiometricUnlock.name }

    var lastVerifiedBackup: Date? {
        get { UserDefaults.standard.object(forKey: "lastVerifiedBackup") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastVerifiedBackup"); objectWillChange.send() }
    }

    // MARK: Setup and unlock

    func createVault(passphrase: String) async {
        busy = true
        defer { busy = false }
        let url = vaultURL
        do {
            let result = try await Task.detached { try Vault.create(at: url, passphrase: passphrase) }.value
            vault = result.vault
            screen = .showRecovery(result.recoveryCode)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func finishSetup() {
        reload()
        screen = .unlocked
        touch()
    }

    func unlock(passphrase: String) async {
        guard let vault else { return }
        busy = true
        defer { busy = false }
        do {
            try await Task.detached { try vault.unlock(passphrase: passphrase) }.value
            didUnlock()
            rearmTouchID()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func unlock(recoveryCode: String) async {
        guard let vault else { return }
        busy = true
        defer { busy = false }
        do {
            try await Task.detached { try vault.unlock(recoveryCode: recoveryCode) }.value
            screen = .newPassphrase
        } catch VaultError.wrongSecret {
            errorMessage = "That is a well-formed recovery code, but not the current one for this vault. If you replaced the code, use the newer one."
        } catch VaultError.invalidRecoveryCode {
            errorMessage = "That code has a typing mistake: its check digits do not match. Check each group against your paper copy. O and 0, and I, L and 1, are treated as the same."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setNewPassphrase(_ p: String) async {
        guard let vault else { return }
        busy = true
        defer { busy = false }
        do {
            try await Task.detached { try vault.setPassphraseAfterRecovery(p) }.value
            didUnlock()
            rearmTouchID()
            infoMessage = "New passphrase set. Your recovery code still works."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// `automatic`: started by the app, not a button press. Errors stay quiet then; the button shows them.
    func unlockWithTouchID(automatic: Bool = false) async {
        guard let vault, touchIDEnabled, !busy else { return }
        busy = true
        defer { busy = false; touchIDPromptPending = false }
        do {
            try await Task.detached { try vault.unlockWithBiometrics(reason: "unlock your vault") }.value
            didUnlock()
        } catch VaultError.biometricCancelled {
            // User chose the passphrase instead. Nothing to report.
        } catch {
            if !automatic { errorMessage = error.localizedDescription }
        }
    }

    private var touchIDPromptPending = false

    /// Shows the Touch ID prompt without a click, when the lock screen is in front of the user.
    /// Called on app activation, Mac wake or unlock, and after an idle lock. Never after a manual lock.
    func autoPromptTouchID() {
        guard screen == .locked, touchIDEnabled, touchIDAvailable, !busy, !touchIDPromptPending,
              NSApp.isActive, vault != nil else { return }
        touchIDPromptPending = true
        Task { await unlockWithTouchID(automatic: true) }
    }

    /// Turns Touch ID on or off for this vault. Turning on needs the vault unlocked.
    func setTouchID(_ on: Bool) {
        guard let vault else { return }
        if on {
            do {
                try vault.enableBiometricUnlock()
                touchIDEnabled = true
                infoMessage = "\(biometricName) is on for this Mac. Your passphrase and recovery code still work. If you add or remove a fingerprint, unlock once with your passphrase to switch it back on."
            } catch {
                touchIDEnabled = false
                errorMessage = error.localizedDescription
            }
        } else {
            vault.disableBiometricUnlock()
            touchIDEnabled = false
        }
    }

    /// After a passphrase unlock, store the key again so Touch ID keeps working
    /// if fingerprints were added or removed (that invalidates the old Keychain item).
    private func rearmTouchID() {
        guard let vault, touchIDEnabled, touchIDAvailable else { return }
        try? vault.enableBiometricUnlock()
    }

    private func didUnlock() {
        lockedManually = false
        reload()
        screen = .unlocked
        touch()
        runWeeklyBackupIfDue()
    }

    /// True after Command-L or the Lock button, until the app is next activated.
    @Published var lockedManually = false

    /// Lock from a button or Command-L: no automatic Touch ID prompt straight after.
    func lockManually() {
        lock()
        lockedManually = true
    }

    func lock() {
        guard screen == .unlocked || screen == .newPassphrase else { return }
        vault?.lock()
        entries = []
        selection = nil
        editing = nil
        search = ""
        showGenerator = false
        showImport = false
        Clipboard.clearIfOurs()
        screen = .locked
    }

    // MARK: Records

    func reload() {
        guard let vault, vault.isUnlocked else { return }
        do {
            let r = try vault.loadAll()
            entries = r.entries
            integrityFailures = r.failedIDs.count
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var visibleEntries: [Entry] { filtered(filter ?? .all, search: search) }

    func count(_ f: SidebarFilter) -> Int { filtered(f, search: "").count }

    func filtered(_ f: SidebarFilter, search: String) -> [Entry] {
        var list = entries.filter { e in
            switch f {
            case .all: return !e.isDeleted
            case .favourites: return !e.isDeleted && e.favourite
            case .expiring: return !e.isDeleted && e.expires(within: AppModel.expiringDays)
            case .deleted: return e.isDeleted
            case .type(let t): return !e.isDeleted && e.type == t
            }
        }
        let q = search.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            list = list.filter { $0.searchableText.localizedCaseInsensitiveContains(q) }
        }
        if f == .expiring {
            return list.sorted { ($0.expiryDate ?? .distantFuture) < ($1.expiryDate ?? .distantFuture) }
        }
        return list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func beginNew(_ type: RecordType) {
        guard isUnlocked else { return }
        editing = Entry(type: type)
    }

    func save(_ entry: Entry) {
        guard let vault else { return }
        do {
            try vault.save(entry)
            reload()
            selection = entry.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleFavourite(_ entry: Entry) {
        var e = entry
        e.favourite.toggle()
        save(e)
    }

    func moveToDeleted(_ entry: Entry) {
        var e = entry
        e.deletedAt = Date()
        save(e)
        selection = nil
    }

    func restoreDeleted(_ entry: Entry) {
        var e = entry
        e.deletedAt = nil
        save(e)
    }

    func purge(_ entry: Entry) {
        guard let vault else { return }
        do {
            try vault.purge(id: entry.id)
            selection = nil
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Import

    func commitImport(_ newEntries: [Entry]) {
        guard let vault, !newEntries.isEmpty else { return }
        do {
            try vault.snapshot(reason: "import")
            try vault.saveAll(newEntries)
            vault.audit("import.committed")
            reload()
            infoMessage = "Imported \(newEntries.count) items."
        } catch {
            errorMessage = "Nothing was imported. \(error.localizedDescription)"
        }
    }

    // MARK: Secrets

    func changePassphrase(current: String, new: String) async -> Bool {
        guard let vault else { return false }
        busy = true
        defer { busy = false }
        do {
            try await Task.detached { try vault.changePassphrase(current: current, new: new) }.value
            infoMessage = "Passphrase changed. Older backups still open with the old passphrase until you make a new one."
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// New recovery code to show. Nothing changes until commitRecoveryCode.
    func prepareRecoveryCode() -> PendingRecoveryCode? {
        guard let vault, vault.isUnlocked else { return nil }
        return vault.prepareRecoveryCode()
    }

    func commitRecoveryCode(_ pending: PendingRecoveryCode) -> Bool {
        guard let vault else { return false }
        do {
            try vault.commitRecoveryCode(pending)
            infoMessage = "New recovery code is active. The old one no longer opens this vault, but still opens backups made before today."
            return true
        } catch {
            errorMessage = "The recovery code was not changed. \(error.localizedDescription)"
            return false
        }
    }

    // MARK: Backup, restore, export

    func backupNow() {
        guard let vault, vault.isUnlocked else { return }
        guard let folder = backupFolder else {
            errorMessage = "Choose a backup folder in Settings first."
            return
        }
        do {
            try Backup.writeToFolder(vault: vault, folder: folder, keep: 4)
            lastVerifiedBackup = Date()
            infoMessage = "Backup written and verified."
        } catch {
            errorMessage = "Backup failed. \(error.localizedDescription)"
        }
    }

    private func runWeeklyBackupIfDue() {
        guard weeklyBackup, backupFolder != nil else { return }
        let due = lastVerifiedBackup.map { Date().timeIntervalSince($0) > 7 * 24 * 3600 } ?? true
        if due { backupNow() }
    }

    func openBackup(at url: URL, secret: String, isRecoveryCode: Bool) throws -> OpenedBackup {
        let archive = try Backup.read(from: url)
        return isRecoveryCode ? try Backup.open(archive, recoveryCode: secret)
                              : try Backup.open(archive, passphrase: secret)
    }

    /// Replaces the working vault with a verified backup. The current vault is kept beside it.
    func restore(_ opened: OpenedBackup) {
        lock()
        vault?.close()
        vault = nil
        do {
            try Backup.restore(opened, to: vaultURL)
            vault = try Vault.open(at: vaultURL)
            screen = .locked
            infoMessage = "Restored. Unlock with the passphrase that was current when the backup was made. The previous vault was kept beside it."
        } catch {
            vault = try? Vault.open(at: vaultURL)
            screen = vault == nil ? .setup : .locked
            errorMessage = "Restore failed. \(error.localizedDescription)"
        }
    }

    func exportCSV(passphrase: String, to url: URL) -> Bool {
        guard let vault, vault.verify(passphrase: passphrase) else {
            errorMessage = "That passphrase is not correct."
            return false
        }
        do {
            let text = try CSVExport.make(entries)
            try Data(text.utf8).write(to: url, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            vault.audit("export.plaintext_csv")
            infoMessage = "Exported \(entries.filter { !$0.isDeleted }.count) items. This file is not encrypted. Delete it when you are done."
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: Auto-lock (spec section 5)

    func touch() { lastActivity = Date() }

    private func startLockMonitors() {
        _ = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated { self?.touch() }
            return event
        }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isUnlocked, !self.showingRecoveryCode else { return }
                if Date().timeIntervalSince(self.lastActivity) > Double(self.autoLockMinutes) * 60 {
                    self.lock()
                    self.autoPromptTouchID()   // waiting for a finger when Nino comes back
                }
            }
        }
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            _ = ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lock() }
            }
        }
        _ = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsLocked"),
                                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lock() }
        }
        // Prompt for a fingerprint when the user arrives at the lock screen.
        _ = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                   object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.lockedManually = false
                self?.autoPromptTouchID()
            }
        }
        _ = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"),
                                                                object: nil, queue: .main) { [weak self] _ in
            // Give the Mac a moment to finish waking before showing the prompt.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                MainActor.assumeIsolated {
                    self?.lockedManually = false
                    self?.autoPromptTouchID()
                }
            }
        }
    }
}

/// Copy rules from spec F05: this Mac only (no Universal Clipboard), marked concealed for
/// clipboard managers, cleared after 30 seconds only if still ours.
@MainActor
enum Clipboard {
    private static var ourChangeCount: Int?
    static let clearAfter: TimeInterval = 30

    static func copy(_ value: String, concealed: Bool) {
        let pb = NSPasteboard.general
        _ = pb.prepareForNewContents(with: .currentHostOnly)
        pb.setString(value, forType: .string)
        if concealed {
            pb.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
            pb.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        }
        let change = pb.changeCount
        ourChangeCount = change
        DispatchQueue.main.asyncAfter(deadline: .now() + clearAfter) {
            MainActor.assumeIsolated {
                if NSPasteboard.general.changeCount == change { NSPasteboard.general.clearContents() }
            }
        }
    }

    static func clearIfOurs() {
        if let c = ourChangeCount, NSPasteboard.general.changeCount == c {
            NSPasteboard.general.clearContents()
        }
        ourChangeCount = nil
    }
}
