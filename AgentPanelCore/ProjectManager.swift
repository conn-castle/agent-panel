//
//  ProjectManager.swift
//  AgentPanelCore
//
//  Single point of entry for all project operations:
//  listing, sorting, selecting, closing, and focus management.
//

import Foundation

// MARK: - ProjectError

/// Errors that can occur during project operations.
public enum ProjectError: Error, Equatable, Sendable {
    /// Project ID not found in config.
    case projectNotFound(projectId: String)

    /// Config has not been loaded yet.
    case configNotLoaded

    /// AeroSpace operation failed.
    case aeroSpaceError(detail: String)

    /// IDE failed to launch or appear.
    case ideLaunchFailed(detail: String)

    /// Chrome failed to launch or appear.
    case chromeLaunchFailed(detail: String)

    /// No project is currently active (for exit operation).
    case noActiveProject

    /// No previous window to return to.
    case noPreviousWindow

    /// Expected window not found after setup.
    case windowNotFound(detail: String)

    /// Focus could not be stabilized on the IDE window.
    case focusUnstable(detail: String)
}

/// Snapshot of AgentPanel workspace state from a single AeroSpace query.
public struct ProjectWorkspaceState: Equatable, Sendable {
    /// The currently focused AgentPanel project ID, if any.
    public let activeProjectId: String?

    /// Set of AgentPanel project IDs with open workspaces.
    public let openProjectIds: Set<String>

    /// Creates a workspace state snapshot.
    /// - Parameters:
    ///   - activeProjectId: Focused AgentPanel project ID, if present.
    ///   - openProjectIds: Open AgentPanel project workspace IDs.
    public init(activeProjectId: String?, openProjectIds: Set<String>) {
        self.activeProjectId = activeProjectId
        self.openProjectIds = openProjectIds
    }
}

// Note: CapturedFocus and internal protocols (AeroSpaceProviding,
// IdeLauncherProviding, ChromeLauncherProviding) are defined in Dependencies.swift

// MARK: - ProjectManager

/// Single point of entry for all project operations.
///
/// Handles:
/// - Config loading
/// - Project listing and sorting
/// - Project selection, closing, and exit
/// - Focus capture/restore for switcher UX
///
/// Thread Safety: Not thread-safe. All methods must be called from the main thread.
public final class ProjectManager {
    /// Prefix for all AgentPanel workspaces.
    public static let workspacePrefix = "ap-"

    private static let windowPollTimeout: TimeInterval = 10.0
    private static let windowPollInterval: TimeInterval = 0.1
    private static let maxRecentProjects = 100

    // Config
    private var config: Config?

    // Recency tracking - simple list of project IDs, most recent first
    private var recentProjectIds: [String] = []
    private let recencyFilePath: URL

    // Focus capture for project exit
    private var capturedProjectExitFocus: CapturedFocus?

    // Internal dependencies
    private let aerospace: AeroSpaceProviding
    private let ideLauncher: IdeLauncherProviding
    private let chromeLauncher: ChromeLauncherProviding
    private let logger: AgentPanelLogging

    // MARK: - Public Properties

    /// All projects from config, or empty if config not loaded.
    public var projects: [ProjectConfig] {
        config?.projects ?? []
    }

    /// Returns the open + focused AgentPanel workspace state from a single AeroSpace query.
    public func workspaceState() -> Result<ProjectWorkspaceState, ProjectError> {
        let workspaceSummaries: [ApWorkspaceSummary]
        switch aerospace.listWorkspacesWithFocus() {
        case .failure(let error):
            logEvent("workspace_state.failed", level: .warn, message: error.message)
            return .failure(.aeroSpaceError(detail: error.message))
        case .success(let result):
            workspaceSummaries = result
        }

        var openProjectIds = Set<String>()
        var activeProjectId: String?

        for summary in workspaceSummaries {
            guard let projectId = Self.projectId(fromWorkspace: summary.workspace) else {
                continue
            }

            openProjectIds.insert(projectId)
            if summary.isFocused, activeProjectId == nil {
                activeProjectId = projectId
            }
        }

        return .success(
            ProjectWorkspaceState(
                activeProjectId: activeProjectId,
                openProjectIds: openProjectIds
            )
        )
    }

    // MARK: - Initialization

    /// Creates a ProjectManager with default dependencies.
    public init() {
        self.aerospace = ApAeroSpace()
        self.ideLauncher = ApVSCodeLauncher()
        self.chromeLauncher = ApChromeLauncher()
        self.logger = AgentPanelLogger()
        self.recencyFilePath = DataPaths.default().recentProjectsFile

        loadRecency()
    }

    /// Creates a ProjectManager with injected dependencies (for testing).
    init(
        aerospace: AeroSpaceProviding,
        ideLauncher: IdeLauncherProviding,
        chromeLauncher: ChromeLauncherProviding,
        logger: AgentPanelLogging,
        recencyFilePath: URL
    ) {
        self.aerospace = aerospace
        self.ideLauncher = ideLauncher
        self.chromeLauncher = chromeLauncher
        self.logger = logger
        self.recencyFilePath = recencyFilePath

        loadRecency()
    }

    // MARK: - Configuration

    /// Loads configuration from the default path.
    ///
    /// Call this before using other methods. Returns the config on success.
    @discardableResult
    public func loadConfig() -> Result<Config, ConfigLoadError> {
        switch Config.loadDefault() {
        case .success(let loadedConfig):
            self.config = loadedConfig
            logEvent("config.loaded", context: ["project_count": "\(loadedConfig.projects.count)"])
            return .success(loadedConfig)
        case .failure(let error):
            self.config = nil
            logEvent("config.failed", level: .error, message: "\(error)")
            return .failure(error)
        }
    }

    // MARK: - Focus Capture/Restore (for Switcher UX)

    /// Captures the currently focused window for later restoration.
    public func captureCurrentFocus() -> CapturedFocus? {
        switch aerospace.focusedWindow() {
        case .failure(let error):
            logEvent("focus.capture.failed", level: .warn, message: error.message)
            return nil
        case .success(let window):
            let captured = CapturedFocus(windowId: window.windowId, appBundleId: window.appBundleId)
            logEvent("focus.captured", context: [
                "window_id": "\(captured.windowId)",
                "app_bundle_id": captured.appBundleId
            ])
            return captured
        }
    }

    /// Restores focus to a previously captured window.
    @discardableResult
    public func restoreFocus(_ focus: CapturedFocus) -> Bool {
        focusWindow(windowId: focus.windowId)
    }

    /// Focuses a workspace by name.
    ///
    /// Uses `summon-workspace` (preferred, pulls workspace to current monitor) with
    /// fallback to `workspace` (switches to workspace wherever it is).
    ///
    /// - Parameter name: Workspace name to focus.
    /// - Returns: True if the workspace was focused successfully.
    @discardableResult
    public func focusWorkspace(name: String) -> Bool {
        switch aerospace.focusWorkspace(name: name) {
        case .failure(let error):
            logEvent("focus.workspace.failed", level: .warn, message: error.message, context: ["workspace": name])
            return false
        case .success:
            logEvent("focus.workspace.succeeded", context: ["workspace": name])
            return true
        }
    }

    /// Focuses a window by its AeroSpace window ID.
    @discardableResult
    public func focusWindow(windowId: Int) -> Bool {
        switch aerospace.focusWindow(windowId: windowId) {
        case .failure(let error):
            logEvent("focus.restore.failed", level: .warn, message: error.message, context: ["window_id": "\(windowId)"])
            return false
        case .success:
            logEvent("focus.restored", context: ["window_id": "\(windowId)"])
            return true
        }
    }

    /// Focuses a window and polls until focus is stable.
    ///
    /// Re-asserts focus if macOS steals it during the polling window.
    ///
    /// - Parameters:
    ///   - windowId: AeroSpace window ID to focus.
    ///   - timeout: Maximum time to wait for stable focus.
    ///   - pollInterval: Interval between focus checks.
    /// - Returns: True if focus is stable within the timeout.
    @discardableResult
    public func focusWindowStable(
        windowId: Int,
        timeout: TimeInterval = 10.0,
        pollInterval: TimeInterval = 0.1
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            switch aerospace.focusedWindow() {
            case .success(let focused) where focused.windowId == windowId:
                return true
            default:
                // Re-assert focus (macOS can steal it briefly during Space/app switches)
                _ = aerospace.focusWindow(windowId: windowId)
            }

            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }

        return false
    }

    // MARK: - Project Sorting

    /// Returns projects sorted and filtered for display.
    ///
    /// - Parameter query: Search query (empty = no filter, just sort by recency)
    /// - Returns: Sorted (and filtered if query non-empty) projects
    public func sortedProjects(query: String) -> [ProjectConfig] {
        let projects = self.projects
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Build recency map: projectId -> rank (0 = most recent)
        var recencyRank: [String: Int] = [:]
        for (index, projectId) in recentProjectIds.enumerated() {
            if recencyRank[projectId] == nil {
                recencyRank[projectId] = index
            }
        }

        // Build config order map
        var configOrder: [String: Int] = [:]
        for (index, project) in projects.enumerated() {
            configOrder[project.id] = index
        }

        let noHistoryRank = recentProjectIds.count

        if trimmedQuery.isEmpty {
            // No filter, just sort by recency then config order
            return projects.sorted { a, b in
                let rankA = recencyRank[a.id] ?? noHistoryRank
                let rankB = recencyRank[b.id] ?? noHistoryRank
                if rankA != rankB {
                    return rankA < rankB
                }
                let configA = configOrder[a.id] ?? Int.max
                let configB = configOrder[b.id] ?? Int.max
                return configA < configB
            }
        }

        // Filter and compute match type
        let matched = projects.compactMap { project -> (project: ProjectConfig, matchType: Int)? in
            let matchType = self.matchType(project: project, query: trimmedQuery)
            guard matchType < 99 else { return nil }
            return (project, matchType)
        }

        // Sort by: match type, then recency, then config order
        let sorted = matched.sorted { a, b in
            if a.matchType != b.matchType {
                return a.matchType < b.matchType
            }
            let rankA = recencyRank[a.project.id] ?? noHistoryRank
            let rankB = recencyRank[b.project.id] ?? noHistoryRank
            if rankA != rankB {
                return rankA < rankB
            }
            let configA = configOrder[a.project.id] ?? Int.max
            let configB = configOrder[b.project.id] ?? Int.max
            return configA < configB
        }

        return sorted.map { $0.project }
    }

    private func matchType(project: ProjectConfig, query: String) -> Int {
        let nameLower = project.name.lowercased()
        let idLower = project.id.lowercased()

        if nameLower.hasPrefix(query) { return 0 }  // name prefix
        if idLower.hasPrefix(query) { return 1 }    // id prefix
        if nameLower.contains(query) { return 2 }   // name infix
        if idLower.contains(query) { return 3 }     // id infix
        return 99  // no match
    }

    // MARK: - Project Operations

    /// Activates a project by ID (sequential flow).
    ///
    /// Runs the full activation sequence matching the proven shell-script order exactly:
    /// 1. Look up project in config
    /// 2. Store pre-captured focus (for later exit)
    /// 3. Find or launch Chrome (do NOT move yet)
    /// 4. Find or launch VS Code (do NOT move yet)
    /// 5. Move Chrome to workspace (no focus follow)
    /// 6. Move VS Code to workspace (with focus follow)
    /// 7. Verify both windows arrived in workspace
    /// 8. Focus workspace (poll until confirmed)
    /// 9. Focus IDE window + verify stability
    ///
    /// The order is critical: both windows must exist before any moves happen.
    /// Moving Chrome before VS Code is launched can cause VS Code to open on
    /// a different macOS Space.
    ///
    /// - Parameters:
    ///   - projectId: The project ID to activate.
    ///   - preCapturedFocus: Focus state captured before showing UI, used for restoring
    ///     focus when exiting the project later.
    /// - Returns: The IDE window ID on success, for post-dismissal focusing.
    public func selectProject(projectId: String, preCapturedFocus: CapturedFocus) async -> Result<Int, ProjectError> {
        guard config != nil else {
            return .failure(.configNotLoaded)
        }

        guard let project = projects.first(where: { $0.id == projectId }) else {
            logEvent("select.project_not_found", level: .warn, context: ["project_id": projectId])
            return .failure(.projectNotFound(projectId: projectId))
        }

        let targetWorkspace = Self.workspacePrefix + projectId

        // Store pre-captured focus for later exit (only if we haven't already)
        if capturedProjectExitFocus == nil {
            capturedProjectExitFocus = preCapturedFocus
        }

        // --- Phase 1: Find or launch all windows (no moves yet) ---

        let chromeWindow: ApWindow
        switch await findOrLaunchWindow(
            appBundleId: ApChromeLauncher.bundleId,
            projectId: projectId,
            launchAction: { self.chromeLauncher.openNewWindow(identifier: projectId) },
            windowLabel: "Chrome",
            eventSource: "chrome"
        ) {
        case .failure(let error):
            return .failure(error)
        case .success(let window):
            chromeWindow = window
        }

        let ideWindow: ApWindow
        switch await findOrLaunchWindow(
            appBundleId: ApVSCodeLauncher.bundleId,
            projectId: projectId,
            launchAction: { self.ideLauncher.openNewWindow(identifier: projectId, projectPath: project.path) },
            windowLabel: "VS Code",
            eventSource: "vscode"
        ) {
        case .failure(let error):
            return .failure(error)
        case .success(let window):
            ideWindow = window
        }

        // --- Phase 2: Move windows to workspace (Chrome first, then VS Code) ---

        let chromeWindowId = chromeWindow.windowId
        let ideWindowId = ideWindow.windowId

        if chromeWindow.workspace != targetWorkspace {
            logEvent("select.chrome_moving", context: ["window_id": "\(chromeWindowId)", "workspace": targetWorkspace])
            switch aerospace.moveWindowToWorkspace(workspace: targetWorkspace, windowId: chromeWindowId, focusFollows: false) {
            case .failure(let error):
                return .failure(.aeroSpaceError(detail: error.message))
            case .success:
                logEvent("select.chrome_moved", context: ["workspace": targetWorkspace])
            }
        }

        if ideWindow.workspace != targetWorkspace {
            logEvent("select.vscode_moving", context: ["window_id": "\(ideWindowId)", "workspace": targetWorkspace, "focus_follows": "true"])
            switch aerospace.moveWindowToWorkspace(workspace: targetWorkspace, windowId: ideWindowId, focusFollows: true) {
            case .failure(let error):
                return .failure(.aeroSpaceError(detail: error.message))
            case .success:
                logEvent("select.vscode_moved", context: ["workspace": targetWorkspace])
            }
        }

        // --- Phase 3: Verify, focus workspace, focus IDE ---

        switch await pollForWindowsInWorkspace(
            chromeWindowId: chromeWindowId,
            ideWindowId: ideWindowId,
            workspace: targetWorkspace
        ) {
        case .failure(let error):
            return .failure(error)
        case .success:
            break
        }

        if !(await ensureWorkspaceFocused(name: targetWorkspace)) {
            let detail = "Workspace \(targetWorkspace) could not be focused within timeout"
            logEvent("select.workspace_focus_failed", level: .error, message: detail)
            return .failure(.aeroSpaceError(detail: detail))
        }

        _ = aerospace.focusWindow(windowId: ideWindowId)
        if !(await focusWindowStable(windowId: ideWindowId)) {
            let detail = "IDE window \(ideWindowId) could not be stably focused in workspace \(targetWorkspace)"
            logEvent("select.focus_unstable", level: .error, message: detail)
            return .failure(.focusUnstable(detail: detail))
        }

        // Record activation
        recordActivation(projectId: projectId)
        logEvent("select.completed", context: ["project_id": projectId, "ide_window_id": "\(ideWindowId)"])

        return .success(ideWindowId)
    }

    /// Closes a project by ID and restores focus to the previous non-project window.
    public func closeProject(projectId: String) -> Result<Void, ProjectError> {
        guard config != nil else {
            return .failure(.configNotLoaded)
        }

        guard projects.contains(where: { $0.id == projectId }) else {
            return .failure(.projectNotFound(projectId: projectId))
        }

        let workspace = Self.workspacePrefix + projectId

        switch aerospace.closeWorkspace(name: workspace) {
        case .failure(let error):
            logEvent("close.failed", level: .error, context: ["error": error.message])
            return .failure(.aeroSpaceError(detail: error.message))
        case .success:
            logEvent("close.workspace_closed", context: ["project_id": projectId])
        }

        // Restore focus to the previous non-project window
        if let focus = capturedProjectExitFocus {
            let restored = restoreFocus(focus)
            if restored {
                logEvent("close.focus_restored", context: ["window_id": "\(focus.windowId)"])
            } else {
                logEvent("close.focus_restore_failed", level: .warn, context: ["window_id": "\(focus.windowId)"])
            }
            capturedProjectExitFocus = nil
        }

        logEvent("close.completed", context: ["project_id": projectId])
        return .success(())
    }

    /// Exits to the last non-project window without closing the project.
    public func exitToNonProjectWindow() -> Result<Void, ProjectError> {
        let state: ProjectWorkspaceState
        switch workspaceState() {
        case .failure(let error):
            return .failure(error)
        case .success(let snapshot):
            state = snapshot
        }

        guard state.activeProjectId != nil else {
            logEvent("exit.no_active_project", level: .warn)
            return .failure(.noActiveProject)
        }

        guard let focus = capturedProjectExitFocus else {
            logEvent("exit.no_previous_window", level: .warn)
            return .failure(.noPreviousWindow)
        }

        let restored = restoreFocus(focus)
        if restored {
            logEvent("exit.focus_restored")
        } else {
            logEvent("exit.focus_restore_failed", level: .warn)
        }

        capturedProjectExitFocus = nil
        logEvent("exit.completed")

        return .success(())
    }

    // MARK: - Sequential Window Setup

    /// Finds an existing tagged window or launches a new one and polls until it appears.
    ///
    /// This helper handles find/launch/poll only — it does NOT move the window.
    /// The caller is responsible for moving the window to the target workspace.
    ///
    /// - Parameters:
    ///   - appBundleId: Bundle ID to search for (e.g., Chrome or VS Code).
    ///   - projectId: Project ID used for the window token.
    ///   - launchAction: Closure that launches a new window if none exists.
    ///   - windowLabel: Human-readable label for logging (e.g., "Chrome", "VS Code").
    ///   - eventSource: Stable log event key source (e.g., "chrome", "vscode").
    /// - Returns: The found or launched window on success.
    private func findOrLaunchWindow(
        appBundleId: String,
        projectId: String,
        launchAction: () -> Result<Void, ApCoreError>,
        windowLabel: String,
        eventSource: String
    ) async -> Result<ApWindow, ProjectError> {
        // Find existing tagged window (global search with fallback)
        if let window = findWindowByToken(appBundleId: appBundleId, projectId: projectId) {
            logEvent(Self.activationWindowEventName(source: eventSource, action: "found"), context: ["window_id": "\(window.windowId)"])
            return .success(window)
        }

        // Launch a new window
        switch launchAction() {
        case .failure(let error):
            logEvent(Self.activationWindowEventName(source: eventSource, action: "launch_failed"), level: .error, context: ["error": error.message])
            let projectError: ProjectError = windowLabel == "Chrome"
                ? .chromeLaunchFailed(detail: "\(windowLabel) launch failed: \(error.message)")
                : .ideLaunchFailed(detail: "\(windowLabel) launch failed: \(error.message)")
            return .failure(projectError)
        case .success:
            logEvent(Self.activationWindowEventName(source: eventSource, action: "launched"), context: ["project_id": projectId])
        }

        // Poll until window appears
        return await pollForWindowByToken(appBundleId: appBundleId, projectId: projectId, windowLabel: windowLabel)
    }

    // MARK: - Private Helpers

    /// Returns an AgentPanel project ID from a workspace name.
    /// - Parameter workspace: Raw AeroSpace workspace name.
    /// - Returns: Project ID when workspace uses the `ap-` prefix, otherwise nil.
    private static func projectId(fromWorkspace workspace: String) -> String? {
        guard workspace.hasPrefix(Self.workspacePrefix) else {
            return nil
        }
        return String(workspace.dropFirst(Self.workspacePrefix.count))
    }

    /// Polls until the target workspace is confirmed focused.
    ///
    /// Matches the shell script's `ensure_workspace_focused`: repeatedly calls
    /// `summon-workspace`/`workspace` and verifies via `list-workspaces --focused`
    /// until the target workspace is reported, with a bounded timeout.
    private func ensureWorkspaceFocused(name: String) async -> Bool {
        let deadline = Date().addingTimeInterval(Self.windowPollTimeout)

        while Date() < deadline {
            // Check if already focused
            if case .success(let workspaces) = aerospace.listWorkspacesWithFocus(),
               workspaces.contains(where: { $0.workspace == name && $0.isFocused }) {
                logEvent("focus.workspace.verified", context: ["workspace": name])
                return true
            }

            // Attempt to focus (summon-workspace with fallback to workspace)
            _ = aerospace.focusWorkspace(name: name)

            try? await Task.sleep(nanoseconds: UInt64(Self.windowPollInterval * 1_000_000_000))
        }

        return false
    }

    /// Finds a tagged window for the given app across all monitors.
    private func findWindowByToken(appBundleId: String, projectId: String) -> ApWindow? {
        guard case .success(let windows) = aerospace.listWindowsForApp(bundleId: appBundleId) else {
            return nil
        }
        let token = "\(ApIdeToken.prefix)\(projectId)"
        return windows.first { $0.windowTitle.contains(token) }
    }

    /// Polls for a tagged window to appear after launch.
    private func pollForWindowByToken(
        appBundleId: String,
        projectId: String,
        windowLabel: String
    ) async -> Result<ApWindow, ProjectError> {
        let deadline = Date().addingTimeInterval(Self.windowPollTimeout)

        while Date() < deadline {
            if let window = findWindowByToken(appBundleId: appBundleId, projectId: projectId) {
                return .success(window)
            }
            try? await Task.sleep(nanoseconds: UInt64(Self.windowPollInterval * 1_000_000_000))
        }

        return .failure(.windowNotFound(detail: "\(windowLabel) window did not appear within timeout"))
    }

    /// Polls until both windows are in the target workspace.
    private func pollForWindowsInWorkspace(chromeWindowId: Int, ideWindowId: Int, workspace: String) async -> Result<Void, ProjectError> {
        let deadline = Date().addingTimeInterval(Self.windowPollTimeout)

        while Date() < deadline {
            switch aerospace.listWindowsWorkspace(workspace: workspace) {
            case .failure:
                // Workspace might not be queryable yet, keep polling
                break
            case .success(let windows):
                let windowIds = Set(windows.map { $0.windowId })
                if windowIds.contains(chromeWindowId) && windowIds.contains(ideWindowId) {
                    logEvent("select.windows_verified_in_workspace", context: ["workspace": workspace])
                    return .success(())
                }
            }

            try? await Task.sleep(nanoseconds: UInt64(Self.windowPollInterval * 1_000_000_000))
        }

        return .failure(.aeroSpaceError(detail: "Windows did not arrive in workspace within timeout"))
    }

    // MARK: - Recency Tracking

    private func recordActivation(projectId: String) {
        // Remove existing entry if present
        recentProjectIds.removeAll { $0 == projectId }
        // Add to front
        recentProjectIds.insert(projectId, at: 0)
        // Trim to max
        if recentProjectIds.count > Self.maxRecentProjects {
            recentProjectIds = Array(recentProjectIds.prefix(Self.maxRecentProjects))
        }
        saveRecency()
    }

    private func loadRecency() {
        let path = recencyFilePath.path
        guard FileManager.default.fileExists(atPath: path) else {
            recentProjectIds = []
            return
        }

        do {
            let data = try Data(contentsOf: recencyFilePath)
            let ids = try JSONDecoder().decode([String].self, from: data)
            recentProjectIds = ids
        } catch {
            recentProjectIds = []
            logEvent(
                "recency.load_failed",
                level: .warn,
                message: String(describing: error),
                context: ["path": path]
            )
        }
    }

    private func saveRecency() {
        let data: Data
        do {
            data = try JSONEncoder().encode(recentProjectIds)
        } catch {
            logEvent(
                "recency.encode_failed",
                level: .warn,
                message: String(describing: error),
                context: ["path": recencyFilePath.path]
            )
            return
        }

        // Ensure directory exists
        let directory = recencyFilePath.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            logEvent(
                "recency.directory_create_failed",
                level: .warn,
                message: String(describing: error),
                context: ["path": directory.path]
            )
            return
        }

        do {
            try data.write(to: recencyFilePath, options: .atomic)
        } catch {
            logEvent(
                "recency.write_failed",
                level: .warn,
                message: String(describing: error),
                context: ["path": recencyFilePath.path]
            )
        }
    }

    // MARK: - Logging

    private func logEvent(_ event: String, level: LogLevel = .info, message: String? = nil, context: [String: String]? = nil) {
        _ = logger.log(event: "project_manager.\(event)", level: level, message: message, context: context)
    }

    /// Builds an activation event name from a stable source key and action.
    ///
    /// Example: `select.chrome_found`, `select.vscode_launch_failed`.
    static func activationWindowEventName(source: String, action: String) -> String {
        "select.\(source)_\(action)"
    }
}
