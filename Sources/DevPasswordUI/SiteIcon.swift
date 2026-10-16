import SwiftUI
import AppKit
import VaultCore

/// A login's site logo (decision 0009), else a coloured letter tile. Other records, and logins
/// where Nino chose his own icon, keep their symbol.
struct SiteIcon: View {
    @EnvironmentObject var model: AppModel
    let entry: Entry
    var size: CGFloat = 22

    var body: some View {
        if let symbol = SiteLogos.genericSymbol(for: entry) {
            GenericTile(symbol: symbol, size: size)
        } else {
            logoOrTile
        }
    }

    @ViewBuilder private var logoOrTile: some View {
        let host = model.logoHost(for: entry)
        if host != nil || (entry.type == .login && entry.icon == nil) {
            if let host, let img = model.logo(for: host) {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08)))
            } else {
                LetterTile(text: host ?? tileText, size: size)
            }
        } else {
            ItemIcon(entry.symbol, size: size * 0.75)
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }

    /// The site name if there is one, else the title.
    private var tileText: String {
        let h = AppleImport.host(entry.urls.first ?? "")
        return h.isEmpty ? entry.title : h
    }
}

/// First letter on a colour chosen from the text, so the same site always gets the same colour.
struct LetterTile: View {
    let text: String
    let size: CGFloat

    private static let palette: [Color] = [
        Color(red: 0.20, green: 0.45, blue: 0.75), Color(red: 0.15, green: 0.55, blue: 0.45),
        Color(red: 0.55, green: 0.35, blue: 0.70), Color(red: 0.80, green: 0.40, blue: 0.20),
        Color(red: 0.70, green: 0.25, blue: 0.35), Color(red: 0.25, green: 0.50, blue: 0.55),
        Color(red: 0.45, green: 0.45, blue: 0.50), Color(red: 0.60, green: 0.50, blue: 0.15),
    ]

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(Self.colour(for: text))
            .frame(width: size, height: size)
            .overlay(Text(letter).font(.system(size: size * 0.55, weight: .semibold)).foregroundStyle(.white))
    }

    private var letter: String {
        let t = text.lowercased().hasPrefix("www.") ? String(text.dropFirst(4)) : text
        return t.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() } ?? "?"
    }

    /// Stable across launches (Swift's hashValue is not).
    static func colour(for text: String) -> Color {
        let sum = text.lowercased().unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        return palette[sum % palette.count]
    }
}

/// A standard symbol (Wi-Fi, key, alarm) on a quiet grey tile, the same shape as logos and letter tiles.
struct GenericTile: View {
    let symbol: String
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(Color(red: 0.42, green: 0.45, blue: 0.50))
            .frame(width: size, height: size)
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white))
    }
}
