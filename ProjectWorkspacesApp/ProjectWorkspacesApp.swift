import AppKit
import SwiftUI

import ProjectWorkspacesCore

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
    private var doctorWindow: NSWindow?
    private var doctorTextView: NSTextView?

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

    /// Runs Doctor and presents the report in a modal-style panel.
    @objc private func runDoctor() {
        let report = Doctor().run().rendered()
        showDoctorReport(report)
    }

    /// Terminates the app.
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    /// Displays the Doctor report in a scrollable, selectable text view.
    /// - Parameter report: Rendered Doctor report string.
    private func showDoctorReport(_ report: String) {
        let textView: NSTextView
        let window: NSWindow

        if let existingWindow = doctorWindow, let existingTextView = doctorTextView {
            window = existingWindow
            textView = existingTextView
        } else {
            let panel = makeDoctorPanel()
            textView = makeDoctorTextView()
            let scrollView = NSScrollView(frame: panel.contentView?.bounds ?? .zero)
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.autoresizingMask = [.width, .height]
            scrollView.documentView = textView
            panel.contentView = scrollView
            panel.isReleasedWhenClosed = false

            doctorWindow = panel
            doctorTextView = textView
            window = panel
        }

        textView.string = report
        textView.scrollToBeginningOfDocument(nil)

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Creates the Doctor panel window.
    /// - Returns: Configured panel instance.
    private func makeDoctorPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Doctor report"
        panel.center()
        return panel
    }

    /// Creates a selectable, non-editable text view for Doctor output.
    /// - Returns: Configured text view instance.
    private func makeDoctorTextView() -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textContainer?.widthTracksTextView = true
        return textView
    }
}
