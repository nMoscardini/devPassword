import SwiftUI
import AppKit
import DevPasswordUI

/// `swift run DevPasswordMac` entry point. Touch ID needs the signed app in App/ instead.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when running from the Swift package so the window takes keyboard focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct DevPasswordPackageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene { DevPasswordScenes() }
}

DevPasswordPackageApp.main()
