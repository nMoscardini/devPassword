import SwiftUI
import VaultCore

struct MainView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } content: {
            EntryListView()
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            if let id = model.selection, let entry = model.entries.first(where: { $0.id == id }) {
                EntryDetailView(entry: entry).id(entry.id)   // new id resets reveal state
                    .paneBackground(.detail)
            } else {
                ContentUnavailableView("No item selected", systemImage: "lock.open")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .paneBackground(.detail)
            }
        }
        .searchable(text: $model.search, placement: .toolbar, prompt: "Search")
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    ForEach(RecordType.allCases) { t in
                        Button { model.beginNew(t) } label: { Label { Text(t.displayName) } icon: { IconStyle.image(t.symbol) } }
                    }
                } label: {
                    Label("New", systemImage: "plus")
                }
                Menu {
                    Picker("Sort by", selection: $model.sortOrder) {
                        ForEach(ListSortOrder.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort by name or by when items were last changed")
                Button { model.showGenerator = true } label: { Label("Generate", systemImage: "wand.and.stars") }
                    .help("Generate a password")
                Button { model.lockManually() } label: { Label("Lock", systemImage: "lock") }
                    .help("Lock now (Command-L)")
            }
        }
        .sheet(item: $model.editing) { e in EntryEditorView(entry: e) }
        .sheet(isPresented: $model.showGenerator) { GeneratorView(onUse: nil) }
        .sheet(isPresented: $model.showImport) { ImportView() }
        .sheet(isPresented: $model.showRestore) { RestoreView() }
        .safeAreaInset(edge: .bottom) {
            if model.integrityFailures > 0 {
                Text("\(model.integrityFailures) record(s) failed their integrity check and are hidden. They are unchanged on disk. Restore from a backup if this persists.")
                    .font(.callout)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.2))
            }
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject var model: AppModel

    // Every row is built the same way: a ForEach over the List's selection type (SidebarFilter?).
    // Mixing hand-written rows with ForEach rows left the hand-written ones unclickable.
    private static let top: [SidebarFilter?] = [.all, .favourites, .expiring]
    private static let types: [SidebarFilter?] = RecordType.allCases.map { Optional(SidebarFilter.type($0)) }
    private static let bottom: [SidebarFilter?] = [.deleted]

    var body: some View {
        let groupRows: [SidebarFilter?] = model.groups.map { Optional(SidebarFilter.group($0.id)) }
        List(selection: $model.filter) {
            Section { rows(Self.top) }
            if !groupRows.isEmpty {
                Section("Groups") { rows(groupRows) }
            }
            Section("Types") { rows(Self.types) }
            Section { rows(Self.bottom) }
        }
        .paneBackground(.sidebar)
    }

    private func rows(_ filters: [SidebarFilter?]) -> some View {
        ForEach(filters, id: \.self) { f in
            if let f {
                Label { Text(title(f)) } icon: { ItemIcon(symbol(f)) }
                    .badge(model.count(f))
                    .tag(f as SidebarFilter?)
            }
        }
    }

    private func title(_ f: SidebarFilter) -> String {
        switch f {
        case .all: return "All Items"
        case .favourites: return "Favourites"
        case .expiring: return "Expiring Soon"
        case .deleted: return "Deleted"
        case .type(let t): return t.pluralName
        case .group(let id): return model.groups.first { $0.id == id }?.name ?? "Group"
        }
    }

    private func symbol(_ f: SidebarFilter) -> String {
        switch f {
        case .all: return "tray.full"
        case .favourites: return "star"
        case .expiring: return "calendar.badge.exclamationmark"
        case .deleted: return "trash"
        case .type(let t): return t.symbol
        case .group(let id): return model.groups.first { $0.id == id }?.icon ?? EntryGroup.defaultIcon
        }
    }
}

struct EntryListView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let items = model.visibleEntries
        List(items, selection: $model.selection) { e in
            HStack(spacing: 10) {
                ItemIcon(e.symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.title).lineLimit(1)
                    Text(model.filter == .expiring ? expiryText(e)
                         : (model.sortOrder == .name ? e.subtitle
                            : "Changed " + e.modified.formatted(date: .abbreviated, time: .omitted)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if e.tags.contains(Importer.reviewTag) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).help("Imported conflict. Review it.")
                }
                if let g = model.group(for: e) {
                    ItemIcon(g.icon)
                        .foregroundStyle(.secondary)
                        .font(.body)
                        .help("Group: \(g.name)")
                }
                if e.favourite {
                    // Yellow fill with a dark amber outline: plain yellow vanished on a light list.
                    ZStack {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                        Image(systemName: "star").foregroundStyle(Color(red: 0.62, green: 0.40, blue: 0.0))
                    }
                    .font(.body)
                    .help("Favourite")
                }
            }
            .padding(.vertical, 2)
        }
        .paneBackground(.list)
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(model.search.isEmpty ? "Nothing here" : "No results",
                                       systemImage: model.search.isEmpty ? "tray" : "magnifyingglass")
            }
        }
    }

    private func expiryText(_ e: Entry) -> String {
        guard let d = e.expiryDate else { return e.subtitle }
        return e.expiryText(d) + " " + d.formatted(date: .abbreviated, time: .omitted)
    }
}

struct EntryDetailView: View {
    @EnvironmentObject var model: AppModel
    let entry: Entry
    @State private var revealed: Set<String> = []
    @State private var confirmPurge = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    ItemIcon(entry.symbol, size: 30).foregroundStyle(.secondary)
                    VStack(alignment: .leading) {
                        Text(entry.title).font(.title2.bold()).textSelection(.enabled)
                        Text(entry.type.displayName + (model.group(for: entry).map { "  ·  " + $0.name } ?? ""))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if let exp = entry.expiryDate {
                    Label(entry.expiryText(exp) + " " + exp.formatted(date: .long, time: .omitted),
                          systemImage: "calendar")
                        .foregroundStyle(entry.expires(within: AppModel.expiringDays) ? Color.orange : Color.secondary)
                }
                if entry.isDeleted {
                    Label("In Deleted. Put it back, or delete it permanently.", systemImage: "trash")
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(entry.urls.enumerated()), id: \.offset) { pair in
                        FieldRow(id: "url\(pair.offset)", label: "Website", value: pair.element, concealed: false, lastFour: false, revealed: $revealed, isURL: true)
                    }
                    ForEach(entry.type.fieldDefs, id: \.key) { def in
                        let v = entry[field: def.key]
                        if !v.isEmpty {
                            FieldRow(id: def.key, label: def.label, value: v, concealed: def.kind == .concealed,
                                     lastFour: def.showsLastFour, revealed: $revealed)
                        }
                    }
                    ForEach(entry.customFields) { f in
                        FieldRow(id: f.id.uuidString, label: f.label, value: f.value, concealed: f.kind == .concealed,
                                 lastFour: false, revealed: $revealed)
                    }
                    if let prev = entry.previousPassword {
                        FieldRow(id: "previous", label: "Previous password", value: prev.value, concealed: true,
                                 lastFour: false, revealed: $revealed)
                        HStack {
                            Text("Changed \(prev.changedAt.formatted(date: .abbreviated, time: .shortened)). Keep it until the new one works.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("New one works, forget old") {
                                var e = entry
                                e.previousPassword = nil
                                model.save(e)
                            }
                            .buttonStyle(.link).font(.caption)
                        }
                        .padding(.leading, 160)
                    }
                }

                if !entry.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Notes").foregroundStyle(.secondary)
                            if entry.notesConcealed {
                                Button { toggle("notes") } label: {
                                    Image(systemName: revealed.contains("notes") ? "eye.slash" : "eye")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        if entry.notesConcealed && !revealed.contains("notes") {
                            Text(Masking.dots).foregroundStyle(.secondary)
                        } else {
                            Text(entry.notes).textSelection(.enabled)
                        }
                    }
                }
                if !entry.tags.isEmpty {
                    Text(entry.tags.map { "#" + $0 }.joined(separator: "  ")).foregroundStyle(.secondary)
                }
                Text("Created \(entry.created.formatted(date: .abbreviated, time: .shortened))  ·  Modified \(entry.modified.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if entry.isDeleted {
                    Button { model.restoreDeleted(entry) } label: { Label("Put Back", systemImage: "arrow.uturn.backward") }
                        .help("Move this item out of Deleted")
                    Button("Delete Permanently", role: .destructive) { confirmPurge = true }
                } else {
                    Button { model.toggleFavourite(entry) } label: {
                        Label("Favourite", systemImage: entry.favourite ? "star.fill" : "star")
                    }
                    groupMenu
                    Button { model.editing = entry } label: { Label("Edit", systemImage: "pencil") }
                        .keyboardShortcut("e", modifiers: [.command])
                    Button { model.moveToDeleted(entry) } label: { Label("Move to Deleted", systemImage: "trash") }
                        .help("Move to the Deleted list. You can put it back from there.")
                }
            }
        }
        .confirmationDialog("Delete \"\(entry.title)\" permanently?", isPresented: $confirmPurge) {
            Button("Delete Permanently", role: .destructive) { model.purge(entry) }
        } message: {
            Text("This cannot be undone in the app. A local snapshot is taken first.")
        }
        .onDisappear { revealed = [] }
    }

    private func toggle(_ id: String) {
        if revealed.contains(id) { revealed.remove(id) } else { revealed.insert(id) }
    }

    /// Next to the star: pick the item's one group, or None.
    private var groupMenu: some View {
        let current = model.group(for: entry)
        return Menu {
            Picker("Group", selection: Binding(get: { current?.id }, set: { model.setGroup(entry, to: $0) })) {
                Text("No Group").tag(UUID?.none)
                ForEach(model.groups) { g in
                    Label { Text(g.name) } icon: { IconStyle.image(g.icon) }.tag(Optional(g.id))
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Edit Groups…") {
                model.settingsTab = .groups
                openWindow(id: "settings")
            }
        } label: {
            Label { Text("Group") } icon: { IconStyle.image(current?.icon ?? EntryGroup.defaultIcon) }
        }
        .help(current.map { "Group: \($0.name)" } ?? "Not in a group")
    }
}

struct FieldRow: View {
    let id: String
    let label: String
    let value: String
    let concealed: Bool
    let lastFour: Bool
    @Binding var revealed: Set<String>
    var isURL = false

    private var isRevealed: Bool { revealed.contains(id) }

    private var display: String {
        if !concealed || isRevealed { return value }
        return lastFour ? Masking.lastFour(value) : Masking.dots
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .trailing)
            Group {
                if isURL, let url = URL(string: value), url.scheme?.hasPrefix("http") == true {
                    Link(value, destination: url)
                } else if concealed && !isRevealed {
                    Text(display).font(.body.monospaced())
                } else {
                    Text(display).font(concealed ? .body.monospaced() : .body).textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if concealed {
                Button {
                    if isRevealed { revealed.remove(id) } else { revealed.insert(id) }
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                }
                .help(isRevealed ? "Hide" : "Reveal")
            }
            Button {
                Clipboard.copy(value, concealed: concealed)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy. Clears after 30 seconds.")
        }
        .buttonStyle(.borderless)
    }
}
