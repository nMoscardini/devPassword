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
    case group(UUID)
}

/// App state. Main actor only. Decrypted records live in memory while unlocked and are
/// dropped on lock.
enum ListSortOrder: String, CaseIterable, Identifiable {
    case name, newest, oldest
    var id: String { rawValue }
    var label: String {
        switch self {
        case .name: return "Name"
        case .newest: return "Recently changed first"
        case .oldest: return "Longest unchanged first"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var screen: Screen = .locked
    @Published private(set) var entries: [Entry] = []
    /// Groups in sidebar order. Held only while unlocked, like the records.
    @Published private(set) var groups: [EntryGroup] = []
    /// Set when the stored group list fails its check. Group changes are refused so a
    /// damaged list is never overwritten.
    private var groupsUnavailable = false
    @Published var filter: SidebarFilter? = .all
    @Published var search = ""
    @Published var selection: UUID?
    @Published var editing: Entry?
    @Published var showGenerator = false
    @Published var showImport = false
    @Published var showRestore = false
    @Published var sortOrder: ListSortOrder = ListSortOrder(rawValue: UserDefaults.standard.string(forKey: "sortOrder") ?? "") ?? .name {
        didSet { UserDefaults.standard.set(sortOrder.rawValue, forKey: "sortOrder") }
    }
    /// One-line note shown on the lock screen, e.g. after a restore. Cleared on unlock.
    @Published var lockNotice: String?
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
        _ = umask(0o077)   // every file this app creates is owner-only
        AppearanceMode.apply(UserDefaults.standard.string(forKey: AppearanceMode.key) ?? "")
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
            infoMessage = "New vault password set. Your recovery code still works."
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
            // User chose to type the vault password. Do not ask again until the next lock.
            autoPromptSuppressed = true
        } catch {
            autoPromptSuppressed = true
            if !automatic { errorMessage = error.localizedDescription }
        }
    }

    private var touchIDPromptPending = false
    /// Set when the Touch ID prompt is cancelled or fails. Cleared by the next lock or unlock.
    /// Stops the prompt coming straight back when macOS returns focus to the app after Cancel.
    private var autoPromptSuppressed = false

    /// Shows the Touch ID prompt without a click, when the lock screen is in front of the user.
    /// Called on app activation, Mac wake or unlock, and after an idle lock. Never after a manual lock.
    func autoPromptTouchID() {
        guard screen == .locked, touchIDEnabled, touchIDAvailable, !busy, !touchIDPromptPending, !autoPromptSuppressed,
              NSApp.isActive, vault != nil else { return }
        touchIDPromptPending = true
        NSApp.activate(ignoringOtherApps: true)
        Task {
            // Let window changes (restore, unlock screen) finish so the prompt opens over a settled, active app.
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard screen == .locked else { touchIDPromptPending = false; return }
            await unlockWithTouchID(automatic: true)
        }
    }

    /// Turns Touch ID on or off for this vault. Turning on needs the vault unlocked.
    func setTouchID(_ on: Bool) {
        guard let vault else { return }
        if on {
            do {
                try vault.enableBiometricUnlock()
                touchIDEnabled = true
                infoMessage = "\(biometricName) is on for this Mac. Your vault password and recovery code still work. If you add or remove a fingerprint, unlock once with your vault password to switch it back on."
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
        lockNotice = nil
        lockedManually = false
        autoPromptSuppressed = false
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
        autoPromptSuppressed = false   // a new lock may prompt again
        vault?.lock()
        entries = []
        groups = []
        selection = nil
        editing = nil
        search = ""
        showGenerator = false
        showImport = false
        showRestore = false
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
        do {
            groups = try vault.loadGroups()
            groupsUnavailable = false
        } catch {
            groups = []
            groupsUnavailable = true
            errorMessage = "Your groups failed their integrity check and are hidden. Items are not affected. Restore from a backup if this persists."
        }
        if case .group(let id) = filter, !groups.contains(where: { $0.id == id }) { filter = .all }
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
            case .group(let id): return !e.isDeleted && e.groupID == id
            }
        }
        let q = search.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            list = list.filter { $0.searchableText.localizedCaseInsensitiveContains(q) }
        }
        if f == .expiring {
            return list.sorted { ($0.expiryDate ?? .distantFuture) < ($1.expiryDate ?? .distantFuture) }
        }
        switch sortOrder {
        case .name: return list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .newest: return list.sorted { $0.modified > $1.modified }
        case .oldest: return list.sorted { $0.modified < $1.modified }
        }
    }

    func beginNew(_ type: RecordType) {
        guard isUnlocked else { return }
        editing = Entry(type: type)
    }

    func save(_ entry: Entry, touchModified: Bool = true) {
        guard let vault else { return }
        do {
            try vault.save(entry, touchModified: touchModified)
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

    // MARK: Groups

    /// The item's group, or nil if none (or its group was deleted).
    func group(for entry: Entry) -> EntryGroup? {
        guard let id = entry.groupID else { return nil }
        return groups.first { $0.id == id }
    }

    /// Files an item in a group, or takes it out with nil. Keeps its changed date.
    func setGroup(_ entry: Entry, to id: UUID?) {
        guard entry.groupID != id else { return }
        var e = entry
        e.groupID = id
        save(e, touchModified: false)
    }

    /// Adds a new group or renames an existing one. Returns false and shows why on failure.
    func saveGroup(_ d: GroupDraft) -> Bool {
        var list = groups
        let name = d.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let icon = d.icon ?? EntryGroup.defaultIcon
        if let id = d.groupID, let i = list.firstIndex(where: { $0.id == id }) {
            list[i].name = name
            list[i].icon = icon
        } else {
            list.append(EntryGroup(name: name, icon: icon))
        }
        return storeGroups(list, audit: d.groupID == nil ? "group.created" : "group.changed")
    }

    func moveGroups(from source: IndexSet, to destination: Int) {
        var list = groups
        list.move(fromOffsets: source, toOffset: destination)
        _ = storeGroups(list, audit: nil)
    }

    /// Deletes a group after the user has confirmed. Its items stay, with no group.
    func deleteGroup(_ g: EntryGroup) {
        guard let vault, !groupsUnavailable else { return }
        do {
            let n = try vault.deleteGroup(id: g.id)
            reload()
            infoMessage = n == 0 ? "Group deleted." : "Group deleted. \(n) item\(n == 1 ? " is" : "s are") no longer in a group."
        } catch {
            errorMessage = "The group was not deleted. \(error.localizedDescription)"
            reload()
        }
    }

    private func storeGroups(_ list: [EntryGroup], audit action: String?) -> Bool {
        guard let vault else { return false }
        guard !groupsUnavailable else {
            errorMessage = "Groups cannot be changed while the stored list is damaged. Restore from a backup."
            return false
        }
        do {
            try vault.saveGroups(list)
            groups = list
            if let action { vault.audit(action) }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func moveToDeleted(_ entry: Entry) {
        var e = entry
        e.deletedAt = Date()
        save(e)
        vault?.audit("entry.moved_to_deleted")
        selection = nil
    }

    /// Puts one item back from the Deleted list. Not the same as restoring a backup.
    func restoreDeleted(_ entry: Entry) {
        var e = entry
        e.deletedAt = nil
        save(e)
        vault?.audit("entry.put_back_from_deleted")
    }

    /// Which Settings tab to show. Lets the Vault menu open Settings straight at Backup.
    @Published var settingsTab: SettingsTab = .security

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
            infoMessage = "Vault password changed. Local snapshots made with the old vault password were removed. Encrypted backups made before today still open with the OLD vault password: make a new backup now, and delete older ones if you think the old vault password is known to anyone."
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
            infoMessage = "New recovery code is active. Local snapshots made with the old code were removed. Encrypted backups made before today still open with the OLD code: make a new backup now, and delete older ones if the old code may have been seen."
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
            // No alert: it would sit on top of the Touch ID prompt. A quiet line on the lock screen instead.
            lockNotice = "Restored from the backup. Your previous vault is kept beside it."
        } catch {
            vault = try? Vault.open(at: vaultURL)
            screen = vault == nil ? .setup : .locked
            errorMessage = "Restore failed. \(error.localizedDescription)"
        }
    }

    func exportCSV(passphrase: String, to url: URL) -> Bool {
        guard let vault else { return false }
        do {
            let result = try vault.exportPlaintextCSV(passphrase: passphrase)
            try Data(result.csv.utf8).write(to: url, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            infoMessage = "Exported \(result.count) items. This file is not encrypted. Delete it when you are done."
            return true
        } catch VaultError.wrongSecret {
            errorMessage = "That vault password is not correct."
            return false
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
