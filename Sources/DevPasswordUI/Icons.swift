import SwiftUI
import AppKit

/// Icons for record types, items and groups: SF Symbols plus our own drawn ones
/// (names starting "custom."), and the optional colour for each.
enum IconStyle {
    /// UserDefaults key for Settings > Appearance > Coloured icons. Per Mac, not secret.
    static let colouredKey = "colouredIcons"

    /// SF Symbols has no caravan, so it is drawn here.
    static let caravan = "custom.caravan"

    static func isCustom(_ name: String) -> Bool { name.hasPrefix("custom.") }

    /// The icon as a template image, so it takes the colour around it. Works in menus too.
    /// A symbol this macOS does not know shows a dashed square rather than nothing.
    static func image(_ name: String) -> Image {
        if name == caravan { return Image(nsImage: caravanImage) }
        if NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil { return Image(systemName: name) }
        return Image(systemName: "questionmark.square.dashed")
    }

    /// Colour for each icon, chosen by meaning: money green, health red and pink, travel
    /// cyan and teal, and so on. Neighbouring record types get different colours.
    /// No plain yellow: it vanishes on a light background.
    static func color(for name: String) -> Color {
        if let c = colors[name] { return c }
        // Stable fallback for any icon not listed (String.hashValue changes every launch).
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return fallback[sum % fallback.count]
    }

    private static let amber = Color(red: 0.85, green: 0.58, blue: 0.0)
    private static let fallback: [Color] = [.blue, .green, .orange, .purple, .teal, .pink, .indigo, .brown, .red, .cyan, .mint]

    private static let colors: [String: Color] = [
        // Record types
        "key.horizontal": .orange, "note.text": amber, "creditcard": .blue, "building.columns": .brown,
        "person.text.rectangle": .teal, "pills": .mint, "car": .red, "envelope": .cyan,
        "umbrella": .purple, "barcode": .indigo,
        // Sidebar
        "tray.full": .blue, "star": amber, "calendar.badge.exclamationmark": .red, "trash": .gray, "folder": .blue,
        // Item and group icons
        "lock": .indigo, "globe": .teal, "airplane": .cyan, "tram": .orange, "bicycle": .green,
        "house": .orange, "building.2": .gray, "briefcase": .brown, "cart": .green, "bag": .pink, "gift": .red,
        "heart": .pink, "cross.case": .red, "stethoscope": .teal, "graduationcap": .indigo, "book": .brown,
        "phone": .green, "iphone": .gray, "laptopcomputer": .gray, "desktopcomputer": .gray, "wifi": .blue,
        "tv": .purple, "gamecontroller": .purple, "music.note": .pink, "camera": .gray, "newspaper": .gray,
        "film": .purple, "sportscourt": .green, "figure.run": .orange, "dumbbell": .gray, "fork.knife": .orange,
        "cup.and.saucer": .brown, "pawprint": .brown, "leaf": .green, "shield": .blue, "bolt": amber,
        "drop": .cyan, "flame": .orange, "wrench.and.screwdriver": .gray,
        "sterlingsign.circle": .green, "eurosign.circle": .green, "dollarsign.circle": .green,
        "chart.line.uptrend.xyaxis": .green, "person": .blue, "person.2": .blue, "bell": .red, "calendar": .red,
        "guitars": .brown, caravan: .teal,
    ]

    /// Side view of a touring caravan: body, window, door, wheel, A-frame hitch with jockey wheel.
    /// Drawn on demand at any size, so it stays sharp. Template, so it takes the surrounding colour.
    static let caravanImage: NSImage = {
        let img = NSImage(size: NSSize(width: 21, height: 16), flipped: true) { _ in
            let lw: CGFloat = 1.5
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let body = NSBezierPath(roundedRect: NSRect(x: 1, y: 2, width: 15, height: 9.8), xRadius: 3, yRadius: 3)
            body.lineWidth = lw
            body.stroke()

            let window = NSBezierPath(roundedRect: NSRect(x: 3.6, y: 4.6, width: 4.8, height: 3.2), xRadius: 0.8, yRadius: 0.8)
            window.lineWidth = lw
            window.stroke()

            let door = NSBezierPath(rect: NSRect(x: 10.6, y: 4.6, width: 3, height: 7.2))
            door.lineWidth = lw
            door.stroke()

            let hitch = NSBezierPath()
            hitch.move(to: NSPoint(x: 16, y: 9.6))
            hitch.line(to: NSPoint(x: 20, y: 11.4))
            hitch.move(to: NSPoint(x: 18.8, y: 10.9))
            hitch.line(to: NSPoint(x: 18.8, y: 14.2))
            hitch.lineWidth = lw
            hitch.lineCapStyle = .round
            hitch.stroke()

            // Clear the body line behind the wheel, then draw the wheel over the gap.
            let wheelRect = NSRect(x: 4.4, y: 9.8, width: 5, height: 5)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: wheelRect.insetBy(dx: -0.6, dy: -0.6)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            let wheel = NSBezierPath(ovalIn: wheelRect)
            wheel.lineWidth = lw
            wheel.stroke()
            NSBezierPath(ovalIn: NSRect(x: 6.2, y: 11.6, width: 1.4, height: 1.4)).fill()
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Caravan"
        return img
    }()
}

/// An item, type or group icon. Takes the surrounding colour, or its own colour when
/// Settings > Appearance > Coloured icons is on.
struct ItemIcon: View {
    let name: String
    let size: CGFloat?
    @AppStorage(IconStyle.colouredKey) private var coloured = false

    init(_ name: String, size: CGFloat? = nil) {
        self.name = name
        self.size = size
    }

    var body: some View {
        sized.modifier(IconTint(color: coloured ? IconStyle.color(for: name) : nil))
    }

    @ViewBuilder private var sized: some View {
        let img = IconStyle.image(name)
        if let size {
            if IconStyle.isCustom(name) {
                img.resizable().scaledToFit().frame(width: size * 1.3, height: size)
            } else {
                img.font(.system(size: size))
            }
        } else {
            img
        }
    }
}

/// Applies the icon's own colour, or leaves the caller's colour alone.
private struct IconTint: ViewModifier {
    let color: Color?

    @ViewBuilder func body(content: Content) -> some View {
        if let color { content.foregroundStyle(color) } else { content }
    }
}
