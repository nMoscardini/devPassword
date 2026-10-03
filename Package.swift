// swift-tools-version:5.9
// devPassword - Stage 1 local vault. Class: Personal (see SPEC.md).
import PackageDescription

let package = Package(
    name: "devPassword",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "VaultCore", targets: ["VaultCore"]),
        .library(name: "DevPasswordUI", targets: ["DevPasswordUI"]),
        .executable(name: "DevPasswordMac", targets: ["DevPasswordMac"]),
    ],
    targets: [
        // Shared core: model, crypto, storage, backup, CSV. No UI. Used by the Mac app now, iOS later.
        .target(name: "VaultCore"),
        // macOS user interface (SwiftUI). Shared by the signed Xcode app (App/) and swift run.
        .target(name: "DevPasswordUI", dependencies: ["VaultCore"]),
        // `swift run DevPasswordMac`: unsigned, no Touch ID.
        .executableTarget(name: "DevPasswordMac", dependencies: ["DevPasswordUI"]),
        .testTarget(name: "VaultCoreTests", dependencies: ["VaultCore"]),
    ]
)
