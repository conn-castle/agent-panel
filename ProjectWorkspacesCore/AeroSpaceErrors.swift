import Foundation

/// Errors surfaced when executing AeroSpace CLI commands.
public enum AeroSpaceCommandError: Error, Equatable, Sendable {
    case executionFailed(CommandExecutionError)
    case timedOut(command: String, timeoutSeconds: TimeInterval, result: CommandResult)
    case decodingFailed(payload: String, underlyingError: String)
    case unexpectedOutput(command: String, detail: String)
    case notReady(AeroSpaceNotReady)
}

extension AeroSpaceCommandError {
    /// User-facing summary for CLI output.
    public var userFacingMessage: String {
        switch self {
        case .executionFailed(let error):
            switch error {
            case .launchFailed(let command, let underlyingError):
                return "Failed to launch AeroSpace command: \(command). \(underlyingError)"
            case .nonZeroExit(let command, let result):
                return "Command exited with code \(result.exitCode): \(command)"
            }
        case .timedOut(let command, let timeoutSeconds, _):
            return """
            Timed out after \(timeoutSeconds)s while running: \(command).
            If this hangs when run manually, restart AeroSpace and try again.
            """
        case .decodingFailed(_, let underlyingError):
            return "Failed to decode AeroSpace output: \(underlyingError)"
        case .unexpectedOutput(let command, let detail):
            return "Unexpected output from \(command): \(detail)"
        case .notReady(let payload):
            return """
            AeroSpace not ready after \(payload.timeoutSeconds)s.
            Last command: \(payload.lastCommandDescription) (exit \(payload.lastCommand.exitCode)).
            Readiness probe: \(payload.lastProbeDescription) (exit \(payload.lastProbe.exitCode)).
            """
        }
    }
}

/// Error returned when AeroSpace is not ready within the retry budget.
public struct AeroSpaceNotReady: Error, Equatable, Sendable {
    public let timeoutSeconds: TimeInterval
    public let lastCommandDescription: String
    public let lastCommand: CommandResult
    public let lastProbeDescription: String
    public let lastProbe: CommandResult

    /// Creates a not-ready error payload.
    /// - Parameters:
    ///   - timeoutSeconds: Total retry budget in seconds.
    ///   - lastCommandDescription: Description of the last attempted command.
    ///   - lastCommand: Result of the last attempted command.
    ///   - lastProbeDescription: Description of the last readiness probe.
    ///   - lastProbe: Result of the last readiness probe.
    public init(
        timeoutSeconds: TimeInterval,
        lastCommandDescription: String,
        lastCommand: CommandResult,
        lastProbeDescription: String,
        lastProbe: CommandResult
    ) {
        self.timeoutSeconds = timeoutSeconds
        self.lastCommandDescription = lastCommandDescription
        self.lastCommand = lastCommand
        self.lastProbeDescription = lastProbeDescription
        self.lastProbe = lastProbe
    }
}
