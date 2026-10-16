import SwiftUI
import AppKit
import VaultCore

/// All of devPassword's windows and menus. Used by both the signed Xcode app and `swift run`.
public struct DevPasswordScenes: Scene {
    @StateObject private var model = AppModel()

    public init() {}

    public var body: some Scene {
        Window("devPassword", id: "main") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 880, minHeight: 540)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsMenuButton()
            }
            CommandGroup(replacing: .newItem) {
                ForEach(RecordType.allCases) { t in
                    Button("New \(t.displayName)") { model.beginNew(t) }
                        .keyboardShortcut(t == .login ? KeyboardShortcut("n") : nil)
                        .disabled(!model.isUnlocked)
                }
            }
            CommandGroup(after: .sidebar) {
                Toggle("Sidebar Tiles", isOn: $model.sidebarTiles)
                Picker("Items", selection: $model.listStyle) {
                    Text("As List").tag(ListStyleChoice.list)
                    Text("As Cards").tag(ListStyleChoice.cards)
                }
                Divider()
            }
            CommandMenu("Vault") {
                Button("Lock") { model.lockManually() }
                    .keyboardShortcut("l", modifiers: [.command])
                    .disabled(!model.isUnlocked)
                Button("Generate Password…") { model.showGenerator = true }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(!model.isUnlocked)
                Divider()
                Button("Import from Apple Passwords…") { model.showAppleImport = true }
                    .disabled(!model.isUnlocked)
                Button("Move from LastPass…") { model.showLastPass = true }
                    .disabled(!model.isUnlocked)
                Toggle("Hide Apple Logins", isOn: $model.hideAppleLogins)
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(!model.isUnlocked)
                Button("Import CSV…") { model.showImport = true }
                    .disabled(!model.isUnlocked)
                Button("Back Up Now") { model.backupNow() }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                    .disabled(!model.isUnlocked)
                RestoreMenuButton(model: model)
                Divider()
                Button("Print Emergency Sheet…") { EmergencySheet.print(model: model) }
                    .disabled(!model.isUnlocked)
            }
        }

        // Double-click a list row: the item in its own window. Closes when the vault locks.
        WindowGroup("Item", id: "item", for: UUID.self) { $id in
            ItemWindow(id: id)
                .environmentObject(model)
        }
        .defaultSize(width: 620, height: 640)

        // A normal window rather than SwiftUI's Settings scene, which cannot be resized.
        Window("devPassword Settings", id: "settings") {
            SettingsView()
                .environmentObject(model)
        }
        .defaultSize(width: 760, height: 680)
        .windowResizability(.contentMinSize)
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            switch model.screen {
            case .setup: SetupView()
            case .showRecovery(let code): RecoveryCodeView(code: code, onDone: { model.finishSetup() })
            case .locked: UnlockView()
            case .newPassphrase: NewPassphraseView()
            case .unlocked: MainView()
            }
        }
        .alert("devPassword", isPresented: Binding(get: { model.errorMessage != nil },
                                                   set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert("devPassword", isPresented: Binding(get: { model.infoMessage != nil && model.errorMessage == nil },
                                                   set: { if !$0 { model.infoMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(model.infoMessage ?? "")
        }
    }
}

/// devPassword > Settings… (Command-comma). Opens or brings forward the settings window.
struct SettingsMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Settings…") { openWindow(id: "settings") }
            .keyboardShortcut(",", modifiers: [.command])
    }
}

/// Vault > Restore from Backup… opens the restore steps over the main window.
struct RestoreMenuButton: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Restore from Backup…") {
            openWindow(id: "main")
            model.showRestore = true
        }
        .disabled(!model.isUnlocked)
    }
}

/// One record in its own window. Shows nothing and closes itself when the vault is locked,
/// including a window macOS restores at launch.
struct ItemWindow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow
    let id: UUID?

    var body: some View {
        Group {
            if model.isUnlocked, let id, let entry = model.entries.first(where: { $0.id == id }) {
                EntryDetailView(entry: entry)
                    .id(entry.id)
                    .paneBackground(.detail)
                    .navigationTitle(entry.displayTitle)
            } else {
                Color.clear.onAppear(perform: close)
            }
        }
        .frame(minWidth: 480, minHeight: 400)
        .onChange(of: model.isUnlocked) { _, unlocked in if !unlocked { close() } }
        // Escape closes this window. A sheet open on top (the icon panel) takes Escape first.
        .background(EscapeCloses())
    }

    private func close() {
        dismissWindow(id: "item", value: id)
    }
}

/// Closes the window it sits in when Escape is pressed there, unless a sheet is attached
/// (the sheet gets Escape). Watches key presses only while the view is in a window.
struct EscapeCloses: NSViewRepresentable {
    func makeNSView(context: Context) -> Watcher { Watcher() }
    func updateNSView(_ view: Watcher, context: Context) {}

    final class Watcher: NSView {
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let win = self.window, event.keyCode == 53,   // Escape
                      event.window === win, win.attachedSheet == nil else { return event }
                win.performClose(nil)
                return nil
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
