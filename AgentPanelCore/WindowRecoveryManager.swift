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
/// Thread Safety: Not thread-safe. Call from a single queue (typically a background queue
/// dispatched from the App layer). AeroSpace CLI calls and AX operations may block.
public final class WindowRecoveryManager {
    private let aerospace: AeroSpaceProviding
    private let windowPositioner: WindowPositioning
    private let screenVisibleFrame: CGRect
    private let logger: AgentPanelLogging

    /// Creates a WindowRecoveryManager with production defaults for AeroSpace.
    /// - Parameters:
    ///   - windowPositioner: Window positioning provider for AX operations.
    ///   - screenVisibleFrame: The screen's visible frame (minus dock/menu bar) to clamp within.
    ///   - logger: Logger for structured event logging.
    ///   - processChecker: Process checker for AeroSpace auto-recovery. Pass nil to disable.
    public init(
        windowPositioner: WindowPositioning,
        screenVisibleFrame: CGRect,
        logger: AgentPanelLogging,
        processChecker: RunningApplicationChecking? = nil
    ) {
        self.aerospace = ApAeroSpace(processChecker: processChecker)
        self.windowPositioner = windowPositioner
        self.screenVisibleFrame = screenVisibleFrame
        self.logger = logger
    }

    /// Creates a WindowRecoveryManager with injected dependencies (for testing).
    init(
        aerospace: AeroSpaceProviding,
        windowPositioner: WindowPositioning,
        screenVisibleFrame: CGRect,
        logger: AgentPanelLogging
    ) {
        self.aerospace = aerospace
        self.windowPositioner = windowPositioner
        self.screenVisibleFrame = screenVisibleFrame
        self.logger = logger
    }

    /// Recovers all windows in the given workspace by shrinking oversized windows and centering them.
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

        let result = recoverWindows(windows)

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

    /// Recovers all windows across all workspaces by moving each to workspace "1"
    /// and ensuring it fits on screen.
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

        for workspace in workspaces {
            switch aerospace.listWindowsWorkspace(workspace: workspace) {
            case .success(let windows):
                allWindows.append(contentsOf: windows)
            case .failure(let error):
                errors.append("Failed to list workspace \(workspace): \(error.message)")
                logEvent("recover_all.workspace_list_failed", level: .warn, message: error.message, context: ["workspace": workspace])
            }
        }

        var processed = 0
        var recovered = 0

        for (index, window) in allWindows.enumerated() {
            // Move window to workspace "1" (focusFollows ensures it becomes frontmost)
            switch aerospace.moveWindowToWorkspace(workspace: "1", windowId: window.windowId, focusFollows: true) {
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

        // Restore original window focus (all windows are now on workspace "1",
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

    private func logEvent(
        _ event: String,
        level: LogLevel = .info,
        message: String? = nil,
        context: [String: String]? = nil
    ) {
        _ = logger.log(event: event, level: level, message: message, context: context)
    }
}
