import Foundation

/// A warning emitted during IDE launch that still allows a successful outcome.
public enum IdeLaunchWarning: Equatable, Sendable {
    case ideCommandFailed(command: String, error: ProcessCommandError)
    case launcherFailed(command: String, error: ProcessCommandError)
}

/// Errors emitted when IDE launch cannot complete.
public enum IdeLaunchError: Error, Equatable, Sendable {
    case workspaceGenerationFailed(VSCodeWorkspaceError)
    case appResolutionFailed(ide: IdeKind, error: IdeAppResolutionError)
    case shimInstallFailed(VSCodeShimError)
    case cliResolutionFailed(VSCodeCLIError)
    case openFailed(ProcessCommandError)
    case reuseWindowFailed(ProcessCommandError)
}

/// Successful IDE launch output with warnings.
public struct IdeLaunchSuccess: Equatable, Sendable {
    public let warnings: [IdeLaunchWarning]

    /// Creates a successful launch output.
    /// - Parameter warnings: Non-fatal launch warnings.
    public init(warnings: [IdeLaunchWarning]) {
        self.warnings = warnings
    }
}

/// Errors returned when executing external commands.
public enum ProcessCommandError: Error, Equatable, Sendable {
    case launchFailed(command: String, underlyingError: String)
    case nonZeroExit(command: String, result: CommandResult)
}
