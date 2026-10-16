import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

/// Site logos (decision 0009). Fetched only when Nino asks, straight from each site, over HTTPS,
/// from two fixed paths. No HTML is read. Each image is redrawn to a 64 by 64 PNG before it is kept,
/// and the cache is sealed under the vault key because the list of sites is personal.
public enum SiteLogos {
    public static let pixelSize = 64
    public static let maxBytes = 200_000
    public static let timeout: TimeInterval = 8
    /// Big sites (British Airways, Bosch) stall or refuse requests that do not look like a browser.
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
    /// Fixed, well-known icon files only. No page is read (decision 0009).
    public static let paths = ["/apple-touch-icon.png", "/apple-touch-icon-precomposed.png", "/favicon.ico",
                               "/favicon.png", "/favicon-32x32.png", "/favicon-196x196.png"]
    /// A site with no icon is not asked again for this long.
    public static let missRetry: TimeInterval = 30 * 86_400

    // MARK: Which hosts may be asked

    /// The host to fetch a logo from, or nil for IP addresses, local names and logins with no site.
    public static func fetchableHost(_ url: String) -> String? {
        let h = AppleImport.host(url)
        guard !h.isEmpty, h.contains(".") else { return nil }
        if h.allSatisfy({ $0.isNumber || $0 == "." }) { return nil }        // IPv4
        if h.contains(":") || h.hasPrefix("[") { return nil }               // IPv6
        for local in [".local", ".lan", ".home", ".internal", ".localdomain", ".arpa"] where h.hasSuffix(local) { return nil }
        guard h.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }) else { return nil }
        return h
    }

    /// The hosts worth asking, once each, for a set of records.
    public static func hosts(for entries: [Entry]) -> [String] {
        let index = labelIndex(entries)
        var seen = Set<String>()
        var out: [String] = []
        for e in entries where !e.isDeleted {
            guard let h = logoHost(for: e, index: index), seen.insert(h).inserted else { continue }
            out.append(h)
        }
        return out.sorted()
    }

    // MARK: Which site's logo a record shows

    /// In order: the website Nino chose; nothing if he chose his own icon; a login's own website;
    /// for a login with no website, a site already in the vault whose name matches the title, then
    /// the built-in brand list. Never a guessed address: "Front Door Key" is not frontdoorkey.com.
    public static func logoHost(for e: Entry, index: [String: String]) -> String? {
        if let s = e.logoSite, let h = fetchableHost(s) { return h }
        guard e.icon == nil, e.type == .login else { return nil }
        if let h = e.urls.first.flatMap(fetchableHost) { return h }
        if genericSymbol(for: e) != nil { return nil }   // "Edgbarrow WiFi" is Wi-Fi, not a school logo
        for key in nameKeys(e.title) {
            if let h = index[key] { return h }
            if let h = knownBrands[key] { return h }
        }
        // Any word that is a well-known brand: "Debbies Apple Account" -> apple.com, "HP printer" -> hp.com.
        for word in e.title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let w = word.lowercased()
            if w.count >= 2, !vagueWords.contains(w), let h = knownBrands[w] { return h }
        }
        return nil
    }

    // MARK: Generic symbols (no network)

    /// Title words that say what kind of thing a record is, and the SF Symbol for it. First match wins.
    static let genericWords: [(words: Set<String>, symbol: String)] = [
        (["wifi", "wlan", "ssid", "broadband", "hotspot"], "wifi"),
        (["alarm"], "bell.fill"),
        (["key", "keys", "keysafe", "keybox"], "key.fill"),
        (["door", "gate", "garage"], "door.left.hand.closed"),
        (["lock", "padlock", "combination"], "lock.fill"),
        (["printer"], "printer.fill"),
        (["router", "nas", "modem"], "wifi.router"),
    ]

    /// A standard symbol for logins and notes with no real website, from a word in the title, or
    /// a router for a login at an IP address. Nil when Nino chose an icon or a logo site.
    public static func genericSymbol(for e: Entry) -> String? {
        guard e.icon == nil, e.logoSite == nil, e.type == .login || e.type == .secureNote else { return nil }
        if e.urls.first.flatMap(fetchableHost) != nil { return nil }
        var words = Set(e.title.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        if words.contains("wi") && words.contains("fi") { words.insert("wifi") }   // "Wi-Fi", "Wi Fi"
        for g in genericWords where !g.words.isDisjoint(with: words) { return g.symbol }
        let site = AppleImport.host(e.urls.first ?? "")
        if !site.isEmpty, site.allSatisfy({ $0.isNumber || $0 == "." }) { return "wifi.router" }   // 192.168.1.1
        if e.title.allSatisfy({ $0.isNumber || $0 == "." }), e.title.contains(".") { return "wifi.router" }
        return nil
    }

    /// "account.bbc.com" -> "bbc", "amazon.co.uk" -> "amazon", "britishairways.com" -> "britishairways".
    public static func label(ofHost host: String) -> String {
        var parts = host.lowercased().split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return parts.first ?? "" }
        parts.removeLast()                                    // com, uk, org, de ...
        if parts.count >= 2, ["co", "org", "ac", "gov", "net", "com", "ltd", "plc", "me", "nhs"].contains(parts.last!) {
            parts.removeLast()                                // co.uk, org.uk, gov.uk ...
        }
        return parts.last ?? ""
    }

    /// Site label -> host, for every real website already in the vault. The shortest host wins.
    public static func labelIndex(_ entries: [Entry]) -> [String: String] {
        var index: [String: String] = [:]
        for e in entries where !e.isDeleted {
            guard let h = e.urls.first.flatMap(fetchableHost) else { continue }
            let l = label(ofHost: h)
            guard l.count >= 3 else { continue }
            if let old = index[l], old.count <= h.count { continue }
            index[l] = h
        }
        return index
    }

    /// Words that say nothing about which site a record is for.
    public static let vagueWords: Set<String> = ["my", "the", "old", "new", "home", "front", "back", "main", "work", "church",
                                          "admin", "test", "personal", "account", "login", "app", "card", "wifi",
                                          "door", "key", "code", "alarm", "debbie", "nino", "glass"]

    /// "British Airways Debbie" -> ["britishairwaysdebbie", "britishairways", "british"]: the whole
    /// name, then dropping a word from the end each time. Letters and digits only. Vague words and
    /// keys shorter than three letters are left out.
    public static func nameKeys(_ title: String) -> [String] {
        let words = title.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        var keys: [String] = []
        var seen = Set<String>()
        for n in stride(from: words.count, through: 1, by: -1) {
            let k = words[0..<n].joined()
            if k.count >= 3, !vagueWords.contains(k), seen.insert(k).inserted { keys.append(k) }
        }
        return keys
    }

    /// Well-known names and their real websites, written in by hand. Only an exact match counts.
    public static let knownBrands: [String: String] = [
        "amazon": "amazon.co.uk", "amazonprime": "amazon.co.uk", "apple": "apple.com", "google": "google.com",
        "microsoft": "microsoft.com", "netflix": "netflix.com", "disneyplus": "disneyplus.com", "spotify": "spotify.com",
        "paypal": "paypal.com", "ebay": "ebay.co.uk", "dropbox": "dropbox.com", "facebook": "facebook.com",
        "instagram": "instagram.com", "linkedin": "linkedin.com", "whatsapp": "whatsapp.com", "zoom": "zoom.us",
        "adobe": "adobe.com", "bbc": "bbc.co.uk", "bbcsport": "bbc.co.uk", "bbcgoodfood": "bbcgoodfood.com",
        "hp": "hp.com", "ee": "ee.co.uk", "o2": "o2.co.uk", "godivachocolates": "godiva.com",
        "hiltonhonours": "hilton.com", "garminconnect": "garmin.com", "garminexpress": "garmin.com",
        "bosch": "bosch.com", "boschhomeconnect": "home-connect.com", "homeconnect": "home-connect.com", "britishairways": "britishairways.com", "easyjet": "easyjet.com", "ryanair": "ryanair.com",
        "trainline": "thetrainline.com", "airbnb": "airbnb.co.uk", "booking": "booking.com", "hilton": "hilton.com",
        "hiltonhonors": "hilton.com", "marriott": "marriott.com", "uber": "uber.com",
        "deliveroo": "deliveroo.co.uk", "justeat": "just-eat.co.uk", "dominos": "dominos.co.uk", "costa": "costa.co.uk",
        "costacoffee": "costa.co.uk", "tesco": "tesco.com", "sainsburys": "sainsburys.co.uk", "asda": "asda.com",
        "waitrose": "waitrose.com", "ocado": "ocado.com", "johnlewis": "johnlewis.com", "argos": "argos.co.uk",
        "boots": "boots.com", "ikea": "ikea.com", "currys": "currys.co.uk", "barclays": "barclays.co.uk",
        "hsbc": "hsbc.co.uk", "natwest": "natwest.com", "lloyds": "lloydsbank.com", "santander": "santander.co.uk",
        "nationwide": "nationwide.co.uk", "halifax": "halifax.co.uk", "firstdirect": "firstdirect.com",
        "monzo": "monzo.com", "starling": "starlingbank.com", "virginmedia": "virginmedia.com", "bt": "bt.com",
        "sky": "sky.com", "vodafone": "vodafone.co.uk", "giffgaff": "giffgaff.com", "britishgas": "britishgas.co.uk",
        "octopus": "octopus.energy", "experian": "experian.co.uk", "clearscore": "clearscore.com",
        "hargreaveslansdown": "hl.co.uk", "garmin": "garmin.com", "strava": "strava.com", "wiggle": "wiggle.com",
        "chainreaction": "chainreactioncycles.com", "evanscycles": "evanscycles.com", "gear4music": "gear4music.com",
        "fender": "fender.com", "cleanmymac": "macpaw.com", "flipboard": "flipboard.com", "godiva": "godiva.com",
        "nhs": "nhs.uk", "hmrc": "gov.uk", "dvla": "gov.uk", "companieshouse": "gov.uk", "congestioncharge": "tfl.gov.uk",
        "tfl": "tfl.gov.uk", "britishfencing": "britishfencing.com", "gigaclear": "gigaclear.com",
    ]

    // MARK: Redraw

    /// Decodes an image once and redraws it to a square PNG. The site's original bytes are never kept.
    /// Returns nil for anything that is not a usable image.
    public static func normalise(_ data: Data) -> Data? { normalise(data, limit: maxBytes, side: pixelSize) }

    /// A picture Nino pasted (a screen grab of a logo). Any size in, a 128 by 128 PNG out,
    /// typically a few kilobytes, so it can live on the record and travel with backups.
    public static let pastedSize = 128
    public static func normalisePasted(_ data: Data) -> Data? {
        normalise(data, limit: 50_000_000, side: pastedSize, padWithEdge: true)
    }

    /// A logo copied from another devPassword record: already a clean square, so no trimming or
    /// padding, just redrawn to the stored size (still decoded fresh, never stored as given).
    public static func normaliseCopied(_ data: Data) -> Data? {
        normalise(data, limit: 5_000_000, side: pastedSize, padWithEdge: false)
    }

    /// The average colour of an image's four corners, for filling the gaps when a wide or tall
    /// picture is fitted into a square (the Amex box stays blue, no white bars).
    static func edgeColour(_ img: CGImage) -> CGColor? {
        let side = 8
        var px = [UInt8](repeating: 0, count: side * side * 4)
        let ok: Bool = px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard ok else { return nil }
        var r = 0.0, g = 0.0, b = 0.0, a = 0.0
        for (x, y) in [(0, 0), (side - 1, 0), (0, side - 1), (side - 1, side - 1)] {
            let i = (y * side + x) * 4
            r += Double(px[i]); g += Double(px[i + 1]); b += Double(px[i + 2]); a += Double(px[i + 3])
        }
        guard a / 4 > 200 else { return nil }   // transparent corners: leave the gaps clear
        return CGColor(srgbRed: r / 4 / 255, green: g / 4 / 255, blue: b / 4 / 255, alpha: 1)
    }

    /// Cuts off a plain border (white page, or any single colour) around a pasted grab, so a loose
    /// grab gives the same result as a tight one. Returns the image unchanged if there is no border
    /// or if trimming would leave almost nothing.
    static func trimBorder(_ img: CGImage) -> CGImage {
        let w = img.width, h = img.height
        guard w > 8, h > 8 else { return img }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return img }
        // Row 0 in the buffer is the top of the picture.
        func at(_ x: Int, _ y: Int) -> (Int, Int, Int, Int) {
            let i = (y * w + x) * 4
            return (Int(px[i]), Int(px[i + 1]), Int(px[i + 2]), Int(px[i + 3]))
        }
        let corners = [at(0, 0), at(w - 1, 0), at(0, h - 1), at(w - 1, h - 1)]
        let bg = (corners.map(\.0).reduce(0, +) / 4, corners.map(\.1).reduce(0, +) / 4,
                  corners.map(\.2).reduce(0, +) / 4, corners.map(\.3).reduce(0, +) / 4)
        func isBackground(_ p: (Int, Int, Int, Int)) -> Bool {
            abs(p.0 - bg.0) + abs(p.1 - bg.1) + abs(p.2 - bg.2) + abs(p.3 - bg.3) < 60
        }
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where !isBackground(at(x, y)) {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY, maxX - minX >= 8, maxY - minY >= 8 else { return img }
        if minX == 0 && minY == 0 && maxX == w - 1 && maxY == h - 1 { return img }
        return img.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) ?? img
    }

    static func normalise(_ data: Data, limit: Int, side: Int, padWithEdge: Bool = false) -> Data? {
        guard data.count <= limit,
              let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let count = CGImageSourceGetCount(src)
        guard count > 0 else { return nil }
        // .ico files hold several sizes: take the largest.
        var best = 0, bestWidth = 0
        for i in 0..<count {
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let w = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
            if w > bestWidth { best = i; bestWidth = w }
        }
        guard bestWidth >= 16 else { return nil }
        // A pasted grab is read larger, trimmed of any plain border, then drawn down to size.
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceThumbnailMaxPixelSize: padWithEdge ? 512 : side,
                                     kCGImageSourceCreateThumbnailWithTransform: true]
        guard let read = CGImageSourceCreateThumbnailAtIndex(src, best, opts as CFDictionary) else { return nil }
        let img = padWithEdge ? trimBorder(read) : read

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        if padWithEdge, img.width != img.height, let edge = edgeColour(img) {
            ctx.setFillColor(edge)
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
        let scale = min(Double(side) / Double(img.width), Double(side) / Double(img.height))
        let w = Double(img.width) * scale, h = Double(img.height) * scale
        ctx.draw(img, in: CGRect(x: (Double(side) - w) / 2, y: (Double(side) - h) / 2, width: w, height: h))
        guard let out = ctx.makeImage() else { return nil }

        let buffer = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(buffer, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, out, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return buffer as Data
    }

    // MARK: Fetch

    /// Asks one host for its icon. Never throws: a failure is simply no logo.
    public static func fetch(host: String) async -> Data? {
        let session = URLSession(configuration: sessionConfiguration(), delegate: SameHostRedirects(host: host), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        for h in candidates(host) {
            for path in paths {
                guard let url = URL(string: "https://\(h)\(path)") else { continue }
                if let raw = await download(url, session: session), let png = normalise(raw) { return png }
            }
        }
        return nil
    }

    /// Where to ask, in order. A bare domain: www. first, then plain. A sub-site such as
    /// account.bbc.com: itself, then its main site (www.bbc.com, bbc.com), which usually has the icon.
    static func candidates(_ host: String) -> [String] {
        var out: [String] = []
        func add(_ h: String) { if !out.contains(h) { out.append(h) } }
        let main = registrable(host)
        if host == main { add("www." + host); add(host) }
        else { add(host); add("www." + main); add(main) }
        return out
    }

    /// "account.bbc.com" -> "bbc.com", "www.amazon.co.uk" -> "amazon.co.uk", "tfl.gov.uk" -> "tfl.gov.uk".
    public static func registrable(_ host: String) -> String {
        let parts = host.lowercased().split(separator: ".").map(String.init)
        guard parts.count > 2 else { return parts.joined(separator: ".") }
        let secondLevel: Set<String> = ["co", "org", "ac", "gov", "net", "com", "ltd", "plc", "me", "nhs", "sch", "police"]
        let keep = parts[parts.count - 1].count == 2 && secondLevel.contains(parts[parts.count - 2]) ? 3 : 2
        return parts.suffix(keep).joined(separator: ".")
    }

    static func sessionConfiguration() -> URLSessionConfiguration {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.httpCookieAcceptPolicy = .never
        c.urlCache = nil
        c.urlCredentialStorage = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = timeout
        c.timeoutIntervalForResource = timeout * 2
        c.httpAdditionalHeaders = ["Accept": "image/avif,image/webp,image/png,image/svg+xml,image/*;q=0.8,*/*;q=0.5",
                                   "Accept-Language": "en-GB,en;q=0.9",
                                   "User-Agent": userAgent]
        return c
    }

    /// Reads at most maxBytes. Stops early on a bad status or an oversized body.
    static func download(_ url: URL, session: URLSession) async -> Data? {
        do {
            var req = URLRequest(url: url)
            req.httpShouldHandleCookies = false
            let (bytes, response) = try await session.bytes(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.url?.scheme == "https" else { return nil }
            if http.expectedContentLength > Int64(maxBytes) { return nil }
            var data = Data()
            for try await b in bytes {
                data.append(b)
                if data.count > maxBytes { return nil }
            }
            return data
        } catch {
            return nil
        }
    }

    /// Follows a redirect only to HTTPS on the same site (with or without www.).
    final class SameHostRedirects: NSObject, URLSessionTaskDelegate {
        let host: String
        init(host: String) { self.host = host }

        /// HTTPS to the same company only: same main name, e.g. bbc.com to www.bbc.co.uk.
        static func allowed(_ target: URL?, host: String) -> Bool {
            guard let t = target, t.scheme == "https", let th = t.host?.lowercased() else { return false }
            let a = SiteLogos.label(ofHost: th), b = SiteLogos.label(ofHost: host)
            return !a.isEmpty && a == b
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(Self.allowed(request.url, host: host) ? request : nil)
        }
    }
}

/// The logo cache: PNGs by host, plus hosts that had no icon and when they were asked.
public struct LogoCache: Codable {
    public var logos: [String: Data] = [:]
    public var misses: [String: Date] = [:]

    public init() {}

    /// Forget which sites had no logo, so the next fetch asks them again.
    public mutating func forgetMisses() { misses = [:] }

    /// Hosts to ask now: not cached, and not a recent miss.
    public func toFetch(_ hosts: [String], now: Date = Date()) -> [String] {
        hosts.filter { h in
            if logos[h] != nil { return false }
            if let m = misses[h], now.timeIntervalSince(m) < SiteLogos.missRetry { return false }
            return true
        }
    }
}

extension Vault {
    /// Beside the vault file. Not part of backups: logos can always be fetched again.
    public var logoCacheURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("logos.sealed")
    }

    /// Fails closed: a changed or swapped cache is ignored and refetched.
    public func loadLogos() -> LogoCache {
        guard let key = try? requireKey(), let sealed = sealedLogos(),
              let cache = Vault.openLogos(sealed, key: key, header: header) else { return LogoCache() }
        return cache
    }

    /// The sealed cache file as stored, for backups. Nil if there is none.
    func sealedLogos() -> Data? { try? Data(contentsOf: logoCacheURL) }

    static func openLogos(_ sealed: Data, key: SymmetricKey, header: VaultHeader) -> LogoCache? {
        guard let plain = try? VaultCrypto.open(sealed, key: key, context: header.logosContext()) else { return nil }
        return try? JSONDecoder().decode(LogoCache.self, from: plain)
    }

    public func saveLogos(_ cache: LogoCache) throws {
        let key = try requireKey()
        let sealed = try VaultCrypto.seal(try JSONEncoder().encode(cache), key: key, context: header.logosContext())
        try sealed.write(to: logoCacheURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: logoCacheURL.path)
        Log.vault.info("event=logos.saved count=\(cache.logos.count, privacy: .public)")
    }
}
