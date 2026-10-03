import SwiftUI
import AppKit
import UniformTypeIdentifiers
import VaultCore

enum SettingsTab: String, CaseIterable, Identifiable {
    case security, backup, export, activity, appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .security: return "Security"
        case .backup: return "Backup"
        case .export: return "Export"
        case .activity: return "Activity"
        case .appearance: return "Appearance"
        }
    }

    var symbol: String {
        switch self {
        case .security: return "lock"
        case .backup: return "externaldrive"
        case .export: return "square.and.arrow.up"
        case .activity: return "list.bullet.rectangle"
        case .appearance: return "paintpalette"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab: SettingsTab = .security

    var body: some View {
        Group {
            if model.isUnlocked {
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        ForEach(SettingsTab.allCases) { t in
                            Button { tab = t } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: t.symbol)
                                        .font(.system(size: 20))
                                        .frame(height: 24)
                                    Text(t.title).font(.caption)
                                }
                                .frame(width: 88, height: 56)
                                .background(tab == t ? Color.secondary.opacity(0.16) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(tab == t ? Color.accentColor : Color.primary)
                            .help(t.title)
                        }
                    }
                    .padding(.vertical, 10)
                    Divider()
                    Group {
                        switch tab {
                        case .security: SecuritySettings()
                        case .backup: BackupSettings()
                        case .export: ExportSettings()
                        case .activity: ActivitySettings()
                        case .appearance: AppearanceSettings()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .navigationTitle(tab.title)
            } else {
                ContentUnavailableView("Unlock the vault to change settings", systemImage: "lock")
            }
        }
        .frame(minWidth: 600, maxWidth: .infinity, minHeight: 480, maxHeight: .infinity)
    }
}

struct SecuritySettings: View {
    @EnvironmentObject var model: AppModel
    @State private var current = ""
    @State private var p1 = ""
    @State private var p2 = ""
    @State private var pending: PendingRecoveryCode?
    @State private var confirmReplace = false

    var body: some View {
        Form {
            Picker("Lock after inactivity", selection: Binding(get: { model.autoLockMinutes }, set: { model.autoLockMinutes = $0 })) {
                ForEach([1, 2, 5, 10, 15], id: \.self) { Text("\($0) minute\($0 == 1 ? "" : "s")").tag($0) }
            }
            Text("The vault also locks on sleep, screen lock and Command-L.").font(.caption).foregroundStyle(.secondary)

            Section("\(model.biometricName)") {
                if model.touchIDAvailable {
                    Toggle("Unlock with \(model.biometricName)",
                           isOn: Binding(get: { model.touchIDEnabled }, set: { model.setTouchID($0) }))
                    Text("The vault key is kept in this Mac's Keychain, released only by a fingerprint enrolled today. It never syncs to iCloud. Adding or removing a fingerprint switches it off until you next unlock with your passphrase.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("No Touch ID found. Connect a Magic Keyboard with Touch ID and enrol a finger in System Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Change master passphrase") {
                SecureField("Current passphrase", text: $current)
                NewPassphraseFields(first: $p1, second: $p2)
                Button("Change Passphrase") {
                    let c = current, n = p1
                    Task {
                        if await model.changePassphrase(current: c, new: n) { current = ""; p1 = ""; p2 = "" }
                    }
                }
                .disabled(current.isEmpty || NewPassphraseFields.problem(p1, p2) != nil || model.busy)
            }

            Section("Recovery code") {
                Text("Replace the code if you think someone has seen it. The new code only takes effect after you type it back. Backups made before the change still open with the old code.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Replace Recovery Code…") { confirmReplace = true }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Replace the recovery code?", isPresented: $confirmReplace) {
            Button("Show New Code") { pending = model.prepareRecoveryCode() }
        } message: {
            Text("You will see a new code. Write it down and type it back. Only then does it replace the old one. Cancel at any point and nothing changes.")
        }
        .sheet(item: $pending) { p in
            RecoveryCodeView(code: p.code,
                             onDone: { if model.commitRecoveryCode(p) { pending = nil } },
                             onCancel: { pending = nil })
                .frame(width: 680, height: 680)
        }
        .onChange(of: pending?.id) { model.showingRecoveryCode = pending != nil }
        .onDisappear { pending = nil; model.showingRecoveryCode = false }
    }
}

struct BackupSettings: View {
    @EnvironmentObject var model: AppModel
    @State private var restoreURL: URL?
    @State private var restoreSecret = ""
    @State private var restoreWithCode = false
    @State private var opened: OpenedBackup?
    @State private var pickBackup = false
    @State private var confirmRestore = false

    var body: some View {
        Form {
            Section("Encrypted backups") {
                LabeledContent("Folder") {
                    HStack {
                        Text(model.backupFolder?.path ?? "Not chosen").lineLimit(1).truncationMode(.middle)
                        Button("Choose…", action: chooseFolder)
                    }
                }
                Toggle("Back up weekly when the vault is unlocked", isOn: Binding(get: { model.weeklyBackup }, set: { model.weeklyBackup = $0 }))
                LabeledContent("Last verified backup") {
                    Text(model.lastVerifiedBackup?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                }
                Button("Back Up Now") { model.backupNow() }
                    .disabled(model.backupFolder == nil)
                Text("Keeps the newest four. Backups open with your passphrase or recovery code. They do not replace an off-site copy: make sure this folder is itself backed up elsewhere.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Restore") {
                Button("Choose Backup File…") { pickBackup = true }
                if let restoreURL {
                    Text(restoreURL.lastPathComponent).font(.caption)
                    Toggle("Open with recovery code", isOn: $restoreWithCode)
                    if restoreWithCode {
                        TextField("Recovery code", text: $restoreSecret).font(.body.monospaced())
                    } else {
                        SecureField("Passphrase at the time of the backup", text: $restoreSecret)
                    }
                    Button("Check Backup") { check(restoreURL) }
                        .disabled(restoreSecret.isEmpty)
                }
                if let p = opened?.preview {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Backup from \(p.createdAt.formatted(date: .abbreviated, time: .shortened)) is intact.").bold()
                        ForEach(RecordType.allCases) { t in
                            if let n = p.countsByType[t] { Text("\(t.pluralName): \(n)") }
                        }
                        if p.deletedCount > 0 { Text("In Deleted: \(p.deletedCount)") }
                        Text("Examples: " + p.sampleTitles.joined(separator: ", ")).foregroundStyle(.secondary)
                    }
                    Button("Restore This Backup…", role: .destructive) { confirmRestore = true }
                }
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $pickBackup, allowedContentTypes: [.data]) { result in
            restoreURL = try? result.get()
            opened = nil
            restoreSecret = ""
        }
        .confirmationDialog("Replace the current vault with this backup?", isPresented: $confirmRestore) {
            Button("Restore", role: .destructive) {
                if let o = opened {
                    opened = nil
                    restoreSecret = ""
                    model.restore(o)
                }
            }
        } message: {
            Text("The current vault is kept beside it as a dated file, not deleted. The app locks.")
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        if panel.runModal() == .OK, let url = panel.url { model.backupFolder = url }
    }

    private func check(_ url: URL) {
        do {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            opened = try model.openBackup(at: url, secret: restoreSecret, isRecoveryCode: restoreWithCode)
        } catch {
            opened = nil
            model.errorMessage = error.localizedDescription
        }
    }
}

struct ExportSettings: View {
    @EnvironmentObject var model: AppModel
    @State private var passphrase = ""

    var body: some View {
        Form {
            Section("Plaintext CSV export") {
                Text("For moving to another password manager only. The file is not encrypted. Anyone who opens it sees every password, card and document number. Keep it off cloud folders and delete it when finished. Deleting a file does not guarantee it is erased from an SSD or from backups.")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                SecureField("Enter your passphrase to confirm", text: $passphrase)
                Button("Export CSV…", action: export)
                    .disabled(passphrase.isEmpty)
            }
        }
        .formStyle(.grouped)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "devPassword-export.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if model.exportCSV(passphrase: passphrase, to: url) { passphrase = "" }
    }
}

struct ActivitySettings: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let log = model.vault?.auditLog() ?? []
        List(log) { r in
            HStack {
                Text(r.at.formatted(date: .abbreviated, time: .shortened)).monospacedDigit().foregroundStyle(.secondary)
                Text(r.action)
            }
        }
        .overlay { if log.isEmpty { Text("No sensitive actions recorded yet.").foregroundStyle(.secondary) } }
    }
}
