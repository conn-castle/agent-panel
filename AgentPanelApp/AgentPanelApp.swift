import AppKit
import ServiceManagement
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
    let recoverAgentPanel: NSMenuItem
    let addWindowToProject: NSMenuItem
    let recoverAllWindows: NSMenuItem
    let launchAtLogin: NSMenuItem
}

/// App lifecycle hook used to create a minimal menu bar presence.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var doctorController: DoctorWindowController?
    private var recoveryController: RecoveryProgressController?
    private var hotkeyManager: HotkeyManager?
    private var focusCycleHotkeyManager: FocusCycleHotkeyManager?
    private var switcherController: SwitcherPanelController?
    private var menuItems: MenuItems?
    private var doctorIndicatorSeverity: DoctorSeverity?
    private var isHealthRefreshInFlight: Bool = false
    private var pendingCriticalContext: ErrorContext?
    private var lastHealthRefreshAt: Date?
    private var lastHotkeyToggleAt: Date?
    private var menuFocusCapture: CapturedFocus?
    /// Cached workspace state for non-blocking menu population.
    /// Updated by background refreshes; read by `menuNeedsUpdate`.
    private var cachedWorkspaceState: ProjectWorkspaceState?
    private let logger: AgentPanelLogging = AgentPanelLogger()
    private let projectManager = ProjectManager(
        windowPositioner: AXWindowPositioner(),
        screenModeDetector: ScreenModeDetector(),
        processChecker: AppKitRunningApplicationChecker()
    )

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

        // Auto-update AeroSpace config if stale (preserves user sections)
        let aeroConfigManager = AeroSpaceConfigManager()
        switch aeroConfigManager.ensureUpToDate() {
        case .success(let result):
            if case .updated(let from, let to) = result {
                logAppEvent(event: "aerospace_config.updated", context: ["from": "\(from)", "to": "\(to)"])
                // Apply updated config to the running AeroSpace process.
                // Dispatched to background to avoid blocking the main thread — the
                // reload calls ApSystemCommandRunner.run() which may trigger the
                // one-time login shell PATH resolution on first use.
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    let aerospace = ApAeroSpace()
                    switch aerospace.reloadConfig() {
                    case .success:
                        self?.logAppEvent(event: "aerospace_config.reloaded")
                    case .failure(let error):
                        self?.logAppEvent(event: "aerospace_config.reload_failed", level: .warn, message: error.message)
                    }
                }
            }
            // Cleanup stale focus scripts from the script-based approach
            cleanupStaleFocusScripts()
        case .failure(let error):
            logAppEvent(event: "aerospace_config.update_failed", level: .warn, message: error.message)
        }

        // Register window cycling hotkeys (Option-Tab / Option-Shift-Tab)
        let windowCycler = WindowCycler(processChecker: AppKitRunningApplicationChecker())
        let focusCycleManager = FocusCycleHotkeyManager()
        focusCycleManager.onCycleNext = { [weak self] in
            DispatchQueue.global(qos: .userInteractive).async {
                if case .failure(let error) = windowCycler.cycleFocus(direction: .next) {
                    self?.logAppEvent(event: "focus_cycle.next.failed", level: .warn, message: error.message)
                }
            }
        }
        focusCycleManager.onCyclePrevious = { [weak self] in
            DispatchQueue.global(qos: .userInteractive).async {
                if case .failure(let error) = windowCycler.cycleFocus(direction: .previous) {
                    self?.logAppEvent(event: "focus_cycle.prev.failed", level: .warn, message: error.message)
                }
            }
        }
        focusCycleManager.registerHotkeys()
        self.focusCycleHotkeyManager = focusCycleManager

        // Wire settings block writes: fires on first loadConfig() and whenever the project list changes.
        // On startup the first fire triggers ensureAll → then Doctor. On subsequent config reloads
        // (e.g., switcher open), only ensureAll runs (Doctor is triggered separately by session end).
        projectManager.onProjectsChanged = { [weak self] projects in
            DispatchQueue.global(qos: .userInitiated).async {
                let results = VSCodeSettingsBlocks.ensureAll(projects: projects)
                for (projectId, result) in results {
                    if case .failure(let error) = result {
                        let isSSH = projects.first(where: { $0.id == projectId })?.isSSH == true
                        self?.logAppEvent(
                            event: "settings_block.write_failed",
                            level: .warn,
                            message: error.message,
                            context: [
                                "project_id": projectId,
                                "type": isSSH ? "ssh" : "local"
                            ]
                        )
                    }
                }
                // On startup, run Doctor after settings blocks are written so it doesn't
                // report spurious warnings for blocks that are still being written.
                if self?.lastHealthRefreshAt == nil {
                    DispatchQueue.main.async {
                        self?.refreshHealthInBackground(trigger: "startup", force: true)
                    }
                }
            }
        }

        // Load config on the main thread (ProjectManager is not thread-safe).
        // The onProjectsChanged callback above handles settings block writes + startup Doctor.
        let configResult = projectManager.loadConfig()
        let loadedConfig = try? configResult.get()

        // Apply auto-start at login from config (only when config loaded successfully)
        if let loadedConfig {
            syncLaunchAtLogin(configValue: loadedConfig.config.app.autoStartAtLogin)
        }

        // If config load failed (no projects), the callback never fired — run Doctor directly.
        if loadedConfig == nil {
            refreshHealthInBackground(trigger: "startup", force: true)
        }

        let dataStore = DataPaths.default()
        logAppEvent(
            event: "app.started",
            context: [
                "version": AgentPanel.version,
                "binary_path": Bundle.main.executablePath ?? "unknown",
                "bundle_path": Bundle.main.bundlePath,
                "log_path": dataStore.primaryLogFile.path,
                "config_path": dataStore.configFile.path,
                "macos_version": ProcessInfo.processInfo.operatingSystemVersionString
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

    /// Removes stale focus cycling scripts from the previous script-based approach.
    private func cleanupStaleFocusScripts() {
        let binDir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/agent-panel/bin")
        for name in ["ap-focus-next", "ap-focus-prev"] {
            let fileURL = binDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: fileURL)
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

        // Recovery and window management items
        let recoverAgentPanelItem = NSMenuItem(
            title: "Recover Project",
            action: #selector(recoverAgentPanel),
            keyEquivalent: ""
        )
        recoverAgentPanelItem.target = self
        recoverAgentPanelItem.isEnabled = false // Toggled in menuNeedsUpdate
        menu.addItem(recoverAgentPanelItem)

        let addWindowToProjectItem = NSMenuItem(
            title: "Move Current Window",
            action: nil,
            keyEquivalent: ""
        )
        addWindowToProjectItem.submenu = NSMenu()
        addWindowToProjectItem.isHidden = true // Toggled in menuNeedsUpdate
        menu.addItem(addWindowToProjectItem)

        let recoverAllWindowsItem = NSMenuItem(
            title: "Recover All Windows...",
            action: #selector(recoverAllWindowsAction),
            keyEquivalent: ""
        )
        recoverAllWindowsItem.target = self
        menu.addItem(recoverAllWindowsItem)

        menu.addItem(.separator())

        menu.addItem(
            NSMenuItem(
                title: "Run Doctor...",
                action: #selector(runDoctor),
                keyEquivalent: "d"
            )
        )
        menu.addItem(.separator())

        let launchAtLoginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit",
                action: #selector(quit),
                keyEquivalent: "q"
            )
        )

        menu.delegate = self

        menuItems = MenuItems(
            hotkeyWarning: hotkeyWarningItem,
            openSwitcher: openSwitcherItem,
            recoverAgentPanel: recoverAgentPanelItem,
            addWindowToProject: addWindowToProjectItem,
            recoverAllWindows: recoverAllWindowsItem,
            launchAtLogin: launchAtLoginItem
        )

        return menu
    }

    /// Opens the switcher panel from the menu bar.
    @objc private func openSwitcher(_ sender: Any?) {
        logAppEvent(
            event: "switcher.menu.invoked",
            context: ["menu_item": "Open Switcher..."]
        )
        // Use cached focus from menuNeedsUpdate (no blocking CLI call).
        // The cache was refreshed when the menu opened, so it's recent enough
        // for focus restoration on cancel.
        let previousApp = NSWorkspace.shared.frontmostApplication
        let capturedFocus = menuFocusCapture
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

    /// Minimum interval between hotkey toggles to prevent session storms during AeroSpace outages.
    private static let hotkeyDebounceSeconds: TimeInterval = 0.3

    /// Toggles the switcher panel from the global hotkey.
    private func toggleSwitcher() {
        // Debounce: ignore rapid presses within 300ms to prevent session storms
        // when AeroSpace is unresponsive and the user mashes the hotkey.
        let now = Date()
        if let last = lastHotkeyToggleAt,
           now.timeIntervalSince(last) < Self.hotkeyDebounceSeconds {
            logAppEvent(event: "switcher.hotkey.debounced")
            return
        }
        lastHotkeyToggleAt = now

        // Capture the previously active app immediately (AppKit API, instant).
        let previousApp = NSWorkspace.shared.frontmostApplication

        // Capture AeroSpace focus in background to avoid blocking the main thread.
        // The switcher toggle is dispatched to main thread once the capture completes.
        // Thread-safe: captureCurrentFocus() only runs a CLI command and logs,
        // it does not mutate ProjectManager state.
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self else { return }
            let capturedFocus = self.projectManager.captureCurrentFocus()
            DispatchQueue.main.async {
                self.logAppEvent(
                    event: "switcher.hotkey.invoked",
                    context: ["hotkey": "Cmd+Shift+Space"]
                )
                // The panel uses .nonactivatingPanel style mask, so it receives keyboard input
                // without activating the app (and therefore without switching workspaces).
                self.ensureSwitcherController().toggle(origin: .hotkey, previousApp: previousApp, capturedFocus: capturedFocus)
            }
        }
    }

    /// Creates a new SwitcherPanelController instance.
    private func makeSwitcherController() -> SwitcherPanelController {
        let controller = SwitcherPanelController(logger: logger, projectManager: projectManager)
        controller.onProjectOperationFailed = { [weak self] context in
            self?.refreshHealthInBackground(trigger: "project_operation_failed", errorContext: context)
        }
        controller.onSessionEnded = { [weak self] in
            self?.refreshHealthInBackground(trigger: "switcher_session_ended")
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

    /// Logs a comprehensive summary for Doctor reports to aid remote diagnostics.
    /// Includes finding titles, timing breakdown, and the full rendered report text.
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

        // Include FAIL and WARN finding titles for remote diagnostics
        let failTitles = report.findings
            .filter { $0.severity == .fail && !$0.title.isEmpty }
            .map { $0.title }
        let warnTitles = report.findings
            .filter { $0.severity == .warn && !$0.title.isEmpty }
            .map { $0.title }
        if !failTitles.isEmpty {
            context["fail_findings"] = failTitles.joined(separator: "; ")
        }
        if !warnTitles.isEmpty {
            context["warn_findings"] = warnTitles.joined(separator: "; ")
        }

        // Include timing breakdown for performance diagnostics
        context["duration_ms"] = "\(report.metadata.durationMs)"
        let sortedSections = report.metadata.sectionTimings.sorted { $0.key < $1.key }
        for (section, ms) in sortedSections {
            context["timing_\(section)_ms"] = "\(ms)"
        }

        // Include the full rendered report text so remote debugging never lacks detail
        context["rendered_report"] = report.rendered()

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
    /// Critical errors (from `errorContext.isCritical`) skip debounce automatically.
    ///
    /// - Parameters:
    ///   - trigger: Log event name suffix describing what triggered the refresh.
    ///   - force: When true, bypasses the debounce window (e.g., for startup).
    ///   - errorContext: Optional error context that triggered this refresh.
    private func refreshHealthInBackground(
        trigger: String,
        force: Bool = false,
        errorContext: ErrorContext? = nil
    ) {
        let skipDebounce = force || (errorContext?.isCritical == true)

        guard !isHealthRefreshInFlight else {
            // Store critical context so it's not dropped when in-flight
            if let errorContext, errorContext.isCritical {
                pendingCriticalContext = errorContext
            }
            logAppEvent(
                event: "doctor.refresh.skipped",
                context: ["trigger": trigger, "reason": "in_flight"]
            )
            return
        }

        if !skipDebounce, let lastRefresh = lastHealthRefreshAt,
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
            let report = self.makeDoctor().run(context: errorContext)
            DispatchQueue.main.async {
                self.isHealthRefreshInFlight = false
                self.lastHealthRefreshAt = Date()
                self.updateMenuBarHealthIndicator(severity: report.overallSeverity)
                self.logDoctorSummary(report, event: "doctor.refresh.completed")

                // Auto-show Doctor window for critical errors with FAIL findings
                if let ctx = errorContext, ctx.isCritical, report.hasFailures {
                    self.logAppEvent(
                        event: "doctor.auto_show",
                        context: ["trigger": ctx.trigger, "category": ctx.category.rawValue]
                    )
                    self.showDoctorReport(report)
                }

                // Refresh cached workspace/focus state for non-blocking menu updates
                self.refreshMenuStateInBackground()

                // If a critical error was queued while in-flight, trigger a new refresh
                if let pending = self.pendingCriticalContext {
                    self.pendingCriticalContext = nil
                    self.refreshHealthInBackground(
                        trigger: pending.trigger,
                        errorContext: pending
                    )
                }
            }
        }
    }

    /// Refreshes cached workspace state and focus in the background.
    ///
    /// Called after Doctor refreshes, switcher session ends, and on menu open.
    /// The cached values are used by `menuNeedsUpdate` to avoid blocking the
    /// main thread with AeroSpace CLI calls.
    ///
    /// Thread safety: `captureCurrentFocus()` and `workspaceState()` only run
    /// stateless CLI commands and log — they do not mutate ProjectManager state.
    private func refreshMenuStateInBackground() {
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self else { return }
            let focus = self.projectManager.captureCurrentFocus()
            let state = try? self.projectManager.workspaceState().get()
            DispatchQueue.main.async {
                self.cachedWorkspaceState = state
                // Also update menuFocusCapture so it stays fresh between menu opens
                if let focus {
                    self.menuFocusCapture = focus
                }
            }
        }
    }

    /// Creates a Doctor instance with the current hotkey status providers.
    private func makeDoctor() -> Doctor {
        Doctor(
            runningApplicationChecker: AppKitRunningApplicationChecker(),
            hotkeyStatusProvider: hotkeyManager,
            focusCycleStatusProvider: focusCycleHotkeyManager,
            windowPositioner: AXWindowPositioner()
        )
    }

    /// Runs Doctor and presents the report in a modal-style panel.
    @objc private func runDoctor() {
        logAppEvent(event: "doctor.run.requested")
        // Capture focus before dispatching to background if no focus is currently held.
        // Re-runs from within the Doctor window keep the original focus (capturedFocus != nil).
        let needsCapture = doctorController?.capturedFocus == nil && doctorController?.previousApp == nil
        // Capture previousApp instantly (AppKit API, non-blocking) on the main thread.
        let previousApp = needsCapture ? NSWorkspace.shared.frontmostApplication : nil

        // Show Doctor window immediately with loading state so the user gets instant
        // feedback. Doctor.run() can take 20-30s (SSH timeouts) on the background thread.
        let controller = ensureDoctorController()
        if let previousApp, needsCapture {
            controller.previousApp = previousApp
        }
        controller.showLoading()

        // Focus capture and Doctor run both dispatch to background to avoid blocking
        // the main thread — captureCurrentFocus() calls AeroSpace CLI which can timeout.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let capturedFocus = needsCapture ? self.projectManager.captureCurrentFocus() : nil
            let report = self.makeDoctor().run()
            DispatchQueue.main.async {
                if let capturedFocus {
                    controller.capturedFocus = capturedFocus
                }
                self.updateMenuBarHealthIndicator(severity: report.overallSeverity)
                controller.showReport(report)
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
        // Show loading state immediately — the action + re-run can take 20-30s.
        doctorController?.showLoading()
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

    /// Requests Accessibility permission and refreshes the report.
    private func requestAccessibility() {
        runDoctorAction(
            { $0.requestAccessibility() },
            requestedEvent: "doctor.request_accessibility.requested",
            completedEvent: "doctor.request_accessibility.completed"
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
            // Try to restore precise window focus first.
            if let focus, projectManager.restoreFocus(focus) {
                await MainActor.run {
                    logEvent("doctor.focus.restored", ["window_id": "\(focus.windowId)"])
                }
                return
            }

            // If precise focus restore fails or was not possible, fall back to activating the previous app.
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

    // MARK: - Launch at Login

    /// Syncs SMAppService registration with the config value.
    /// - Parameter configValue: The `autoStartAtLogin` value from config.
    private func syncLaunchAtLogin(configValue: Bool) {
        let service = SMAppService.mainApp
        if configValue {
            do {
                try service.register()
                logAppEvent(event: "launch_at_login.registered")
            } catch {
                logAppEvent(
                    event: "launch_at_login.register_failed",
                    level: .warn,
                    message: "Launch at login configured but registration failed: \(error.localizedDescription)"
                )
            }
        } else {
            do {
                try service.unregister()
                logAppEvent(event: "launch_at_login.unregistered")
            } catch {
                // Unregister failure when not registered is expected; only warn if meaningful
                logAppEvent(
                    event: "launch_at_login.unregister_failed",
                    level: .warn,
                    message: "\(error.localizedDescription)"
                )
            }
        }
    }

    /// Toggles the Launch at Login menu item.
    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        let isCurrentlyEnabled = service.status == .enabled
        let newValue = !isCurrentlyEnabled

        if newValue {
            do {
                try service.register()
                logAppEvent(event: "launch_at_login.toggled_on")
            } catch {
                logAppEvent(
                    event: "launch_at_login.toggle_register_failed",
                    level: .error,
                    message: "Failed to enable launch at login: \(error.localizedDescription)"
                )
                return
            }
        } else {
            do {
                try service.unregister()
                logAppEvent(event: "launch_at_login.toggled_off")
            } catch {
                logAppEvent(
                    event: "launch_at_login.toggle_unregister_failed",
                    level: .error,
                    message: "Failed to disable launch at login: \(error.localizedDescription)"
                )
                return
            }
        }

        // Write back to config.toml
        let configURL = DataPaths.default().configFile
        do {
            try ConfigWriteBack.setAutoStartAtLogin(newValue, in: configURL)
            logAppEvent(event: "launch_at_login.config_written", context: ["value": "\(newValue)"])
            menuItems?.launchAtLogin.title = "Launch at Login"
        } catch {
            logAppEvent(
                event: "launch_at_login.config_write_failed",
                level: .error,
                message: "Config save failed: \(error.localizedDescription)"
            )
            // Rollback SMAppService toggle since config write failed
            if newValue {
                try? service.unregister()
            } else {
                try? service.register()
            }
            menuItems?.launchAtLogin.title = "Launch at Login"
        }
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
        controller.onRequestAccessibility = { [weak self] in self?.requestAccessibility() }
        controller.onClose = { [weak self] in self?.closeDoctorWindow() }
        doctorController = controller
        return controller
    }

    // MARK: - Window Recovery & Move to Project

    /// Creates a WindowRecoveryManager with an already-captured screen frame.
    /// The screen frame must be read on the main thread before calling this.
    /// - Parameters:
    ///   - screenFrame: Screen visible frame captured on the main thread.
    ///   - layoutConfig: Layout config for layout-aware recovery. Pass nil to disable layout phase.
    private func makeWindowRecoveryManager(screenFrame: CGRect, layoutConfig: LayoutConfig? = nil) -> WindowRecoveryManager {
        WindowRecoveryManager(
            windowPositioner: AXWindowPositioner(),
            screenVisibleFrame: screenFrame,
            logger: logger,
            processChecker: AppKitRunningApplicationChecker(),
            screenModeDetector: layoutConfig != nil ? ScreenModeDetector() : nil,
            layoutConfig: layoutConfig ?? LayoutConfig()
        )
    }

    /// Recovers all windows in the current project workspace.
    @objc private func recoverAgentPanel() {
        logAppEvent(event: "recover_agent_panel.requested")
        statusItem?.menu?.cancelTracking()

        guard let focus = menuFocusCapture, focus.workspace.hasPrefix(ProjectManager.workspacePrefix) else {
            logAppEvent(event: "recover_agent_panel.skipped", level: .warn, message: "Not in a project workspace")
            return
        }

        // Capture screen frame on main thread (AppKit API)
        guard let screenFrame = NSScreen.main?.visibleFrame else {
            logAppEvent(event: "recovery.no_screen", level: .error, message: "No primary screen available")
            return
        }

        // Read current layout config without triggering a config load (non-mutating)
        let layoutConfig = projectManager.currentLayoutConfig

        let workspace = focus.workspace
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let manager = self.makeWindowRecoveryManager(screenFrame: screenFrame, layoutConfig: layoutConfig)
            let result = manager.recoverWorkspaceWindows(workspace: workspace)
            DispatchQueue.main.async {
                switch result {
                case .success(let recovery):
                    self.logAppEvent(
                        event: "recover_agent_panel.completed",
                        context: [
                            "processed": "\(recovery.windowsProcessed)",
                            "recovered": "\(recovery.windowsRecovered)"
                        ]
                    )
                case .failure(let error):
                    self.logAppEvent(
                        event: "recover_agent_panel.failed",
                        level: .error,
                        message: error.message
                    )
                }
            }
        }
    }

    /// Recovers all windows across all workspaces, moving them to workspace "1".
    @objc private func recoverAllWindowsAction() {
        logAppEvent(event: "recover_all_windows.requested")
        statusItem?.menu?.cancelTracking()

        // Capture screen frame on main thread (AppKit API)
        guard let screenFrame = NSScreen.main?.visibleFrame else {
            logAppEvent(event: "recovery.no_screen", level: .error, message: "No primary screen available")
            return
        }

        // Show progress panel
        let controller = RecoveryProgressController()
        controller.onClose = { [weak self] in
            self?.recoveryController = nil
        }
        recoveryController = controller
        controller.show()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let manager = self.makeWindowRecoveryManager(screenFrame: screenFrame)

            let result = manager.recoverAllWindows { current, total in
                DispatchQueue.main.async {
                    self.recoveryController?.updateProgress(current: current, total: total)
                }
            }

            DispatchQueue.main.async {
                switch result {
                case .success(let recovery):
                    let message: String
                    if recovery.errors.isEmpty {
                        message = "Recovered \(recovery.windowsRecovered) of \(recovery.windowsProcessed) windows."
                    } else {
                        message = "Recovered \(recovery.windowsRecovered) of \(recovery.windowsProcessed) windows (\(recovery.errors.count) errors)."
                    }
                    self.recoveryController?.showCompletion(message: message)
                    self.logAppEvent(
                        event: "recover_all_windows.completed",
                        context: [
                            "processed": "\(recovery.windowsProcessed)",
                            "recovered": "\(recovery.windowsRecovered)",
                            "errors": "\(recovery.errors.count)"
                        ]
                    )
                case .failure(let error):
                    self.recoveryController?.showCompletion(
                        message: "Recovery failed: \(error.message)"
                    )
                    self.logAppEvent(
                        event: "recover_all_windows.failed",
                        level: .error,
                        message: error.message
                    )
                }
            }
        }
    }

    /// Moves the focused window to the selected project's workspace.
    @objc private func addWindowToProject(_ sender: NSMenuItem) {
        guard let projectId = sender.representedObject as? String else { return }
        guard let focus = menuFocusCapture else {
            logAppEvent(event: "add_window_to_project.no_focus", level: .warn)
            return
        }

        // No-op if window is already in the target project workspace
        if focus.workspace == ProjectManager.workspacePrefix + projectId { return }

        logAppEvent(
            event: "add_window_to_project.requested",
            context: ["window_id": "\(focus.windowId)", "project_id": projectId]
        )

        // Dispatch to background to avoid blocking the main thread — moveWindowToProject
        // calls AeroSpace CLI which can timeout if AeroSpace is unresponsive.
        // Thread-safe: moveWindowToProject() only reads immutable config state and calls CLI.
        let windowId = focus.windowId
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.projectManager.moveWindowToProject(windowId: windowId, projectId: projectId)
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.logAppEvent(
                        event: "add_window_to_project.completed",
                        context: ["window_id": "\(windowId)", "project_id": projectId]
                    )
                    // Refresh workspace state cache after the move
                    self.refreshMenuStateInBackground()
                case .failure(let error):
                    self.logAppEvent(
                        event: "add_window_to_project.failed",
                        level: .error,
                        message: "\(error)"
                    )
                }
            }
        }
    }

    /// Moves the focused window out of its project workspace to the default workspace.
    @objc private func removeWindowFromProject(_ sender: NSMenuItem) {
        guard let focus = menuFocusCapture else {
            logAppEvent(event: "remove_window_from_project.no_focus", level: .warn)
            return
        }

        // No-op if window is not in a project workspace
        guard focus.workspace.hasPrefix(ProjectManager.workspacePrefix) else { return }

        logAppEvent(
            event: "remove_window_from_project.requested",
            context: ["window_id": "\(focus.windowId)", "workspace": focus.workspace]
        )

        let windowId = focus.windowId
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.projectManager.moveWindowFromProject(windowId: windowId)
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.logAppEvent(
                        event: "remove_window_from_project.completed",
                        context: ["window_id": "\(windowId)"]
                    )
                    self.refreshMenuStateInBackground()
                case .failure(let error):
                    self.logAppEvent(
                        event: "remove_window_from_project.failed",
                        level: .error,
                        message: "\(error)"
                    )
                }
            }
        }
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    /// Updates dynamic menu items each time the menu opens.
    ///
    /// Uses cached workspace state and focus to avoid blocking the main thread
    /// with AeroSpace CLI calls. The cache is refreshed in the background after
    /// Doctor runs, switcher sessions end, and each menu open.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let menuItems else { return }

        // Reflect Launch at Login state
        menuItems.launchAtLogin.state = SMAppService.mainApp.status == .enabled ? .on : .off

        // Use cached focus (updated by background refreshes, not a live CLI call)
        let inProjectWorkspace = menuFocusCapture.map { $0.workspace.hasPrefix(ProjectManager.workspacePrefix) } ?? false
        menuItems.recoverAgentPanel.isEnabled = inProjectWorkspace

        // Populate "Move Current Window" submenu from cached workspace state
        let submenu = menuItems.addWindowToProject.submenu ?? NSMenu()
        submenu.removeAllItems()

        let currentWorkspace = menuFocusCapture?.workspace
        let inProjectWorkspaceForMove = currentWorkspace?.hasPrefix(ProjectManager.workspacePrefix) ?? false

        var hasOpenProjects = false
        if let state = cachedWorkspaceState {
            let openProjects = projectManager.projects.filter { state.openProjectIds.contains($0.id) }
            if !openProjects.isEmpty {
                hasOpenProjects = true
                for project in openProjects {
                    let item = NSMenuItem(
                        title: project.name,
                        action: #selector(addWindowToProject(_:)),
                        keyEquivalent: ""
                    )
                    item.target = self
                    item.representedObject = project.id
                    if currentWorkspace == ProjectManager.workspacePrefix + project.id {
                        item.state = .on
                    }
                    submenu.addItem(item)
                }
            }
        }

        // Separator + "No Project" option
        if hasOpenProjects {
            submenu.addItem(.separator())
        }
        let noProjectItem = NSMenuItem(
            title: "No Project",
            action: #selector(removeWindowFromProject(_:)),
            keyEquivalent: ""
        )
        noProjectItem.target = self
        if !inProjectWorkspaceForMove {
            noProjectItem.state = .on
        }
        submenu.addItem(noProjectItem)

        menuItems.addWindowToProject.submenu = submenu
        menuItems.addWindowToProject.isHidden = !hasOpenProjects && !inProjectWorkspaceForMove

        // Refresh cache in background for next menu open
        refreshMenuStateInBackground()
    }
}
