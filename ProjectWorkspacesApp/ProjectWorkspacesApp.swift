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

private struct DoctorButtons {
    let runDoctor: NSButton
    let copyReport: NSButton
    let installAeroSpace: NSButton
    let installSafeConfig: NSButton
    let startAeroSpace: NSButton
    let reloadConfig: NSButton
    let disableAeroSpace: NSButton
    let uninstallSafeConfig: NSButton
    let close: NSButton
}

/// App lifecycle hook used to create a minimal menu bar presence.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var doctorWindow: NSWindow?
    private var doctorTextView: NSTextView?
    private var doctorButtons: DoctorButtons?
    private var lastDoctorReport: DoctorReport?

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
                title: "Run Doctor...",
                action: #selector(runDoctor),
                keyEquivalent: "d"
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "Emergency: Disable AeroSpace",
                action: #selector(disableAeroSpace),
                keyEquivalent: ""
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
        let report = Doctor().run()
        showDoctorReport(report)
    }

    /// Copies the current Doctor report to the clipboard.
    @objc private func copyDoctorReport() {
        guard let report = lastDoctorReport?.rendered() else {
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report, forType: .string)
    }

    /// Installs AeroSpace via Homebrew and refreshes the report.
    @objc private func installAeroSpace() {
        let report = Doctor().installAeroSpace()
        showDoctorReport(report)
    }

    /// Installs the safe AeroSpace config and refreshes the report.
    @objc private func installSafeAeroSpaceConfig() {
        let report = Doctor().installSafeAeroSpaceConfig()
        showDoctorReport(report)
    }

    /// Starts AeroSpace and refreshes the report.
    @objc private func startAeroSpace() {
        let report = Doctor().startAeroSpace()
        showDoctorReport(report)
    }

    /// Reloads AeroSpace config and refreshes the report.
    @objc private func reloadAeroSpaceConfig() {
        let report = Doctor().reloadAeroSpaceConfig()
        showDoctorReport(report)
    }

    /// Disables AeroSpace window management and refreshes the report.
    @objc private func disableAeroSpace() {
        let report = Doctor().disableAeroSpace()
        showDoctorReport(report)
    }

    /// Uninstalls the safe AeroSpace config and refreshes the report.
    @objc private func uninstallSafeAeroSpaceConfig() {
        let report = Doctor().uninstallSafeAeroSpaceConfig()
        showDoctorReport(report)
    }

    /// Closes the Doctor window.
    @objc private func closeDoctorWindow() {
        doctorWindow?.close()
    }

    /// Terminates the app.
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    /// Displays the Doctor report in a scrollable, selectable text view.
    /// - Parameter report: Doctor report payload.
    private func showDoctorReport(_ report: DoctorReport) {
        let textView: NSTextView
        let window: NSWindow

        if let existingWindow = doctorWindow, let existingTextView = doctorTextView {
            window = existingWindow
            textView = existingTextView
        } else {
            let panel = makeDoctorPanel()
            let textViewInstance = makeDoctorTextView()
            let buttons = makeDoctorButtons()
            let contentView = makeDoctorContentView(textView: textViewInstance, buttons: buttons)
            panel.contentView = contentView
            panel.isReleasedWhenClosed = false

            doctorWindow = panel
            doctorTextView = textViewInstance
            doctorButtons = buttons
            window = panel
            textView = textViewInstance
        }

        updateDoctorUI(with: report)

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func updateDoctorUI(with report: DoctorReport) {
        lastDoctorReport = report
        doctorTextView?.string = report.rendered()
        doctorTextView?.scrollToBeginningOfDocument(nil)

        if let buttons = doctorButtons {
            buttons.installAeroSpace.isEnabled = report.actions.canInstallAeroSpace
            buttons.installSafeConfig.isEnabled = report.actions.canInstallSafeAeroSpaceConfig
            buttons.startAeroSpace.isEnabled = report.actions.canStartAeroSpace
            buttons.reloadConfig.isEnabled = report.actions.canReloadAeroSpaceConfig
            buttons.disableAeroSpace.isEnabled = report.actions.canDisableAeroSpace
            buttons.uninstallSafeConfig.isHidden = !report.actions.canUninstallSafeAeroSpaceConfig
            buttons.uninstallSafeConfig.isEnabled = report.actions.canUninstallSafeAeroSpaceConfig
        }
    }

    /// Creates the Doctor panel window.
    /// - Returns: Configured panel instance.
    private func makeDoctorPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Doctor"
        panel.center()
        return panel
    }

    private func makeDoctorContentView(textView: NSTextView, buttons: DoctorButtons) -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 12
        container.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = textView
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)

        let primaryRow = makeButtonRow(buttons: [
            buttons.runDoctor,
            buttons.copyReport,
            buttons.installAeroSpace,
            buttons.installSafeConfig,
            buttons.startAeroSpace
        ])

        let secondaryRow = makeButtonRow(buttons: [
            buttons.reloadConfig,
            buttons.disableAeroSpace,
            buttons.uninstallSafeConfig,
            buttons.close
        ])

        container.addArrangedSubview(scrollView)
        container.addArrangedSubview(primaryRow)
        container.addArrangedSubview(secondaryRow)

        let contentView = NSView()
        contentView.addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])

        return contentView
    }

    private func makeButtonRow(buttons: [NSButton]) -> NSStackView {
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.distribution = .fillProportionally
        return row
    }

    private func makeDoctorButtons() -> DoctorButtons {
        let runDoctorButton = makeButton(title: "Run Doctor", action: #selector(runDoctor))
        let copyReportButton = makeButton(title: "Copy Report", action: #selector(copyDoctorReport))
        let installAeroSpaceButton = makeButton(title: "Install AeroSpace", action: #selector(installAeroSpace))
        let installSafeConfigButton = makeButton(
            title: "Install Safe AeroSpace Config",
            action: #selector(installSafeAeroSpaceConfig)
        )
        let startAeroSpaceButton = makeButton(title: "Start AeroSpace", action: #selector(startAeroSpace))
        let reloadConfigButton = makeButton(title: "Reload AeroSpace Config", action: #selector(reloadAeroSpaceConfig))
        let disableAeroSpaceButton = makeButton(
            title: "Emergency: Disable AeroSpace",
            action: #selector(disableAeroSpace)
        )
        let uninstallSafeConfigButton = makeButton(
            title: "Uninstall Safe AeroSpace Config",
            action: #selector(uninstallSafeAeroSpaceConfig)
        )
        let closeButton = makeButton(title: "Close", action: #selector(closeDoctorWindow))

        return DoctorButtons(
            runDoctor: runDoctorButton,
            copyReport: copyReportButton,
            installAeroSpace: installAeroSpaceButton,
            installSafeConfig: installSafeConfigButton,
            startAeroSpace: startAeroSpaceButton,
            reloadConfig: reloadConfigButton,
            disableAeroSpace: disableAeroSpaceButton,
            uninstallSafeConfig: uninstallSafeConfigButton,
            close: closeButton
        )
    }

    private func makeButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
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
