import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LocalAuthentication
import VaultCore

/// Restore from an encrypted backup, step by step, over the main window.
/// 1 choose a file, 2 enter the secret that was current when the backup was made, 3 check it,
/// 4 restore. The current vault is kept beside the restored one, never deleted.
struct RestoreView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var url: URL?
    @State private var secret = ""
    @State private var method: Method = .password

    enum Method: Hashable { case password, recoveryCode, touchID }
    private var useRecoveryCode: Bool { method == .recoveryCode }
    @State private var opened: OpenedBackup?
    @State private var problem: String?
    @State private var checking = false
    @State private var confirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Restore from Backup").font(.title2.bold())
            Text("Replaces the whole vault with the backup. Your current vault is kept beside it, not deleted. To get back one item, use the Deleted list instead.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            step(1, "Choose the backup") {
                HStack {
                    Button("Choose Backup File…", action: chooseFile)
                    Text(url?.lastPathComponent ?? "No file chosen")
                        .foregroundStyle(url == nil ? .secondary : .primary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }

            step(2, "Open the backup with") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: $method) {
                        Text("Vault password").tag(Method.password)
                        Text("Recovery code").tag(Method.recoveryCode)
                        if model.touchIDEnabled && model.touchIDAvailable {
                            Text(model.biometricName).tag(Method.touchID)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 420)
                    Text(methodHelp)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if method != .touchID {
                    SecretField(placeholder: useRecoveryCode ? "Recovery code" : "Vault password",
                                text: $secret, monospaced: useRecoveryCode, onSubmit: check)
                    if useRecoveryCode && !secret.isEmpty {
                        let n = RecoveryCode.characterCount(secret)
                        Text(n == RecoveryCode.length
                             ? "55 characters."
                             : "\(n) of \(RecoveryCode.length) characters. A recovery code is the long code the app gave you at setup, not your vault password.")
                            .font(.caption)
                            .foregroundStyle(n == RecoveryCode.length ? Color.secondary : Color.orange)
                    }
                    }
                }
            }
            .disabled(url == nil)

            step(3, "Check it") {
                HStack {
                    Button("Check Backup", action: check)
                        .disabled(url == nil || (method != .touchID && secret.isEmpty) || checking)
                    if checking { ProgressView().controlSize(.small) }
                }
            }

            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let p = opened?.preview {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Backup from \(p.createdAt.formatted(date: .abbreviated, time: .shortened)) is intact.",
                          systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green).bold()
                    ForEach(RecordType.allCases) { t in
                        if let n = p.countsByType[t] { Text("\(t.pluralName): \(n)") }
                    }
                    if p.deletedCount > 0 { Text("In Deleted: \(p.deletedCount)") }
                    if !p.sampleTitles.isEmpty {
                        Text("Examples: " + p.sampleTitles.joined(separator: ", ")).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Restore This Backup…") { confirm = true }
                    .keyboardShortcut(.defaultAction)
                    .disabled(opened == nil)
            }
        }
        .padding(24)
        .frame(width: 580, height: 600)
        .onChange(of: secret) { opened = nil; problem = nil }
        .onChange(of: method) {
            opened = nil; problem = nil; secret = ""
            if method == .touchID && url != nil { check() }   // no extra click needed
        }
        .onAppear {
            if model.touchIDEnabled && model.touchIDAvailable { method = .touchID }
        }
        .confirmationDialog("Replace the current vault with this backup?", isPresented: $confirm) {
            Button("Restore", role: .destructive) {
                guard let o = opened else { return }
                opened = nil
                secret = ""
                dismiss()
                dismissWindow(id: "settings")   // nothing left open behind the lock screen
                model.restore(o)
            }
        } message: {
            Text("The current vault is kept beside it as a dated file. The app then locks: unlock with Touch ID or the vault password.")
        }
    }

    private func step<Content: View>(_ n: Int, _ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(n). \(title)").font(.headline)
            content()
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = model.backupFolder
        if let type = UTType(filenameExtension: BackupArchive.fileExtension) {
            panel.allowedContentTypes = [type]
        }
        panel.prompt = "Choose"
        panel.message = "Choose a devPassword backup (.dpbackup)"
        if panel.runModal() == .OK, let picked = panel.url {
            url = picked
            opened = nil
            problem = nil
            if method == .touchID { check() }   // straight to the fingerprint prompt
        }
    }

    private var methodHelp: String {
        switch method {
        case .password: return "The vault password you unlock the app with."
        case .recoveryCode: return "The 55-character code shown once when the vault was created or the code was last replaced. Your spare key if the vault password is forgotten."
        case .touchID: return "Only for a backup of this vault. Your fingerprint confirms the restore, and the app opens the backup with the key it already holds."
        }
    }

    private func checkWithTouchID(_ url: URL) {
        guard let vault = model.vault else { return }
        problem = nil
        opened = nil
        checking = true
        Task {
            defer { checking = false }
            do {
                let context = LAContext()
                context.localizedCancelTitle = "Cancel"
                _ = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                                     localizedReason: "restore your vault from a backup")
                let archive = try Backup.read(from: url)
                opened = try Backup.open(archive, withUnlockedVault: vault)
            } catch let e as LAError where e.code == .userCancel || e.code == .appCancel || e.code == .systemCancel {
                // Cancelled: nothing to report.
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    private func check() {
        if method == .touchID, let url { checkWithTouchID(url); return }
        guard let url, !secret.isEmpty else { return }
        problem = nil
        opened = nil
        checking = true
        let s = secret, code = useRecoveryCode
        Task {
            defer { checking = false }
            do {
                let result = try await Task.detached { () throws -> OpenedBackup in
                    let archive = try Backup.read(from: url)
                    return code ? try Backup.open(archive, recoveryCode: s) : try Backup.open(archive, passphrase: s)
                }.value
                opened = result
            } catch VaultError.wrongSecret {
                problem = useRecoveryCode
                    ? "That recovery code does not open this backup. It needs the code that was current when the backup was made."
                    : "That vault password does not open this backup. It needs the vault password that was current when the backup was made."
            } catch {
                problem = error.localizedDescription
            }
        }
    }
}
