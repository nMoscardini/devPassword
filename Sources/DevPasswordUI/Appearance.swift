import SwiftUI
import AppKit

/// The three panes of the main window.
enum Pane: String, CaseIterable, Identifiable {
    case sidebar, list, detail, lockScreen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sidebar: return "Sidebar"
        case .list: return "Item list"
        case .detail: return "Details"
        case .lockScreen: return "Lock screen"
        }
    }

    /// UserDefaults key. Empty value means "System" (follows light and dark mode).
    var storageKey: String { "paneColor.\(rawValue)" }
}

/// Colours are stored per Mac as "r,g,b" in sRGB, 0 to 1. Not secret.
enum PaneColors {
    static func decode(_ s: String) -> Color? {
        let parts = s.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 3 else { return nil }
        return Color(.sRGB, red: parts[0], green: parts[1], blue: parts[2], opacity: 1)
    }

    static func encode(_ c: Color) -> String {
        guard let ns = NSColor(c).usingColorSpace(.sRGB) else { return "" }
        return String(format: "%.4f,%.4f,%.4f", ns.redComponent, ns.greenComponent, ns.blueComponent)
    }
}

/// Applies a pane's chosen colour behind a List or ScrollView. Does nothing on "System".
struct PaneBackground: ViewModifier {
    let pane: Pane
    @AppStorage private var stored: String

    init(_ pane: Pane) {
        self.pane = pane
        _stored = AppStorage(wrappedValue: "", pane.storageKey)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if let color = PaneColors.decode(stored) {
            content
                .scrollContentBackground(.hidden)
                .background(color)
        } else {
            content
        }
    }
}

extension View {
    func paneBackground(_ pane: Pane) -> some View { modifier(PaneBackground(pane)) }
}

struct AppearanceSettings: View {
    @AppStorage(Pane.sidebar.storageKey) private var sidebar = ""
    @AppStorage(Pane.list.storageKey) private var list = ""
    @AppStorage(Pane.detail.storageKey) private var detail = ""
    @AppStorage(Pane.lockScreen.storageKey) private var lockScreen = ""

    var body: some View {
        Form {
            Section("Pane colours") {
                row(.sidebar, $sidebar)
                row(.list, $list)
                row(.detail, $detail)
            }
            Section("Lock screen") {
                row(.lockScreen, $lockScreen)
            }
            Section {
                Text("System follows light and dark mode. A chosen colour stays the same in both, so pick one that keeps the text easy to read.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Reset All to System") {
                    sidebar = ""; list = ""; detail = ""; lockScreen = ""
                }
                .disabled(sidebar.isEmpty && list.isEmpty && detail.isEmpty && lockScreen.isEmpty)
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ pane: Pane, _ value: Binding<String>) -> some View {
        HStack {
            Text(pane.title)
            Spacer()
            if value.wrappedValue.isEmpty {
                Text("System").foregroundStyle(.secondary)
            }
            ColorPicker(pane.title,
                        selection: Binding(get: { PaneColors.decode(value.wrappedValue) ?? Color(nsColor: .windowBackgroundColor) },
                                           set: { value.wrappedValue = PaneColors.encode($0) }),
                        supportsOpacity: false)
                .labelsHidden()
            Button("System") { value.wrappedValue = "" }
                .disabled(value.wrappedValue.isEmpty)
        }
    }
}
