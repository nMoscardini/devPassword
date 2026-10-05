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
    /// Text colour for the pane. Empty means "System".
    var textKey: String { "textColor.\(rawValue)" }
}

/// Light, dark or follow the Mac. Applies to every devPassword window, sheet and menu.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    static let key = "appearanceMode"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// Called at launch and when the setting changes.
    static func apply(_ raw: String) {
        switch AppearanceMode(rawValue: raw) ?? .system {
        case .system: NSApplication.shared.appearance = nil
        case .light: NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark: NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
    }
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

    /// WCAG contrast ratio between two colours, 1 to 21. 4.5 or more reads well.
    static func contrast(_ a: Color, _ b: Color) -> Double? {
        guard let x = luminance(a), let y = luminance(b) else { return nil }
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    private static func luminance(_ c: Color) -> Double? {
        guard let ns = NSColor(c).usingColorSpace(.sRGB) else { return nil }
        func lin(_ v: CGFloat) -> Double {
            let d = Double(v)
            return d <= 0.03928 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(ns.redComponent) + 0.7152 * lin(ns.greenComponent) + 0.0722 * lin(ns.blueComponent)
    }
}

/// Applies a pane's chosen background and text colours. Does nothing on "System".
/// Secondary text (captions, subtitles) is a lighter shade of the chosen text colour.
struct PaneBackground: ViewModifier {
    let pane: Pane
    @AppStorage private var stored: String
    @AppStorage private var text: String

    init(_ pane: Pane) {
        self.pane = pane
        _stored = AppStorage(wrappedValue: "", pane.storageKey)
        _text = AppStorage(wrappedValue: "", pane.textKey)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        let tinted = content.modifier(TextTint(color: PaneColors.decode(text)))
        if let color = PaneColors.decode(stored) {
            tinted
                .scrollContentBackground(.hidden)
                .background(color)
        } else {
            tinted
        }
    }
}

private struct TextTint: ViewModifier {
    let color: Color?

    @ViewBuilder func body(content: Content) -> some View {
        if let color { content.foregroundStyle(color) } else { content }
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
    @AppStorage(IconStyle.colouredKey) private var colouredIcons = false
    @AppStorage(AppearanceMode.key) private var mode = AppearanceMode.system.rawValue
    @AppStorage(Pane.sidebar.textKey) private var sidebarText = ""
    @AppStorage(Pane.list.textKey) private var listText = ""
    @AppStorage(Pane.detail.textKey) private var detailText = ""
    @AppStorage(Pane.lockScreen.textKey) private var lockScreenText = ""

    var body: some View {
        Form {
            Section("Mode") {
                Picker("Appearance", selection: $mode) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                Text("Dark or Light applies to devPassword only. System follows the Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Icons") {
                Toggle("Coloured icons", isOn: $colouredIcons)
                Text("Gives each icon its own colour in the sidebar, the item list, the details and the icon picker. Menus stay plain.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Pane colours") {
                pane(.sidebar, $sidebar, $sidebarText)
                pane(.list, $list, $listText)
                pane(.detail, $detail, $detailText)
            }
            Section("Lock screen") {
                pane(.lockScreen, $lockScreen, $lockScreenText)
            }
            Section {
                Text("System follows light and dark mode. A chosen colour stays the same in both, so pick one that keeps the text easy to read.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Reset All Colours to System") {
                    sidebar = ""; list = ""; detail = ""; lockScreen = ""
                    sidebarText = ""; listText = ""; detailText = ""; lockScreenText = ""
                }
                .disabled(allColours.allSatisfy(\.isEmpty))
            }
        }
        .formStyle(.grouped)
        .onChange(of: mode) { AppearanceMode.apply(mode) }
    }

    private var allColours: [String] {
        [sidebar, list, detail, lockScreen, sidebarText, listText, detailText, lockScreenText]
    }

    private func pane(_ pane: Pane, _ background: Binding<String>, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pane.title).bold()
            row("Background", background, fallback: .windowBackgroundColor)
            row("Text", text, fallback: .labelColor)
            if let warning = readability(background.wrappedValue, text.wrappedValue) {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    private func row(_ label: String, _ value: Binding<String>, fallback: NSColor) -> some View {
        HStack {
            Text(label).padding(.leading, 12)
            Spacer()
            if value.wrappedValue.isEmpty {
                Text("System").foregroundStyle(.secondary)
            }
            ColorPicker(label,
                        selection: Binding(get: { PaneColors.decode(value.wrappedValue) ?? Color(nsColor: fallback) },
                                           set: { value.wrappedValue = PaneColors.encode($0) }),
                        supportsOpacity: false)
                .labelsHidden()
            Button("System") { value.wrappedValue = "" }
                .disabled(value.wrappedValue.isEmpty)
        }
    }

    /// A warning when text may be hard to read, or nil.
    private func readability(_ background: String, _ text: String) -> String? {
        guard let fg = PaneColors.decode(text) else { return nil }
        guard let bg = PaneColors.decode(background) else {
            return "The System background changes between light and dark. Check this text colour in both, or choose a background too."
        }
        guard let ratio = PaneColors.contrast(fg, bg), ratio < 4.5 else { return nil }
        return String(format: "Hard to read: contrast %.1f to 1. Aim for 4.5 or more.", ratio)
    }
}
