import AppKit
import SwiftUI

@main
struct ProjectWorkspacesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

/// App lifecycle hook used to create a minimal menu bar presence.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "PW"
        statusItem.menu = makeMenu()
        self.statusItem = statusItem
    }

    /// Creates the menu bar menu.
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(
            NSMenuItem(
                title: "Run Doctor…",
                action: #selector(runDoctor),
                keyEquivalent: "d"
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit",
                action: #selector(quit),
                keyEquivalent: "q"
            )
        )

        return menu
    }

    /// Placeholder for the Phase 0 in-app "Run Doctor" action.
    @objc private func runDoctor() {
        NSLog("Run Doctor clicked (not implemented yet)")
    }

    /// Terminates the app.
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

