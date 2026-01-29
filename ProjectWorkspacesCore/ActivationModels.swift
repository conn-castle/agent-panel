import Foundation

/// Identifies the kind of window managed during activation.
public enum ActivationWindowKind: String, Sendable {
    case ide
    case chrome
}

/// Output returned after a successful activation.
public struct ActivationReport: Equatable, Sendable {
    public let projectId: String
    public let workspaceName: String
    public let ideWindowId: Int
    public let chromeWindowId: Int

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
        chromeWindowId: Int
    ) {
        self.projectId = projectId
        self.workspaceName = workspaceName
        self.ideWindowId = ideWindowId
        self.chromeWindowId = chromeWindowId
    }
}

/// Non-fatal warnings emitted during activation.
public enum ActivationWarning: Equatable, Sendable {
    case configWarning(DoctorFinding)
    case ideLaunchWarning(IdeLaunchWarning)
    case multipleWindows(kind: ActivationWindowKind, workspace: String, chosenId: Int, extraIds: [Int])
    case layoutFailed(kind: ActivationWindowKind, windowId: Int, error: AeroSpaceCommandError)
    case moveFailed(kind: ActivationWindowKind, windowId: Int, workspace: String, error: AeroSpaceCommandError)
    case stateRecovered(backupPath: String)
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
        case .multipleWindows(let kind, let workspace, let chosenId, let extraIds):
            return "multipleWindows(\(kind.rawValue)): \(workspace) chose \(chosenId), extras \(extraIds.sorted())"
        case .layoutFailed(let kind, let windowId, let error):
            return "layoutFailed(\(kind.rawValue)): window \(windowId), error: \(error)"
        case .moveFailed(let kind, let windowId, let workspace, let error):
            return "moveFailed(\(kind.rawValue)): window \(windowId) to \(workspace), error: \(error)"
        case .stateRecovered(let backupPath):
            return "stateRecovered: \(backupPath)"
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
        }
    }
}

private extension AeroSpaceCommandError {
    var description: String {
        switch self {
        case .launchFailed(let command, let underlyingError):
            return "\(command): \(underlyingError)"
        case .nonZeroExit(let command, let result):
            return "\(command) exited \(result.exitCode)"
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
        }
    }
}
