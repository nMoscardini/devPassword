import SwiftUI
import UniformTypeIdentifiers
import VaultCore

/// Spec F06 and section 3: map, preview, then commit all approved rows together or nothing.
struct ImportView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var fileName = ""
    @State private var headers: [String] = []
    @State private var rows: [[String]] = []
    @State private var mapping = ImportMapping(defaultType: .login, targets: [])
    @State private var preview: ImportPreview?
    @State private var picking = false
    @State private var problem: String?
    @State private var isMSecure = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import CSV").font(.title2.bold())
            Text("Use a UTF-8 CSV exported from your current password manager. Nothing is saved until you press Import. The CSV file is not encrypted: delete it when you are done, and keep it out of cloud folders.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Choose File…") { picking = true }
                Text(fileName).foregroundStyle(.secondary).lineLimit(1)
            }
            if let problem { Text(problem).foregroundStyle(.orange) }

            if !headers.isEmpty {
                Picker("Record type when the file has no type column", selection: $mapping.defaultType) {
                    ForEach(RecordType.allCases) { Text($0.displayName).tag($0) }
                }
                .frame(maxWidth: 460)
                .onChange(of: mapping.defaultType) {
                    mapping = Importer.guess(headers: headers, defaultType: mapping.defaultType)
                }

                Text("Columns").font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(headers.indices, id: \.self) { i in
                            HStack {
                                Text(headers[i].isEmpty ? "(no name)" : headers[i])
                                    .frame(width: 220, alignment: .leading)
                                    .lineLimit(1)
                                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                                Picker("", selection: $mapping.targets[i]) {
                                    ForEach(ImportTarget.all) { t in Text(t.label).tag(t) }
                                }
                                .labelsHidden()
                            }
                        }
                    }
                }
                .frame(height: 170)
            }
            if isMSecure {
                Label("mSecure export recognised. Each mSecure type is mapped automatically; fields without a standard place become custom fields. The mSecure group becomes a tag.",
                      systemImage: "checkmark.seal")
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let p = preview {
                    HStack(spacing: 16) {
                        Text("New \(p.count(.new))")
                        Text("Conflicts \(p.count(.conflict))").foregroundStyle(p.count(.conflict) > 0 ? Color.orange : Color.primary)
                        Text("Duplicates \(p.count(.duplicate))").foregroundStyle(.secondary)
                        Text("Rejected \(p.count(.rejected))").foregroundStyle(p.count(.rejected) > 0 ? Color.red : Color.primary)
                    }
                    .font(.callout.monospacedDigit())
                    // Problems first. A rejected row has no title of its own, so name the item
                    // before it in the file: that is where to look in mSecure.
                    List(problemsFirst(p.rows)) { r in
                        HStack {
                            Text("\(r.id)").monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                            Image(systemName: r.entry?.symbol ?? "xmark.octagon")
                                .foregroundStyle(r.entry == nil ? Color.red : Color.primary)
                                .frame(width: 20)
                            Text(r.entry?.title ?? itemBefore(r, in: p.rows)).lineLimit(1)
                                .foregroundStyle(r.entry == nil ? Color.secondary : Color.primary)
                            Spacer()
                            Text(r.reason ?? r.status.rawValue).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .frame(minHeight: 160)
            }
            Spacer(minLength: 0)
            HStack {
                Text("Conflicts are kept as separate entries tagged \(Importer.reviewTag). Nothing is overwritten.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Import \(preview?.toCommit.count ?? 0) Items") {
                    if let p = preview { model.commitImport(p.toCommit) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(preview?.toCommit.isEmpty ?? true)
            }
        }
        .padding(24)
        .frame(width: 760, height: 680)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .plainText, .data]) { result in
            load(result)
        }
        .onChange(of: mapping) { refresh() }
    }

    private func problemsFirst(_ rows: [ImportRow]) -> [ImportRow] {
        func rank(_ r: ImportRow) -> Int {
            switch r.status { case .rejected: return 0; case .conflict: return 1; default: return 2 }
        }
        return rows.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }

    private func itemBefore(_ r: ImportRow, in rows: [ImportRow]) -> String {
        guard let i = rows.firstIndex(where: { $0.id == r.id }),
              let prev = rows[..<i].last(where: { $0.entry != nil })?.entry else { return "Unreadable row" }
        return "Unreadable row, after \u{201C}\(prev.title)\u{201D} (\(prev.type.displayName))"
    }

    private func load(_ result: Result<URL, Error>) {
        problem = nil
        preview = nil
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else {
                problem = "That file is not UTF-8. Export it again as UTF-8 CSV."
                return
            }
            fileName = url.lastPathComponent
            if MSecureImporter.isMSecureExport(text) {
                isMSecure = true
                headers = []
                rows = []
                preview = Importer.classify(try MSecureImporter.read(text), existing: model.entries)
                return
            }
            isMSecure = false
            let table = try Importer.table(from: text)
            headers = table.headers
            rows = table.rows
            mapping = Importer.guess(headers: headers, defaultType: mapping.defaultType)
            refresh()
        } catch {
            problem = error.localizedDescription
        }
    }

    private func refresh() {
        guard !headers.isEmpty, mapping.targets.count == headers.count else { return }
        preview = Importer.preview(headers: headers, rows: rows, mapping: mapping, existing: model.entries)
    }
}
