//
//  devPasswordApp.swift
//  devPassword
//
//  Signed Mac app (Touch ID). All screens and logic live in the Swift package
//  (DevPasswordUI and VaultCore). Keep this file a thin wrapper.
//

import SwiftUI
import DevPasswordUI

@main
struct devPasswordApp: App {
    var body: some Scene {
        DevPasswordScenes()
    }
}
