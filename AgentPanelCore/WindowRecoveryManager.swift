import Foundation

/// Result of a window recovery operation.
public struct RecoveryResult: Equatable, Sendable {
    /// Number of windows checked during recovery.
    public let windowsProcessed: Int
    /// Number of windows that were actually resized or moved.
    public let windowsRecovered: Int
    /// Non-fatal error messages encountered during recovery.
    public let errors: [String]

    public init(windowsProcessed: Int, windowsRecovered: Int, errors: [String]) {
        self.windowsProcessed = windowsProcessed
        self.windowsRecovered = windowsRecovered
        self.errors = errors
    }
}

/// Handles window recovery operations: shrink oversized windows and center them on screen.
///
/// For project workspaces (`ap-<projectId>`), an optional layout-aware recovery phase
/// repositions IDE and Chrome windows using computed canonical layout before generic recovery.
///
/// Thread Safety: Not thread-safe. Call from a single queue (typically a background queue
/// dispatched from the App layer). AeroSpace CLI calls and AX operations may block.
public final class WindowRecoveryManager {
    private let aerospace: AeroSpaceProviding
    private let windowPositioner: WindowPositioning
    private let screenVisibleFrame: CGRect
    private let logger: AgentPanelLogging
    private let screenModeDetector: ScreenModeDetecting?
    private let layoutConfig: LayoutConfig

    /// Creates a WindowRecoveryManager with production defaults for AeroSpace.
    /// - Parameters:
    ///   - windowPositioner: Window positioning provider for AX operations.
    ///   - screenVisibleFrame: The screen's visible frame (minus dock/menu bar) to clamp within.
    ///   - logger: Logger for structured event logging.
    ///   - processChecker: Process checker for AeroSpace auto-recovery. Pass nil to disable.
    ///   - screenModeDetector: Screen mode detector for layout-aware recovery. Pass nil to disable layout phase.
    ///   - layoutConfig: Layout configuration for computing canonical positions. Defaults to `LayoutConfig()`.
    public init(
        windowPositioner: WindowPositioning,
        screenVisibleFrame: CGRect,
        logger: AgentPanelLogging,
        processChecker: RunningApplicationChecking? = nil,
        screenModeDetector: ScreenModeDetecting? = nil,
        layoutConfig: LayoutConfig = LayoutConfig()
    ) {
        self.aerospace = ApAeroSpace(processChecker: processChecker)
        self.windowPositioner = windowPositioner
        self.screenVisibleFrame = screenVisibleFrame
        self.logger = logger
        self.screenModeDetector = screenModeDetector
        self.layoutConfig = layoutConfig
    }

    /// Creates a WindowRecoveryManager with injected dependencies (for testing).
    init(
        aerospace: AeroSpaceProviding,
        windowPositioner: WindowPositioning,
        screenVisibleFrame: CGRect,
        logger: AgentPanelLogging,
        screenModeDetector: ScreenModeDetecting? = nil,
        layoutConfig: LayoutConfig = LayoutConfig()
    ) {
        self.aerospace = aerospace
        self.windowPositioner = windowPositioner
        self.screenVisibleFrame = screenVisibleFrame
        self.logger = logger
        self.screenModeDetector = screenModeDetector
        self.layoutConfig = layoutConfig
    }

    /// Recovers all windows in the given workspace.
    ///
    /// For project workspaces (`ap-<projectId>`), runs a layout-aware phase first that
    /// repositions IDE and Chrome windows to computed canonical positions. Then runs
    /// generic per-window recovery (shrink/center) for all windows.
    ///
    /// Focuses each window via AeroSpace before recovery to disambiguate duplicate titles.
    /// Re-focuses the originally focused window at the end.
    ///
    /// - Parameter workspace: AeroSpace workspace name to recover.
    /// - Returns: Recovery result with counts and any errors.
    public func recoverWorkspaceWindows(workspace: String) -> Result<RecoveryResult, ApCoreError> {
        logEvent("recover_workspace.started", context: ["workspace": workspace])

        // Capture focused window for restoration
        let originalFocus = try? aerospace.focusedWindow().get()

        // List all windows in the workspace
        let windows: [ApWindow]
        switch aerospace.listWindowsWorkspace(workspace: workspace) {
        case .success(let result):
            windows = result
        case .failure(let error):
            logEvent("recover_workspace.list_failed", level: .error, message: error.message)
            return .failure(error)
        }

        // Layout-aware phase for project workspaces
        var layoutRecovered = 0
        var layoutErrors: [String] = []
        var layoutHandledWindowIds: Set<Int> = []

        if let projectId = projectId(fromWorkspace: workspace), screenModeDetector != nil {
            let layoutResult = recoverProjectWorkspaceLayout(projectId: projectId, workspaceWindows: windows)
            layoutRecovered = layoutResult.recovered
            layoutErrors = layoutResult.errors
            layoutHandledWindowIds = layoutResult.handledWindowIds
        }

        // Generic per-window recovery (shrink/center), skipping windows already handled by layout phase.
        // Uses window-level IDs (not bundle IDs) so that non-token windows of the same bundle
        // (e.g., extra VS Code windows without AP:<projectId>) still get generic recovery.
        let genericWindows = windows.filter { !layoutHandledWindowIds.contains($0.windowId) }
        let genericResult = recoverWindows(genericWindows)

        // Merge counts: processed = all workspace windows, recovered = layout + generic (no overlap)
        let totalRecovered = layoutRecovered + genericResult.windowsRecovered
        let totalErrors = layoutErrors + genericResult.errors
        let result = RecoveryResult(
            windowsProcessed: windows.count,
            windowsRecovered: totalRecovered,
            errors: totalErrors
        )

        // Restore focus to original window
        if let originalFocus {
            _ = aerospace.focusWindow(windowId: originalFocus.windowId)
        }

        logEvent("recover_workspace.completed", context: [
            "workspace": workspace,
            "processed": "\(result.windowsProcessed)",
            "recovered": "\(result.windowsRecovered)",
            "errors": "\(result.errors.count)"
        ])

        return .success(result)
    }

    /// Recovers all windows across all workspaces by moving each to the preferred
    /// non-project workspace and ensuring it fits on screen.
    ///
    /// Destination is selected via ``WorkspaceRouting/preferredNonProjectWorkspace(from:hasWindows:)``
    /// which prefers a non-project workspace that already has windows, falling back to
    /// ``WorkspaceRouting/fallbackWorkspace`` when no candidate exists.
    ///
    /// Iterates workspaces directly (instead of using `listAllWindows()`) to surface
    /// per-workspace failures as non-fatal errors rather than silently skipping them.
    /// Focuses each window via AeroSpace before recovery to disambiguate duplicate titles.
    /// Reports progress via callback after each window.
    /// Restores focus to the originally focused window at the end.
    ///
    /// - Parameter progress: Called with `(currentIndex, totalCount)` after each window.
    /// - Returns: Recovery result with counts and any errors.
    public func recoverAllWindows(
        progress: @escaping (_ current: Int, _ total: Int) -> Void
    ) -> Result<RecoveryResult, ApCoreError> {
        logEvent("recover_all.started")

        // Capture originally focused window for restoration
        let originalFocus = try? aerospace.focusedWindow().get()

        // Get all workspaces, then iterate each to collect windows (surfaces per-workspace errors)
        let workspaces: [String]
        switch aerospace.getWorkspaces() {
        case .success(let result):
            workspaces = result
        case .failure(let error):
            logEvent("recover_all.list_workspaces_failed", level: .error, message: error.message)
            return .failure(error)
        }

        var allWindows: [ApWindow] = []
        var errors: [String] = []
        var queriedWorkspaces: [String] = []
        var workspacesWithWindows: Set<String> = []

        for workspace in workspaces {
            switch aerospace.listWindowsWorkspace(workspace: workspace) {
            case .success(let windows):
                allWindows.append(contentsOf: windows)
                queriedWorkspaces.append(workspace)
                if !windows.isEmpty {
                    workspacesWithWindows.insert(workspace)
                }
            case .failure(let error):
                errors.append("Failed to list workspace \(workspace): \(error.message)")
                logEvent("recover_all.workspace_list_failed", level: .warn, message: error.message, context: ["workspace": workspace])
            }
        }

        // Select destination using canonical non-project workspace strategy.
        // Only workspaces whose listing succeeded are candidates; failed-listing
        // workspaces are excluded to avoid routing to unhealthy targets.
        let destination = WorkspaceRouting.preferredNonProjectWorkspace(
            from: queriedWorkspaces,
            hasWindows: { workspacesWithWindows.contains($0) }
        )

        var processed = 0
        var recovered = 0

        for (index, window) in allWindows.enumerated() {
            // Move window to destination (focusFollows ensures it becomes frontmost)
            switch aerospace.moveWindowToWorkspace(workspace: destination, windowId: window.windowId, focusFollows: true) {
            case .success:
                break
            case .failure(let error):
                errors.append("Move failed for window \(window.windowId) (\(window.windowTitle)): \(error.message)")
                progress(index + 1, allWindows.count)
                processed += 1
                continue
            }

            // Recover the window (shrink/center if needed)
            let outcome = recoverSingleWindow(window)
            switch outcome {
            case .recovered: recovered += 1
            case .notFound:
                errors.append("Window not found for recovery: \(window.windowId) (\(window.windowTitle))")
            case .error(let message):
                errors.append(message)
            case .unchanged:
                break
            }

            processed += 1
            progress(index + 1, allWindows.count)
        }

        // Restore original window focus (all windows are now on the destination workspace,
        // so restoring the workspace is unnecessary — focusWindow handles it).
        if let originalFocus {
            _ = aerospace.focusWindow(windowId: originalFocus.windowId)
        }

        let result = RecoveryResult(
            windowsProcessed: processed,
            windowsRecovered: recovered,
            errors: errors
        )

        logEvent("recover_all.completed", context: [
            "processed": "\(result.windowsProcessed)",
            "recovered": "\(result.windowsRecovered)",
            "errors": "\(result.errors.count)"
        ])

        return .success(result)
    }

    // MARK: - Private Helpers

    /// Internal result of recovering a single window, used to simplify control flow.
    private enum SingleRecoveryResult {
        case recovered
        case unchanged
        case notFound
        case error(String)
    }

    /// Focuses a window via AeroSpace, then runs AX recovery.
    private func recoverSingleWindow(_ window: ApWindow) -> SingleRecoveryResult {
        // Focus the window so AX can find it unambiguously (handles duplicate titles).
        // If focus fails, skip recovery — proceeding could target the wrong window.
        if case .failure(let error) = aerospace.focusWindow(windowId: window.windowId) {
            return .error("Focus failed for window \(window.windowId) (\(window.windowTitle)): \(error.message)")
        }

        switch windowPositioner.recoverWindow(
            bundleId: window.appBundleId,
            windowTitle: window.windowTitle,
            screenVisibleFrame: screenVisibleFrame
        ) {
        case .success(.recovered): return .recovered
        case .success(.unchanged): return .unchanged
        case .success(.notFound): return .notFound
        case .failure(let error):
            return .error("Recover failed for window \(window.windowId) (\(window.windowTitle)): \(error.message)")
        }
    }

    /// Recovers a list of windows in-place (no workspace moves).
    /// Focuses each window via AeroSpace before recovery to disambiguate duplicate titles.
    private func recoverWindows(_ windows: [ApWindow]) -> RecoveryResult {
        var processed = 0
        var recovered = 0
        var errors: [String] = []

        for window in windows {
            let outcome = recoverSingleWindow(window)
            switch outcome {
            case .recovered: recovered += 1
            case .notFound:
                errors.append("Window not found for recovery: \(window.windowId) (\(window.windowTitle))")
            case .error(let message):
                errors.append(message)
            case .unchanged:
                break
            }
            processed += 1
        }

        return RecoveryResult(
            windowsProcessed: processed,
            windowsRecovered: recovered,
            errors: errors
        )
    }

    // MARK: - Layout-Aware Recovery

    /// Extracts project ID from an `ap-<projectId>` workspace name, or nil for non-project workspaces.
    /// Delegates to ``WorkspaceRouting/projectId(fromWorkspace:)``.
    private func projectId(fromWorkspace workspace: String) -> String? {
        WorkspaceRouting.projectId(fromWorkspace: workspace)
    }

    /// Runs layout-aware recovery for a project workspace: computes canonical layout positions
    /// and applies them to IDE and Chrome windows via `setWindowFrames`.
    ///
    /// Only targets bundle IDs that have at least one window in the workspace (workspace-scoped).
    /// Returns the set of window IDs (AeroSpace) that were handled so the caller can skip them
    /// in generic recovery. Uses token matching (`AP:<projectId>`) to identify handled windows,
    /// ensuring non-token windows of the same bundle still get generic recovery.
    ///
    /// - Parameters:
    ///   - projectId: The project identifier derived from the workspace name.
    ///   - workspaceWindows: Windows currently in the target workspace (from AeroSpace).
    /// - Returns: Count of windows positioned, non-fatal errors, and set of handled window IDs.
    private func recoverProjectWorkspaceLayout(
        projectId: String,
        workspaceWindows: [ApWindow]
    ) -> (recovered: Int, errors: [String], handledWindowIds: Set<Int>) {
        guard let detector = screenModeDetector else { return (0, [], []) }

        var errors: [String] = []

        // Determine which layout-eligible bundle IDs are present in the workspace
        let workspaceBundleIds = Set(workspaceWindows.map { $0.appBundleId })
        let layoutTargets: [(bundleId: String, frameKeyPath: KeyPath<WindowLayout, CGRect>, label: String)] = [
            (ApVSCodeLauncher.bundleId, \.ideFrame, "IDE"),
            (ApChromeLauncher.bundleId, \.chromeFrame, "Chrome"),
        ].filter { workspaceBundleIds.contains($0.bundleId) }

        guard !layoutTargets.isEmpty else { return (0, [], []) }

        // Detect screen mode using center of screen visible frame
        let centerPoint = CGPoint(x: screenVisibleFrame.midX, y: screenVisibleFrame.midY)

        let screenMode: ScreenMode
        switch detector.detectMode(containingPoint: centerPoint, threshold: layoutConfig.smallScreenThreshold) {
        case .success(let mode):
            screenMode = mode
        case .failure(let error):
            logEvent("recover_layout.screen_mode_failed", level: .warn, message: error.message)
            errors.append("Recovery screen mode detection failed (\(error.message)); using wide fallback")
            screenMode = .wide
        }

        let physicalWidth: Double
        switch detector.physicalWidthInches(containingPoint: centerPoint) {
        case .success(let width):
            physicalWidth = width
        case .failure(let error):
            logEvent("recover_layout.physical_width_failed", level: .warn, message: error.message)
            errors.append("Recovery physical width detection failed (\(error.message)); using 32\" fallback")
            physicalWidth = 32.0
        }

        // Compute canonical layout (ignores saved positions — recovery converges to known-good baseline)
        let targetLayout = WindowLayoutEngine.computeLayout(
            screenVisibleFrame: screenVisibleFrame,
            screenPhysicalWidthInches: physicalWidth,
            screenMode: screenMode,
            config: layoutConfig
        )

        // Compute cascade offset: 0.5 inches * (screen points / screen inches)
        let cascadeOffsetPoints = CGFloat(0.5 * (Double(screenVisibleFrame.width) / physicalWidth))

        let token = "\(ApIdeToken.prefix)\(projectId)"
        var recovered = 0
        var handledWindowIds: Set<Int> = []

        for target in layoutTargets {
            // Identify workspace windows that match this target's bundle AND have the project token.
            // These are the windows setWindowFrames will position via AX.
            let tokenMatchingWindows = workspaceWindows.filter {
                $0.appBundleId == target.bundleId && $0.windowTitle.contains(token)
            }

            switch windowPositioner.setWindowFrames(
                bundleId: target.bundleId,
                projectId: projectId,
                primaryFrame: targetLayout[keyPath: target.frameKeyPath],
                cascadeOffsetPoints: cascadeOffsetPoints
            ) {
            case .success(let result):
                // Cap recovered count at workspace-scoped matches (setWindowFrames may also
                // position same-token windows outside this workspace via AX, but we only
                // account for the ones in our workspace).
                recovered += min(result.positioned, tokenMatchingWindows.count)
                for w in tokenMatchingWindows {
                    handledWindowIds.insert(w.windowId)
                }
                logEvent("recover_layout.\(target.label.lowercased())_positioned", context: [
                    "positioned": "\(result.positioned)", "matched": "\(result.matched)"
                ])
            case .failure(let error):
                logEvent("recover_layout.\(target.label.lowercased())_failed", level: .warn, message: error.message)
                errors.append("Recovery \(target.label) positioning failed: \(error.message)")
            }
        }

        return (recovered, errors, handledWindowIds)
    }

    private func logEvent(
        _ event: String,
        level: LogLevel = .info,
        message: String? = nil,
        context: [String: String]? = nil
    ) {
        _ = logger.log(event: event, level: level, message: message, context: context)
    }
}
