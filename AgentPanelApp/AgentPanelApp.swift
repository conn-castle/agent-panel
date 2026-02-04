import AppKit
import SwiftUI

import AgentPanelCore

/// Timing constants for menu behavior.
private enum MenuTiming {
    /// Delay after dismissing the menu before showing the switcher.
    /// Required to let AppKit finish menu dismissal animation.
    static let menuDismissDelaySeconds: TimeInterval = 0.05
}

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
    private let stateStore = StateStore()
    private let focusHistoryStore = FocusHistoryStore()
    private var appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run onboarding check asynchronously before setting up the app
        let onboarding = Onboarding(logger: logger)
        onboarding.runIfNeeded { [weak self] result in
            guard let self else { return }

            if result == .declined {
                NSApplication.shared.terminate(nil)
                return
            }

            self.completeAppSetup()
        }
    }

    /// Completes app setup after onboarding succeeds.
    private func completeAppSetup() {
        NSApp.setActivationPolicy(.accessory)
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "AP"
        statusItem.menu = makeMenu()
        self.statusItem = statusItem

        // Load persisted state and record session start
        loadStateAndRecordSessionStart()

        let switcherController = SwitcherPanelController(
            logger: logger,
            stateStore: stateStore,
            focusHistoryStore: focusHistoryStore
        )
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

        let dataStore = DataPaths.default()
        logAppEvent(
            event: "app.started",
            context: [
                "version": AgentPanel.version,
                "log_path": dataStore.primaryLogFile.path,
                "config_path": dataStore.configFile.path
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
        // Small delay required to let the menu dismiss before showing the switcher.
        // Without this, AppKit may have visual conflicts between the closing menu and opening panel.
        DispatchQueue.main.asyncAfter(deadline: .now() + MenuTiming.menuDismissDelaySeconds) { [weak self] in
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
        let controller = SwitcherPanelController(
            logger: logger,
            stateStore: stateStore,
            focusHistoryStore: focusHistoryStore
        )
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

    /// Runs a Doctor action and shows the resulting report.
    /// - Parameters:
    ///   - action: The Doctor method to call.
    ///   - requestedEvent: Event name to log before the action.
    ///   - completedEvent: Event name to log after the action.
    private func runDoctorAction(
        _ action: (Doctor) -> DoctorReport,
        requestedEvent: String,
        completedEvent: String
    ) {
        logAppEvent(event: requestedEvent)
        let report = action(makeDoctor())
        showDoctorReport(report)
        logDoctorSummary(report, event: completedEvent)
    }

    /// Installs AeroSpace via Homebrew and refreshes the report.
    private func installAeroSpace() {
        runDoctorAction(
            { $0.installAeroSpace() },
            requestedEvent: "doctor.install_aerospace.requested",
            completedEvent: "doctor.install_aerospace.completed"
        )
    }

    /// Starts AeroSpace and refreshes the report.
    private func startAeroSpace() {
        runDoctorAction(
            { $0.startAeroSpace() },
            requestedEvent: "doctor.start_aerospace.requested",
            completedEvent: "doctor.start_aerospace.completed"
        )
    }

    /// Reloads AeroSpace config and refreshes the report.
    private func reloadAeroSpaceConfig() {
        runDoctorAction(
            { $0.reloadAeroSpaceConfig() },
            requestedEvent: "doctor.reload_aerospace.requested",
            completedEvent: "doctor.reload_aerospace.completed"
        )
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

    // MARK: - App Lifecycle State Management

    /// Called when the app is about to terminate.
    func applicationWillTerminate(_ notification: Notification) {
        recordSessionEndAndSave()
    }

    /// Loads persisted state and records a session start event.
    private func loadStateAndRecordSessionStart() {
        switch stateStore.load() {
        case .success(let loadedState):
            appState = loadedState
        case .failure(let error):
            logAppEvent(
                event: "state.load.failed",
                level: .error,
                message: "Failed to load state: \(error)"
            )
            // Continue with fresh state
            appState = AppState()
        }

        // Record session start and update last launched time
        let event = FocusEvent.sessionStarted(
            metadata: ["version": AgentPanel.version]
        )
        appState = focusHistoryStore.record(event: event, state: appState)
        appState.lastLaunchedAt = Date()
        saveState()
    }

    /// Records a session end event and saves state.
    ///
    /// Reloads state from disk before recording to avoid overwriting events
    /// that may have been recorded by other components (e.g., SwitcherPanelController).
    private func recordSessionEndAndSave() {
        // Reload state to get any events recorded since app launch
        switch stateStore.load() {
        case .success(let freshState):
            appState = freshState
        case .failure(let error):
            logAppEvent(
                event: "state.reload.failed",
                level: .error,
                message: "Failed to reload state before session end: \(error)"
            )
            // Continue with existing state; better to record sessionEnded than lose it
        }

        let event = FocusEvent.sessionEnded()
        appState = focusHistoryStore.record(event: event, state: appState)
        saveState()
        logAppEvent(event: "app.session.ended")
    }

    /// Saves the current app state to disk with pruning.
    private func saveState() {
        let result = stateStore.save(appState, prunedWith: focusHistoryStore)
        if case .failure(let error) = result {
            logAppEvent(
                event: "state.save.failed",
                level: .error,
                message: "Failed to save state: \(error)"
            )
        }
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
