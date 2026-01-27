import Foundation

/// Identifies the kind of window managed during activation.
public enum ActivationWindowKind: String, Sendable {
    case ide
    case chrome
}

/// Reasons layout application may be skipped during activation.
public enum LayoutSkipReason: Equatable, Sendable {
    case screenUnavailable
    case focusNotVerified(
        expectedWindowId: Int,
        expectedWorkspace: String,
        actualWindowId: Int?,
        actualWorkspace: String?
    )
}

/// Warnings surfaced during activation that do not fail the operation.
public enum ActivationWarning: Equatable, Sendable {
    case multipleWindows(
        kind: ActivationWindowKind,
        workspace: String,
        chosenId: Int,
        extraIds: [Int]
    )
    case floatingFailed(
        kind: ActivationWindowKind,
        windowId: Int,
        error: AeroSpaceCommandError
    )
    case moveFailed(
        kind: ActivationWindowKind,
        windowId: Int,
        workspace: String,
        error: AeroSpaceCommandError
    )
    case createdElsewhereMoveFailed(
        kind: ActivationWindowKind,
        windowId: Int,
        actualWorkspace: String,
        error: AeroSpaceCommandError
    )
    case ideLaunchWarning(IdeLaunchWarning)
    case layoutSkipped(LayoutSkipReason)
    case layoutFailed(
        kind: ActivationWindowKind,
        windowId: Int,
        error: WindowGeometryError
    )
    case stateRecovered(backupPath: String)
}

/// Activation success output with warnings and resolved window ids.
public struct ActivationOutcome: Equatable, Sendable {
    public let ideWindowId: Int
    public let chromeWindowId: Int
    public let warnings: [ActivationWarning]

    /// Creates an activation outcome.
    /// - Parameters:
    ///   - ideWindowId: Selected IDE window id in the project workspace.
    ///   - chromeWindowId: Selected Chrome window id in the project workspace.
    ///   - warnings: Non-fatal warnings emitted during activation.
    public init(ideWindowId: Int, chromeWindowId: Int, warnings: [ActivationWarning]) {
        self.ideWindowId = ideWindowId
        self.chromeWindowId = chromeWindowId
        self.warnings = warnings
    }
}

/// Errors emitted when activation fails.
public enum ActivationError: Error, Equatable, Sendable {
    case configMissing(path: String)
    case configReadFailed(path: String, detail: String)
    case configInvalid(findings: [DoctorFinding])
    case projectNotFound(projectId: String)
    case aeroSpaceResolutionFailed(AeroSpaceBinaryResolutionError)
    case aeroSpaceFailed(AeroSpaceCommandError)
    case ideResolutionFailed(ide: IdeKind, error: IdeAppResolutionError)
    case ideBundleIdUnavailable(ide: IdeKind, appPath: String)
    case ideLaunchFailed(IdeLaunchError)
    case ideWindowNotDetected(ide: IdeKind)
    case ideWindowAmbiguous(newWindowIds: [Int])
    case chromeLaunchFailed(ChromeLaunchError)
    case workspaceNotEmpty(workspaceName: String, windowCount: Int)
    case stateReadFailed(path: String, detail: String)
    case stateWriteFailed(path: String, detail: String)
    case finalFocusFailed(AeroSpaceCommandError)

    /// Human-readable summary for CLI output.
    public var message: String {
        switch self {
        case .configMissing(let path):
            return "Config file missing: \(path)"
        case .configReadFailed(let path, let detail):
            return "Failed to read config: \(path). \(detail)"
        case .configInvalid:
            return "Config is invalid. Run `pwctl doctor` for details."
        case .projectNotFound(let projectId):
            return "Project not found: \(projectId)"
        case .aeroSpaceResolutionFailed(let error):
            return "AeroSpace CLI resolution failed: \(error.detail)"
        case .aeroSpaceFailed(let error):
            return "AeroSpace command failed: \(error.userFacingMessage)"
        case .ideResolutionFailed(let ide, let error):
            return "Failed to resolve \(ide.rawValue) app: \(error)"
        case .ideBundleIdUnavailable(let ide, let appPath):
            return "Unable to resolve bundle id for \(ide.rawValue) at \(appPath)"
        case .ideLaunchFailed(let error):
            return "IDE launch failed: \(error)"
        case .ideWindowNotDetected(let ide):
            return "Failed to detect newly created \(ide.rawValue) window."
        case .ideWindowAmbiguous(let newWindowIds):
            return "Multiple new IDE windows detected: \(newWindowIds)"
        case .chromeLaunchFailed(let error):
            return "Chrome launch failed: \(error)"
        case .workspaceNotEmpty(let workspaceName, let windowCount):
            return "Workspace \(workspaceName) is not empty (\(windowCount) windows). Move windows out before first activation."
        case .stateReadFailed(let path, let detail):
            return "Failed to read state file \(path): \(detail)"
        case .stateWriteFailed(let path, let detail):
            return "Failed to write state file \(path): \(detail)"
        case .finalFocusFailed(let error):
            return "Failed to focus IDE window: \(error)"
        }
    }
}
