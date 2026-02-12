import AppKit
import SwiftUI

import AgentPanelAppKit
import AgentPanelCore

/// Timing constants for menu behavior.
private enum MenuTiming {
    /// Delay after dismissing the menu before showing the switcher.
    /// Required to let AppKit finish menu dismissal animation.
    static let menuDismissDelaySeconds: TimeInterval = 0.05
}

/// Menu bar indicator constants.
private enum MenuBarHealthIndicator {
    static let symbolName = "square.stack"
    static let accessibilityDescription = "AgentPanel health indicator"
    /// Minimum interval between background Doctor refreshes to avoid spamming CLI calls.
    static let refreshDebounceSeconds: TimeInterval = 30.0
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
    private var doctorIndicatorSeverity: DoctorSeverity?
    private var isHealthRefreshInFlight: Bool = false
    private var lastHealthRefreshAt: Date?
    private let logger: AgentPanelLogging = AgentPanelLogger()
    private let projectManager = ProjectManager()

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
        statusItem.menu = makeMenu()
        self.statusItem = statusItem
        updateMenuBarHealthIndicator(severity: nil)

        self.switcherController = makeSwitcherController()

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

        // Auto-start AeroSpace if installed but not running
        ensureAeroSpaceRunning()

        // Load config on the main thread (ProjectManager is not thread-safe), then
        // ensure VS Code settings blocks in the background (may use SSH).
        let configResult = projectManager.loadConfig()
        let projects = (try? configResult.get())?.config.projects ?? []

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if !projects.isEmpty {
                let results = VSCodeSettingsBlocks.ensureAll(projects: projects)
                for (projectId, result) in results {
                    if case .failure(let error) = result {
                        self?.logAppEvent(
                            event: "settings_block.write_failed",
                            level: .warn,
                            message: error.message,
                            context: ["project_id": projectId]
                        )
                    }
                }
            }

            DispatchQueue.main.async {
                self?.refreshHealthInBackground(trigger: "startup", force: true)
            }
        }

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

    /// Ensures AeroSpace is running if it's installed.
    private func ensureAeroSpaceRunning() {
        let aerospace = ApAeroSpace()
        let checker = AppKitRunningApplicationChecker()

        guard aerospace.isAppInstalled() else {
            logAppEvent(
                event: "aerospace.autostart.skipped",
                level: .warn,
                message: "AeroSpace not installed"
            )
            return
        }

        if checker.isApplicationRunning(bundleIdentifier: ApAeroSpace.bundleIdentifier) {
            logAppEvent(event: "aerospace.autostart.skipped", message: "Already running")
            return
        }

        logAppEvent(event: "aerospace.autostart.starting")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            switch aerospace.start() {
            case .success:
                self?.logAppEvent(event: "aerospace.autostart.success")
            case .failure(let error):
                self?.logAppEvent(
                    event: "aerospace.autostart.failed",
                    level: .error,
                    message: error.message
                )
            }
        }
    }

    /// Creates the menu bar menu.
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let aboutItem = NSMenuItem(
            title: "About Agent Panel",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        menu.addItem(aboutItem)

        menu.addItem(.separator())

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

        let viewConfigItem = NSMenuItem(
            title: "View Config File...",
            action: #selector(viewConfigFile),
            keyEquivalent: ""
        )
        viewConfigItem.target = self
        menu.addItem(viewConfigItem)

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
        refreshHealthInBackground(trigger: "switcher_open")
        // Capture both the previously active app AND focus state BEFORE the menu dismisses
        // and before we activate. This ensures restore-on-cancel returns to the correct window.
        let previousApp = NSWorkspace.shared.frontmostApplication
        let capturedFocus = projectManager.captureCurrentFocus()
        statusItem?.menu?.cancelTracking()
        // Small delay required to let the menu dismiss before showing the switcher.
        // Without this, AppKit may have visual conflicts between the closing menu and opening panel.
        DispatchQueue.main.asyncAfter(deadline: .now() + MenuTiming.menuDismissDelaySeconds) { [weak self] in
            guard let self else {
                return
            }
            // The panel uses .nonactivatingPanel style mask, so it receives keyboard input
            // without activating the app (and therefore without switching workspaces).
            self.ensureSwitcherController().show(origin: .menu, previousApp: previousApp, capturedFocus: capturedFocus)
        }
    }

    /// Toggles the switcher panel from the global hotkey.
    private func toggleSwitcher() {
        // Capture both the previously active app AND focus state BEFORE we show the switcher.
        // This must happen outside the async block to capture the correct window.
        let previousApp = NSWorkspace.shared.frontmostApplication
        let capturedFocus = projectManager.captureCurrentFocus()
        refreshHealthInBackground(trigger: "switcher_toggle")
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.logAppEvent(
                event: "switcher.hotkey.invoked",
                context: ["hotkey": "Cmd+Shift+Space"]
            )
            // The panel uses .nonactivatingPanel style mask, so it receives keyboard input
            // without activating the app (and therefore without switching workspaces).
            self.ensureSwitcherController().toggle(origin: .hotkey, previousApp: previousApp, capturedFocus: capturedFocus)
        }
    }

    /// Creates a new SwitcherPanelController instance.
    private func makeSwitcherController() -> SwitcherPanelController {
        let controller = SwitcherPanelController(logger: logger, projectManager: projectManager)
        controller.onProjectOperationFailed = { [weak self] in
            self?.refreshHealthInBackground(trigger: "project_operation_failed")
        }
        return controller
    }

    /// Ensures the switcher controller exists for menu/hotkey actions.
    /// - Returns: Switcher panel controller instance.
    private func ensureSwitcherController() -> SwitcherPanelController {
        if let switcherController {
            return switcherController
        }
        let controller = makeSwitcherController()
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

    /// Updates the menu bar icon using the latest Doctor severity.
    ///
    /// For pending (nil) and pass states, the image uses template rendering so macOS
    /// handles light/dark menu bar appearance automatically. For warn/fail, palette
    /// colors are baked into the symbol configuration so the color is always visible
    /// regardless of menu bar appearance.
    ///
    /// - Parameter severity: Worst severity from the latest Doctor report. Nil means pending/unknown.
    private func updateMenuBarHealthIndicator(severity: DoctorSeverity?) {
        doctorIndicatorSeverity = severity
        guard let button = statusItem?.button else {
            return
        }

        button.title = ""
        button.imagePosition = .imageOnly
        button.contentTintColor = nil

        let sizeConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)

        let image: NSImage?
        switch severity {
        case .fail:
            let colorConfig = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            image = NSImage(
                systemSymbolName: MenuBarHealthIndicator.symbolName,
                accessibilityDescription: MenuBarHealthIndicator.accessibilityDescription
            )?.withSymbolConfiguration(sizeConfig.applying(colorConfig))
            image?.isTemplate = false
        case .warn:
            let colorConfig = NSImage.SymbolConfiguration(paletteColors: [.systemOrange])
            image = NSImage(
                systemSymbolName: MenuBarHealthIndicator.symbolName,
                accessibilityDescription: MenuBarHealthIndicator.accessibilityDescription
            )?.withSymbolConfiguration(sizeConfig.applying(colorConfig))
            image?.isTemplate = false
        case .pass, .none:
            image = NSImage(
                systemSymbolName: MenuBarHealthIndicator.symbolName,
                accessibilityDescription: MenuBarHealthIndicator.accessibilityDescription
            )?.withSymbolConfiguration(sizeConfig)
            image?.isTemplate = true
        }

        button.image = image
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

        let level: LogLevel = {
            switch report.overallSeverity {
            case .fail:
                return .error
            case .warn:
                return .warn
            case .pass:
                return .info
            }
        }()

        var context: [String: String] = [
            "pass_count": "\(passCount)",
            "warn_count": "\(warnCount)",
            "fail_count": "\(failCount)"
        ]
        context["overall_severity"] = report.overallSeverity.rawValue
        if let doctorIndicatorSeverity {
            context["menu_bar_severity"] = doctorIndicatorSeverity.rawValue
        } else {
            context["menu_bar_severity"] = "PENDING"
        }

        logAppEvent(
            event: event,
            level: level,
            context: context
        )
    }

    /// Runs Doctor in the background and updates the menu bar health indicator.
    ///
    /// Debounced: skips the run if a refresh is already in flight or if the last
    /// refresh completed less than `MenuBarHealthIndicator.refreshDebounceSeconds` ago.
    /// Pass `force: true` to bypass debouncing (used for startup).
    ///
    /// - Parameters:
    ///   - trigger: Log event name suffix describing what triggered the refresh.
    ///   - force: When true, bypasses the debounce window (e.g., for startup).
    private func refreshHealthInBackground(trigger: String, force: Bool = false) {
        guard !isHealthRefreshInFlight else {
            logAppEvent(
                event: "doctor.refresh.skipped",
                context: ["trigger": trigger, "reason": "in_flight"]
            )
            return
        }

        if !force, let lastRefresh = lastHealthRefreshAt,
           Date().timeIntervalSince(lastRefresh) < MenuBarHealthIndicator.refreshDebounceSeconds {
            logAppEvent(
                event: "doctor.refresh.skipped",
                context: ["trigger": trigger, "reason": "debounced"]
            )
            return
        }

        isHealthRefreshInFlight = true
        logAppEvent(event: "doctor.refresh.requested", context: ["trigger": trigger])

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let report = self.makeDoctor().run()
            DispatchQueue.main.async {
                self.isHealthRefreshInFlight = false
                self.lastHealthRefreshAt = Date()
                self.updateMenuBarHealthIndicator(severity: report.overallSeverity)
                self.logDoctorSummary(report, event: "doctor.refresh.completed")
            }
        }
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
        // Capture focus before dispatching to background if no focus is currently held.
        // Re-runs from within the Doctor window keep the original focus (capturedFocus != nil).
        let needsCapture = doctorController?.capturedFocus == nil && doctorController?.previousApp == nil
        let capturedFocus = needsCapture ? projectManager.captureCurrentFocus() : nil
        let previousApp = needsCapture ? NSWorkspace.shared.frontmostApplication : nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let report = self.makeDoctor().run()
            DispatchQueue.main.async {
                self.updateMenuBarHealthIndicator(severity: report.overallSeverity)
                self.showDoctorReport(report, capturedFocus: capturedFocus, previousApp: previousApp)
                self.logDoctorSummary(report, event: "doctor.run.completed")
            }
        }
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
        _ action: @escaping (Doctor) -> DoctorReport,
        requestedEvent: String,
        completedEvent: String
    ) {
        logAppEvent(event: requestedEvent)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let report = action(self.makeDoctor())
            DispatchQueue.main.async {
                self.updateMenuBarHealthIndicator(severity: report.overallSeverity)
                self.showDoctorReport(report)
                self.logDoctorSummary(report, event: completedEvent)
            }
        }
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

    /// Closes the Doctor window and restores previously captured focus.
    ///
    /// Focus restoration runs on a detached task so AeroSpace CLI calls don't block the main
    /// thread. Without this, clicking the menu bar immediately after closing Doctor causes a
    /// beachball. This mirrors SwitcherPanelController.restorePreviousFocus().
    private func closeDoctorWindow() {
        logAppEvent(event: "doctor.window.closed")
        let focus = doctorController?.capturedFocus
        let previousApp = doctorController?.previousApp
        doctorController?.capturedFocus = nil
        doctorController?.previousApp = nil
        let projectManager = self.projectManager
        let logEvent: (String, [String: String]?) -> Void = { [weak self] event, context in
            self?.logAppEvent(event: event, context: context)
        }
        Task.detached(priority: .userInitiated) {
            if let focus {
                if projectManager.restoreFocus(focus) {
                    await MainActor.run {
                        logEvent("doctor.focus.restored", ["window_id": "\(focus.windowId)"])
                    }
                    return
                } else if let previousApp {
                    await MainActor.run {
                        previousApp.activate()
                        logEvent("doctor.focus.restored.app_fallback", ["bundle_id": previousApp.bundleIdentifier ?? "unknown"])
                    }
                    return
                }
            }
            if let previousApp {
                await MainActor.run {
                    previousApp.activate()
                    logEvent("doctor.focus.restored.app_fallback", ["bundle_id": previousApp.bundleIdentifier ?? "unknown"])
                }
            }
        }
    }

    /// Opens Finder to reveal the config file.
    /// If the config file does not exist, triggers config load (which creates a starter config).
    @objc private func viewConfigFile() {
        logAppEvent(event: "config.view.requested")
        statusItem?.menu?.cancelTracking()
        let configURL = DataPaths.default().configFile
        if !FileManager.default.fileExists(atPath: configURL.path) {
            // loadConfig() calls ConfigLoader which creates a starter config as a side-effect
            _ = projectManager.loadConfig()
            if FileManager.default.fileExists(atPath: configURL.path) {
                logAppEvent(event: "config.view.created_starter")
            } else {
                logAppEvent(
                    event: "config.view.create_failed",
                    level: .error,
                    message: "Failed to create starter config at \(configURL.path)"
                )
            }
        }
        // Reveal the file if it exists, otherwise reveal the parent directory
        if FileManager.default.fileExists(atPath: configURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([configURL])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([configURL.deletingLastPathComponent()])
        }
    }

    /// Shows the standard About panel with app name and version.
    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Agent Panel",
            .applicationVersion: AgentPanel.version
        ])
    }

    /// Terminates the app.
    @objc private func quit() {
        logAppEvent(event: "app.quit.requested")
        NSApplication.shared.terminate(nil)
    }

    // MARK: - App Lifecycle State Management

    /// Called when the app is about to terminate.
    func applicationWillTerminate(_ notification: Notification) {
        logAppEvent(event: "app.terminated")
    }

    /// Displays the Doctor report using the DoctorWindowController.
    /// - Parameters:
    ///   - report: Doctor report payload.
    ///   - capturedFocus: AeroSpace focus captured before showing the window (nil if re-opening).
    ///   - previousApp: Frontmost app captured before showing the window (nil if re-opening).
    private func showDoctorReport(
        _ report: DoctorReport,
        capturedFocus: CapturedFocus? = nil,
        previousApp: NSRunningApplication? = nil
    ) {
        let controller = ensureDoctorController()
        // Only set focus state on first open (capturedFocus/previousApp are nil on re-runs).
        if let capturedFocus {
            controller.capturedFocus = capturedFocus
        }
        if let previousApp {
            controller.previousApp = previousApp
        }
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
