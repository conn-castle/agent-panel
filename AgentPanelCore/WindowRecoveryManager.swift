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

/// Handles window recovery operations: resize oversized windows and center them on screen.
/// For project workspaces (`ap-<projectId>`), an optional layout phase applies canonical IDE/Chrome layout first.
/// Not thread-safe; call from one queue.
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
    public func recoverWorkspaceWindows(workspace: String) -> Result<RecoveryResult, ApCoreError> {
        logEvent("recover_workspace.started", context: ["workspace": workspace])

        let originalFocus = try? aerospace.focusedWindow().get()

        let windows: [ApWindow]
        switch aerospace.listWindowsWorkspace(workspace: workspace) {
        case .success(let result):
            windows = result
        case .failure(let error):
            logEvent("recover_workspace.list_failed", level: .error, message: error.message)
            return .failure(error)
        }

        var layoutRecovered = 0
        var layoutErrors: [String] = []
        var layoutHandledWindowIds: Set<Int> = []

        if let projectId = projectId(fromWorkspace: workspace), screenModeDetector != nil {
            let layoutResult = recoverProjectWorkspaceLayout(projectId: projectId, workspaceWindows: windows)
            layoutRecovered = layoutResult.recovered
            layoutErrors = layoutResult.errors
            layoutHandledWindowIds = layoutResult.handledWindowIds
        }

        let genericWindows = windows.filter { !layoutHandledWindowIds.contains($0.windowId) }
        let genericResult = recoverWindows(genericWindows)

        let totalRecovered = layoutRecovered + genericResult.windowsRecovered
        let totalErrors = layoutErrors + genericResult.errors
        let result = RecoveryResult(
            windowsProcessed: windows.count,
            windowsRecovered: totalRecovered,
            errors: totalErrors
        )

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

    /// Recovers all windows across all workspaces.
    /// Moves each window to the preferred non-project workspace and runs generic recovery.
    public func recoverAllWindows(
        progress: @escaping (_ current: Int, _ total: Int) -> Void
    ) -> Result<RecoveryResult, ApCoreError> {
        logEvent("recover_all.started")

        let originalFocus = try? aerospace.focusedWindow().get()

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

        let destination = WorkspaceRouting.preferredNonProjectWorkspace(
            from: queriedWorkspaces,
            hasWindows: { workspacesWithWindows.contains($0) }
        )

        var processed = 0
        var recovered = 0

        for (index, window) in allWindows.enumerated() {
            switch aerospace.moveWindowToWorkspace(workspace: destination, windowId: window.windowId, focusFollows: true) {
            case .success:
                break
            case .failure(let error):
                errors.append("Move failed for window \(window.windowId) (\(window.windowTitle)): \(error.message)")
                progress(index + 1, allWindows.count)
                processed += 1
                continue
            }

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

    private enum SingleRecoveryResult {
        case recovered
        case unchanged
        case notFound
        case error(String)
    }

    private func recoverSingleWindow(_ window: ApWindow) -> SingleRecoveryResult {
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

    /// Recovers a list of windows in-place.
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

    /// Extracts project ID from an `ap-<projectId>` workspace name.
    private func projectId(fromWorkspace workspace: String) -> String? {
        WorkspaceRouting.projectId(fromWorkspace: workspace)
    }

    /// Runs layout-aware recovery for a project workspace.
    private func recoverProjectWorkspaceLayout(
        projectId: String,
        workspaceWindows: [ApWindow]
    ) -> (recovered: Int, errors: [String], handledWindowIds: Set<Int>) {
        guard let detector = screenModeDetector else { return (0, [], []) }

        var errors: [String] = []

        let workspaceBundleIds = Set(workspaceWindows.map { $0.appBundleId })
        let layoutTargets: [(bundleId: String, frameKeyPath: KeyPath<WindowLayout, CGRect>, label: String)] = [
            (ApVSCodeLauncher.bundleId, \.ideFrame, "IDE"),
            (ApChromeLauncher.bundleId, \.chromeFrame, "Chrome"),
        ].filter { workspaceBundleIds.contains($0.bundleId) }

        guard !layoutTargets.isEmpty else { return (0, [], []) }

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

        let targetLayout = WindowLayoutEngine.computeLayout(
            screenVisibleFrame: screenVisibleFrame,
            screenPhysicalWidthInches: physicalWidth,
            screenMode: screenMode,
            config: layoutConfig
        )

        let cascadeOffsetPoints = CGFloat(0.5 * (Double(screenVisibleFrame.width) / physicalWidth))

        let token = "\(ApIdeToken.prefix)\(projectId)"
        var recovered = 0
        var handledWindowIds: Set<Int> = []

        for target in layoutTargets {
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
