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
        if let pasted = model.customLogos[entry.id] {
            logoImage(pasted)
        } else if let symbol = SiteLogos.genericSymbol(for: entry) {
            GenericTile(symbol: symbol, size: size)
        } else {
            logoOrTile
        }
    }

    @ViewBuilder private var logoOrTile: some View {
        let host = model.logoHost(for: entry)
        if host != nil || (entry.type == .login && entry.icon == nil) {
            if let host, let img = model.logo(for: host) {
                logoImage(img)
            } else {
                LetterTile(text: host ?? tileText, size: size)
            }
        } else {
            ItemIcon(entry.symbol, size: size * 0.75)
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }

    private func logoImage(_ img: NSImage) -> some View {
        Image(nsImage: img)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08)))
    }

    /// The site name if there is one, else the title.
    private var tileText: String { SiteIcon.tileText(entry) }

    static func tileText(_ e: Entry) -> String {
        let h = AppleImport.host(e.urls.first ?? "")
        return h.isEmpty ? e.title : h
    }

    /// The main colour of a logo: the average of its coloured pixels, ignoring white, near-black
    /// and transparent ones (a white BA logo with a red and blue swoosh gives its red-blue).
    static func dominantColour(_ img: NSImage) -> Color? {
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = 24
        var px = [UInt8](repeating: 0, count: side * side * 4)
        // The buffer must stay valid while the context draws into it: keep both inside one closure.
        let drawn: Bool = px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        for i in stride(from: 0, to: px.count, by: 4) {
            let a = Double(px[i + 3]) / 255
            guard a > 0.5 else { continue }
            let pr = Double(px[i]) / 255 / a, pg = Double(px[i + 1]) / 255 / a, pb = Double(px[i + 2]) / 255 / a
            let mx = max(pr, pg, pb), mn = min(pr, pg, pb)
            guard mx - mn > 0.15 else { continue }   // skip white, grey and black
            r += pr; g += pg; b += pb; n += 1
        }
        guard n >= 4 else { return nil }
        return Color(red: r / n, green: g / n, blue: b / n)
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
