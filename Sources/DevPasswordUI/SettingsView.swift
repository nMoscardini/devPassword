import SwiftUI
import AppKit
import UniformTypeIdentifiers
import VaultCore

enum SettingsTab: String, CaseIterable, Identifiable {
    case security, backup, groups, export, activity, appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .security: return "Security"
        case .backup: return "Backup"
        case .groups: return "Groups"
        case .export: return "Export"
        case .activity: return "Activity"
        case .appearance: return "Appearance"
        }
    }

    var symbol: String {
        switch self {
        case .security: return "lock"
        case .backup: return "externaldrive"
        case .groups: return "folder"
        case .export: return "square.and.arrow.up"
        case .activity: return "list.bullet.rectangle"
        case .appearance: return "paintpalette"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    private var tab: SettingsTab { model.settingsTab }

    var body: some View {
        Group {
            if model.isUnlocked {
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        ForEach(SettingsTab.allCases) { t in
                            Button { model.settingsTab = t } label: {
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
                        case .groups: GroupsSettings()
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
                    Text("The vault key is kept in this Mac's Keychain, released only by a fingerprint enrolled today. It never syncs to iCloud. Adding or removing a fingerprint switches it off until you next unlock with your password.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("No Touch ID found. Connect a Magic Keyboard with Touch ID and enrol a finger in System Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Change vault password") {
                SecureField("Current vault password", text: $current)
                NewPassphraseFields(first: $p1, second: $p2)
                Button("Change Vault Password") {
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
                Button("Print Emergency Sheet…") { EmergencySheet.print(model: model) }
                Text("A one-page guide to getting back in, with boxes to write the recovery code by hand. It contains no passwords.")
                    .font(.caption).foregroundStyle(.secondary)
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
    @Environment(\.openWindow) private var openWindow

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
                Text("Keeps the newest four. Backups open with your vault password or recovery code. They do not replace an off-site copy: make sure this folder is itself backed up elsewhere.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Restore") {
                Text("Replaces the whole vault with a backup. To get back one item you deleted, use the Deleted list in the sidebar instead.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Restore from Backup…") {
                    openWindow(id: "main")
                    model.showRestore = true
                }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        if panel.runModal() == .OK, let url = panel.url { model.backupFolder = url }
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
                SecureField("Enter your vault password to confirm", text: $passphrase)
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

/// A group being added (groupID nil) or edited.
struct GroupDraft: Identifiable {
    let id = UUID()
    var groupID: UUID?
    var name: String
    /// Nil means the default folder icon.
    var icon: String?

    init() { groupID = nil; name = ""; icon = nil }
    init(_ g: EntryGroup) {
        groupID = g.id
        name = g.name
        icon = g.icon == EntryGroup.defaultIcon ? nil : g.icon
    }
}

struct GroupsSettings: View {
    @EnvironmentObject var model: AppModel
    @State private var editing: GroupDraft?
    @State private var deleting: EntryGroup?

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(model.groups) { g in
                    HStack(spacing: 10) {
                        ItemIcon(g.icon).foregroundStyle(.secondary).frame(width: 22)
                        Text(g.name)
                        Spacer()
                        Text("\(model.count(.group(g.id)))").monospacedDigit().foregroundStyle(.secondary)
                        Button { editing = GroupDraft(g) } label: { Image(systemName: "pencil") }
                            .help("Rename or change the icon")
                        Button { deleting = g } label: { Image(systemName: "trash") }
                            .help("Delete this group. Its items are kept.")
                    }
                    .buttonStyle(.borderless)
                    .padding(.vertical, 2)
                }
                .onMove { model.moveGroups(from: $0, to: $1) }
            }
            .overlay {
                if model.groups.isEmpty {
                    ContentUnavailableView("No groups yet", systemImage: EntryGroup.defaultIcon,
                                           description: Text("Add a group here. Then put items in it from the Group menu next to the star, or in the item's editor."))
                }
            }
            Divider()
            HStack {
                Button { editing = GroupDraft() } label: { Label("Add Group", systemImage: "plus") }
                Spacer()
                Text("Drag to change the sidebar order. An item can be in one group.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
        }
        .sheet(item: $editing) { d in GroupEditor(draft: d) }
        .confirmationDialog("Delete the group \"\(deleting?.name ?? "")\"?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            presenting: deleting) { g in
            Button("Delete Group", role: .destructive) { model.deleteGroup(g) }
        } message: { g in
            let n = model.count(.group(g.id))
            Text(n == 0 ? "No items are in this group."
                 : "\(n) item\(n == 1 ? " is" : "s are") in this group. They are kept, but will no longer be in any group. A local snapshot is taken first.")
        }
    }
}

struct GroupEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: GroupDraft

    init(draft: GroupDraft) {
        _draft = State(initialValue: draft)
    }

    private var problem: String? {
        EntryGroup.nameProblem(draft.name, in: model.groups, except: draft.groupID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.groupID == nil ? "New Group" : "Edit Group").font(.headline)
            TextField("Name", text: $draft.name)
            if let p = problem, !draft.name.isEmpty {
                Text(p).font(.caption).foregroundStyle(.orange)
            }
            Text("Icon").foregroundStyle(.secondary)
            IconPicker(selection: $draft.icon, typeSymbol: EntryGroup.defaultIcon, resetTitle: "Use Folder Icon")
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(draft.groupID == nil ? "Add" : "Save") {
                    if model.saveGroup(draft) { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(problem != nil)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
