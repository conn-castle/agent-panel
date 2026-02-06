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

    /// The currently active project, derived from the focused workspace.
    public var activeProject: ProjectConfig? {
        guard case .success(let workspaces) = aerospace.listWorkspacesFocused(),
              let focused = workspaces.first,
              focused.hasPrefix(Self.workspacePrefix) else {
            return nil
        }

        let projectId = String(focused.dropFirst(Self.workspacePrefix.count))
        return projects.first { $0.id == projectId }
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

    /// Activates a project by ID.
    ///
    /// Steps:
    /// 1. Look up project in config
    /// 2. Store pre-captured focus (for later exit)
    /// 3. Run Chrome and IDE setup in parallel (find, launch if needed, move to workspace)
    /// 4. Verify both windows arrived in workspace
    /// 5. Record activation
    ///
    /// - Parameters:
    ///   - projectId: The project ID to activate.
    ///   - preCapturedFocus: Focus state captured before showing UI, used for restoring
    ///     focus when exiting the project later.
    /// - Returns: The IDE window ID on success, for focusing after UI dismissal.
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

        // Run Chrome and IDE setup in parallel
        async let chromeResult = prepareChrome(projectId: projectId, targetWorkspace: targetWorkspace)
        async let ideResult = prepareIde(projectId: projectId, targetWorkspace: targetWorkspace, projectPath: project.path)

        // Wait for both to complete
        let (chrome, ide) = await (chromeResult, ideResult)

        // Check for errors
        let chromeWindow: ApWindow
        switch chrome {
        case .failure(let error):
            return .failure(error)
        case .success(let window):
            chromeWindow = window
        }

        let ideWindow: ApWindow
        switch ide {
        case .failure(let error):
            return .failure(error)
        case .success(let window):
            ideWindow = window
        }

        // Verify both windows are in the workspace
        switch await pollForWindowsInWorkspace(
            chromeWindowId: chromeWindow.windowId,
            ideWindowId: ideWindow.windowId,
            workspace: targetWorkspace
        ) {
        case .failure(let error):
            return .failure(error)
        case .success:
            break
        }

        // Record activation
        recordActivation(projectId: projectId)
        logEvent("select.completed", context: ["project_id": projectId, "ide_window_id": "\(ideWindow.windowId)"])

        return .success(ideWindow.windowId)
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
        guard activeProject != nil else {
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

    // MARK: - Async Window Setup

    /// Prepares a Chrome window for the project: finds or launches, then moves to target workspace.
    /// - Parameters:
    ///   - projectId: The project ID.
    ///   - targetWorkspace: The workspace to move the window to.
    /// - Returns: The Chrome window on success.
    private func prepareChrome(projectId: String, targetWorkspace: String) async -> Result<ApWindow, ProjectError> {
        // Find existing Chrome window
        var chromeWindow = findChromeWindow(projectId: projectId)

        // Launch if not found
        if chromeWindow == nil {
            switch chromeLauncher.openNewWindow(identifier: projectId) {
            case .failure(let error):
                logEvent("select.chrome_launch_failed", level: .error, context: ["error": error.message])
                return .failure(.chromeLaunchFailed(detail: error.message))
            case .success:
                logEvent("select.chrome_launched", context: ["project_id": projectId])
            }

            // Poll until window appears
            switch await pollForChromeWindow(projectId: projectId) {
            case .failure(let error):
                return .failure(error)
            case .success(let window):
                chromeWindow = window
            }
        }

        guard let window = chromeWindow else {
            return .failure(.chromeLaunchFailed(detail: "Chrome window not found"))
        }

        // Move to workspace if needed (auto-creates workspace)
        if window.workspace != targetWorkspace {
            switch aerospace.moveWindowToWorkspace(workspace: targetWorkspace, windowId: window.windowId) {
            case .failure(let error):
                return .failure(.aeroSpaceError(detail: error.message))
            case .success:
                logEvent("select.chrome_moved", context: ["workspace": targetWorkspace])
            }
            // Return window with updated workspace
            return .success(ApWindow(
                windowId: window.windowId,
                appBundleId: window.appBundleId,
                workspace: targetWorkspace,
                windowTitle: window.windowTitle
            ))
        }

        return .success(window)
    }

    /// Prepares an IDE window for the project: finds or launches, then moves to target workspace.
    /// - Parameters:
    ///   - projectId: The project ID.
    ///   - targetWorkspace: The workspace to move the window to.
    ///   - projectPath: The path to open in the IDE.
    /// - Returns: The IDE window on success.
    private func prepareIde(projectId: String, targetWorkspace: String, projectPath: String) async -> Result<ApWindow, ProjectError> {
        // Find existing IDE window
        var ideWindow = findIdeWindow(projectId: projectId)

        // Launch if not found
        if ideWindow == nil {
            switch ideLauncher.openNewWindow(identifier: projectId, projectPath: projectPath) {
            case .failure(let error):
                logEvent("select.ide_launch_failed", level: .error, context: ["error": error.message])
                return .failure(.ideLaunchFailed(detail: error.message))
            case .success:
                logEvent("select.ide_launched", context: ["project_id": projectId])
            }

            // Poll until window appears
            switch await pollForIdeWindow(projectId: projectId) {
            case .failure(let error):
                return .failure(error)
            case .success(let window):
                ideWindow = window
            }
        }

        guard let window = ideWindow else {
            return .failure(.ideLaunchFailed(detail: "IDE window not found"))
        }

        // Move to workspace if needed (auto-creates workspace)
        if window.workspace != targetWorkspace {
            switch aerospace.moveWindowToWorkspace(workspace: targetWorkspace, windowId: window.windowId) {
            case .failure(let error):
                return .failure(.aeroSpaceError(detail: error.message))
            case .success:
                logEvent("select.ide_moved", context: ["workspace": targetWorkspace])
            }
            // Return window with updated workspace
            return .success(ApWindow(
                windowId: window.windowId,
                appBundleId: window.appBundleId,
                workspace: targetWorkspace,
                windowTitle: window.windowTitle
            ))
        }

        return .success(window)
    }

    // MARK: - Private Helpers

    private func findChromeWindow(projectId: String) -> ApWindow? {
        guard case .success(let windows) = aerospace.listChromeWindowsOnFocusedMonitor() else {
            return nil
        }
        let token = "\(ApIdeToken.prefix)\(projectId)"
        return windows.first { $0.windowTitle.contains(token) }
    }

    private func findIdeWindow(projectId: String) -> ApWindow? {
        guard case .success(let windows) = aerospace.listVSCodeWindowsOnFocusedMonitor() else {
            return nil
        }
        let token = "\(ApIdeToken.prefix)\(projectId)"
        return windows.first { $0.windowTitle.contains(token) }
    }

    private func pollForChromeWindow(projectId: String) async -> Result<ApWindow, ProjectError> {
        let deadline = Date().addingTimeInterval(Self.windowPollTimeout)

        while Date() < deadline {
            if let window = findChromeWindow(projectId: projectId) {
                return .success(window)
            }
            try? await Task.sleep(nanoseconds: UInt64(Self.windowPollInterval * 1_000_000_000))
        }

        return .failure(.chromeLaunchFailed(detail: "Chrome window did not appear within timeout"))
    }

    private func pollForIdeWindow(projectId: String) async -> Result<ApWindow, ProjectError> {
        let deadline = Date().addingTimeInterval(Self.windowPollTimeout)

        while Date() < deadline {
            if let window = findIdeWindow(projectId: projectId) {
                return .success(window)
            }
            try? await Task.sleep(nanoseconds: UInt64(Self.windowPollInterval * 1_000_000_000))
        }

        return .failure(.ideLaunchFailed(detail: "IDE window did not appear within timeout"))
    }

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
        guard let data = try? Data(contentsOf: recencyFilePath),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            recentProjectIds = []
            return
        }
        recentProjectIds = ids
    }

    private func saveRecency() {
        guard let data = try? JSONEncoder().encode(recentProjectIds) else {
            return
        }

        // Ensure directory exists
        let directory = recencyFilePath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try? data.write(to: recencyFilePath)
    }

    // MARK: - Logging

    private func logEvent(_ event: String, level: LogLevel = .info, message: String? = nil, context: [String: String]? = nil) {
        _ = logger.log(event: "project_manager.\(event)", level: level, message: message, context: context)
    }
}
