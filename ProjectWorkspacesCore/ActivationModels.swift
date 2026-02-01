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

/// Progress milestones during activation.
public enum ActivationProgress: Equatable, Sendable {
    case switchingWorkspace(String)
    case confirmingWorkspace(String)
    case resolvingWindows
    case movingWindows
    case applyingLayout
    case resizingIde
    case focusingIde
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
    case aeroSpaceIncompatible(failingCommand: String, stderr: String)
    case configFailed(findings: [DoctorFinding])
    case projectNotFound(projectId: String, availableProjectIds: [String])
    case workspaceNotFocused(expected: String, observed: String, elapsedMs: Int)
    case workspaceNotFocusedAfterMove(expected: String, observed: String, elapsedMs: Int)
    case requiredWindowMissing(appBundleId: String)
    case ambiguousWindows(appBundleId: String, count: Int)
    case moveFailed(windowId: Int, workspace: String, exitCode: Int, stderr: String)
    case layoutFailed(exitCode: Int, stderr: String)
    case resizeFailed(exitCode: Int, stderr: String)
    case screenMetricsUnavailable(screenIndex: Int, detail: String)
    case commandFailed(command: String, arguments: [String], exitCode: Int?, stderr: String, detail: String?)
    case stateLoadFailed(detail: String)
    case stateSaveFailed(detail: String)
    case aeroSpaceResolutionFailed(AeroSpaceBinaryResolutionError)
    case logWriteFailed(LogWriteError)
    case cancelled
}

/// Outcome of an activation attempt.
public enum ActivationOutcome: Equatable, Sendable {
    case success(report: ActivationReport)
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
    let errorCode: String?
    let errorContext: [String: String]?
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

extension ActivationError {
    /// Returns a stable error code for logging and UI mapping.
    var code: String {
        switch self {
        case .aeroSpaceIncompatible:
            return "aerospace_incompatible"
        case .configFailed:
            return "config_failed"
        case .projectNotFound:
            return "project_not_found"
        case .workspaceNotFocused:
            return "workspace_not_focused"
        case .workspaceNotFocusedAfterMove:
            return "workspace_not_focused_after_move"
        case .requiredWindowMissing:
            return "required_window_missing"
        case .ambiguousWindows:
            return "ambiguous_windows"
        case .moveFailed:
            return "move_failed"
        case .layoutFailed:
            return "layout_failed"
        case .resizeFailed:
            return "resize_failed"
        case .screenMetricsUnavailable:
            return "screen_metrics_unavailable"
        case .commandFailed:
            return "command_failed"
        case .stateLoadFailed:
            return "state_load_failed"
        case .stateSaveFailed:
            return "state_save_failed"
        case .aeroSpaceResolutionFailed:
            return "aerospace_resolution_failed"
        case .logWriteFailed:
            return "log_write_failed"
        case .cancelled:
            return "cancelled"
        }
    }

    /// Returns a string-keyed context payload for logging.
    var logContext: [String: String] {
        switch self {
        case .aeroSpaceIncompatible(let failingCommand, let stderr):
            return [
                "command": failingCommand,
                "stderr": stderr
            ]
        case .configFailed(let findings):
            return ["finding_count": "\(findings.count)"]
        case .projectNotFound(let projectId, let available):
            return [
                "project_id": projectId,
                "available": available.sorted().joined(separator: ",")
            ]
        case .workspaceNotFocused(let expected, let observed, let elapsedMs):
            return [
                "expected": expected,
                "observed": observed,
                "elapsed_ms": "\(elapsedMs)"
            ]
        case .workspaceNotFocusedAfterMove(let expected, let observed, let elapsedMs):
            return [
                "expected": expected,
                "observed": observed,
                "elapsed_ms": "\(elapsedMs)"
            ]
        case .requiredWindowMissing(let appBundleId):
            return ["app_bundle_id": appBundleId]
        case .ambiguousWindows(let appBundleId, let count):
            return [
                "app_bundle_id": appBundleId,
                "count": "\(count)"
            ]
        case .moveFailed(let windowId, let workspace, let exitCode, let stderr):
            return [
                "window_id": "\(windowId)",
                "workspace": workspace,
                "exit_code": "\(exitCode)",
                "stderr": stderr
            ]
        case .layoutFailed(let exitCode, let stderr):
            return [
                "exit_code": "\(exitCode)",
                "stderr": stderr
            ]
        case .resizeFailed(let exitCode, let stderr):
            return [
                "exit_code": "\(exitCode)",
                "stderr": stderr
            ]
        case .screenMetricsUnavailable(let screenIndex, let detail):
            return [
                "screen_index": "\(screenIndex)",
                "detail": detail
            ]
        case .commandFailed(let command, let arguments, let exitCode, let stderr, let detail):
            var context: [String: String] = [
                "command": command,
                "arguments": arguments.joined(separator: " "),
                "stderr": stderr
            ]
            if let exitCode {
                context["exit_code"] = "\(exitCode)"
            }
            if let detail {
                context["detail"] = detail
            }
            return context
        case .stateLoadFailed(let detail):
            return ["detail": detail]
        case .stateSaveFailed(let detail):
            return ["detail": detail]
        case .aeroSpaceResolutionFailed(let error):
            return [
                "detail": error.detail,
                "fix": error.fix
            ]
        case .logWriteFailed(let error):
            return ["detail": error.message]
        case .cancelled:
            return [:]
        }
    }
}
