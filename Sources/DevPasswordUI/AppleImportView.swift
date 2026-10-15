import SwiftUI
import UniformTypeIdentifiers
import VaultCore

/// Vault > Import from Apple Passwords… (decision 0007). Reads Apple's CSV export, deletes the
/// file at once, shows what would change, and writes only when Nino says so.
struct AppleImportView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var choosing = false
    @State private var plan: AppleImportPlan?
    @State private var fileNote: String?
    @State private var problem: String?
    @State private var done: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import from Apple Passwords").font(.title2.bold())
            if let done {
                Label(done, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
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
            HStack {
                Spacer()
                if done != nil {
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                } else if let plan {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Import") { apply(plan) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(plan.writes == 0)
                } else {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Choose Export File…") { choosing = true }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 560, height: 520)
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            switch result {
            case .success(let url): read(url)
            case .failure(let e): problem = e.localizedDescription
            }
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Logins come in read-only. Apple Passwords stays the master: change passwords there, then import again.")
            Text("1. In Passwords, choose File > Export All Passwords.")
            Text("2. Save it in Downloads. Not Desktop or Documents if they sync to iCloud, and never into OneDrive or a project folder.")
            Text("3. Choose the file here. devPassword reads it, then deletes it at once, before you decide anything.")
            if let age = model.appleSnapshotAge {
                Text("Last import: \(age == 0 ? "today" : "\(age) day\(age == 1 ? "" : "s") ago").")
                    .foregroundStyle(model.appleSnapshotStale ? Color.orange : Color.secondary)
            }
        }
    }

    private func summary(_ p: AppleImportPlan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(p.total) logins in the export.").bold()
                line("New", p.added.count, "plus")
                line("Changed in Apple", p.changed.count, "pencil")
                line("Back in Apple", p.returned.count, "arrow.uturn.backward")
                line("Unchanged", p.unchanged.count, "checkmark")
                line("No longer in Apple (kept, marked removed)", p.removed.count, "minus")
                if p.skipped > 0 { line("Skipped: no website or username", p.skipped, "questionmark") }
                if !p.alsoInDevPassword.isEmpty {
                    Divider()
                    Text("\(p.alsoInDevPassword.count) new Apple logins match an editable devPassword login (from mSecure). Both are kept until the migration, where you choose.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if !p.masterClashes.isEmpty {
                    Divider()
                    Label("devPassword is the master for these, so they were not imported. Remove them from Apple Passwords, or switch the master to Apple in Edit:",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    ForEach(p.masterClashes, id: \.key) { m in
                        Text("· \(m.entry.title)  (\(m.login.username))").font(.callout)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
            let parsed = try AppleImport.parse(text)
            plan = AppleImport.plan(parsed.logins, skipped: parsed.skipped, existing: model.entries)
        } catch {
            problem = (problem.map { $0 + "\n" } ?? "") + error.localizedDescription
        }
    }

    private func apply(_ p: AppleImportPlan) {
        if let n = model.applyAppleImport(p) {
            plan = nil
            done = "Imported. \(p.added.count) new, \(p.changed.count) changed, \(p.removed.count) marked removed. \(n) records written after a snapshot."
        }
    }
}
