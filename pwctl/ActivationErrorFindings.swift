import ProjectWorkspacesCore

/// CLI mapping from activation errors to Doctor findings.
extension ActivationError {
    func asFindings() -> [DoctorFinding] {
        switch self {
        case .aeroSpaceIncompatible(let failingCommand, let stderr):
            return [
                DoctorFinding(
                    severity: .fail,
                    title: "AeroSpace CLI is incompatible",
                    detail: "command=\(failingCommand), stderr=\(stderr)",
                    fix: "Update AeroSpace to a version that supports the required commands."
                )
            ]
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
        case .workspaceNotFocused(let expected, let observed, let elapsedMs):
            return [
                DoctorFinding(
                    severity: .fail,
                    title: "Workspace did not become focused",
                    detail: "expected=\(expected), observed=\(observed), elapsed_ms=\(elapsedMs)",
                    fix: "Retry activation and keep the workspace focused."
                )
            ]
        case .workspaceNotFocusedAfterMove(let expected, let observed, let elapsedMs):
            return [
                DoctorFinding(
                    severity: .fail,
                    title: "Workspace focus changed after move",
                    detail: "expected=\(expected), observed=\(observed), elapsed_ms=\(elapsedMs)",
                    fix: "Retry activation and keep the workspace focused."
                )
            ]
        case .requiredWindowMissing(let appBundleId):
            return [
                DoctorFinding(
                    severity: .fail,
                    title: "Required window not detected",
                    detail: "app_bundle_id=\(appBundleId)",
                    fix: "Ensure the app can open a window and retry activation."
                )
            ]
        case .ambiguousWindows(let appBundleId, let count):
            return [
                DoctorFinding(
                    severity: .fail,
                    title: "Multiple windows matched the project token",
                    detail: "app_bundle_id=\(appBundleId), count=\(count)",
                    fix: "Close or rename duplicate project windows and retry activation."
                )
            ]
        case .moveFailed(let windowId, let workspace, let exitCode, let stderr):
            return [
                DoctorFinding(
                    severity: .fail,
                    title: "Failed to move window",
                    detail: "window_id=\(windowId), workspace=\(workspace), exit_code=\(exitCode), stderr=\(stderr)",
                    fix: "Retry activation after ensuring AeroSpace is running."
                )
            ]
        case .layoutFailed(let exitCode, let stderr):
            return [
                DoctorFinding(
                    severity: .fail,
                    title: "Layout command failed",
                    detail: "exit_code=\(exitCode), stderr=\(stderr)",
                    fix: "Ensure AeroSpace is running and retry activation."
                )
            ]
        case .resizeFailed(let exitCode, let stderr):
            return [
                DoctorFinding(
                    severity: .fail,
                    title: "Resize command failed",
                    detail: "exit_code=\(exitCode), stderr=\(stderr)",
                    fix: "Ensure AeroSpace is running and retry activation."
                )
            ]
        case .screenMetricsUnavailable(let screenIndex, let detail):
            return [
                DoctorFinding(
                    severity: .fail,
                    title: "Screen metrics unavailable",
                    detail: "screen_index=\(screenIndex), detail=\(detail)",
                    fix: "Ensure the target screen is available and retry activation."
                )
            ]
        case .commandFailed(let command, let arguments, let exitCode, let stderr, let detail):
            var detailLines: [String] = ["command=\(command)", "arguments=\(arguments.joined(separator: " "))", "stderr=\(stderr)"]
            if let exitCode {
                detailLines.append("exit_code=\(exitCode)")
            }
            if let detail {
                detailLines.append("detail=\(detail)")
            }
            return [
                DoctorFinding(
                    severity: .fail,
                    title: "Command failed",
                    detail: detailLines.joined(separator: ", "),
                    fix: "Fix the command error above and retry activation."
                )
            ]
        case .stateLoadFailed(let detail):
            return [
                DoctorFinding(
                    severity: .fail,
                    title: "State file could not be loaded",
                    detail: detail,
                    fix: "Fix the state file permissions or delete it to regenerate."
                )
            ]
        case .stateSaveFailed(let detail):
            return [
                DoctorFinding(
                    severity: .fail,
                    title: "State file could not be saved",
                    detail: detail,
                    fix: "Fix the state directory permissions and retry activation."
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
