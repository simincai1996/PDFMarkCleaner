//
//  PDFMarkCleanerApp.swift
//  PDFMarkCleaner
//
//  Created by simin on 2/11/26.
//

import SwiftUI
import AppKit

@main
struct PDFMarkCleanerApp: App {
    init() {
        let icon = NSImage(named: "AppIcon") ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        icon.isTemplate = false
        NSApplication.shared.applicationIconImage = icon
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        Settings {
            SettingsView()
        }
    }
}
