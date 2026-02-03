import AppKit
import SwiftUI

import AgentPanelCore

@main
struct AgentPanelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

private struct MenuItems {
    let hotkeyWarning: NSMenuItem
    let openSwitcher: NSMenuItem
}

/// App lifecycle hook used to create a minimal menu bar presence.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var doctorController: DoctorWindowController?
    private var hotkeyManager: HotkeyManager?
    private var switcherController: SwitcherPanelController?
    private var menuItems: MenuItems?
    private let logger: AgentPanelLogging = AgentPanelLogger()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run onboarding check before setting up the app
        let onboarding = Onboarding(logger: logger)
        if onboarding.runIfNeeded() == .declined {
            NSApplication.shared.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "AP"
        statusItem.menu = makeMenu()
        self.statusItem = statusItem

        let switcherController = SwitcherPanelController(logger: logger)
        self.switcherController = switcherController

        let hotkeyManager = HotkeyManager()
        hotkeyManager.onHotkey = { [weak self] in
            self?.toggleSwitcher()
        }
        hotkeyManager.onStatusChange = { [weak self] status in
            self?.updateHotkeyStatus(status)
        }
        hotkeyManager.registerHotkey()
        self.hotkeyManager = hotkeyManager
        updateHotkeyStatus(hotkeyManager.hotkeyRegistrationStatus())

        let paths = AgentPanelPaths.defaultPaths()
        logAppEvent(
            event: "app.started",
            context: [
                "version": AgentPanel.version,
                "log_path": paths.primaryLogFile.path,
                "config_path": paths.configFile.path
            ]
        )
    }

    /// Creates the menu bar menu.
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let hotkeyWarningItem = NSMenuItem(
            title: "Hotkey unavailable",
            action: nil,
            keyEquivalent: ""
        )
        hotkeyWarningItem.isEnabled = false
        hotkeyWarningItem.isHidden = true
        menu.addItem(hotkeyWarningItem)

        let openSwitcherItem = NSMenuItem(
            title: "Open Switcher...",
            action: #selector(openSwitcher(_:)),
            keyEquivalent: ""
        )
        openSwitcherItem.target = self
        menu.addItem(openSwitcherItem)

        menu.addItem(.separator())

        menu.addItem(
            NSMenuItem(
                title: "Run Doctor...",
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

        menuItems = MenuItems(hotkeyWarning: hotkeyWarningItem, openSwitcher: openSwitcherItem)

        return menu
    }

    /// Opens the switcher panel from the menu bar.
    @objc private func openSwitcher(_ sender: Any?) {
        logAppEvent(
            event: "switcher.menu.invoked",
            context: ["menu_item": "Open Switcher..."]
        )
        statusItem?.menu?.cancelTracking()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else {
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            self.ensureSwitcherController().show(origin: .menu)
        }
    }

    /// Toggles the switcher panel from the global hotkey.
    private func toggleSwitcher() {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.logAppEvent(
                event: "switcher.hotkey.invoked",
                context: ["hotkey": "Cmd+Shift+Space"]
            )
            NSApp.activate(ignoringOtherApps: true)
            self.ensureSwitcherController().toggle(origin: .hotkey)
        }
    }

    /// Ensures the switcher controller exists for menu/hotkey actions.
    /// - Returns: Switcher panel controller instance.
    private func ensureSwitcherController() -> SwitcherPanelController {
        if let switcherController {
            return switcherController
        }
        let controller = SwitcherPanelController(logger: logger)
        switcherController = controller
        return controller
    }

    /// Updates menu bar UI and tooltip based on hotkey registration status.
    private func updateHotkeyStatus(_ status: HotkeyRegistrationStatus?) {
        guard let statusItem, let menuItems else {
            return
        }

        switch status {
        case .registered:
            menuItems.hotkeyWarning.isHidden = true
            statusItem.button?.toolTip = nil
        case .failed(let osStatus):
            menuItems.hotkeyWarning.title = "Hotkey unavailable (OSStatus: \(osStatus))"
            menuItems.hotkeyWarning.isHidden = false
            statusItem.button?.toolTip = "Hotkey unavailable (OSStatus: \(osStatus))"
        case nil:
            menuItems.hotkeyWarning.isHidden = true
            statusItem.button?.toolTip = nil
        }
    }

    /// Writes a structured log entry for app-level events.
    /// - Parameters:
    ///   - event: Event name to log.
    ///   - level: Severity level.
    ///   - message: Optional message for the log entry.
    ///   - context: Optional structured context.
    private func logAppEvent(
        event: String,
        level: LogLevel = .info,
        message: String? = nil,
        context: [String: String]? = nil
    ) {
        _ = logger.log(event: event, level: level, message: message, context: context)
    }

    /// Logs a summary for Doctor reports to aid diagnostics.
    /// - Parameters:
    ///   - report: Doctor report to summarize.
    ///   - event: Event name to log.
    private func logDoctorSummary(_ report: DoctorReport, event: String) {
        let passCount = report.findings.filter { $0.severity == .pass }.count
        let warnCount = report.findings.filter { $0.severity == .warn }.count
        let failCount = report.findings.filter { $0.severity == .fail }.count

        let level: LogLevel
        if failCount > 0 {
            level = .error
        } else if warnCount > 0 {
            level = .warn
        } else {
            level = .info
        }

        logAppEvent(
            event: event,
            level: level,
            context: [
                "pass_count": "\(passCount)",
                "warn_count": "\(warnCount)",
                "fail_count": "\(failCount)"
            ]
        )
    }

    /// Creates a Doctor instance with the current hotkey status provider.
    private func makeDoctor() -> Doctor {
        Doctor(
            runningApplicationChecker: AppKitRunningApplicationChecker(),
            hotkeyStatusProvider: hotkeyManager
        )
    }

    /// Runs Doctor and presents the report in a modal-style panel.
    @objc private func runDoctor() {
        logAppEvent(event: "doctor.run.requested")
        let report = makeDoctor().run()
        showDoctorReport(report)
        logDoctorSummary(report, event: "doctor.run.completed")
    }

    /// Copies the current Doctor report to the clipboard.
    private func copyDoctorReport() {
        guard let report = doctorController?.lastReport?.rendered() else {
            logAppEvent(event: "doctor.copy.skipped", level: .warn, message: "No report to copy.")
            return
        }
        logAppEvent(event: "doctor.copy.requested")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report, forType: .string)
    }

    /// Installs AeroSpace via Homebrew and refreshes the report.
    private func installAeroSpace() {
        logAppEvent(event: "doctor.install_aerospace.requested")
        let report = makeDoctor().installAeroSpace()
        showDoctorReport(report)
        logDoctorSummary(report, event: "doctor.install_aerospace.completed")
    }

    /// Starts AeroSpace and refreshes the report.
    private func startAeroSpace() {
        logAppEvent(event: "doctor.start_aerospace.requested")
        let report = makeDoctor().startAeroSpace()
        showDoctorReport(report)
        logDoctorSummary(report, event: "doctor.start_aerospace.completed")
    }

    /// Reloads AeroSpace config and refreshes the report.
    private func reloadAeroSpaceConfig() {
        logAppEvent(event: "doctor.reload_aerospace.requested")
        let report = makeDoctor().reloadAeroSpaceConfig()
        showDoctorReport(report)
        logDoctorSummary(report, event: "doctor.reload_aerospace.completed")
    }

    /// Closes the Doctor window.
    private func closeDoctorWindow() {
        logAppEvent(event: "doctor.window.closed")
        doctorController?.close()
    }

    /// Terminates the app.
    @objc private func quit() {
        logAppEvent(event: "app.quit.requested")
        NSApplication.shared.terminate(nil)
    }

    /// Displays the Doctor report using the DoctorWindowController.
    /// - Parameter report: Doctor report payload.
    private func showDoctorReport(_ report: DoctorReport) {
        let controller = ensureDoctorController()
        controller.showReport(report)
    }

    /// Ensures the DoctorWindowController exists and has callbacks configured.
    /// - Returns: The doctor window controller instance.
    private func ensureDoctorController() -> DoctorWindowController {
        if let existing = doctorController {
            return existing
        }

        let controller = DoctorWindowController()
        controller.onRunDoctor = { [weak self] in self?.runDoctor() }
        controller.onCopyReport = { [weak self] in self?.copyDoctorReport() }
        controller.onInstallAeroSpace = { [weak self] in self?.installAeroSpace() }
        controller.onStartAeroSpace = { [weak self] in self?.startAeroSpace() }
        controller.onReloadConfig = { [weak self] in self?.reloadAeroSpaceConfig() }
        controller.onClose = { [weak self] in self?.closeDoctorWindow() }
        doctorController = controller
        return controller
    }
}
