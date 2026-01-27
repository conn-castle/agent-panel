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
    private var doctorStatusLabel: NSTextField?
    private var doctorProgressIndicator: NSProgressIndicator?
    private var lastDoctorReport: DoctorReport?
    private var isDoctorBusy = false

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
        runDoctorAction(statusMessage: "Running Doctor...") {
            Doctor().run()
        }
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
        runDoctorAction(statusMessage: "Installing AeroSpace...") {
            Doctor().installAeroSpace()
        }
    }

    /// Installs the safe AeroSpace config and refreshes the report.
    @objc private func installSafeAeroSpaceConfig() {
        runDoctorAction(statusMessage: "Installing safe AeroSpace config...") {
            Doctor().installSafeAeroSpaceConfig()
        }
    }

    /// Starts AeroSpace and refreshes the report.
    @objc private func startAeroSpace() {
        runDoctorAction(statusMessage: "Starting AeroSpace...") {
            Doctor().startAeroSpace()
        }
    }

    /// Reloads AeroSpace config and refreshes the report.
    @objc private func reloadAeroSpaceConfig() {
        runDoctorAction(statusMessage: "Reloading AeroSpace config...") {
            Doctor().reloadAeroSpaceConfig()
        }
    }

    /// Disables AeroSpace window management and refreshes the report.
    @objc private func disableAeroSpace() {
        runDoctorAction(statusMessage: "Disabling AeroSpace...") {
            Doctor().disableAeroSpace()
        }
    }

    /// Uninstalls the safe AeroSpace config and refreshes the report.
    @objc private func uninstallSafeAeroSpaceConfig() {
        runDoctorAction(statusMessage: "Uninstalling safe AeroSpace config...") {
            Doctor().uninstallSafeAeroSpaceConfig()
        }
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
        let window = ensureDoctorWindow()

        updateDoctorUI(with: report)

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func updateDoctorUI(with report: DoctorReport) {
        lastDoctorReport = report
        doctorTextView?.string = report.rendered()
        doctorTextView?.scrollToBeginningOfDocument(nil)

        if let buttons = doctorButtons {
            if isDoctorBusy {
                disableDoctorButtons()
                return
            }

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
        panel.hidesOnDeactivate = false
        return panel
    }

    private func makeDoctorContentView(
        textView: NSTextView,
        statusRow: NSView,
        buttons: DoctorButtons
    ) -> NSView {
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

        container.addArrangedSubview(statusRow)
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

    private func makeDoctorStatusRow() -> (view: NSView, label: NSTextField, indicator: NSProgressIndicator) {
        let indicator = NSProgressIndicator()
        indicator.style = .spinning
        indicator.controlSize = .small
        indicator.isDisplayedWhenStopped = false

        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)

        let row = NSStackView(views: [indicator, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8

        return (row, label, indicator)
    }

    private func runDoctorAction(statusMessage: String, action: @escaping () -> DoctorReport) {
        let window = ensureDoctorWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        guard !isDoctorBusy else {
            return
        }

        setDoctorBusy(true, message: statusMessage)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let report = action()
            DispatchQueue.main.async {
                self?.setDoctorBusy(false, message: nil)
                self?.showDoctorReport(report)
            }
        }
    }

    private func setDoctorBusy(_ isBusy: Bool, message: String?) {
        isDoctorBusy = isBusy
        doctorStatusLabel?.stringValue = message ?? ""
        if isBusy {
            doctorProgressIndicator?.startAnimation(nil)
            disableDoctorButtons()
        } else {
            doctorProgressIndicator?.stopAnimation(nil)
        }
    }

    private func disableDoctorButtons() {
        guard let buttons = doctorButtons else {
            return
        }

        buttons.runDoctor.isEnabled = false
        buttons.copyReport.isEnabled = false
        buttons.installAeroSpace.isEnabled = false
        buttons.installSafeConfig.isEnabled = false
        buttons.startAeroSpace.isEnabled = false
        buttons.reloadConfig.isEnabled = false
        buttons.disableAeroSpace.isEnabled = false
        buttons.uninstallSafeConfig.isEnabled = false
        buttons.close.isEnabled = true
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

    private func ensureDoctorWindow() -> NSWindow {
        if let existingWindow = doctorWindow, doctorTextView != nil {
            return existingWindow
        }

        let panel = makeDoctorPanel()
        let textViewInstance = makeDoctorTextView()
        let statusRow = makeDoctorStatusRow()
        let buttons = makeDoctorButtons()
        let contentView = makeDoctorContentView(
            textView: textViewInstance,
            statusRow: statusRow.view,
            buttons: buttons
        )
        panel.contentView = contentView
        panel.isReleasedWhenClosed = false

        doctorWindow = panel
        doctorTextView = textViewInstance
        doctorButtons = buttons
        doctorStatusLabel = statusRow.label
        doctorProgressIndicator = statusRow.indicator
        return panel
    }
}
