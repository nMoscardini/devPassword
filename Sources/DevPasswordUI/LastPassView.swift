import SwiftUI
import AppKit
import UniformTypeIdentifiers
import VaultCore

/// Vault > Move from LastPass… (decision 0007 migration). LastPass logins go to Apple Passwords
/// through a one-off file; LastPass notes become devPassword records.
struct LastPassView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var choosing = false
    @State private var plan: LastPassPlan?
    @State private var includeDiffering = false
    @State private var appleFile: URL?
    @State private var savedRecords = 0
    @State private var fileNote: String?
    @State private var problem: String?
    @State private var finished = false
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Move from LastPass").font(.title2.bold())
            if finished {
                finishedView
            } else if let appleFile {
                appleStep(appleFile)
            } else if let plan {
                summary(plan)
            } else {
                steps
            }
            if let fileNote {
                Label(fileNote, systemImage: "trash").font(.callout).foregroundStyle(.secondary)
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            Spacer(minLength: 0)
            buttons
        }
        .padding(24)
        .frame(width: 600, height: 560)
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            switch result {
            case .success(let url): read(url)
            case .failure(let e): problem = e.localizedDescription
            }
        }
        // The plaintext file for Apple never outlives this window.
        .onDisappear { deleteAppleFile() }
    }

    @ViewBuilder private var buttons: some View {
        HStack {
            Spacer()
            if finished {
                Button("Import from Apple Passwords…") {
                    dismiss()
                    model.showAppleImport = true
                }
                Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
            } else if appleFile != nil {
                Button("Show in Finder") { if let f = appleFile { NSWorkspace.shared.activateFileViewerSelecting([f]) } }
                Button("I Have Imported It - Delete the File") { confirmDelete = true }
                    .keyboardShortcut(.defaultAction)
                    .confirmationDialog("Has Passwords imported the file?", isPresented: $confirmDelete) {
                        Button("Yes, Delete the File") {
                            deleteAppleFile()
                            finished = true
                        }
                        Button("Not Yet", role: .cancel) {}
                    } message: {
                        Text("In Passwords: File > Import Passwords, then choose the file. Once it is deleted, the only way back is a new LastPass export.")
                    }
            } else if let plan {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(nextLabel(plan)) { go(plan) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(toApple(plan).isEmpty && plan.newRecords.isEmpty)
            } else {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Choose LastPass Export…") { choosing = true }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Logins go to Apple Passwords, not into devPassword (decision 0007). LastPass secure notes, and logins with no website, become devPassword records.")
            Text("1. In LastPass: Advanced Options > Export > LastPass CSV File.")
            Text("2. Save it in Downloads. Not a synced folder, not the project folder.")
            Text("3. Choose it here. devPassword reads it and deletes it at once.")
            Text("Import from Apple Passwords first, so devPassword can skip logins Apple already has.")
                .foregroundStyle(model.hasAppleLogins ? Color.secondary : Color.orange)
        }
    }

    private func summary(_ p: LastPassPlan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(p.total) items in the LastPass export.").bold()
                line("New to Apple Passwords: go in the file for Apple", p.toApple.count, "arrow.right.circle")
                line("Already in Apple with the same password: skipped", p.alreadyInApple, "checkmark")
                line("Same login twice in LastPass: counted once", p.duplicatesInFile, "doc.on.doc")
                line("Notes and website-less logins: new devPassword records", p.newRecords.count, "note.text")
                line("Already in devPassword: skipped", p.alreadyInDevPassword, "checkmark")
                if p.skipped > 0 { line("Empty rows: skipped", p.skipped, "questionmark") }
                if !p.passwordDiffers.isEmpty {
                    Divider()
                    Text("In Apple with a different password (\(p.passwordDiffers.count)). Apple's is usually newer.")
                        .foregroundStyle(.orange)
                    ForEach(p.passwordDiffers) { m in
                        Text("· \(m.entry.title)  (\(m.item.username))").font(.callout)
                    }
                    Toggle("Send LastPass's password for these too. Passwords will ask which to keep.", isOn: $includeDiffering)
                }
                if !p.devPasswordMastered.isEmpty {
                    Divider()
                    Text("devPassword is the master for these, so they stay out of Apple (\(p.devPasswordMastered.count)). Check the password in devPassword is current:")
                        .foregroundStyle(.secondary)
                    ForEach(p.devPasswordMastered) { m in
                        Text("· \(m.entry.title)  (\(m.item.username))").font(.callout)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func appleStep(_ file: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if savedRecords > 0 {
                Label("\(savedRecords) notes and logins saved in devPassword, tagged #lastpass.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Text("Now put the logins into Apple Passwords:").bold()
            Text("1. In Passwords, choose File > Import Passwords.")
            Text("2. Choose this file:")
            Text(file.path).font(.callout.monospaced()).textSelection(.enabled)
            Text("3. Check the count Passwords reports. Only then come back and click the button below.")
            Label("The file holds passwords in plain text. devPassword deletes it when you click below or close this window.",
                  systemImage: "exclamationmark.shield")
                .foregroundStyle(.orange)
        }
    }

    private var finishedView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Done. The file for Apple has been deleted.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            Text("Next: export from Passwords and import into devPassword again, so the LastPass logins arrive as read-only Apple logins.")
            Text("Keep LastPass for a few weeks before you close the account.").foregroundStyle(.secondary)
        }
    }

    private func line(_ label: String, _ n: Int, _ symbol: String) -> some View {
        HStack {
            Label(label, systemImage: symbol)
            Spacer()
            Text("\(n)").monospacedDigit()
        }
        .foregroundStyle(n == 0 ? Color.secondary : Color.primary)
    }

    private func toApple(_ p: LastPassPlan) -> [LastPassItem] {
        p.toApple + (includeDiffering ? p.passwordDiffers.map(\.item) : [])
    }

    private func nextLabel(_ p: LastPassPlan) -> String {
        toApple(p).isEmpty ? "Save Records" : "Save Records and Make File for Apple"
    }

    private func read(_ url: URL) {
        problem = nil
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let synced = AppleImport.isSyncedFolder(url)
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            problem = "Could not read the file: \(error.localizedDescription)"
            return
        }
        do {
            try AppleImport.destroyExport(at: url)
            fileNote = "\(url.lastPathComponent) has been deleted." + (synced
                ? " It was in a folder that syncs to the cloud: check that service's deleted files too."
                : " Check the Bin is empty.")
        } catch {
            problem = error.localizedDescription
        }
        do {
            plan = LastPassMigration.plan(try LastPassMigration.parse(text), existing: model.entries)
        } catch {
            problem = (problem.map { $0 + "\n" } ?? "") + error.localizedDescription
        }
    }

    @State private var recordsSaved = false

    private func go(_ p: LastPassPlan) {
        if !recordsSaved {
            guard let n = model.saveLastPassRecords(p) else { return }
            savedRecords = n
            recordsSaved = true
        }
        let items = toApple(p)
        guard !items.isEmpty else { finished = true; return }
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        do {
            let url = try LastPassMigration.writeForApple(LastPassMigration.appleCSV(items), in: folder)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw VaultError.importFailed("The file was not created in \(folder.path).")
            }
            model.pendingAppleFile = url
            appleFile = url
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }

    private func deleteAppleFile() {
        guard let f = appleFile ?? model.pendingAppleFile else { return }
        do {
            try AppleImport.destroyExport(at: f)
            model.pendingAppleFile = nil
            fileNote = "\(f.lastPathComponent) has been deleted."
        } catch {
            problem = error.localizedDescription
        }
    }
}
