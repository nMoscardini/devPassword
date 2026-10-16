import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import VaultCore

/// Decision 0009. No network in tests: fetching itself is checked by hand.
final class SiteLogoTests: XCTestCase {
    func testOnlyRealSitesAreAsked() {
        XCTAssertEqual(SiteLogos.fetchableHost("https://www.example.com/login"), "example.com")
        XCTAssertNil(SiteLogos.fetchableHost("http://192.168.1.1/"))
        XCTAssertNil(SiteLogos.fetchableHost("https://[::1]/"))
        XCTAssertNil(SiteLogos.fetchableHost("http://router/"))
        XCTAssertNil(SiteLogos.fetchableHost("http://nas.local/"))
        XCTAssertNil(SiteLogos.fetchableHost("http://"))
        XCTAssertNil(SiteLogos.fetchableHost(""))
        XCTAssertNil(SiteLogos.fetchableHost("https://bad host.com/"))
    }

    func testHostsAreUniqueAndFromLoginsOnly() {
        var a = Entry(type: .login, title: "a"); a.urls = ["https://www.a.test/x"]
        var a2 = Entry(type: .login, title: "a2"); a2.urls = ["https://a.test/"]
        var note = Entry(type: .secureNote, title: "n"); note.urls = ["https://n.test/"]
        var gone = Entry(type: .login, title: "g"); gone.urls = ["https://g.test/"]; gone.deletedAt = Date()
        XCTAssertEqual(SiteLogos.hosts(for: [a, a2, note, gone]), ["a.test"])
    }

    func testSiteLabels() {
        XCTAssertEqual(SiteLogos.label(ofHost: "account.bbc.com"), "bbc")
        XCTAssertEqual(SiteLogos.label(ofHost: "amazon.co.uk"), "amazon")
        XCTAssertEqual(SiteLogos.label(ofHost: "britishairways.com"), "britishairways")
        XCTAssertEqual(SiteLogos.label(ofHost: "access.login.nhs.uk"), "login")
    }

    func testNameKeys() {
        XCTAssertEqual(SiteLogos.nameKeys("BBC Sport"), ["bbcsport", "bbc"])
        XCTAssertEqual(SiteLogos.nameKeys("British Airways- Debbie"), ["britishairwaysdebbie", "britishairways", "british"])
        XCTAssertEqual(SiteLogos.nameKeys("British Airways Debbie"), ["britishairwaysdebbie", "britishairways", "british"])
        XCTAssertEqual(SiteLogos.nameKeys("Front Door Key"), ["frontdoorkey", "frontdoor"])
        XCTAssertEqual(SiteLogos.nameKeys("My"), [])
    }

    func testLogoFromTheName() {
        func login(_ title: String, _ url: String? = nil) -> Entry {
            var e = Entry(type: .login, title: title)
            if let url { e.urls = [url] }
            return e
        }
        let vault = [login("x", "https://www.amazon.co.uk/"), login("y", "https://account.bbc.com/"),
                     login("z", "https://www.britishairways.com/")]
        let index = SiteLogos.labelIndex(vault)
        XCTAssertEqual(SiteLogos.logoHost(for: login("Amazon"), index: index), "amazon.co.uk", "site already in the vault")
        XCTAssertEqual(SiteLogos.logoHost(for: login("BBC Sport"), index: index), "bbc.co.uk", "built-in list wins over first word")
        XCTAssertEqual(SiteLogos.logoHost(for: login("British Airways- Debbie"), index: index), "britishairways.com")
        XCTAssertEqual(SiteLogos.logoHost(for: login("Bosch"), index: [:]), "bosch.com", "built-in list")
        XCTAssertEqual(SiteLogos.logoHost(for: login("British Airways Debbie"), index: index), "britishairways.com")
        XCTAssertEqual(SiteLogos.logoHost(for: login("Bosch home connect"), index: [:]), "home-connect.com")
        XCTAssertNil(SiteLogos.logoHost(for: login("Front Door Key"), index: index), "never a guessed address")
        XCTAssertNil(SiteLogos.logoHost(for: login("Amazon", "http://192.168.1.1/"), index: [:]),
                     "an IP address is a router: generic symbol, never a logo fetch")
        XCTAssertEqual(SiteLogos.genericSymbol(for: login("Amazon", "http://192.168.1.1/")), "wifi.router")

        XCTAssertEqual(SiteLogos.logoHost(for: login("Debbies Apple Account"), index: [:]), "apple.com", "any word")
        XCTAssertEqual(SiteLogos.logoHost(for: login("Congestion Charge"), index: [:]), "tfl.gov.uk")
        XCTAssertEqual(SiteLogos.candidates("bosch.com"), ["www.bosch.com", "bosch.com"])
        XCTAssertEqual(SiteLogos.candidates("tfl.gov.uk"), ["www.tfl.gov.uk", "tfl.gov.uk"])
        XCTAssertEqual(SiteLogos.candidates("account.bbc.com"), ["account.bbc.com", "www.bbc.com", "bbc.com"])
        XCTAssertEqual(SiteLogos.candidates("www.amazon.co.uk"), ["www.amazon.co.uk", "amazon.co.uk"])
        XCTAssertEqual(SiteLogos.registrable("signin.aws.amazon.com"), "amazon.com")

        var own = login("Amazon"); own.icon = "cart"
        XCTAssertNil(SiteLogos.logoHost(for: own, index: index), "Nino's own icon wins")
        var card = Entry(type: .paymentCard, title: "Barclaycard"); card.logoSite = "https://www.barclaycard.co.uk"
        XCTAssertEqual(SiteLogos.logoHost(for: card, index: index), "barclaycard.co.uk", "chosen website, any type")
        XCTAssertNil(SiteLogos.logoHost(for: Entry(type: .paymentCard, title: "Amazon"), index: index),
                     "other types only by choice")
        XCTAssertEqual(SiteLogos.hosts(for: vault + [login("Bosch")]),
                       ["amazon.co.uk", "account.bbc.com", "bosch.com", "britishairways.com"].sorted())
    }

    func testGenericSymbols() {
        func rec(_ title: String, _ type: RecordType = .login, url: String? = nil) -> Entry {
            var e = Entry(type: type, title: title)
            if let url { e.urls = [url] }
            return e
        }
        XCTAssertEqual(SiteLogos.genericSymbol(for: rec("Edgbarrow WiFi")), "wifi")
        XCTAssertEqual(SiteLogos.genericSymbol(for: rec("Home Wi-Fi")), "wifi")
        XCTAssertEqual(SiteLogos.genericSymbol(for: rec("Emily&Nick Alarm")), "bell.fill")
        XCTAssertEqual(SiteLogos.genericSymbol(for: rec("Front Door Key")), "key.fill", "key before door")
        XCTAssertEqual(SiteLogos.genericSymbol(for: rec("Glass door")), "door.left.hand.closed")
        XCTAssertEqual(SiteLogos.genericSymbol(for: rec("Alarm code", .secureNote)), "bell.fill")
        XCTAssertEqual(SiteLogos.genericSymbol(for: rec("192.168.1.1", url: "http://192.168.1.1/")), "wifi.router")
        XCTAssertNil(SiteLogos.genericSymbol(for: rec("Keystone", url: "https://keystone.com/")), "real website wins")
        XCTAssertNil(SiteLogos.genericSymbol(for: rec("Monkey business")), "whole words only")
        XCTAssertNil(SiteLogos.genericSymbol(for: rec("Door Card", .paymentCard)), "other types keep their icon")
        XCTAssertNil(SiteLogos.logoHost(for: rec("Edgbarrow WiFi"), index: ["edgbarrow": "edgbarrow.school"]))
        XCTAssertEqual(SiteLogos.logoHost(for: rec("HP"), index: [:]), "hp.com")
        XCTAssertEqual(SiteLogos.logoHost(for: rec("Godiva Chocolates"), index: [:]), "godiva.com")
    }

    func testRedrawsToSquarePNG() throws {
        let png = try makePNG(width: 180, height: 120)
        let out = try XCTUnwrap(SiteLogos.normalise(png))
        let src = try XCTUnwrap(CGImageSourceCreateWithData(out as CFData, nil))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        XCTAssertEqual(img.width, 64)
        XCTAssertEqual(img.height, 64)
        XCTAssertNotEqual(out, png, "the original bytes are never kept")
    }

    func testPastedPictureIsShrunkWhateverItsSize() throws {
        let big = try makeNoisyPNG(width: 900, height: 500)
        XCTAssertGreaterThan(big.count, SiteLogos.maxBytes, "a screen grab is bigger than a fetched icon may be")
        let out = try XCTUnwrap(SiteLogos.normalisePasted(big))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(try XCTUnwrap(CGImageSourceCreateWithData(out as CFData, nil)), 0, nil))
        XCTAssertEqual(img.width, SiteLogos.pastedSize)
        XCTAssertEqual(img.height, SiteLogos.pastedSize)
        XCTAssertLessThan(out.count, 80_000)

        // A wide solid-blue grab fills the whole square with blue: no white or clear bars.
        let wide = try XCTUnwrap(SiteLogos.normalisePasted(try makePNG(width: 300, height: 120)))
        let wimg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(try XCTUnwrap(CGImageSourceCreateWithData(wide as CFData, nil)), 0, nil))
        var corner = [UInt8](repeating: 0, count: 4)
        corner.withUnsafeMutableBytes { buf in
            let c = CGContext(data: buf.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            c.draw(wimg, in: CGRect(x: 0, y: -Double(wimg.height) + 1, width: Double(wimg.width), height: Double(wimg.height)))
        }
        XCTAssertGreaterThan(corner[3], 200, "top-left corner is filled, not transparent")
        XCTAssertGreaterThan(corner[2], corner[0], "and it is the picture's blue")

        // A loose grab: a blue logo on a white page. The white is trimmed away; corners end up blue.
        let loose = try makeLogoOnPage(page: 400, logoW: 200, logoH: 80)
        let trimmed = try XCTUnwrap(SiteLogos.normalisePasted(loose))
        let timg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(try XCTUnwrap(CGImageSourceCreateWithData(trimmed as CFData, nil)), 0, nil))
        var tc = [UInt8](repeating: 0, count: 4)
        tc.withUnsafeMutableBytes { buf in
            let c = CGContext(data: buf.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            c.draw(timg, in: CGRect(x: 0, y: -Double(timg.height) + 1, width: Double(timg.width), height: Double(timg.height)))
        }
        XCTAssertGreaterThan(tc[2], 150, "corner is the logo's blue")
        XCTAssertLessThan(tc[0], 120, "not the white page")

        let (vault, _) = try makeVault()
        var e = Entry(type: .secureNote, title: "Front door")
        e.customLogo = out
        try vault.save(e)
        XCTAssertEqual(try vault.loadAll().entries.first?.customLogo, out, "kept with the record")
    }

    /// A blue rectangle in the middle of a white square "page", like a loose screen grab.
    private func makeLogoOnPage(page: Int, logoW: Int, logoH: Int) throws -> Data {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: page, height: page, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: page, height: page))
        ctx.setFillColor(CGColor(red: 0.0, green: 0.4, blue: 0.85, alpha: 1))
        ctx.fill(CGRect(x: (page - logoW) / 2, y: (page - logoH) / 2, width: logoW, height: logoH))
        let img = try XCTUnwrap(ctx.makeImage())
        let buf = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(buf, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, img, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return buf as Data
    }

    private func makeNoisyPNG(width: Int, height: Int) throws -> Data {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        var rng = SystemRandomNumberGenerator()
        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) {
                ctx.setFillColor(CGColor(red: .random(in: 0...1, using: &rng), green: .random(in: 0...1, using: &rng),
                                         blue: .random(in: 0...1, using: &rng), alpha: 1))
                ctx.fill(CGRect(x: x, y: y, width: 2, height: 2))
            }
        }
        let img = try XCTUnwrap(ctx.makeImage())
        let buf = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(buf, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, img, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return buf as Data
    }

    func testRejectsJunkTinyAndOversized() throws {
        XCTAssertNil(SiteLogos.normalise(Data("<html>not an image</html>".utf8)))
        XCTAssertNil(SiteLogos.normalise(try makePNG(width: 8, height: 8)))
        XCTAssertNil(SiteLogos.normalise(Data(count: SiteLogos.maxBytes + 1)))
    }

    func testRedirectsStayOnTheSameSite() {
        typealias R = SiteLogos.SameHostRedirects
        XCTAssertTrue(R.allowed(URL(string: "https://www.a.test/icon.png"), host: "a.test"))
        XCTAssertTrue(R.allowed(URL(string: "https://a.test/icon.png"), host: "www.a.test"))
        XCTAssertTrue(R.allowed(URL(string: "https://www.bbc.co.uk/favicon.ico"), host: "bbc.com"), "same company")
        XCTAssertFalse(R.allowed(URL(string: "http://a.test/icon.png"), host: "a.test"))
        XCTAssertFalse(R.allowed(URL(string: "https://cdn.other.test/icon.png"), host: "a.test"))
    }

    func testCacheIsSealedAndSkipsRecentMisses() throws {
        let (vault, _) = try makeVault()
        var cache = LogoCache()
        cache.logos["a.test"] = try makePNG(width: 64, height: 64)
        cache.misses["b.test"] = Date()
        cache.misses["c.test"] = Date().addingTimeInterval(-SiteLogos.missRetry - 60)
        try vault.saveLogos(cache)

        let raw = try Data(contentsOf: vault.logoCacheURL)
        XCTAssertNil(raw.range(of: Data("a.test".utf8)), "host names are not readable on disk")

        let back = vault.loadLogos()
        XCTAssertEqual(back.logos.keys.sorted(), ["a.test"])
        XCTAssertEqual(back.toFetch(["a.test", "b.test", "c.test", "d.test"]), ["c.test", "d.test"])

        try Data(repeating: 7, count: raw.count).write(to: vault.logoCacheURL)
        XCTAssertTrue(vault.loadLogos().logos.isEmpty, "a damaged cache is ignored, never trusted")

        vault.lock()
        XCTAssertTrue(vault.loadLogos().logos.isEmpty, "unreadable while locked")
    }

    func testCopiedLogoIsNotTrimmed() throws {
        // A logo with a white page round it: pasted from outside it is trimmed, copied from devPassword it is not.
        let page = try makeLogoOnPage(page: 128, logoW: 64, logoH: 24)
        let copied = try XCTUnwrap(SiteLogos.normaliseCopied(page))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(try XCTUnwrap(CGImageSourceCreateWithData(copied as CFData, nil)), 0, nil))
        var c = [UInt8](repeating: 0, count: 4)
        c.withUnsafeMutableBytes { buf in
            let ctx = CGContext(data: buf.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(img, in: CGRect(x: 0, y: -Double(img.height) + 1, width: Double(img.width), height: Double(img.height)))
        }
        XCTAssertGreaterThan(c[0], 200, "corner stays the white page: no trimming")
        XCTAssertEqual(img.width, SiteLogos.pastedSize)
    }

    func testLogosTravelWithBackups() throws {
        let dir = tempDir()
        let (vault, _) = try makeVault(in: dir)
        var cache = LogoCache()
        cache.logos["a.test"] = try makePNG(width: 64, height: 64)
        try vault.saveLogos(cache)

        let url = try Backup.writeToFolder(vault: vault, folder: dir.appendingPathComponent("backups"))
        let archive = try Backup.read(from: url)
        XCTAssertNotNil(archive.sealedLogos)
        let opened = try Backup.open(archive, passphrase: testPassphrase)

        let target = tempDir().appendingPathComponent("vault.sqlite")
        try Backup.restore(opened, to: target)
        let restored = try Vault.open(at: target)
        try restored.unlock(passphrase: testPassphrase)
        XCTAssertEqual(restored.loadLogos().logos.keys.sorted(), ["a.test"], "logos come back with a restore")

        // A tampered logo block is refused, like a tampered record.
        var bad = archive
        bad.sealedLogos = Data(repeating: 1, count: 64)
        XCTAssertThrowsError(try Backup.open(bad, passphrase: testPassphrase))
    }

    private func makePNG(width: Int, height: Int) throws -> Data {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let img = try XCTUnwrap(ctx.makeImage())
        let buf = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(buf, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, img, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return buf as Data
    }
}
