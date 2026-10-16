import SwiftUI
import VaultCore

struct MainView: View {
    @EnvironmentObject var model: AppModel

    /// List view: three columns. Cards view: two columns, the cards take the whole width;
    /// details open in the item's own window on double-click.
    @ViewBuilder private var split: some View {
        if model.listStyle == .cards {
            NavigationSplitView {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 190, ideal: 220)
            } detail: {
                // Cards keep the whole width. Click selects; double-click opens the item's own window.
                EntryListView()
            }
        } else {
            NavigationSplitView {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            } content: {
                EntryListView()
                    .navigationSplitViewColumnWidth(min: 260, ideal: 300)
            } detail: {
                selectedDetail
            }
        }
    }

    @ViewBuilder private var selectedDetail: some View {
        if let id = model.selection, let entry = model.entries.first(where: { $0.id == id }) {
            EntryDetailView(entry: entry).id(entry.id)   // new id resets reveal state
                .paneBackground(.detail)
        } else {
            ContentUnavailableView("No item selected", systemImage: "lock.open")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .paneBackground(.detail)
        }
    }

    var body: some View {
        split
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
                Picker("View", selection: $model.listStyle) {
                    Label("List", systemImage: "list.bullet").tag(ListStyleChoice.list)
                    Label("Cards", systemImage: "square.grid.2x2").tag(ListStyleChoice.cards)
                }
                .pickerStyle(.segmented)
                .help("Show items as a list or as cards")
                if model.hasAppleLogins {
                    Toggle(isOn: $model.hideAppleLogins) {
                        Label("Hide Apple Logins", systemImage: "apple.logo")
                    }
                    .toggleStyle(.button)
                    .help(model.hideAppleLogins
                          ? "Apple logins are hidden. Click to show them. They are always in the Apple Passwords row."
                          : "Hide logins imported from Apple Passwords (Shift-Command-A)")
                }
                Button { model.showGenerator = true } label: { Label("Generate", systemImage: "wand.and.stars") }
                    .help("Generate a password")
                Button { model.lockManually() } label: { Label("Lock", systemImage: "lock") }
                    .help("Lock now (Command-L)")
            }
        }
        .sheet(item: $model.editing) { e in EntryEditorView(entry: e) }
        .sheet(isPresented: $model.showGenerator) { GeneratorView(onUse: nil) }
        .sheet(isPresented: $model.showImport) { ImportView() }
        .sheet(isPresented: $model.showAppleImport) { AppleImportView() }
        .sheet(isPresented: $model.showLastPass) { LastPassView() }
        .sheet(isPresented: $model.showRestore) { RestoreView() }
        .safeAreaInset(edge: .top) {
            if model.appleSnapshotStale, let age = model.appleSnapshotAge {
                HStack {
                    Label("Apple Passwords snapshot is \(age) days old. Logins here may be out of date.", systemImage: "clock.arrow.circlepath")
                    Spacer()
                    Button("Refresh…") { model.showAppleImport = true }
                }
                .font(.callout)
                .padding(8)
                .background(Color.orange.opacity(0.2))
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let p = model.logoProgress {
                HStack {
                    ProgressView(value: Double(p.done), total: Double(max(p.total, 1))).frame(width: 160)
                    Text("Fetching site logos: \(p.done) of \(p.total)").font(.callout)
                    Spacer()
                    Button("Stop") { model.cancelLogoFetch() }
                }
                .padding(8)
                .background(.bar)
            }
        }
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
        // Coloured tiles at the top (like Apple Passwords), groups as tiles, types as a plain list.
        let tops: [SidebarFilter] = [.all, .favourites, .expiring]
            + (model.hasAppleLogins ? [.apple] : [])
            + (model.hasRemovedAppleLogins ? [.appleRemoved] : [])
            + (model.hasArchived ? [.archived] : [])
            + [.deleted]
        List(selection: $model.filter) {
            if model.sidebarTiles {
                Section { tiles(tops) }
                if !model.groups.isEmpty {
                    Section("Groups") { tiles(model.groups.map { SidebarFilter.group($0.id) }) }
                }
            } else {
                Section { rows([.all, .favourites, .expiring]) }
                if !model.groups.isEmpty {
                    Section("Groups") { rows(model.groups.map { Optional(SidebarFilter.group($0.id)) }) }
                }
            }
            Section("Types") { rows(Self.types) }
            if !model.sidebarTiles {
                Section { rows(Array(tops.dropFirst(3)).map { Optional($0) }) }
            }
        }
        .paneBackground(.sidebar)
    }

    /// Two tiles to a row. Tapping a tile sets the filter; the tile shows its own selection.
    private func tiles(_ filters: [SidebarFilter]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(filters, id: \.self) { f in
                SidebarTile(title: title(f), symbol: symbol(f), colour: tileColour(f), count: model.count(f),
                            selected: model.filter == f) { model.filter = f }
            }
        }
        .padding(.vertical, 4)
        .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
        .selectionDisabled()
    }

    private func tileColour(_ f: SidebarFilter) -> Color {
        switch f {
        case .all: return Color(red: 0.0, green: 0.48, blue: 1.0)
        case .favourites: return Color(red: 1.0, green: 0.62, blue: 0.0)
        case .expiring: return Color(red: 0.92, green: 0.26, blue: 0.21)
        case .apple: return Color(red: 0.25, green: 0.25, blue: 0.28)
        case .appleRemoved: return Color(red: 0.55, green: 0.55, blue: 0.58)
        case .deleted: return Color(red: 0.95, green: 0.55, blue: 0.10)
        case .archived: return Color(red: 0.55, green: 0.45, blue: 0.35)
        case .group(let id): return LetterTile.colour(for: model.groups.first { $0.id == id }?.name ?? "")
        case .type(let t): return IconStyle.color(for: t.symbol)
        }
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
        case .archived: return "Archive"
        case .apple: return "Apple Passwords"
        case .appleRemoved: return "Removed from Apple"
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
        case .archived: return "archivebox"
        case .apple: return "apple.logo"
        case .appleRemoved: return "minus.circle"
        case .type(let t): return t.symbol
        case .group(let id): return model.groups.first { $0.id == id }?.icon ?? EntryGroup.defaultIcon
        }
    }
}

struct EntryListView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let items = model.visibleEntries
        Group {
            if model.listStyle == .cards {
                EntryCardsView(items: items)
            } else {
                list(items)
            }
        }
        .paneBackground(.list)
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(model.search.isEmpty ? "Nothing here" : "No results",
                                       systemImage: model.search.isEmpty ? "tray" : "magnifyingglass")
            }
        }
    }

    private func list(_ items: [Entry]) -> some View {
        List(items, selection: $model.selection) { e in
            HStack(spacing: 10) {
                SiteIcon(entry: e, size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.displayTitle).lineLimit(1)
                    Text(model.filter == .expiring ? expiryText(e)
                         : (model.sortOrder == .name ? e.subtitle
                            : "Changed " + e.modified.formatted(date: .abbreviated, time: .omitted)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if e.isAppleSnapshot {
                    Image(systemName: e.appleRemovedAt == nil ? "apple.logo" : "minus.circle")
                        .foregroundStyle(.secondary)
                        .help(e.appleRemovedAt == nil ? "From Apple Passwords, read-only" : "No longer in Apple Passwords")
                }
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
        .contextMenu(forSelectionType: UUID.self) { _ in
            EmptyView()
        } primaryAction: { ids in
            // Double-click or Return: open in its own window.
            for id in ids { openWindow(id: "item", value: id) }
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
    @State private var showLogo = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Button { showLogo = true } label: { SiteIcon(entry: entry, size: 40) }
                        .buttonStyle(.plain)
                        .help("Choose the website this record's logo comes from")
                        .sheet(isPresented: $showLogo) {
                            LogoSiteView(entry: entry).environmentObject(model)
                        }
                    VStack(alignment: .leading) {
                        Text(entry.displayTitle).font(.title2.bold()).textSelection(.enabled)
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
                HStack(spacing: 8) {
                    Text(model.logoHost(for: entry).map { "Logo from \($0)" } ?? "No logo website")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Change…") { showLogo = true }
                        .buttonStyle(.link).font(.caption)
                }
                if entry.isArchived, let at = entry.archivedAt {
                    Label("Archived \(at.formatted(date: .abbreviated, time: .omitted)). Old but kept.", systemImage: "archivebox")
                        .foregroundStyle(.secondary)
                }
                if entry.isAppleSnapshot {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("From Apple Passwords. Read-only: change it in Passwords, then import again.", systemImage: "apple.logo")
                        if let seen = entry.appleSeenAt {
                            Text("Snapshot \(seen.formatted(date: .abbreviated, time: .shortened))")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        if let gone = entry.appleRemovedAt {
                            Label("No longer in Apple Passwords since \(gone.formatted(date: .abbreviated, time: .omitted)). This is the last known copy.",
                                  systemImage: "minus.circle")
                                .foregroundStyle(.orange)
                        }
                    }
                } else if entry.type == .login {
                    Label(entry.master.map { "Master: " + $0.displayName } ?? "Master not set",
                          systemImage: entry.master == .apple ? "apple.logo" : "lock.shield")
                        .foregroundStyle(.secondary)
                        .help(entry.master?.explanation ?? "Choose Apple Passwords or devPassword in Edit (decision 0007).")
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

                if let mine = entry.myNotes, !mine.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your notes").foregroundStyle(.secondary)
                        Text(mine).textSelection(.enabled)
                    }
                }
                if !entry.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.isAppleSnapshot ? "Notes from Apple Passwords" : "Notes").foregroundStyle(.secondary)
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
                if let history = entry.appleHistory, !history.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("History").foregroundStyle(.secondary)
                        ForEach(Array(history.reversed().enumerated()), id: \.offset) { pair in
                            Text("\(pair.element.at.formatted(date: .abbreviated, time: .omitted))  \(pair.element.text)")
                                .font(.callout)
                        }
                    }
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
                    Button { model.setArchived(entry, !entry.isArchived) } label: {
                        Label(entry.isArchived ? "Unarchive" : "Archive",
                              systemImage: entry.isArchived ? "arrow.uturn.backward.circle" : "archivebox")
                    }
                    .help(entry.isArchived ? "Bring back into the main lists" : "Old but kept: move to the Archive")
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
    @EnvironmentObject var model: AppModel
    @State private var showPick = false
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
                Button {
                    showPick = true
                } label: {
                    Image(systemName: "character.cursor.ibeam")
                }
                .help("Pick characters, for sites that ask for, say, the 2nd, 5th and 7th")
                .popover(isPresented: $showPick, arrowEdge: .bottom) {
                    CharacterPickView(label: label, value: value).environmentObject(model)
                }
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

/// Click a record's icon: logo from a website, a pasted picture, or a symbol. One tab at a time.
struct LogoSiteView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let entry: Entry
    /// The icon settings when the sheet opened, so Cancel can put them back.
    @State private var original: (icon: String?, site: String?, picture: Data?)?
    @State private var tab: Tab = .website
    @State private var site = ""
    @State private var status = ""
    @State private var busy = false

    enum Tab: String, CaseIterable, Identifiable {
        case website = "Website", picture = "Picture", symbol = "Symbol"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                SiteIcon(entry: current, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.displayTitle).font(.headline).lineLimit(1)
                    Text(describe).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Use Default") { run(nil) }
                    .disabled(busy || (current.logoSite == nil && current.customLogo == nil && current.icon == nil))
            }
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch tab {
                case .website: websiteTab
                case .picture: pictureTab
                case .symbol: symbolTab
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !status.isEmpty {
                Text(status).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            HStack {
                Text("Stays open while you visit the website. Changes show at once.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { cancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Done") { dismiss() }
            }
        }
        .padding(18)
        .frame(width: 560)
        .interactiveDismissDisabled()
        .onAppear {
            if original == nil { original = (current.icon, current.logoSite, current.customLogo) }
            site = current.logoSite ?? model.logoHost(for: current) ?? ""
            tab = current.customLogo != nil ? .picture : (current.icon != nil ? .symbol : .website)
        }
    }

    private var websiteTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Website", text: $site, prompt: Text("For example ba.com"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { run(site) }
                Button("Get Logo") { run(site) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy || site.trimmingCharacters(in: .whitespaces).isEmpty)
                if busy { ProgressView().controlSize(.small) }
            }
            Text("Only that site's icon file is fetched. Your passwords never leave the Mac.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var pictureTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("1. Grab the logo on screen with Shift-Command-Control-4. It goes to the clipboard.")
            Text("2. Click Paste Picture. devPassword keeps a small copy, a few kilobytes.")
            HStack {
                Button("Paste Picture") { status = model.pasteLogo(current) }
                if current.customLogo != nil {
                    Button("Remove Picture") { model.removePastedLogo(current); status = "Picture removed." }
                }
            }
        }
        .font(.callout)
    }

    private var symbolTab: some View {
        IconPicker(selection: Binding(get: { current.icon },
                                      set: { model.setIcon(current, to: $0); status = "" }),
                   typeSymbol: current.type.symbol,
                   resetTitle: "No Symbol")
    }

    /// One line saying where the icon comes from now.
    private var describe: String {
        if current.customLogo != nil { return "Pasted picture" }
        if let i = current.icon { return "Symbol: \(i)" }
        if let s = current.logoSite { return "Logo from \(s)" }
        if let h = model.logoHost(for: current) { return "Logo from \(h) (automatic)" }
        return "Automatic"
    }

    /// Puts the icon back as it was when the sheet opened, then closes.
    private func cancel() {
        if let o = original, o.icon != current.icon || o.site != current.logoSite || o.picture != current.customLogo {
            var e = current
            e.icon = o.icon
            e.logoSite = o.site
            e.customLogo = o.picture
            model.save(e, touchModified: false)
        }
        dismiss()
    }

    /// The record as it is now, after any save.
    private var current: Entry { model.entries.first { $0.id == entry.id } ?? entry }

    private func run(_ value: String?) {
        busy = true
        status = ""
        Task {
            status = await model.setLogoSite(current, to: value)
            if value == nil {
                if current.icon != nil { model.setIcon(current, to: nil) }
                site = model.logoHost(for: current) ?? ""
            }
            busy = false
        }
    }
}

/// A coloured sidebar tile: icon in a circle, count, name. Like the tiles in Apple Passwords.
struct SidebarTile: View {
    let title: String
    let symbol: String
    let colour: Color
    let count: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Circle().fill(selected ? Color.white : colour)
                        .frame(width: 26, height: 26)
                        .overlay(tileIcon.foregroundStyle(selected ? colour : Color.white))
                    Spacer()
                    Text("\(count)").font(.system(.callout, design: .rounded).weight(.semibold))
                        .foregroundStyle(selected ? Color.white : Color.secondary)
                }
                Text(title).font(.callout.weight(.medium)).lineLimit(1)
                    .foregroundStyle(selected ? Color.white : Color.primary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? colour : Color.secondary.opacity(0.10)))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count)")
    }

    /// Plain white symbol: ItemIcon would apply the "coloured icons" setting on top of the tile colour.
    @ViewBuilder private var tileIcon: some View {
        if IconStyle.isCustom(symbol) {
            IconStyle.image(symbol).resizable().scaledToFit().frame(width: 15, height: 12)
        } else {
            IconStyle.image(symbol).font(.system(size: 12, weight: .semibold))
        }
    }
}

/// The middle column as cards (like LastPass): logo on a tinted band, name, username.
struct EntryCardsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    let items: [Entry]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 10)], spacing: 10) {
                ForEach(items) { e in
                    card(e)
                        .onTapGesture(count: 2) { openWindow(id: "item", value: e.id) }
                        .onTapGesture { model.selection = e.id }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // Click empty space to clear the selection.
        .background(Color.clear.contentShape(Rectangle()).onTapGesture { model.selection = nil })
    }

    private func card(_ e: Entry) -> some View {
        let selected = model.selection == e.id
        let tint = model.cardTint(for: e)
        return VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Rectangle().fill(tint.opacity(0.22))
                    .frame(height: 44)
                    .overlay(SiteIcon(entry: e, size: 32))
                HStack(spacing: 3) {
                    if e.isAppleSnapshot { Image(systemName: "apple.logo") }
                    if e.favourite { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(5)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(e.displayTitle).font(.callout.weight(.medium)).lineLimit(1)
                Text(e.subtitle.isEmpty ? e.type.displayName : e.subtitle)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.10), lineWidth: selected ? 2 : 1))
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
        .contentShape(Rectangle())
        .help(e.displayTitle)
    }
}
