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
            CommandMenu("Vault") {
                Button("Lock") { model.lockManually() }
                    .keyboardShortcut("l", modifiers: [.command])
                    .disabled(!model.isUnlocked)
                Button("Generate Password…") { model.showGenerator = true }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(!model.isUnlocked)
                Divider()
                Button("Import CSV…") { model.showImport = true }
                    .disabled(!model.isUnlocked)
                Button("Back Up Now") { model.backupNow() }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                    .disabled(!model.isUnlocked)
                RestoreMenuButton(model: model)
            }
        }

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
