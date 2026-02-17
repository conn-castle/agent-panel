//
//  ApAeroSpace.swift
//  AgentPanelCore
//
//  CLI wrapper for the AeroSpace window manager.
//  Provides methods for installing, starting, and controlling AeroSpace,
//  including workspace management, window operations, and compatibility checks.
//

import Foundation
import os

/// Minimal window data returned by AeroSpace queries.
struct ApWindow: Equatable {
    /// AeroSpace window id.
    let windowId: Int
    /// App bundle identifier for the window.
    let appBundleId: String
    /// Workspace name for the window.
    let workspace: String
    /// Window title as reported by AeroSpace.
    let windowTitle: String
}

/// Workspace summary data returned by AeroSpace queries.
struct ApWorkspaceSummary: Equatable, Sendable {
    /// Workspace name.
    let workspace: String
    /// True when this workspace is focused.
    let isFocused: Bool
}

/// AeroSpace CLI wrapper for ap.
public struct ApAeroSpace {
    private static let logger = Logger(subsystem: "com.agentpanel", category: "ApAeroSpace")

    /// AeroSpace bundle identifier for Launch Services lookups.
    public static let bundleIdentifier = "bobko.aerospace"

    /// Legacy app path for fallback detection.
    private static let legacyAppPath = "/Applications/AeroSpace.app"

    /// Maximum time to wait for AeroSpace to become ready after launch.
    private static let startupTimeoutSeconds: TimeInterval = 10.0

    /// Interval between readiness checks during startup.
    private static let readinessCheckInterval: TimeInterval = 0.25

    private let commandRunner: CommandRunning
    private let appDiscovery: AppDiscovering
    private let fileSystem: FileSystem
    private let circuitBreaker: AeroSpaceCircuitBreaker
    private let processChecker: RunningApplicationChecking?

    /// Creates a new AeroSpace wrapper with default dependencies.
    /// - Parameter processChecker: Optional process checker for auto-recovery.
    ///   When provided and AeroSpace crashes (circuit breaker open, process dead),
    ///   the wrapper will automatically attempt to restart AeroSpace.
    ///   Pass `nil` to disable auto-recovery (e.g., for Doctor diagnostics).
    public init(processChecker: RunningApplicationChecking? = nil) {
        self.commandRunner = ApSystemCommandRunner()
        self.appDiscovery = LaunchServicesAppDiscovery()
        self.fileSystem = DefaultFileSystem()
        self.circuitBreaker = .shared
        self.processChecker = processChecker
    }

    /// Creates a new AeroSpace wrapper with custom dependencies.
    /// - Parameters:
    ///   - commandRunner: Command runner for CLI operations.
    ///   - appDiscovery: App discovery for installation checks.
    ///   - fileSystem: File system for path checks.
    ///   - circuitBreaker: Circuit breaker for timeout cascade prevention.
    ///   - processChecker: Optional process checker for auto-recovery.
    init(
        commandRunner: CommandRunning,
        appDiscovery: AppDiscovering,
        fileSystem: FileSystem = DefaultFileSystem(),
        circuitBreaker: AeroSpaceCircuitBreaker = .shared,
        processChecker: RunningApplicationChecking? = nil
    ) {
        self.commandRunner = commandRunner
        self.appDiscovery = appDiscovery
        self.fileSystem = fileSystem
        self.circuitBreaker = circuitBreaker
        self.processChecker = processChecker
    }

    /// Returns the path to AeroSpace.app if installed.
    /// Uses Launch Services to find the app by bundle ID, with fallback to legacy path.
    var appPath: String? {
        // Try Launch Services first (handles all install locations)
        if let url = appDiscovery.applicationURL(bundleIdentifier: Self.bundleIdentifier) {
            return url.path
        }
        // Fallback for edge cases where Launch Services hasn't indexed yet
        let legacyURL = URL(fileURLWithPath: Self.legacyAppPath, isDirectory: true)
        if fileSystem.directoryExists(at: legacyURL) {
            return Self.legacyAppPath
        }
        return nil
    }

    // MARK: - App Lifecycle

    /// Installs AeroSpace via Homebrew.
    /// - Returns: Success or an error.
    public func installViaHomebrew() -> Result<Void, ApCoreError> {
        switch commandRunner.run(
            executable: "brew",
            arguments: ["install", "--cask", "nikitabobko/tap/aerospace"],
            timeoutSeconds: 300
        ) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("brew install --cask nikitabobko/tap/aerospace", result: result))
            }
            return .success(())
        }
    }

    /// Starts the AeroSpace application.
    /// - Returns: Success or an error.
    public func start() -> Result<Void, ApCoreError> {
        guard !Thread.isMainThread else {
            return .failure(
                ApCoreError(
                    category: .command,
                    message: "AeroSpace start must run off the main thread."
                )
            )
        }

        switch commandRunner.run(executable: "open", arguments: ["-a", "AeroSpace"], timeoutSeconds: 10) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("open -a AeroSpace", result: result))
            }
            // Fresh start — clear any tripped circuit breaker state
            circuitBreaker.reset()
            // Poll for readiness instead of fixed sleep
            return waitForReadiness()
        }
    }

    /// Waits for AeroSpace CLI to become responsive after launch.
    /// - Returns: Success when CLI is available, or an error on timeout.
    private func waitForReadiness() -> Result<Void, ApCoreError> {
        let deadline = Date().addingTimeInterval(Self.startupTimeoutSeconds)

        while Date() < deadline {
            if isCliAvailable() {
                return .success(())
            }
            Thread.sleep(forTimeInterval: Self.readinessCheckInterval)
        }

        return .failure(ApCoreError(
            category: .command,
            message: "AeroSpace did not become ready within \(Self.startupTimeoutSeconds)s after launch."
        ))
    }

    /// Reloads the AeroSpace configuration.
    /// - Returns: Success or an error.
    public func reloadConfig() -> Result<Void, ApCoreError> {
        switch runAerospace(arguments: ["reload-config"]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace reload-config", result: result))
            }
            return .success(())
        }
    }

    /// Returns true when AeroSpace.app is installed.
    /// - Returns: True if AeroSpace.app exists on disk.
    public func isAppInstalled() -> Bool {
        appPath != nil
    }

    /// Returns true when the aerospace CLI is available on PATH.
    /// - Returns: True if `aerospace --help` succeeds.
    public func isCliAvailable() -> Bool {
        switch runAerospace(arguments: ["--help"], timeoutSeconds: 2) {
        case .failure:
            return false
        case .success(let result):
            return result.exitCode == 0
        }
    }

    // MARK: - Compatibility

    /// Checks whether the installed aerospace CLI supports required commands and flags.
    /// - Returns: Success when compatible, or an error describing missing support.
    func checkCompatibility() -> Result<Void, ApCoreError> {
        let checks: [(command: String, requiredFlags: [String])] = [
            ("list-workspaces", ["--all", "--focused"]),
            ("list-windows", ["--monitor", "--workspace", "--focused", "--app-bundle-id", "--format"]),
            ("summon-workspace", []),
            ("move-node-to-workspace", ["--window-id"]),
            ("focus", ["--window-id", "--boundaries", "--boundaries-action", "dfs-next", "dfs-prev"]),
            ("close", ["--window-id"])
        ]

        let lock = NSLock()
        var failures: [String] = []

        DispatchQueue.concurrentPerform(iterations: checks.count) { index in
            let check = checks[index]
            var localFailure: String?

            switch commandHelpOutput(command: check.command) {
            case .failure(let error):
                localFailure = "aerospace \(check.command) --help failed: \(error.message)"
            case .success(let output):
                let missing = check.requiredFlags.filter { !output.contains($0) }
                if !missing.isEmpty {
                    localFailure = "aerospace \(check.command) missing flags: \(missing.joined(separator: ", "))"
                }
            }

            if let failure = localFailure {
                lock.lock()
                failures.append(failure)
                lock.unlock()
            }
        }

        guard failures.isEmpty else {
            // Sort for deterministic output regardless of concurrent execution order
            let sorted = failures.sorted()
            return .failure(
                ApCoreError(
                    category: .validation,
                    message: "AeroSpace CLI compatibility check failed.",
                    detail: sorted.joined(separator: "\n")
                )
            )
        }

        return .success(())
    }

    // MARK: - Workspaces

    /// Returns a list of focused AeroSpace workspaces.
    /// - Returns: Workspace names on success, or an error.
    func listWorkspacesFocused() -> Result<[String], ApCoreError> {
        switch runAerospace(arguments: ["list-workspaces", "--focused"]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace list-workspaces --focused", result: result))
            }

            let workspaces = result.stdout
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            return .success(workspaces)
        }
    }

    /// Returns a list of AeroSpace workspaces.
    /// - Returns: Workspace names on success, or an error.
    func getWorkspaces() -> Result<[String], ApCoreError> {
        switch runAerospace(arguments: ["list-workspaces", "--all"]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace list-workspaces --all", result: result))
            }

            let workspaces = result.stdout
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            return .success(workspaces)
        }
    }

    /// Returns all AeroSpace workspaces with focus metadata in a single query.
    /// - Returns: Workspace summaries on success, or an error.
    func listWorkspacesWithFocus() -> Result<[ApWorkspaceSummary], ApCoreError> {
        switch runAerospace(
            arguments: ["list-workspaces", "--all", "--format", "%{workspace}||%{workspace-is-focused}"]
        ) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(
                    commandError(
                        "aerospace list-workspaces --all --format %{workspace}||%{workspace-is-focused}",
                        result: result
                    )
                )
            }
            return parseWorkspaceSummaries(output: result.stdout)
        }
    }

    /// Checks whether a workspace name exists.
    /// - Parameter name: Workspace name to look up.
    /// - Returns: True if the workspace exists, or an error.
    func workspaceExists(_ name: String) -> Result<Bool, ApCoreError> {
        switch getWorkspaces() {
        case .failure(let error):
            return .failure(error)
        case .success(let workspaces):
            return .success(workspaces.contains(name))
        }
    }

    /// Creates a new workspace with the provided name.
    /// - Parameter name: Workspace name to create.
    /// - Returns: Success or an error.
    func createWorkspace(_ name: String) -> Result<Void, ApCoreError> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(validationError("Workspace name cannot be empty."))
        }

        switch workspaceExists(trimmed) {
        case .failure(let error):
            return .failure(error)
        case .success(true):
            return .failure(validationError("Workspace already exists: \(trimmed)"))
        case .success(false):
            break
        }

        switch runAerospace(arguments: ["summon-workspace", trimmed]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace summon-workspace \(trimmed)", result: result))
            }
            return .success(())
        }
    }

    /// Closes all windows in the provided workspace.
    /// - Parameter name: Workspace name to close windows in.
    /// - Returns: Success or an error.
    func closeWorkspace(name: String) -> Result<Void, ApCoreError> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(validationError("Workspace name cannot be empty."))
        }

        switch listWindowsWorkspace(workspace: trimmed) {
        case .failure(let error):
            return .failure(error)
        case .success(let windows):
            var failures: [String] = []
            failures.reserveCapacity(windows.count)

            for window in windows {
                switch closeWindow(windowId: window.windowId) {
                case .failure(let error):
                    failures.append("window \(window.windowId): \(error.message)")
                case .success:
                    continue
                }
            }

            guard failures.isEmpty else {
                return .failure(
                    ApCoreError(
                        category: .command,
                        message: "Failed to close \(failures.count) windows in workspace \(trimmed).",
                        detail: failures.joined(separator: "\n")
                    )
                )
            }

            return .success(())
        }
    }

    // MARK: - Workspace Focus

    /// Focuses a workspace by name.
    ///
    /// Uses `summon-workspace` (preferred, pulls workspace to current monitor) with
    /// fallback to `workspace` (switches to workspace wherever it is).
    ///
    /// - Parameter name: Workspace name to focus.
    /// - Returns: Success or an error.
    func focusWorkspace(name: String) -> Result<Void, ApCoreError> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(validationError("Workspace name cannot be empty."))
        }

        // Try summon-workspace first (preferred for multi-monitor)
        let summonResult = runAerospace(arguments: ["summon-workspace", trimmed])
        if !Self.shouldAttemptCompatibilityFallback(summonResult) {
            switch summonResult {
            case .success(let result):
                if result.exitCode == 0 {
                    return .success(())
                }
                return .failure(commandError("aerospace summon-workspace \(trimmed)", result: result))
            case .failure(let error):
                return .failure(error)
            }
        }

        // Fallback to workspace command
        switch runAerospace(arguments: ["workspace", trimmed]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace workspace \(trimmed)", result: result))
            }
            return .success(())
        }
    }

    // MARK: - Windows

    /// Returns windows for the given app across all monitors.
    ///
    /// Searches globally first (no `--monitor` flag). If that fails (older AeroSpace builds),
    /// falls back to `--monitor focused`. This is the one exception to the "prefer scoped
    /// queries" guidance — tagged-window resolution needs global scope.
    ///
    /// - Parameter bundleId: App bundle identifier to filter.
    /// - Returns: Window list or an error.
    func listWindowsForApp(bundleId: String) -> Result<[ApWindow], ApCoreError> {
        // Preferred: global search (no --monitor flag)
        let globalResult = runAerospace(arguments: [
            "list-windows",
            "--app-bundle-id",
            bundleId,
            "--format",
            "%{window-id}||%{app-bundle-id}||%{workspace}||%{window-title}"
        ])
        if !Self.shouldAttemptCompatibilityFallback(globalResult) {
            switch globalResult {
            case .success(let result):
                if result.exitCode == 0 {
                    return parseWindowSummaries(output: result.stdout)
                }
                return .failure(commandError("aerospace list-windows --app-bundle-id \(bundleId)", result: result))
            case .failure(let error):
                return .failure(error)
            }
        }

        // Fallback: focused monitor only
        return listWindowsOnFocusedMonitor(appBundleId: bundleId)
    }

    /// Moves a window into the provided workspace.
    /// - Parameters:
    ///   - workspace: Destination workspace name.
    ///   - windowId: AeroSpace window id to move.
    ///   - focusFollows: When true, includes `--focus-follows-window` so focus moves
    ///     with the window into the target workspace. Falls back to a plain move if
    ///     the flag is not supported.
    /// - Returns: Success or an error.
    func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool = false) -> Result<Void, ApCoreError> {
        let trimmed = workspace.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(validationError("Workspace name cannot be empty."))
        }
        guard windowId > 0 else {
            return .failure(validationError("Window ID must be positive."))
        }

        if focusFollows {
            // Try with --focus-follows-window first; fall back to plain move
            let focusFollowsResult = runAerospace(
                arguments: ["move-node-to-workspace", "--focus-follows-window", "--window-id", "\(windowId)", trimmed]
            )
            if !Self.shouldAttemptCompatibilityFallback(focusFollowsResult) {
                switch focusFollowsResult {
                case .success(let result):
                    if result.exitCode == 0 {
                        return .success(())
                    }
                    return .failure(
                        commandError(
                            "aerospace move-node-to-workspace --focus-follows-window --window-id \(windowId) \(trimmed)",
                            result: result
                        )
                    )
                case .failure(let error):
                    return .failure(error)
                }
            }
        }

        switch runAerospace(arguments: ["move-node-to-workspace", "--window-id", "\(windowId)", trimmed]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace move-node-to-workspace --window-id \(windowId) \(trimmed)", result: result))
            }
            return .success(())
        }
    }

    /// Focuses a window by its AeroSpace window id.
    /// - Parameter windowId: AeroSpace window id to focus.
    /// - Returns: Success or an error.
    func focusWindow(windowId: Int) -> Result<Void, ApCoreError> {
        guard windowId > 0 else {
            return .failure(validationError("Window ID must be positive."))
        }

        switch runAerospace(arguments: ["focus", "--window-id", "\(windowId)"]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace focus --window-id \(windowId)", result: result))
            }
            return .success(())
        }
    }

    /// Returns windows on the focused monitor.
    /// - Returns: Window list or an error.
    func listWindowsFocusedMonitor() -> Result<[ApWindow], ApCoreError> {
        switch runAerospace(arguments: [
            "list-windows",
            "--monitor",
            "focused",
            "--format",
            "%{window-id}||%{app-bundle-id}||%{workspace}||%{window-title}"
        ]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace list-windows --monitor focused", result: result))
            }
            return parseWindowSummaries(output: result.stdout)
        }
    }

    /// Returns windows on the focused monitor filtered by app bundle id.
    /// - Parameter appBundleId: App bundle identifier to filter.
    /// - Returns: Window list or an error.
    func listWindowsOnFocusedMonitor(appBundleId: String) -> Result<[ApWindow], ApCoreError> {
        switch runAerospace(arguments: [
            "list-windows",
            "--monitor",
            "focused",
            "--app-bundle-id",
            appBundleId,
            "--format",
            "%{window-id}||%{app-bundle-id}||%{workspace}||%{window-title}"
        ]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace list-windows --monitor focused --app-bundle-id \(appBundleId)", result: result))
            }
            return parseWindowSummaries(output: result.stdout)
        }
    }

    /// Returns VS Code windows on the focused monitor.
    /// - Returns: Window list or an error.
    func listVSCodeWindowsOnFocusedMonitor() -> Result<[ApWindow], ApCoreError> {
        listWindowsOnFocusedMonitor(appBundleId: ApVSCodeLauncher.bundleId)
    }

    /// Returns Chrome windows on the focused monitor.
    /// - Returns: Window list or an error.
    func listChromeWindowsOnFocusedMonitor() -> Result<[ApWindow], ApCoreError> {
        listWindowsOnFocusedMonitor(appBundleId: ApChromeLauncher.bundleId)
    }

    /// Returns the currently focused window.
    /// - Returns: Focused window or an error.
    func focusedWindow() -> Result<ApWindow, ApCoreError> {
        switch listWindowsFocused() {
        case .failure(let error):
            return .failure(error)
        case .success(let windows):
            guard windows.count == 1, let window = windows.first else {
                return .failure(
                    ApCoreError(
                        category: .parse,
                        message: "Expected exactly one focused window, found \(windows.count)."
                    )
                )
            }
            return .success(window)
        }
    }

    /// Returns windows for the given workspace.
    /// - Parameter workspace: Workspace name to query.
    /// - Returns: Window list or an error.
    func listWindowsWorkspace(workspace: String) -> Result<[ApWindow], ApCoreError> {
        switch runAerospace(arguments: [
            "list-windows",
            "--workspace",
            workspace,
            "--format",
            "%{window-id}||%{app-bundle-id}||%{workspace}||%{window-title}"
        ]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace list-windows --workspace \(workspace)", result: result))
            }
            return parseWindowSummaries(output: result.stdout)
        }
    }

    /// Returns all windows across all workspaces.
    /// - Returns: Combined window list from all workspaces, or an error.
    func listAllWindows() -> Result<[ApWindow], ApCoreError> {
        let workspaces: [String]
        switch getWorkspaces() {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            workspaces = result
        }

        var allWindows: [ApWindow] = []
        for workspace in workspaces {
            switch listWindowsWorkspace(workspace: workspace) {
            case .success(let windows):
                allWindows.append(contentsOf: windows)
            case .failure:
                // Skip workspaces that fail (e.g., transient workspaces that disappeared)
                continue
            }
        }
        return .success(allWindows)
    }

    // MARK: - Circuit Breaker

    /// Runs an aerospace CLI command with circuit breaker protection and auto-recovery.
    ///
    /// Checks the breaker before spawning a process. If AeroSpace is unresponsive
    /// (breaker open), returns a descriptive error immediately instead of waiting
    /// for a 5s timeout. After the call, records the outcome so that a timeout
    /// trips the breaker for subsequent calls.
    ///
    /// When a `processChecker` is available and the breaker is open, checks whether
    /// AeroSpace has actually crashed (process dead). If so, automatically attempts
    /// to restart it (up to 2 attempts) and retries the original command.
    ///
    /// - Parameters:
    ///   - arguments: Arguments to pass to the `aerospace` executable.
    ///   - timeoutSeconds: Timeout in seconds. Defaults to 5s.
    /// - Returns: Command result on success, or an error.
    private func runAerospace(
        arguments: [String],
        timeoutSeconds: TimeInterval = 5
    ) -> Result<ApCommandResult, ApCoreError> {
        if circuitBreaker.shouldAllow() {
            return executeAndRecord(arguments: arguments, timeoutSeconds: timeoutSeconds)
        }

        // Breaker is open — attempt auto-recovery if process checker is available
        if let checker = processChecker,
           !checker.isApplicationRunning(bundleIdentifier: Self.bundleIdentifier),
           circuitBreaker.beginRecovery() {
            Self.logger.info("circuit_breaker.recovery_started thread=\(Thread.isMainThread ? "main" : "background", privacy: .public)")
            if Thread.isMainThread {
                // Main thread: fire-and-forget recovery in the background, fail fast now.
                // start() blocks for up to ~10s (open + readiness poll) — unacceptable on main.
                // The next off-main call will benefit from the recovered state.
                DispatchQueue.global(qos: .userInitiated).async {
                    switch self.start() {
                    case .success:
                        Self.logger.info("circuit_breaker.recovery_succeeded")
                        self.circuitBreaker.endRecovery(success: true)
                    case .failure:
                        Self.logger.warning("circuit_breaker.recovery_failed")
                        self.circuitBreaker.endRecovery(success: false)
                    }
                }
            } else {
                // Off-main: recover synchronously and retry the command.
                switch start() {
                case .success:
                    Self.logger.info("circuit_breaker.recovery_succeeded")
                    circuitBreaker.endRecovery(success: true)
                    return executeAndRecord(arguments: arguments, timeoutSeconds: timeoutSeconds)
                case .failure:
                    Self.logger.warning("circuit_breaker.recovery_failed")
                    circuitBreaker.endRecovery(success: false)
                }
            }
        }

        return .failure(breakerOpenError())
    }

    /// Executes an aerospace command and records the outcome on the circuit breaker.
    private func executeAndRecord(
        arguments: [String],
        timeoutSeconds: TimeInterval
    ) -> Result<ApCommandResult, ApCoreError> {
        let result = commandRunner.run(
            executable: "aerospace",
            arguments: arguments,
            timeoutSeconds: timeoutSeconds
        )

        switch result {
        case .success:
            circuitBreaker.recordSuccess()
        case .failure(let error):
            if error.message.hasPrefix("Command timed out") {
                let wasOpen = !circuitBreaker.shouldAllow()
                circuitBreaker.recordTimeout()
                if !wasOpen {
                    Self.logger.warning("circuit_breaker.tripped command=aerospace \(arguments.joined(separator: " "), privacy: .public) timeout=\(timeoutSeconds)s")
                }
            }
        }

        return result
    }

    /// Returns the standard error for when the circuit breaker is open.
    private func breakerOpenError() -> ApCoreError {
        ApCoreError(
            category: .command,
            message: "AeroSpace is unresponsive (circuit breaker open).",
            detail: "A previous aerospace command timed out. Failing fast to prevent cascade. Retry in \(Int(circuitBreaker.cooldownSeconds))s."
        )
    }

    // MARK: - Private Helpers

    /// Returns windows scoped to the focused window query.
    /// - Returns: Window list or an error.
    private func listWindowsFocused() -> Result<[ApWindow], ApCoreError> {
        switch runAerospace(arguments: [
            "list-windows",
            "--focused",
            "--format",
            "%{window-id}||%{app-bundle-id}||%{workspace}||%{window-title}"
        ]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace list-windows --focused", result: result))
            }
            return parseWindowSummaries(output: result.stdout)
        }
    }

    /// Closes a window by its AeroSpace window id.
    /// - Parameter windowId: AeroSpace window id to close.
    /// - Returns: Success or an error.
    private func closeWindow(windowId: Int) -> Result<Void, ApCoreError> {
        guard windowId > 0 else {
            return .failure(validationError("Window ID must be positive."))
        }

        switch runAerospace(arguments: ["close", "--window-id", "\(windowId)"]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace close --window-id \(windowId)", result: result))
            }
            return .success(())
        }
    }

    /// Parses window summaries from formatted AeroSpace output.
    ///
    /// Expected format: `<window-id>||<app-bundle-id>||<workspace>||<window-title>`
    /// where fields are separated by `||` (double pipe).
    ///
    /// - Parameter output: Output from `aerospace list-windows --format`.
    /// - Returns: Parsed window summaries or an error.
    private func parseWindowSummaries(output: String) -> Result<[ApWindow], ApCoreError> {
        let lines = output.split(whereSeparator: \.isNewline)
        var windows: [ApWindow] = []
        windows.reserveCapacity(lines.count)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }

            guard let firstSeparator = trimmed.range(of: "||") else {
                return .failure(parseError(
                    "Unexpected aerospace output format.",
                    detail: "Expected '<window-id>||<app-bundle-id>||<workspace>||<window-title>', got: \(trimmed)"
                ))
            }

            let idPart = String(trimmed[..<firstSeparator.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let windowId = Int(idPart) else {
                return .failure(parseError(
                    "Window id was not an integer.",
                    detail: "Got: \(idPart)"
                ))
            }

            let remainder = trimmed[firstSeparator.upperBound...]
            guard let secondSeparator = remainder.range(of: "||") else {
                return .failure(parseError(
                    "Unexpected aerospace output format.",
                    detail: "Expected '<window-id>||<app-bundle-id>||<workspace>||<window-title>', got: \(trimmed)"
                ))
            }

            let appBundleId = String(remainder[..<secondSeparator.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let remainderAfterBundle = remainder[secondSeparator.upperBound...]
            guard let thirdSeparator = remainderAfterBundle.range(of: "||") else {
                return .failure(parseError(
                    "Unexpected aerospace output format.",
                    detail: "Expected '<window-id>||<app-bundle-id>||<workspace>||<window-title>', got: \(trimmed)"
                ))
            }
            let workspace = String(remainderAfterBundle[..<thirdSeparator.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let titlePart = remainderAfterBundle[thirdSeparator.upperBound...]
            let windowTitle = String(titlePart).trimmingCharacters(in: .whitespacesAndNewlines)

            windows.append(
                ApWindow(
                    windowId: windowId,
                    appBundleId: appBundleId,
                    workspace: workspace,
                    windowTitle: windowTitle
                )
            )
        }

        return .success(windows)
    }

    /// Parses workspace summaries from formatted AeroSpace output.
    ///
    /// Expected format: `<workspace>||<is-focused>`
    /// where fields are separated by `||` (double pipe), and focus values are `true` or `false`.
    ///
    /// - Parameter output: Output from `aerospace list-workspaces --all --format`.
    /// - Returns: Parsed workspace summaries or an error.
    private func parseWorkspaceSummaries(output: String) -> Result<[ApWorkspaceSummary], ApCoreError> {
        let lines = output.split(whereSeparator: \.isNewline)
        var workspaces: [ApWorkspaceSummary] = []
        workspaces.reserveCapacity(lines.count)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }

            guard let separator = trimmed.range(of: "||") else {
                return .failure(parseError(
                    "Unexpected workspace summary format.",
                    detail: "Expected '<workspace>||<is-focused>', got: \(trimmed)"
                ))
            }

            let workspace = String(trimmed[..<separator.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let focusToken = String(trimmed[separator.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            let isFocused: Bool
            switch focusToken {
            case "true":
                isFocused = true
            case "false":
                isFocused = false
            default:
                return .failure(parseError(
                    "Unexpected workspace focus value.",
                    detail: "Expected 'true' or 'false', got: \(focusToken)"
                ))
            }

            workspaces.append(ApWorkspaceSummary(workspace: workspace, isFocused: isFocused))
        }

        return .success(workspaces)
    }

    /// Returns help output for a CLI command.
    /// - Parameter command: AeroSpace command name to query.
    /// - Returns: Help output or an error.
    private func commandHelpOutput(command: String) -> Result<String, ApCoreError> {
        switch runAerospace(arguments: [command, "--help"], timeoutSeconds: 2) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace \(command) --help", result: result))
            }

            let output = [result.stdout, result.stderr]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            return .success(output)
        }
    }

    /// Returns true when a primary command result should trigger a compatibility fallback.
    ///
    /// Fallback is attempted only for non-zero command exits whose output suggests a
    /// CLI version or flag incompatibility (e.g. "unknown option", "unrecognized command").
    /// Hard command-run failures (for example executable resolution failures) do not fall back,
    /// and neither do non-zero exits caused by operational errors (workspace not found, etc.).
    static func shouldAttemptCompatibilityFallback(_ result: Result<ApCommandResult, ApCoreError>) -> Bool {
        switch result {
        case .success(let output):
            guard output.exitCode != 0 else {
                return false
            }
            let diagnosticText = (output.stderr + "\n" + output.stdout).lowercased()
            let compatibilityIndicators = [
                "unknown option",
                "unknown flag",
                "unknown command",
                "unknown subcommand",
                "unrecognized option",
                "unrecognised option",
                "unrecognized command",
                "invalid option",
                "no such option",
                "no such command",
                "mandatory option is not specified"
            ]
            return compatibilityIndicators.contains { diagnosticText.contains($0) }
        case .failure:
            return false
        }
    }
}

// MARK: - AeroSpaceHealthChecking Conformance

extension ApAeroSpace: AeroSpaceHealthChecking {
    /// Returns the installation status of AeroSpace.
    func installStatus() -> AeroSpaceInstallStatus {
        AeroSpaceInstallStatus(isInstalled: isAppInstalled(), appPath: appPath)
    }

    /// Checks whether the installed aerospace CLI is compatible.
    /// Translates the internal Result type to the intent-based AeroSpaceCompatibility enum.
    func healthCheckCompatibility() -> AeroSpaceCompatibility {
        guard isCliAvailable() else {
            return .cliUnavailable
        }
        switch checkCompatibility() {
        case .success:
            return .compatible
        case .failure(let error):
            return .incompatible(detail: error.detail ?? error.message)
        }
    }

    /// Installs AeroSpace via Homebrew.
    /// - Returns: True if installation succeeded.
    func healthInstallViaHomebrew() -> Bool {
        switch installViaHomebrew() {
        case .success:
            return true
        case .failure:
            return false
        }
    }

    /// Starts AeroSpace.
    /// - Returns: True if start succeeded.
    func healthStart() -> Bool {
        switch start() {
        case .success:
            return true
        case .failure:
            return false
        }
    }

    /// Reloads the AeroSpace configuration.
    /// - Returns: True if reload succeeded.
    func healthReloadConfig() -> Bool {
        switch reloadConfig() {
        case .success:
            return true
        case .failure:
            return false
        }
    }
}
