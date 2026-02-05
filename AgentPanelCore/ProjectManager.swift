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
        switch aerospace.focusWindow(windowId: focus.windowId) {
        case .failure(let error):
            logEvent("focus.restore.failed", level: .warn, message: error.message, context: ["window_id": "\(focus.windowId)"])
            return false
        case .success:
            logEvent("focus.restored", context: ["window_id": "\(focus.windowId)"])
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
    /// 2. Capture current focus (for later exit)
    /// 3. Ensure workspace exists
    /// 4. Check if Chrome exists; open if not
    /// 5. Check if IDE exists; open if not
    /// 6. Poll until both windows exist
    /// 7. Move Chrome to workspace if not there
    /// 8. Move IDE to workspace if not there, then focus it
    /// 9. Record activation
    public func selectProject(projectId: String) -> Result<Void, ProjectError> {
        guard config != nil else {
            return .failure(.configNotLoaded)
        }

        guard let project = projects.first(where: { $0.id == projectId }) else {
            logEvent("select.project_not_found", level: .warn, context: ["project_id": projectId])
            return .failure(.projectNotFound(projectId: projectId))
        }

        let workspace = Self.workspacePrefix + projectId

        // Capture current focus (only if we haven't already)
        if capturedProjectExitFocus == nil {
            capturedProjectExitFocus = captureCurrentFocus()
        }

        // Ensure workspace exists
        switch ensureWorkspaceExists(workspace: workspace) {
        case .failure(let error):
            return .failure(error)
        case .success:
            break
        }

        // Check if Chrome exists; open if not
        let chromeExistsBefore = chromeWindowExists(projectId: projectId)
        if !chromeExistsBefore {
            switch chromeLauncher.openNewWindow(identifier: projectId) {
            case .failure(let error):
                logEvent("select.chrome_open_failed", level: .error, context: ["error": error.message])
                return .failure(.chromeLaunchFailed(detail: error.message))
            case .success:
                logEvent("select.chrome_opened", context: ["project_id": projectId])
            }
        }

        // Check if IDE exists; open if not
        let ideExistsBefore = ideWindowExists(projectId: projectId)
        if !ideExistsBefore {
            switch ideLauncher.openNewWindow(identifier: projectId, projectPath: project.path) {
            case .failure(let error):
                logEvent("select.ide_open_failed", level: .error, context: ["error": error.message])
                return .failure(.ideLaunchFailed(detail: error.message))
            case .success:
                logEvent("select.ide_opened", context: ["project_id": projectId])
            }
        }

        // Poll until both windows exist
        if !chromeExistsBefore || !ideExistsBefore {
            switch pollForWindows(projectId: projectId) {
            case .failure(let error):
                return .failure(error)
            case .success:
                break
            }
        }

        // Move Chrome to workspace if not there
        var movedChrome = false
        if let chromeWindow = findChromeWindow(projectId: projectId) {
            if chromeWindow.workspace != workspace {
                switch aerospace.moveWindowToWorkspace(workspace: workspace, windowId: chromeWindow.windowId) {
                case .failure(let error):
                    return .failure(.aeroSpaceError(detail: error.message))
                case .success:
                    movedChrome = true
                    logEvent("select.chrome_moved", context: ["workspace": workspace])
                }
            }
        }

        // Move IDE to workspace if not there
        var movedIde = false
        if let ideWindow = findIdeWindow(projectId: projectId) {
            if ideWindow.workspace != workspace {
                switch aerospace.moveWindowToWorkspace(workspace: workspace, windowId: ideWindow.windowId) {
                case .failure(let error):
                    return .failure(.aeroSpaceError(detail: error.message))
                case .success:
                    movedIde = true
                    logEvent("select.ide_moved", context: ["workspace": workspace])
                }
            }
        }

        // If we moved any windows, verify they arrived in the workspace
        if movedChrome || movedIde {
            switch pollForWindowsInWorkspace(projectId: projectId, workspace: workspace) {
            case .failure(let error):
                return .failure(error)
            case .success:
                break
            }
        }

        // Focus the IDE window (use fresh window data after moves)
        if let ideWindow = findIdeWindow(projectId: projectId) {
            switch aerospace.focusWindow(windowId: ideWindow.windowId) {
            case .failure(let error):
                return .failure(.aeroSpaceError(detail: error.message))
            case .success:
                logEvent("select.ide_focused", context: ["window_id": "\(ideWindow.windowId)"])
            }
        }

        // Record activation
        recordActivation(projectId: projectId)
        logEvent("select.completed", context: ["project_id": projectId])

        return .success(())
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

    // MARK: - Private Helpers

    private func ensureWorkspaceExists(workspace: String) -> Result<Void, ProjectError> {
        switch aerospace.workspaceExists(workspace) {
        case .failure(let error):
            return .failure(.aeroSpaceError(detail: error.message))
        case .success(true):
            return .success(())
        case .success(false):
            switch aerospace.createWorkspace(workspace) {
            case .failure(let error):
                return .failure(.aeroSpaceError(detail: error.message))
            case .success:
                logEvent("select.workspace_created", context: ["workspace": workspace])
                return .success(())
            }
        }
    }

    private func chromeWindowExists(projectId: String) -> Bool {
        findChromeWindow(projectId: projectId) != nil
    }

    private func ideWindowExists(projectId: String) -> Bool {
        findIdeWindow(projectId: projectId) != nil
    }

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
        // Look for the AP:<projectId> token in the window title
        let token = "\(ApIdeToken.prefix)\(projectId)"
        return windows.first { $0.windowTitle.contains(token) }
    }

    private func pollForWindows(projectId: String) -> Result<Void, ProjectError> {
        let deadline = Date().addingTimeInterval(Self.windowPollTimeout)

        while Date() < deadline {
            let chromeExists = chromeWindowExists(projectId: projectId)
            let ideExists = ideWindowExists(projectId: projectId)

            if chromeExists && ideExists {
                return .success(())
            }

            Thread.sleep(forTimeInterval: Self.windowPollInterval)
        }

        let chromeExists = chromeWindowExists(projectId: projectId)
        let ideExists = ideWindowExists(projectId: projectId)

        if !chromeExists && !ideExists {
            return .failure(.chromeLaunchFailed(detail: "Chrome and IDE windows did not appear within timeout"))
        } else if !chromeExists {
            return .failure(.chromeLaunchFailed(detail: "Chrome window did not appear within timeout"))
        } else {
            return .failure(.ideLaunchFailed(detail: "IDE window did not appear within timeout"))
        }
    }

    private func pollForWindowsInWorkspace(projectId: String, workspace: String) -> Result<Void, ProjectError> {
        let deadline = Date().addingTimeInterval(Self.windowPollTimeout)

        while Date() < deadline {
            let chromeInWorkspace = findChromeWindow(projectId: projectId)?.workspace == workspace
            let ideInWorkspace = findIdeWindow(projectId: projectId)?.workspace == workspace

            if chromeInWorkspace && ideInWorkspace {
                logEvent("select.windows_verified_in_workspace", context: ["workspace": workspace])
                return .success(())
            }

            Thread.sleep(forTimeInterval: Self.windowPollInterval)
        }

        let chromeInWorkspace = findChromeWindow(projectId: projectId)?.workspace == workspace
        let ideInWorkspace = findIdeWindow(projectId: projectId)?.workspace == workspace

        if !chromeInWorkspace && !ideInWorkspace {
            return .failure(.aeroSpaceError(detail: "Chrome and IDE windows did not arrive in workspace within timeout"))
        } else if !chromeInWorkspace {
            return .failure(.aeroSpaceError(detail: "Chrome window did not arrive in workspace within timeout"))
        } else {
            return .failure(.aeroSpaceError(detail: "IDE window did not arrive in workspace within timeout"))
        }
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
