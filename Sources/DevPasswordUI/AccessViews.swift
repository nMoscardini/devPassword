import SwiftUI
import VaultCore

/// Two passphrase fields with the policy check. Shared by setup, recovery and change.
struct NewPassphraseFields: View {
    @Binding var first: String
    @Binding var second: String

    static func problem(_ a: String, _ b: String) -> String? {
        if let p = PassphrasePolicy.problem(a) { return p }
        if a != b { return "The two passwords do not match." }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField("New vault password", text: $first)
            SecureField("Repeat vault password", text: $second)
            if !first.isEmpty, let p = NewPassphraseFields.problem(first, second) {
                Text(p).font(.callout).foregroundStyle(.orange)
            }
        }
        .textFieldStyle(.roundedBorder)
    }
}

struct SetupView: View {
    @EnvironmentObject var model: AppModel
    @State private var p1 = ""
    @State private var p2 = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Create your vault", systemImage: "lock.shield").font(.largeTitle.bold())
            Text("Choose a vault password. It encrypts everything in the vault. Nobody can reset it, so pick one you will remember. Four or more random words works well.")
                .foregroundStyle(.secondary)
            Text("Next you will get a recovery code. It is the only other way in.")
                .foregroundStyle(.secondary)
            NewPassphraseFields(first: $p1, second: $p2)
            HStack {
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button("Create Vault") {
                    let p = p1
                    Task { await model.createVault(passphrase: p) }
                    p1 = ""; p2 = ""
                }
                .keyboardShortcut(.defaultAction)
                .disabled(NewPassphraseFields.problem(p1, p2) != nil || model.busy)
            }
        }
        .padding(40)
        .frame(maxWidth: 560)
    }
}

/// Shows a recovery code and makes the user type it back before continuing.
struct RecoveryCodeView: View {
    let code: String
    let onDone: () -> Void
    var onCancel: (() -> Void)? = nil
    @State private var writtenDown = false
    @State private var typed = ""

    private var matches: Bool {
        guard let a = try? RecoveryCode.parse(typed), let b = try? RecoveryCode.parse(code) else { return false }
        return a == b
    }

    /// The code split into rows of four groups, so it never wraps mid-group.
    private var rows: [String] {
        let groups = code.split(separator: "-").map(String.init)
        return stride(from: 0, to: groups.count, by: 4).map { groups[$0..<min($0 + 4, groups.count)].joined(separator: "  ") }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Your recovery code", systemImage: "key.viewfinder").font(.largeTitle.bold())
                Text("Write this down on paper and keep it somewhere safe, away from this Mac and away from your backups. With your vault password forgotten, this code is the only way back in. It is shown once.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { pair in
                        Text(pair.element).font(.system(.title2, design: .monospaced))
                    }
                }
                .textSelection(.disabled)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                Toggle("I have written it down", isOn: $writtenDown)
                if writtenDown {
                    Text("Type it back to confirm. Spaces, hyphens and case do not matter.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    TextField("Recovery code", text: $typed)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    CodeProgress(typed: typed, ok: matches)
                }
                HStack {
                    if let onCancel {
                        Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                    }
                    Spacer()
                    Button("Continue", action: onDone)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!(writtenDown && matches))
                }
            }
            .padding(40)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 640, minHeight: 640)
    }
}

/// Live feedback while typing a recovery code: count, then whether it checks out.
struct CodeProgress: View {
    let typed: String
    let ok: Bool

    var body: some View {
        let n = RecoveryCode.characterCount(typed)
        Group {
            if n == 0 {
                Text("\(RecoveryCode.length) characters. Spaces and hyphens are ignored.")
            } else if n < RecoveryCode.length {
                Text("\(n) of \(RecoveryCode.length) characters")
            } else if n > RecoveryCode.length {
                Text("\(n) characters. That is \(n - RecoveryCode.length) too many.").foregroundStyle(.orange)
            } else if ok {
                Label("Code checks out", systemImage: "checkmark.circle").foregroundStyle(.green)
            } else {
                Text("55 characters, but there is a typing mistake. Check each group.").foregroundStyle(.orange)
            }
        }
        .font(.callout.monospacedDigit())
        .foregroundStyle(.secondary)
    }
}

struct UnlockView: View {
    @EnvironmentObject var model: AppModel
    @State private var secret = ""
    @State private var useRecovery = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("devPassword is locked").font(.title.bold())
            if let notice = model.lockNotice {
                Label(notice, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            SecretField(placeholder: useRecovery ? "Recovery code" : "Vault password",
                        text: $secret, monospaced: useRecovery, onSubmit: unlock)
                .frame(width: 380)
            if useRecovery {
                CodeProgress(typed: secret, ok: (try? RecoveryCode.parse(secret)) != nil)
                    .frame(width: 380, alignment: .leading)
            }
            if model.touchIDEnabled && model.touchIDAvailable && !useRecovery {
                Button {
                    Task { await model.unlockWithTouchID() }
                } label: {
                    Label("Unlock with \(model.biometricName)", systemImage: "touchid")
                        .frame(width: 360)
                }
                .controlSize(.large)
                .disabled(model.busy)
            }
            HStack {
                Button(useRecovery ? "Use vault password" : "Forgot vault password? Use recovery code") {
                    useRecovery.toggle()
                    secret = ""
                }
                .buttonStyle(.link)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button("Unlock", action: unlock)
                    .keyboardShortcut(.defaultAction)
                    .disabled(secret.isEmpty || model.busy || model.vault == nil)
            }
            .frame(width: 380)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paneBackground(.lockScreen)
        .onAppear {
            // App launch or idle lock: prompt at once. Not straight after Command-L.
            if !model.lockedManually { model.autoPromptTouchID() }
        }
    }

    private func unlock() {
        let s = secret
        secret = ""
        Task {
            if useRecovery { await model.unlock(recoveryCode: s) } else { await model.unlock(passphrase: s) }
        }
    }
}

struct NewPassphraseView: View {
    @EnvironmentObject var model: AppModel
    @State private var p1 = ""
    @State private var p2 = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set a new vault password").font(.largeTitle.bold())
            Text("You opened the vault with your recovery code. Choose a new vault password. Your recovery code keeps working.")
                .foregroundStyle(.secondary)
            NewPassphraseFields(first: $p1, second: $p2)
            HStack {
                Button("Lock") { model.lockManually() }
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button("Set Vault Password") {
                    let p = p1
                    Task { await model.setNewPassphrase(p) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(NewPassphraseFields.problem(p1, p2) != nil || model.busy)
            }
        }
        .padding(40)
        .frame(maxWidth: 560)
    }
}

/// A secret entry box: hidden by default, with an eye button to show it while typing.
/// Used for passphrases and recovery codes, so neither appears on screen by accident.
struct SecretField: View {
    let placeholder: String
    @Binding var text: String
    var monospaced = false
    var onSubmit: () -> Void = {}
    @State private var shown = false

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if shown {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .font(monospaced ? .body.monospaced() : .body)
            .textFieldStyle(.roundedBorder)
            .onSubmit(onSubmit)
            Button { shown.toggle() } label: {
                Image(systemName: shown ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .help(shown ? "Hide" : "Show while typing")
        }
        .onDisappear { shown = false }
    }
}
