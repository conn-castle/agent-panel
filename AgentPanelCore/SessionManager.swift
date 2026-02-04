//
//  SessionManager.swift
//  AgentPanelCore
//
//  Manages application session lifecycle, state persistence, and focus history.
//  This is the primary interface for App to interact with state management.
//

import Foundation

// MARK: - CapturedFocus

/// Represents a captured window focus state for restoration.
///
/// Used to save the currently focused window before showing UI (like the switcher)
/// and restore it when the UI is dismissed without a selection.
public struct CapturedFocus: Sendable, Equatable {
    /// AeroSpace window ID.
    public let windowId: Int

    /// App bundle identifier of the focused window.
    public let appBundleId: String

    /// Creates a captured focus state.
    ///
    /// - Parameters:
    ///   - windowId: AeroSpace window ID.
    ///   - appBundleId: App bundle identifier.
    public init(windowId: Int, appBundleId: String) {
        self.windowId = windowId
        self.appBundleId = appBundleId
    }
}

// MARK: - FocusOperationsProviding

/// Protocol for window focus capture and restoration.
///
/// This is an intent-based protocol: callers say "capture focus" and "restore focus"
/// without needing to know about AeroSpace, window IDs, or other implementation details.
///
/// Allows dependency injection for testing and decouples SessionManager from ApCore.
public protocol FocusOperationsProviding {
    /// Captures the currently focused window for later restoration.
    ///
    /// - Returns: CapturedFocus if a window is focused, nil otherwise.
    func captureCurrentFocus() -> CapturedFocus?

    /// Restores focus to a previously captured window.
    ///
    /// - Parameter focus: The captured focus state to restore.
    /// - Returns: True if focus was restored successfully.
    func restoreFocus(_ focus: CapturedFocus) -> Bool
}

// MARK: - SessionManager

/// Reason why state is considered unhealthy (blocking saves).
public enum StateHealthIssue: Equatable, Sendable {
    /// State file was corrupted and could not be decoded.
    case corrupted(detail: String)

    /// State file is from a newer version of the app.
    case newerVersion(found: Int, supported: Int)
}

/// Manages application session lifecycle, state persistence, and focus history.
///
/// This is the primary interface for App to interact with state management.
/// It consolidates state ownership, eliminating the need for App components
/// to directly access StateStore, FocusHistoryStore, or AppState.
///
/// State Health: SessionManager tracks whether state loaded successfully.
/// If state load fails due to corruption or newer version, saves are blocked
/// to avoid overwriting potentially valuable data. Check `stateHealthIssue`
/// to determine if intervention is needed.
///
/// Thread Safety: SessionManager is not thread-safe. All methods must be
/// called from the main thread.
public final class SessionManager {
    private let stateStore: StateStore
    private let focusHistoryStore: FocusHistoryStore
    private let logger: AgentPanelLogging
    private var focusOperations: FocusOperationsProviding?

    private var appState: AppState

    /// If non-nil, state is unhealthy and saves are blocked.
    ///
    /// This is set when loading state fails due to corruption or newer version.
    /// The app should display a warning and may need to prompt for recovery.
    public private(set) var stateHealthIssue: StateHealthIssue?

    /// Creates a SessionManager with default dependencies.
    public init() {
        self.stateStore = StateStore()
        self.focusHistoryStore = FocusHistoryStore()
        self.logger = AgentPanelLogger()
        self.appState = AppState()
        self.focusOperations = nil

        loadState()
    }

    /// Creates a SessionManager with full dependency injection (for testing).
    ///
    /// - Parameters:
    ///   - stateStore: Store for persisting app state.
    ///   - focusHistoryStore: Store for focus history operations.
    ///   - logger: Logger for diagnostics.
    ///   - focusOperations: Optional focus operations provider.
    init(
        stateStore: StateStore,
        focusHistoryStore: FocusHistoryStore,
        logger: AgentPanelLogging,
        focusOperations: FocusOperationsProviding? = nil
    ) {
        self.stateStore = stateStore
        self.focusHistoryStore = focusHistoryStore
        self.logger = logger
        self.appState = AppState()
        self.focusOperations = focusOperations

        loadState()
    }

    // MARK: - Configuration

    /// Sets the focus operations provider.
    ///
    /// Call this after loading configuration to enable focus capture/restore.
    ///
    /// - Parameter provider: The focus operations provider to use.
    public func setFocusOperations(_ provider: FocusOperationsProviding?) {
        self.focusOperations = provider
    }

    // MARK: - Session Lifecycle

    /// Records session start. Call once when the app launches.
    ///
    /// - Parameter version: The app version string for metadata.
    public func sessionStarted(version: String) {
        let event = FocusEvent.sessionStarted(
            metadata: ["version": version]
        )
        appState = focusHistoryStore.record(event: event, state: appState)
        appState.lastLaunchedAt = Date()
        saveState()

        logEvent("session.started", context: ["version": version])
    }

    /// Records session end. Call when the app is about to terminate.
    ///
    /// Reloads state from disk before recording to avoid overwriting events
    /// that may have been recorded by other calls during the session.
    public func sessionEnded() {
        // Reload state to get any events recorded since session start
        reloadState()

        let event = FocusEvent.sessionEnded()
        appState = focusHistoryStore.record(event: event, state: appState)
        saveState()

        logEvent("session.ended")
    }

    // MARK: - Focus Capture and Restore

    /// Captures the currently focused window for later restoration.
    ///
    /// - Returns: CapturedFocus if a window is focused, nil otherwise.
    public func captureCurrentFocus() -> CapturedFocus? {
        guard let focusOps = focusOperations else {
            logEvent("focus.capture.skipped", level: .warn, message: "No focus operations provider.")
            return nil
        }

        guard let captured = focusOps.captureCurrentFocus() else {
            logEvent("focus.capture.failed", level: .warn, message: "Could not capture focused window.")
            return nil
        }

        // Record windowDefocused event
        let event = FocusEvent.windowDefocused(
            windowId: captured.windowId,
            appBundleId: captured.appBundleId,
            metadata: ["source": "focus_captured"]
        )
        appState = focusHistoryStore.record(event: event, state: appState)
        saveState()

        logEvent(
            "focus.captured",
            context: [
                "window_id": "\(captured.windowId)",
                "app_bundle_id": captured.appBundleId
            ]
        )

        return captured
    }

    /// Attempts to restore focus to a previously captured window.
    ///
    /// - Parameter captured: The focus state to restore.
    /// - Returns: True if focus was restored, false otherwise.
    @discardableResult
    public func restoreFocus(_ captured: CapturedFocus) -> Bool {
        guard let focusOps = focusOperations else {
            logEvent("focus.restore.skipped", level: .warn, message: "No focus operations provider.")
            return false
        }

        let success = focusOps.restoreFocus(captured)

        if success {
            // Record windowFocused event for restore
            let event = FocusEvent.windowFocused(
                windowId: captured.windowId,
                appBundleId: captured.appBundleId,
                metadata: ["source": "focus_restored"]
            )
            appState = focusHistoryStore.record(event: event, state: appState)
            saveState()

            logEvent(
                "focus.restored",
                context: ["window_id": "\(captured.windowId)"]
            )
        } else {
            logEvent(
                "focus.restore.failed",
                level: .warn,
                message: "Failed to restore focus.",
                context: ["window_id": "\(captured.windowId)"]
            )
        }

        return success
    }

    // MARK: - Project Events

    /// Records that a project was activated.
    ///
    /// - Parameter projectId: The normalized project identifier.
    public func projectActivated(projectId: String) {
        let event = FocusEvent.projectActivated(projectId: projectId)
        appState = focusHistoryStore.record(event: event, state: appState)
        saveState()

        logEvent("project.activated", context: ["project_id": projectId])
    }

    /// Records that a project was deactivated.
    ///
    /// - Parameter projectId: The normalized project identifier.
    public func projectDeactivated(projectId: String) {
        let event = FocusEvent.projectDeactivated(projectId: projectId)
        appState = focusHistoryStore.record(event: event, state: appState)
        saveState()

        logEvent("project.deactivated", context: ["project_id": projectId])
    }

    // MARK: - Focus History Access

    /// The current focus history for display purposes.
    ///
    /// Returns all focus events, oldest first.
    public var focusHistory: [FocusEvent] {
        focusHistoryStore.events(in: appState)
    }

    /// Returns the most recent focus events.
    ///
    /// - Parameter count: Maximum number of events to return.
    /// - Returns: Most recent events, newest first.
    public func recentFocusHistory(count: Int) -> [FocusEvent] {
        let events = focusHistoryStore.events(in: appState)
        return Array(events.suffix(count).reversed())
    }

    /// Returns the most recent project activation events.
    ///
    /// - Parameter count: Maximum number of events to return.
    /// - Returns: Most recent project activation events, newest first.
    public func recentProjectActivations(count: Int) -> [FocusEvent] {
        let events = focusHistoryStore.events(ofKind: .projectActivated, in: appState)
        return Array(events.suffix(count).reversed())
    }

    // MARK: - Private Helpers

    /// Loads state from disk.
    ///
    /// On success, state is loaded and saves are allowed.
    /// On corruption or newer version error, saves are blocked to prevent data loss.
    /// On file not found or file system error, a fresh state is used (saves allowed).
    private func loadState() {
        switch stateStore.load() {
        case .success(let state):
            appState = state
            stateHealthIssue = nil

        case .failure(let error):
            switch error {
            case .corruptedState(let detail):
                // Block saves - corrupted state might be recoverable
                stateHealthIssue = .corrupted(detail: detail)
                appState = AppState()
                logEvent(
                    "state.load.corrupted",
                    level: .error,
                    message: "State file is corrupted. Saves are blocked until resolved.",
                    context: ["detail": detail]
                )

            case .newerVersion(let found, let supported):
                // Block saves - newer version state should not be overwritten
                stateHealthIssue = .newerVersion(found: found, supported: supported)
                appState = AppState()
                logEvent(
                    "state.load.newer_version",
                    level: .error,
                    message: "State file is from a newer version. Saves are blocked.",
                    context: [
                        "found_version": "\(found)",
                        "supported_version": "\(supported)"
                    ]
                )

            case .fileSystemError(let detail):
                // File system errors (including file not found) use fresh state
                // Saves are allowed since there's nothing to corrupt
                stateHealthIssue = nil
                appState = AppState()
                logEvent(
                    "state.load.file_error",
                    level: .warn,
                    message: "Could not read state file, using fresh state.",
                    context: ["detail": detail]
                )
            }
        }
    }

    /// Reloads state from disk, preserving current state on failure.
    ///
    /// On corruption or newer version error, saves are blocked.
    /// On file system error, existing state is preserved and saves remain allowed.
    private func reloadState() {
        switch stateStore.load() {
        case .success(let state):
            appState = state
            stateHealthIssue = nil

        case .failure(let error):
            switch error {
            case .corruptedState(let detail):
                stateHealthIssue = .corrupted(detail: detail)
                logEvent(
                    "state.reload.corrupted",
                    level: .error,
                    message: "State file is corrupted during reload. Saves are blocked.",
                    context: ["detail": detail]
                )

            case .newerVersion(let found, let supported):
                stateHealthIssue = .newerVersion(found: found, supported: supported)
                logEvent(
                    "state.reload.newer_version",
                    level: .error,
                    message: "State file is from a newer version during reload. Saves are blocked.",
                    context: [
                        "found_version": "\(found)",
                        "supported_version": "\(supported)"
                    ]
                )

            case .fileSystemError(let detail):
                // File system error during reload - preserve existing state
                // Don't change health status
                logEvent(
                    "state.reload.file_error",
                    level: .warn,
                    message: "Could not reload state file, preserving existing state.",
                    context: ["detail": detail]
                )
            }
        }
    }

    /// Saves state to disk with pruning.
    ///
    /// If state is unhealthy (corruption or newer version), saves are blocked
    /// to prevent overwriting potentially valuable data.
    private func saveState() {
        // Block saves if state is unhealthy to prevent data loss
        if let issue = stateHealthIssue {
            logEvent(
                "state.save.blocked",
                level: .warn,
                message: "Save blocked due to state health issue.",
                context: ["issue": "\(issue)"]
            )
            return
        }

        let result = stateStore.save(appState, prunedWith: focusHistoryStore)
        if case .failure(let error) = result {
            logEvent(
                "state.save.failed",
                level: .error,
                message: "Failed to save state: \(error)"
            )
        }
    }

    /// Logs an event using the logger.
    private func logEvent(
        _ event: String,
        level: LogLevel = .info,
        message: String? = nil,
        context: [String: String]? = nil
    ) {
        _ = logger.log(
            event: "session_manager.\(event)",
            level: level,
            message: message,
            context: context
        )
    }
}
