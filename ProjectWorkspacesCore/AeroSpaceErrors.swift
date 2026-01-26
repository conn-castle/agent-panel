import Foundation

/// Errors surfaced when executing AeroSpace CLI commands.
public enum AeroSpaceCommandError: Error, Equatable, Sendable {
    case launchFailed(command: String, underlyingError: String)
    case nonZeroExit(command: String, result: CommandResult)
    case timedOut(command: String, timeoutSeconds: TimeInterval, result: CommandResult)
    case decodingFailed(payload: String, underlyingError: String)
    case notReady(AeroSpaceNotReady)
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
