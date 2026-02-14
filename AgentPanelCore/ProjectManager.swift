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

/// Success result from project activation.
public struct ProjectActivationSuccess: Equatable, Sendable {
    /// AeroSpace window ID for the IDE window (used for post-dismissal focusing).
    public let ideWindowId: Int
    /// Warning message if tab restore failed (non-fatal).
    public let tabRestoreWarning: String?
    /// Warning message if window positioning failed (non-fatal).
    public let layoutWarning: String?

    /// Creates a new activation success result.
    /// - Parameters:
    ///   - ideWindowId: AeroSpace window ID for the IDE window.
    ///   - tabRestoreWarning: Optional non-fatal warning if tab restore failed.
    ///   - layoutWarning: Optional non-fatal warning if window positioning failed.
    public init(ideWindowId: Int, tabRestoreWarning: String?, layoutWarning: String? = nil) {
        self.ideWindowId = ideWindowId
        self.tabRestoreWarning = tabRestoreWarning
        self.layoutWarning = layoutWarning
    }
}

/// Success result from project close.
public struct ProjectCloseSuccess: Equatable, Sendable {
    /// Warning message if tab capture failed (non-fatal).
    public let tabCaptureWarning: String?

    /// Creates a new close success result.
    /// - Parameter tabCaptureWarning: Optional non-fatal warning if tab capture failed.
    public init(tabCaptureWarning: String?) {
        self.tabCaptureWarning = tabCaptureWarning
    }
}

// Note: CapturedFocus and internal protocols (AeroSpaceProviding,
// IdeLauncherProviding, ChromeLauncherProviding) are defined in Dependencies.swift

// MARK: - FocusStack

/// LIFO stack of non-project focus entries for "exit project space" restoration.
///
/// Only non-project windows should be pushed (the caller is responsible for filtering).
/// Not persisted to disk — window IDs don't survive app restarts.
struct FocusStack {
    private var entries: [CapturedFocus] = []
    private let maxSize: Int

    init(maxSize: Int = 20) {
        self.maxSize = maxSize
    }

    /// Pushes a focus entry onto the stack.
    ///
    /// Deduplicates: if the top entry already matches this windowId, the push is skipped.
    /// Enforces maxSize by dropping the oldest (first) entry when full.
    mutating func push(_ focus: CapturedFocus) {
        // Deduplicate consecutive pushes of the same window
        if let top = entries.last, top.windowId == focus.windowId {
            return
        }
        entries.append(focus)
        // Enforce max size — drop oldest
        if entries.count > maxSize {
            entries.removeFirst(entries.count - maxSize)
        }
    }

    /// Pops entries from the top until one passes the validity check.
    ///
    /// Invalid entries (stale windows) are discarded. Returns nil if the stack
    /// is exhausted without finding a valid entry.
    mutating func popFirstValid(isValid: (CapturedFocus) -> Bool) -> CapturedFocus? {
        while let entry = entries.popLast() {
            if isValid(entry) {
                return entry
            }
            // Entry invalid (window gone), discard and try next
        }
        return nil
    }

    var isEmpty: Bool { entries.isEmpty }
    var count: Int { entries.count }
}

// MARK: - ProjectManager

/// Single point of entry for all project operations.
///
/// Handles:
/// - Config loading
/// - Project listing and sorting
/// - Project selection, closing, and exit
/// - Focus capture/restore for switcher UX
///
/// Thread Safety: Not thread-safe. Most methods must be called from the main thread.
/// Exception: `restoreFocus(_:)`, `focusWorkspace(name:)`, and `focusWindow(windowId:)` may be
/// called from a detached task for non-blocking focus restoration (these only invoke AeroSpace CLI
/// commands and do not mutate ProjectManager state).
public final class ProjectManager {
    /// Prefix for all AgentPanel workspaces.
    public static let workspacePrefix = "ap-"

    private static let windowPollTimeout: TimeInterval = 10.0
    private static let windowPollInterval: TimeInterval = 0.1
    private static let maxRecentProjects = 100

    // Config
    private var config: Config?
    private let configLoader: () -> Result<ConfigLoadSuccess, ConfigLoadError>

    /// Non-fatal warnings from the most recent config load.
    public private(set) var configWarnings: [ConfigFinding] = []

    // Recency tracking - simple list of project IDs, most recent first
    private var recentProjectIds: [String] = []
    private let recencyFilePath: URL

    // File I/O abstraction for testability (recency + persistence).
    private let fileSystem: FileSystem

    // Focus stack for "exit project space" restoration (non-project windows only)
    private var focusStack = FocusStack()

    // Internal dependencies
    private let aerospace: AeroSpaceProviding
    private let ideLauncher: IdeLauncherProviding
    private let agentLayerIdeLauncher: IdeLauncherProviding
    private let chromeLauncher: ChromeLauncherProviding
    private let chromeTabStore: ChromeTabStore
    private let chromeTabCapture: ChromeTabCapturing
    private let gitRemoteResolver: GitRemoteResolving
    private let windowPositioner: WindowPositioning?
    private let windowPositionStore: WindowPositionStoring?
    private let screenModeDetector: ScreenModeDetecting?
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
    ///
    /// - Parameters:
    ///   - windowPositioner: Window positioning provider (from AppKit module). Pass nil to disable positioning.
    ///   - screenModeDetector: Screen mode detection provider (from AppKit module). Pass nil to disable positioning.
    public init(
        windowPositioner: WindowPositioning? = nil,
        screenModeDetector: ScreenModeDetecting? = nil
    ) {
        let dataPaths = DataPaths.default()
        self.aerospace = ApAeroSpace()
        self.ideLauncher = ApVSCodeLauncher()
        self.agentLayerIdeLauncher = ApAgentLayerVSCodeLauncher()
        self.chromeLauncher = ApChromeLauncher()
        self.chromeTabStore = ChromeTabStore(directory: dataPaths.chromeTabsDirectory)
        self.chromeTabCapture = ApChromeTabController()
        self.gitRemoteResolver = GitRemoteResolver()
        self.windowPositioner = windowPositioner
        self.screenModeDetector = screenModeDetector
        self.windowPositionStore = (windowPositioner != nil && screenModeDetector != nil)
            ? WindowPositionStore(filePath: dataPaths.windowLayoutsFile)
            : nil
        self.logger = AgentPanelLogger()
        self.recencyFilePath = dataPaths.recentProjectsFile
        self.configLoader = { Config.loadDefault() }
        self.fileSystem = DefaultFileSystem()

        loadRecency()
    }

    /// Creates a ProjectManager with injected dependencies (for testing).
    init(
        aerospace: AeroSpaceProviding,
        ideLauncher: IdeLauncherProviding,
        agentLayerIdeLauncher: IdeLauncherProviding,
        chromeLauncher: ChromeLauncherProviding,
        chromeTabStore: ChromeTabStore,
        chromeTabCapture: ChromeTabCapturing,
        gitRemoteResolver: GitRemoteResolving,
        logger: AgentPanelLogging,
        recencyFilePath: URL,
        configLoader: @escaping () -> Result<ConfigLoadSuccess, ConfigLoadError> = { Config.loadDefault() },
        fileSystem: FileSystem = DefaultFileSystem(),
        windowPositioner: WindowPositioning? = nil,
        windowPositionStore: WindowPositionStoring? = nil,
        screenModeDetector: ScreenModeDetecting? = nil
    ) {
        self.aerospace = aerospace
        self.ideLauncher = ideLauncher
        self.agentLayerIdeLauncher = agentLayerIdeLauncher
        self.chromeLauncher = chromeLauncher
        self.chromeTabStore = chromeTabStore
        self.chromeTabCapture = chromeTabCapture
        self.gitRemoteResolver = gitRemoteResolver
        self.windowPositioner = windowPositioner
        self.windowPositionStore = windowPositionStore
        self.screenModeDetector = screenModeDetector
        self.logger = logger
        self.recencyFilePath = recencyFilePath
        self.configLoader = configLoader
        self.fileSystem = fileSystem

        loadRecency()
    }

    // MARK: - Configuration

    /// Sets config directly for testing (internal; accessible via @testable import).
    func loadTestConfig(_ config: Config) {
        self.config = config
    }

    /// Pushes a focus entry directly onto the focus stack (no filtering).
    ///
    /// Test-only helper for injecting known stack state. Does NOT replicate
    /// the project-workspace filtering from `selectProject` — that logic is
    /// tested via integration tests that drive through `selectProject` directly.
    /// Internal; accessible via @testable import.
    func pushFocusForTest(_ focus: CapturedFocus) {
        focusStack.push(focus)
    }

    /// Loads configuration from the default path.
    ///
    /// Call this before using other methods. Returns the config on success.
    @discardableResult
    public func loadConfig() -> Result<ConfigLoadSuccess, ConfigLoadError> {
        switch configLoader() {
        case .success(let success):
            self.config = success.config
            self.configWarnings = success.warnings
            logEvent("config.loaded", context: ["project_count": "\(success.config.projects.count)"])
            return .success(success)
        case .failure(let error):
            self.config = nil
            self.configWarnings = []
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
            let captured = CapturedFocus(windowId: window.windowId, appBundleId: window.appBundleId, workspace: window.workspace)
            logEvent("focus.captured", context: [
                "window_id": "\(captured.windowId)",
                "app_bundle_id": captured.appBundleId,
                "workspace": captured.workspace
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
    /// - Returns: Activation success (IDE window ID + optional tab restore warning) or error.
    public func selectProject(projectId: String, preCapturedFocus: CapturedFocus) async -> Result<ProjectActivationSuccess, ProjectError> {
        guard config != nil else {
            return .failure(.configNotLoaded)
        }

        guard let project = projects.first(where: { $0.id == projectId }) else {
            logEvent("select.project_not_found", level: .warn, context: ["project_id": projectId])
            return .failure(.projectNotFound(projectId: projectId))
        }

        let targetWorkspace = Self.workspacePrefix + projectId

        // Push pre-captured focus for "exit project space" restoration.
        // Only push if the user is coming from outside project space.
        // Project-to-project switches (ap-* workspace) are not recorded.
        if !preCapturedFocus.workspace.hasPrefix(Self.workspacePrefix) {
            focusStack.push(preCapturedFocus)
        } else {
            logEvent("focus.push_skipped_project_workspace", context: [
                "workspace": preCapturedFocus.workspace,
                "window_id": "\(preCapturedFocus.windowId)"
            ])
        }

        // --- Phase 1: Find or launch all windows (no moves yet) ---

        let chromeWindow: ApWindow
        var chromeFreshlyLaunched = false
        var tabRestoreWarning: String?

        // Check for existing Chrome window first (avoids resolving URLs when not needed)
        if let existingWindow = findWindowByToken(appBundleId: ApChromeLauncher.bundleId, projectId: projectId) {
            logEvent(Self.activationWindowEventName(source: "chrome", action: "found"), context: ["window_id": "\(existingWindow.windowId)"])
            chromeWindow = existingWindow
        } else {
            // Chrome needs a fresh launch — resolve URLs now
            let chromeInitialURLs = resolveInitialURLs(project: project, projectId: projectId)

            switch await findOrLaunchWindow(
                appBundleId: ApChromeLauncher.bundleId,
                projectId: projectId,
                launchAction: { self.chromeLauncher.openNewWindow(identifier: projectId, initialURLs: chromeInitialURLs) },
                windowLabel: "Chrome",
                eventSource: "chrome"
            ) {
            case .failure(let error):
                // If launch-with-tabs failed and we had tabs, retry without tabs
                if !chromeInitialURLs.isEmpty {
                    logEvent("select.chrome_tab_launch_failed", level: .warn, message: "\(error)")
                    switch await findOrLaunchWindow(
                        appBundleId: ApChromeLauncher.bundleId,
                        projectId: projectId,
                        launchAction: { self.chromeLauncher.openNewWindow(identifier: projectId, initialURLs: []) },
                        windowLabel: "Chrome",
                        eventSource: "chrome"
                    ) {
                    case .failure(let fallbackError):
                        return .failure(fallbackError)
                    case .success(let outcome):
                        chromeWindow = outcome.window
                        chromeFreshlyLaunched = outcome.wasLaunched
                        tabRestoreWarning = "Chrome launched without tabs (tab restore failed)"
                    }
                } else {
                    return .failure(error)
                }
            case .success(let outcome):
                chromeWindow = outcome.window
                chromeFreshlyLaunched = outcome.wasLaunched
            }
        }

        let ideWindow: ApWindow
        let selectedIdeLauncher = project.useAgentLayer ? agentLayerIdeLauncher : ideLauncher
        switch await findOrLaunchWindow(
            appBundleId: ApVSCodeLauncher.bundleId,
            projectId: projectId,
            launchAction: {
                selectedIdeLauncher.openNewWindow(
                    identifier: projectId,
                    projectPath: project.path,
                    remoteAuthority: project.remote
                )
            },
            windowLabel: "VS Code",
            eventSource: "vscode"
        ) {
        case .failure(let error):
            return .failure(error)
        case .success(let outcome):
            ideWindow = outcome.window
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

        if chromeFreshlyLaunched {
            logEvent("select.chrome_fresh_launch", context: ["project_id": projectId])
        }

        // Position windows (non-fatal)
        let layoutWarning = positionWindows(projectId: projectId)

        // Record activation
        recordActivation(projectId: projectId)
        logEvent("select.completed", context: ["project_id": projectId, "ide_window_id": "\(ideWindowId)"])

        return .success(ProjectActivationSuccess(
            ideWindowId: ideWindowId,
            tabRestoreWarning: tabRestoreWarning,
            layoutWarning: layoutWarning
        ))
    }

    /// Closes a project by ID and restores focus to the previous non-project window.
    public func closeProject(projectId: String) -> Result<ProjectCloseSuccess, ProjectError> {
        guard config != nil else {
            return .failure(.configNotLoaded)
        }

        guard projects.contains(where: { $0.id == projectId }) else {
            return .failure(.projectNotFound(projectId: projectId))
        }

        // Capture Chrome tabs before closing (non-fatal)
        let tabCaptureWarning = performTabCapture(projectId: projectId)

        // Capture window positions before closing (non-fatal)
        captureWindowPositions(projectId: projectId)

        let workspace = Self.workspacePrefix + projectId

        switch aerospace.closeWorkspace(name: workspace) {
        case .failure(let error):
            logEvent("close.failed", level: .error, context: ["error": error.message])
            return .failure(.aeroSpaceError(detail: error.message))
        case .success:
            logEvent("close.workspace_closed", context: ["project_id": projectId])
        }

        // Restore focus to the previous non-project window (pop from focus stack)
        if let focus = focusStack.popFirstValid(isValid: { entry in
            self.focusWindow(windowId: entry.windowId)
        }) {
            logEvent("close.focus_restored", context: [
                "window_id": "\(focus.windowId)",
                "workspace": focus.workspace
            ])
        } else if let ws = fallbackToNonProjectWorkspace() {
            logEvent("close.focus_fallback_workspace", context: ["workspace": ws])
        } else {
            logEvent("close.focus_restore_exhausted", level: .warn)
        }

        logEvent("close.completed", context: ["project_id": projectId])
        return .success(ProjectCloseSuccess(tabCaptureWarning: tabCaptureWarning))
    }

    /// Moves a window to the specified project's workspace.
    /// - Parameters:
    ///   - windowId: AeroSpace window ID of the window to move.
    ///   - projectId: Target project ID (workspace will be `ap-<projectId>`).
    /// - Returns: Success or error.
    public func moveWindowToProject(windowId: Int, projectId: String) -> Result<Void, ProjectError> {
        guard config != nil else {
            return .failure(.configNotLoaded)
        }
        guard projects.contains(where: { $0.id == projectId }) else {
            return .failure(.projectNotFound(projectId: projectId))
        }
        let targetWorkspace = Self.workspacePrefix + projectId
        switch aerospace.moveWindowToWorkspace(workspace: targetWorkspace, windowId: windowId, focusFollows: false) {
        case .success:
            logEvent("move_window.completed", context: [
                "window_id": "\(windowId)",
                "project_id": projectId,
                "workspace": targetWorkspace
            ])
            return .success(())
        case .failure(let error):
            logEvent("move_window.failed", level: .error, message: error.message, context: [
                "window_id": "\(windowId)",
                "project_id": projectId
            ])
            return .failure(.aeroSpaceError(detail: error.message))
        }
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

        guard let activeProjectId = state.activeProjectId else {
            logEvent("exit.no_active_project", level: .warn)
            return .failure(.noActiveProject)
        }

        // Capture window positions before exiting (non-fatal)
        captureWindowPositions(projectId: activeProjectId)

        if let focus = focusStack.popFirstValid(isValid: { entry in
            self.focusWindow(windowId: entry.windowId)
        }) {
            logEvent("exit.focus_restored", context: [
                "window_id": "\(focus.windowId)",
                "workspace": focus.workspace
            ])
            logEvent("exit.completed")
            return .success(())
        } else if let ws = fallbackToNonProjectWorkspace() {
            logEvent("exit.focus_fallback_workspace", context: ["workspace": ws])
            logEvent("exit.completed")
            return .success(())
        } else {
            logEvent("exit.no_previous_window", level: .warn)
            return .failure(.noPreviousWindow)
        }
    }

    /// Falls back to focusing a non-project workspace when the focus stack is exhausted.
    ///
    /// Queries all workspaces and focuses the first non-project workspace that has
    /// at least one window. This avoids landing on an empty desktop.
    ///
    /// - Returns: The workspace name that was focused, or nil if no suitable workspace exists.
    private func fallbackToNonProjectWorkspace() -> String? {
        guard case .success(let workspaces) = aerospace.listWorkspacesWithFocus() else {
            return nil
        }
        let nonProjectWorkspaces = workspaces.filter { !$0.workspace.hasPrefix(Self.workspacePrefix) }

        // Prefer a workspace that has windows (avoid empty desktops)
        for candidate in nonProjectWorkspaces {
            if case .success(let windows) = aerospace.listWindowsWorkspace(workspace: candidate.workspace),
               !windows.isEmpty {
                if focusWorkspace(name: candidate.workspace) {
                    return candidate.workspace
                }
            }
        }

        // All non-project workspaces are empty; focus the first one anyway as last resort
        if let target = nonProjectWorkspaces.first {
            return focusWorkspace(name: target.workspace) ? target.workspace : nil
        }
        return nil
    }

    // MARK: - Sequential Window Setup

    /// Outcome from find-or-launch: the window and whether it was freshly launched.
    private struct FindOrLaunchOutcome {
        let window: ApWindow
        let wasLaunched: Bool
    }

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
    /// - Returns: The found or launched window on success, with a flag indicating whether it was freshly launched.
    private func findOrLaunchWindow(
        appBundleId: String,
        projectId: String,
        launchAction: () -> Result<Void, ApCoreError>,
        windowLabel: String,
        eventSource: String
    ) async -> Result<FindOrLaunchOutcome, ProjectError> {
        // Find existing tagged window (global search with fallback)
        if let window = findWindowByToken(appBundleId: appBundleId, projectId: projectId) {
            logEvent(Self.activationWindowEventName(source: eventSource, action: "found"), context: ["window_id": "\(window.windowId)"])
            return .success(FindOrLaunchOutcome(window: window, wasLaunched: false))
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
            .map { FindOrLaunchOutcome(window: $0, wasLaunched: true) }
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

    // MARK: - Window Positioning

    /// Positions IDE and Chrome windows after activation.
    ///
    /// Non-fatal: returns a warning string on failure, nil on success.
    /// Requires windowPositioner, screenModeDetector, and windowPositionStore to all be set.
    /// If only some positioning dependencies are wired, returns a diagnostic warning.
    private func positionWindows(projectId: String) -> String? {
        // All three positioning deps must be present. If only some are wired, surface a warning.
        let hasPositioner = windowPositioner != nil
        let hasDetector = screenModeDetector != nil
        let hasStore = windowPositionStore != nil
        let hasAny = hasPositioner || hasDetector || hasStore
        let hasAll = hasPositioner && hasDetector && hasStore

        if hasAny && !hasAll {
            let missing = [
                hasPositioner ? nil : "windowPositioner",
                hasDetector ? nil : "screenModeDetector",
                hasStore ? nil : "windowPositionStore"
            ].compactMap { $0 }
            logEvent("position.partial_deps", level: .warn, message: "Missing: \(missing.joined(separator: ", "))")
            return "Window positioning disabled: missing \(missing.joined(separator: ", "))"
        }

        guard let positioner = windowPositioner,
              let detector = screenModeDetector,
              let store = windowPositionStore,
              let config = config else {
            return nil
        }

        var warnings: [String] = []

        // Read IDE frame to determine which monitor the windows are on
        let ideFrame: CGRect
        switch positioner.getPrimaryWindowFrame(bundleId: ApVSCodeLauncher.bundleId, projectId: projectId) {
        case .success(let frame):
            ideFrame = frame
        case .failure(let error):
            logEvent("position.ide_frame_read_failed", level: .warn, message: error.message)
            return "Window positioning skipped: \(error.message)"
        }

        // Detect screen mode (use center of IDE frame as reference point)
        let centerPoint = CGPoint(x: ideFrame.midX, y: ideFrame.midY)
        let screenMode: ScreenMode
        let physicalWidth: Double
        switch detector.detectMode(containingPoint: centerPoint, threshold: config.layout.smallScreenThreshold) {
        case .success(let mode):
            screenMode = mode
        case .failure(let error):
            // EDID failure: log WARN, use .wide as explicit fallback
            logEvent("position.screen_mode_detection_failed", level: .warn, message: error.message)
            screenMode = .wide
        }

        switch detector.physicalWidthInches(containingPoint: centerPoint) {
        case .success(let width):
            physicalWidth = width
        case .failure(let error):
            logEvent("position.physical_width_detection_failed", level: .warn, message: error.message)
            physicalWidth = 32.0
            warnings.append("Display physical width unknown (using 32\" fallback); layout may be imprecise")
        }

        guard let screenVisibleFrame = detector.screenVisibleFrame(containingPoint: centerPoint) else {
            logEvent("position.screen_frame_not_found", level: .warn)
            return "Window positioning skipped: screen not found"
        }

        // Determine target frames (saved or computed)
        let targetLayout: WindowLayout
        switch store.load(projectId: projectId, mode: screenMode) {
        case .success(let savedFrames):
            if let frames = savedFrames {
                // Validate and clamp saved frames to current screen
                let ideTarget = WindowLayoutEngine.clampToScreen(frame: frames.ide.cgRect, screenVisibleFrame: screenVisibleFrame)
                let chromeTarget = WindowLayoutEngine.clampToScreen(frame: frames.chrome.cgRect, screenVisibleFrame: screenVisibleFrame)
                targetLayout = WindowLayout(ideFrame: ideTarget, chromeFrame: chromeTarget)
                logEvent("position.using_saved_frames", context: ["project_id": projectId, "mode": screenMode.rawValue])
            } else {
                targetLayout = WindowLayoutEngine.computeLayout(
                    screenVisibleFrame: screenVisibleFrame,
                    screenPhysicalWidthInches: physicalWidth,
                    screenMode: screenMode,
                    config: config.layout
                )
                logEvent("position.using_computed_frames", context: ["project_id": projectId, "mode": screenMode.rawValue])
            }
        case .failure(let error):
            logEvent("position.store_load_failed", level: .warn, message: error.message)
            targetLayout = WindowLayoutEngine.computeLayout(
                screenVisibleFrame: screenVisibleFrame,
                screenPhysicalWidthInches: physicalWidth,
                screenMode: screenMode,
                config: config.layout
            )
        }

        // Compute cascade offset in points: 0.5 inches * (screen points / screen inches)
        let cascadeOffsetPoints = CGFloat(0.5 * (Double(screenVisibleFrame.width) / physicalWidth))

        // Position IDE windows
        switch positioner.setWindowFrames(
            bundleId: ApVSCodeLauncher.bundleId,
            projectId: projectId,
            primaryFrame: targetLayout.ideFrame,
            cascadeOffsetPoints: cascadeOffsetPoints
        ) {
        case .success(let result):
            if result.positioned < 1 {
                logEvent("position.ide_set_none", level: .warn)
                warnings.append("IDE: no windows were positioned")
            } else if result.hasPartialFailure {
                logEvent("position.ide_partial", level: .warn, context: ["positioned": "\(result.positioned)", "matched": "\(result.matched)"])
                warnings.append("IDE: positioned \(result.positioned) of \(result.matched) windows")
            } else {
                logEvent("position.ide_positioned", context: ["count": "\(result.positioned)"])
            }
        case .failure(let error):
            logEvent("position.ide_set_failed", level: .warn, message: error.message)
            warnings.append("IDE positioning failed: \(error.message)")
        }

        // Position Chrome windows
        switch positioner.setWindowFrames(
            bundleId: ApChromeLauncher.bundleId,
            projectId: projectId,
            primaryFrame: targetLayout.chromeFrame,
            cascadeOffsetPoints: cascadeOffsetPoints
        ) {
        case .success(let result):
            if result.positioned < 1 {
                logEvent("position.chrome_set_none", level: .warn)
                warnings.append("Chrome: no windows were positioned")
            } else if result.hasPartialFailure {
                logEvent("position.chrome_partial", level: .warn, context: ["positioned": "\(result.positioned)", "matched": "\(result.matched)"])
                warnings.append("Chrome: positioned \(result.positioned) of \(result.matched) windows")
            } else {
                logEvent("position.chrome_positioned", context: ["count": "\(result.positioned)"])
            }
        case .failure(let error):
            logEvent("position.chrome_set_failed", level: .warn, message: error.message)
            warnings.append("Chrome positioning failed: \(error.message)")
        }

        return warnings.isEmpty ? nil : warnings.joined(separator: "; ")
    }

    /// Captures current window positions for a project before closing or exiting.
    ///
    /// Non-fatal: failures are logged but do not block the caller.
    private func captureWindowPositions(projectId: String) {
        guard let positioner = windowPositioner,
              let detector = screenModeDetector,
              let store = windowPositionStore,
              config != nil else {
            return
        }

        // Read IDE primary frame
        let ideFrame: CGRect
        switch positioner.getPrimaryWindowFrame(bundleId: ApVSCodeLauncher.bundleId, projectId: projectId) {
        case .success(let frame):
            ideFrame = frame
        case .failure(let error):
            logEvent("capture_position.ide_read_failed", level: .warn, message: error.message)
            return
        }

        // Read Chrome primary frame
        let chromeFrame: CGRect
        switch positioner.getPrimaryWindowFrame(bundleId: ApChromeLauncher.bundleId, projectId: projectId) {
        case .success(let frame):
            chromeFrame = frame
        case .failure(let error):
            logEvent("capture_position.chrome_read_failed", level: .warn, message: error.message)
            return
        }

        // Detect screen mode
        let centerPoint = CGPoint(x: ideFrame.midX, y: ideFrame.midY)
        let screenMode: ScreenMode
        switch detector.detectMode(containingPoint: centerPoint, threshold: config!.layout.smallScreenThreshold) {
        case .success(let mode):
            screenMode = mode
        case .failure(let error):
            logEvent("capture_position.screen_mode_failed", level: .warn, message: error.message)
            screenMode = .wide
        }

        // Save both frames
        let frames = SavedWindowFrames(
            ide: SavedFrame(rect: ideFrame),
            chrome: SavedFrame(rect: chromeFrame)
        )
        switch store.save(projectId: projectId, mode: screenMode, frames: frames) {
        case .success:
            logEvent("capture_position.saved", context: ["project_id": projectId, "mode": screenMode.rawValue])
        case .failure(let error):
            logEvent("capture_position.save_failed", level: .warn, message: error.message)
        }
    }

    // MARK: - Chrome Tab Operations

    /// Resolves the initial URLs for a fresh Chrome window.
    ///
    /// If a saved snapshot exists, uses it verbatim (complete tab state from last session).
    /// If no snapshot exists (cold start), uses always-open + defaults from config.
    ///
    /// - Parameters:
    ///   - project: Project configuration.
    ///   - projectId: Project identifier.
    /// - Returns: Ordered list of URLs to open, or empty if none.
    private func resolveInitialURLs(project: ProjectConfig, projectId: String) -> [String] {
        guard let config else { return [] }

        // Load saved tab snapshot
        let snapshot: ChromeTabSnapshot?
        switch chromeTabStore.load(projectId: projectId) {
        case .success(let loaded):
            snapshot = loaded
        case .failure(let error):
            logEvent("select.tab_snapshot_load_failed", level: .warn, message: error.message)
            snapshot = nil
        }

        // If snapshot exists, restore it verbatim (it IS the complete tab state)
        if let snapshot, !snapshot.urls.isEmpty {
            return snapshot.urls
        }

        // Cold start: use always-open + defaults from config
        let gitRemoteURL: String?
        if config.chrome.openGitRemote, !project.isSSH {
            gitRemoteURL = gitRemoteResolver.resolve(projectPath: project.path)
        } else {
            gitRemoteURL = nil
        }

        let resolvedTabs = ChromeTabResolver.resolve(
            config: config.chrome,
            project: project,
            gitRemoteURL: gitRemoteURL
        )
        return resolvedTabs.orderedURLs
    }

    /// Captures Chrome tab URLs before closing a project.
    ///
    /// Saves ALL captured URLs verbatim (no filtering). If the Chrome window is gone
    /// (empty capture), deletes any stale snapshot from disk.
    ///
    /// - Returns: Warning message if capture failed, nil on success.
    private func performTabCapture(projectId: String) -> String? {
        guard config != nil else { return nil }

        let windowTitle = "\(ApIdeToken.prefix)\(projectId)"

        // Capture current tab URLs
        let capturedURLs: [String]
        switch chromeTabCapture.captureTabURLs(windowTitle: windowTitle) {
        case .success(let urls):
            capturedURLs = urls
        case .failure(let error):
            logEvent("close.tab_capture_failed", level: .warn, message: error.message)
            // Don't delete snapshot on command failure (timeout, etc.) — only delete
            // on empty success (window confirmed gone). A transient error shouldn't
            // destroy a valid snapshot.
            return "Tab capture failed: \(error.message)"
        }

        // If no tabs captured (window not found or empty), delete stale snapshot
        guard !capturedURLs.isEmpty else {
            _ = chromeTabStore.delete(projectId: projectId)
            return nil
        }

        // Save ALL captured URLs verbatim (snapshot = complete truth)
        let snapshot = ChromeTabSnapshot(urls: capturedURLs, capturedAt: Date())
        switch chromeTabStore.save(snapshot: snapshot, projectId: projectId) {
        case .success:
            logEvent("close.tabs_captured", context: [
                "project_id": projectId,
                "tab_count": "\(capturedURLs.count)"
            ])
            return nil
        case .failure(let error):
            logEvent("close.tab_save_failed", level: .warn, message: error.message)
            return "Tab save failed: \(error.message)"
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
        guard fileSystem.fileExists(at: recencyFilePath) else {
            recentProjectIds = []
            return
        }

        do {
            let data = try fileSystem.readFile(at: recencyFilePath)
            let ids = try JSONDecoder().decode([String].self, from: data)
            recentProjectIds = ids
        } catch {
            recentProjectIds = []
            logEvent(
                "recency.load_failed",
                level: .warn,
                message: String(describing: error),
                context: ["path": recencyFilePath.path]
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
            try fileSystem.createDirectory(at: directory)
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
            try fileSystem.writeFile(at: recencyFilePath, data: data)
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
