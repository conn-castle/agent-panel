import Foundation

/// Identifies the kind of window managed during activation.
public enum ActivationWindowKind: String, Hashable, Sendable {
    case ide
    case chrome
}

/// Output returned after a successful activation.
public struct ActivationReport: Equatable, Sendable {
    public let projectId: String
    public let workspaceName: String
    public let ideWindowId: Int
    public let chromeWindowId: Int
    public let ideBundleId: String?

    /// Creates an activation report.
    /// - Parameters:
    ///   - projectId: Project identifier.
    ///   - workspaceName: AeroSpace workspace name.
    ///   - ideWindowId: Selected IDE window id.
    ///   - chromeWindowId: Selected Chrome window id.
    public init(
        projectId: String,
        workspaceName: String,
        ideWindowId: Int,
        chromeWindowId: Int,
        ideBundleId: String? = nil
    ) {
        self.projectId = projectId
        self.workspaceName = workspaceName
        self.ideWindowId = ideWindowId
        self.chromeWindowId = chromeWindowId
        self.ideBundleId = ideBundleId
    }
}

/// Non-fatal warnings emitted during activation.
public enum ActivationWarning: Equatable, Sendable {
    case configWarning(DoctorFinding)
    case ideLaunchWarning(IdeLaunchWarning)
    case chromeLaunchWarning(ChromeLaunchWarning)
    case multipleWindows(kind: ActivationWindowKind, workspace: String, chosenId: Int, extraIds: [Int])
    case layoutFailed(kind: ActivationWindowKind, windowId: Int, error: AeroSpaceCommandError)
    case moveFailed(kind: ActivationWindowKind, windowId: Int, workspace: String, error: AeroSpaceCommandError)
    case stateRecovered(backupPath: String)
    case stateLoadFailed(detail: String)
    case multipleDisplaysDetected(count: Int)
    case windowOffMainDisplay(kind: ActivationWindowKind, windowId: Int)
    case layoutApplyFailed(kind: ActivationWindowKind, windowId: Int, detail: String)
    case layoutPersistFailed(detail: String)
    case layoutObserverFailed(kind: ActivationWindowKind, windowId: Int, detail: String)
    case layoutSkipped(reason: String)
    case workspaceNotFocused(expected: String, lastFocused: String?)
    case workspaceFocusFailed(detail: String)

    /// User-friendly message describing this warning.
    public var userMessage: String {
        switch self {
        case .chromeLaunchWarning(let chromeLaunchWarning):
            return "Chrome: \(chromeLaunchWarning)"
        case .ideLaunchWarning(let ideLaunchWarning):
            return "IDE: \(ideLaunchWarning)"
        case .configWarning(let doctorFinding):
            return "Config: \(doctorFinding.title)"
        case .multipleWindows(let kind, let workspace, _, let extraIds):
            return "\(kind) has \(extraIds.count) extra windows in \(workspace)"
        case .layoutFailed(let kind, let windowId, let error):
            return "\(kind) layout failed (window \(windowId)): \(error)"
        case .moveFailed(let kind, let windowId, let workspace, let error):
            return "\(kind) move failed (window \(windowId) to \(workspace)): \(error)"
        case .stateRecovered(let backupPath):
            return "State recovered from backup: \(backupPath)"
        case .stateLoadFailed(let detail):
            return "State load failed: \(detail)"
        case .multipleDisplaysDetected(let count):
            return "Multiple displays detected (\(count))"
        case .windowOffMainDisplay(let kind, let windowId):
            return "\(kind) window \(windowId) is off main display"
        case .layoutApplyFailed(let kind, let windowId, let detail):
            return "\(kind) layout apply failed (window \(windowId)): \(detail)"
        case .layoutPersistFailed(let detail):
            return "Layout persist failed: \(detail)"
        case .layoutObserverFailed(let kind, let windowId, let detail):
            return "\(kind) layout observer failed (window \(windowId)): \(detail)"
        case .layoutSkipped(let reason):
            return "Layout skipped: \(reason)"
        case .workspaceNotFocused(let expected, let lastFocused):
            if let lastFocused, !lastFocused.isEmpty {
                return "Workspace not focused (expected \(expected), last \(lastFocused))"
            }
            return "Workspace not focused (expected \(expected))"
        case .workspaceFocusFailed(let detail):
            return "Workspace focus check failed: \(detail)"
        }
    }
}

/// Progress milestones during activation.
public enum ActivationProgress: Equatable, Sendable {
    case switchingWorkspace(String)
    case switchedWorkspace(String)
    case ensuringChrome
    case ensuringIde
    case applyingLayout
    case finishing
}

/// Cancellation token for aborting activation.
public final class ActivationCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    /// Marks activation as cancelled.
    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    /// Returns true if cancellation was requested.
    public var isCancelled: Bool {
        lock.lock()
        let value = cancelled
        lock.unlock()
        return value
    }
}

/// Activation error outcomes.
public enum ActivationError: Error, Equatable, Sendable {
    case configFailed(findings: [DoctorFinding])
    case projectNotFound(projectId: String, availableProjectIds: [String])
    case workspaceFocusChanged(expected: String, actual: String)
    case aeroSpaceFailed(AeroSpaceCommandError)
    case aeroSpaceResolutionFailed(AeroSpaceBinaryResolutionError)
    case ideLaunchFailed(IdeLaunchError)
    case ideWindowNotDetected(expectedWorkspace: String)
    case ideWindowTokenNotDetected(token: String)
    case ideWindowTokenAmbiguous(token: String, windowIds: [Int])
    case chromeLaunchFailed(ChromeLaunchError)
    case logWriteFailed(LogWriteError)
    case cancelled
}

/// Outcome of an activation attempt.
public enum ActivationOutcome: Equatable, Sendable {
    case success(report: ActivationReport, warnings: [ActivationWarning])
    case failure(error: ActivationError)
}

/// Summary of a traced AeroSpace command for activation logs.
struct AeroSpaceCommandLog: Codable, Equatable, Sendable {
    let startedAt: String
    let endedAt: String
    let durationMs: Int
    let command: String
    let arguments: [String]
    let exitCode: Int32?
    let stdout: String?
    let stderr: String?
    let error: String?
}

/// Serialized activation log payload stored inside the logger context.
struct ActivationLogPayload: Codable, Equatable, Sendable {
    let projectId: String
    let workspaceName: String
    let outcome: String
    let ideWindowId: Int?
    let chromeWindowId: Int?
    let warnings: [String]
    let aeroSpaceCommands: [AeroSpaceCommandLog]
}

/// Serialized focus log payload stored inside the logger context.
struct ActivationFocusLogPayload: Codable, Equatable, Sendable {
    let projectId: String
    let workspaceName: String
    let windowId: Int
    let outcome: String
    let aeroSpaceCommands: [AeroSpaceCommandLog]
}

extension ActivationWarning {
    /// Converts an activation warning into a CLI-friendly Doctor finding.
    public func asFinding() -> DoctorFinding {
        switch self {
        case .configWarning(let finding):
            return finding
        case .ideLaunchWarning(let warning):
            switch warning {
            case .ideCommandFailed(let command, let error):
                return DoctorFinding(
                    severity: .warn,
                    title: "IDE launch command failed",
                    detail: "\(command): \(error)",
                    fix: "Fix the command or remove ideCommand from config.toml."
                )
            case .launcherFailed(let command, let error):
                return DoctorFinding(
                    severity: .warn,
                    title: "Agent-layer launcher failed",
                    detail: "\(command): \(error)",
                    fix: "Fix the launcher script or disable ideUseAgentLayerLauncher."
                )
            }
        case .chromeLaunchWarning(let warning):
            switch warning {
            case .multipleWindows(let workspace, let chosenId, let extraIds):
                return DoctorFinding(
                    severity: .warn,
                    title: "Multiple Chrome windows found",
                    detail: "Workspace \(workspace): chose \(chosenId), ignored \(extraIds.map(String.init).joined(separator: ", "))",
                    fix: "Close extra Chrome windows in this workspace."
                )
            }
        case .multipleWindows(let kind, let workspace, let chosenId, let extraIds):
            return DoctorFinding(
                severity: .warn,
                title: "Multiple \(kind.rawValue) windows found in \(workspace)",
                detail: "Chose window \(chosenId). Extra windows: \(extraIds.sorted()).",
                fix: "Close extra \(kind.rawValue) windows if this is unintended."
            )
        case .layoutFailed(let kind, let windowId, let error):
            return DoctorFinding(
                severity: .warn,
                title: "Failed to set \(kind.rawValue) window \(windowId) to floating",
                detail: "\(error)",
                fix: "Window placement may be incorrect; try re-activating the project."
            )
        case .moveFailed(let kind, let windowId, let workspace, let error):
            return DoctorFinding(
                severity: .warn,
                title: "Failed to move \(kind.rawValue) window \(windowId) to \(workspace)",
                detail: "\(error)",
                fix: "The window may need to be closed and recreated."
            )
        case .stateRecovered(let backupPath):
            return DoctorFinding(
                severity: .warn,
                title: "State file was corrupted and recovered",
                detail: "Corrupted state backed up to: \(backupPath)",
                fix: "Previous managed window IDs were lost. Activation will create fresh state."
            )
        case .stateLoadFailed(let detail):
            return DoctorFinding(
                severity: .warn,
                title: "State file could not be loaded",
                detail: detail,
                fix: "Layout persistence may be unavailable; retry activation."
            )
        case .multipleDisplaysDetected(let count):
            return DoctorFinding(
                severity: .warn,
                title: "Multiple displays detected",
                detail: "display_count=\(count)",
                fix: "ProjectWorkspaces uses the main display only in v1."
            )
        case .windowOffMainDisplay(let kind, let windowId):
            return DoctorFinding(
                severity: .warn,
                title: "\(kind.rawValue) window is off the main display",
                detail: "window_id=\(windowId)",
                fix: "Move the window to the main display to enable layout persistence."
            )
        case .layoutApplyFailed(let kind, let windowId, let detail):
            return DoctorFinding(
                severity: .warn,
                title: "Failed to apply layout for \(kind.rawValue) window",
                detail: "window_id=\(windowId); \(detail)",
                fix: "Layout may be incorrect; try re-activating the project."
            )
        case .layoutPersistFailed(let detail):
            return DoctorFinding(
                severity: .warn,
                title: "Failed to persist layout",
                detail: detail,
                fix: "Layout changes may not be saved; try re-activating the project."
            )
        case .layoutObserverFailed(let kind, let windowId, let detail):
            return DoctorFinding(
                severity: .warn,
                title: "Failed to observe \(kind.rawValue) window for layout changes",
                detail: "window_id=\(windowId); \(detail)",
                fix: "Layout changes may not be persisted; try re-activating the project."
            )
        case .layoutSkipped(let reason):
            return DoctorFinding(
                severity: .warn,
                title: "Layout application skipped",
                detail: reason,
                fix: "Resolve the warning and retry activation."
            )
        case .workspaceNotFocused(let expected, let lastFocused):
            let detail = lastFocused.map { "expected=\(expected) last=\($0)" } ?? "expected=\(expected)"
            return DoctorFinding(
                severity: .warn,
                title: "Workspace did not become focused",
                detail: detail,
                fix: "Retry activation after ensuring AeroSpace can focus the workspace."
            )
        case .workspaceFocusFailed(let detail):
            return DoctorFinding(
                severity: .warn,
                title: "Workspace focus check failed",
                detail: detail,
                fix: "Retry activation after ensuring AeroSpace is running."
            )
        }
    }

    /// Returns a short summary for logging context.
    func logSummary() -> String {
        switch self {
        case .configWarning(let finding):
            return "configWarning: \(finding.title)"
        case .ideLaunchWarning(let warning):
            switch warning {
            case .ideCommandFailed(let command, _):
                return "ideCommandFailed: \(command)"
            case .launcherFailed(let command, _):
                return "launcherFailed: \(command)"
            }
        case .chromeLaunchWarning(let warning):
            switch warning {
            case .multipleWindows(let workspace, let chosenId, let extraIds):
                return "chromeLaunchWarning: multipleWindows in \(workspace), chose \(chosenId), extras \(extraIds.sorted())"
            }
        case .multipleWindows(let kind, let workspace, let chosenId, let extraIds):
            return "multipleWindows(\(kind.rawValue)): \(workspace) chose \(chosenId), extras \(extraIds.sorted())"
        case .layoutFailed(let kind, let windowId, let error):
            return "layoutFailed(\(kind.rawValue)): window \(windowId), error: \(error)"
        case .moveFailed(let kind, let windowId, let workspace, let error):
            return "moveFailed(\(kind.rawValue)): window \(windowId) to \(workspace), error: \(error)"
        case .stateRecovered(let backupPath):
            return "stateRecovered: \(backupPath)"
        case .stateLoadFailed(let detail):
            return "stateLoadFailed: \(detail)"
        case .multipleDisplaysDetected(let count):
            return "multipleDisplaysDetected: \(count)"
        case .windowOffMainDisplay(let kind, let windowId):
            return "windowOffMainDisplay(\(kind.rawValue)): window \(windowId)"
        case .layoutApplyFailed(let kind, let windowId, let detail):
            return "layoutApplyFailed(\(kind.rawValue)): window \(windowId), detail: \(detail)"
        case .layoutPersistFailed(let detail):
            return "layoutPersistFailed: \(detail)"
        case .layoutObserverFailed(let kind, let windowId, let detail):
            return "layoutObserverFailed(\(kind.rawValue)): window \(windowId), detail: \(detail)"
        case .layoutSkipped(let reason):
            return "layoutSkipped: \(reason)"
        case .workspaceNotFocused(let expected, let lastFocused):
            let last = lastFocused ?? "unknown"
            return "workspaceNotFocused: expected \(expected), last \(last)"
        case .workspaceFocusFailed(let detail):
            return "workspaceFocusFailed: \(detail)"
        }
    }
}

extension ActivationError {
    /// Converts an activation error into CLI-friendly Doctor findings.
    public func asFindings() -> [DoctorFinding] {
        switch self {
        case .configFailed(let findings):
            return findings
        case .projectNotFound(let projectId, let available):
            let availableList = available.isEmpty ? "none" : available.sorted().joined(separator: ", ")
            return [
                DoctorFinding(
                    severity: .fail,
                    title: "Project not found",
                    detail: "projectId=\(projectId), available=\(availableList)",
                    fix: "Use `pwctl list` to see configured project IDs."
                )
            ]
        case .workspaceFocusChanged(let expected, let actual):
            return [
                DoctorFinding(
                    severity: .fail,
                    title: "Workspace focus changed during activation",
                    detail: "Expected \(expected), but focused workspace was \(actual).",
                    fix: "Re-run activation and keep the project workspace focused."
                )
            ]
        case .aeroSpaceFailed(let error):
            return [
                DoctorFinding(
                    severity: .fail,
                    title: "AeroSpace command failed",
                    detail: error.description,
                    fix: "Ensure AeroSpace is running and the CLI is available."
                )
            ]
        case .aeroSpaceResolutionFailed(let error):
            return [
                DoctorFinding(
                    severity: .fail,
                    title: "AeroSpace CLI could not be resolved",
                    detail: error.detail,
                    fix: error.fix
                )
            ]
        case .ideLaunchFailed(let error):
            return [
                DoctorFinding(
                    severity: .fail,
                    title: "IDE launch failed",
                    detail: "\(error)",
                    fix: "Verify IDE configuration and retry activation."
                )
            ]
        case .ideWindowNotDetected(let expectedWorkspace):
            return [
                DoctorFinding(
                    severity: .fail,
                    title: "IDE window not detected in workspace",
                    detail: "No new IDE window appeared in \(expectedWorkspace).",
                    fix: "Ensure the IDE launches successfully and re-run activation."
                )
            ]
        case .ideWindowTokenNotDetected(let token):
            return [
                DoctorFinding(
                    severity: .fail,
                    title: "IDE window not detected with token",
                    detail: "No IDE window title contained \(token).",
                    fix: "Ensure the IDE window title includes the project token and re-run activation."
                )
            ]
        case .ideWindowTokenAmbiguous(let token, let windowIds):
            return [
                DoctorFinding(
                    severity: .fail,
                    title: "Multiple IDE windows matched token",
                    detail: "Token \(token) matched windows \(windowIds.sorted()).",
                    fix: "Close extra IDE windows with the project token and re-run activation."
                )
            ]
        case .chromeLaunchFailed(let error):
            return [
                DoctorFinding(
                    severity: .fail,
                    title: "Chrome launch failed",
                    detail: error.detailMessage,
                    fix: error.fixMessage
                )
            ]
        case .logWriteFailed(let error):
            return [
                DoctorFinding(
                    severity: .fail,
                    title: "Activation log write failed",
                    detail: error.message,
                    fix: "Check log directory permissions and retry."
                )
            ]
        case .cancelled:
            return [
                DoctorFinding(
                    severity: .warn,
                    title: "Activation cancelled",
                    detail: "Activation was cancelled by the user.",
                    fix: "Retry activation when ready."
                )
            ]
        }
    }
}

private extension AeroSpaceCommandError {
    var description: String {
        switch self {
        case .executionFailed(let error):
            switch error {
            case .launchFailed(let command, let underlyingError):
                return "\(command): \(underlyingError)"
            case .nonZeroExit(let command, let result):
                return "\(command) exited \(result.exitCode)"
            }
        case .timedOut(let command, let timeoutSeconds, _):
            return "\(command) timed out after \(timeoutSeconds)s"
        case .decodingFailed(_, let underlyingError):
            return "Failed to decode list-windows output: \(underlyingError)"
        case .unexpectedOutput(let command, let detail):
            return "\(command): \(detail)"
        case .notReady(let notReady):
            return "AeroSpace not ready after \(notReady.timeoutSeconds)s"
        }
    }
}

private extension ChromeLaunchError {
    var detailMessage: String {
        switch self {
        case .chromeWindowNotDetected(let token):
            return "Chrome window was not detected with token \(token)."
        case .chromeWindowAmbiguous(let token, let windowIds):
            return "Multiple Chrome windows matched token \(token): \(windowIds.sorted())."
        case .chromeNotFound:
            return "Google Chrome could not be discovered."
        case .openFailed(let error):
            return "\(error)"
        case .aeroSpaceFailed(let error):
            return error.description
        case .cancelled:
            return "Activation cancelled."
        }
    }

    var fixMessage: String {
        switch self {
        case .chromeWindowNotDetected:
            return "Re-run activation and confirm the Chrome window title includes the project token."
        case .chromeWindowAmbiguous:
            return "Close extra Chrome windows with the project token and re-run activation."
        case .chromeNotFound:
            return "Install Google Chrome and re-run activation."
        case .openFailed:
            return "Ensure Chrome is installed and accessible."
        case .aeroSpaceFailed:
            return "Ensure AeroSpace is running and the CLI is available."
        case .cancelled:
            return "Retry activation when ready."
        }
    }
}
