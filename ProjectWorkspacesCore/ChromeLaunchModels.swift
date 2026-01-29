import Foundation

/// Outcome of ensuring a Chrome window exists for a workspace.
public enum ChromeLaunchOutcome: Equatable, Sendable {
    /// A new Chrome window was created.
    case created(windowId: Int)
    /// A single existing Chrome window was already present.
    case existing(windowId: Int)
}

/// Non-fatal warnings emitted during Chrome window detection.
public enum ChromeLaunchWarning: Equatable, Sendable {
    case multipleWindows(workspace: String, chosenId: Int, extraIds: [Int])
}

/// Result of ensuring a Chrome window exists, including any warnings.
public struct ChromeLaunchResult: Equatable, Sendable {
    public let outcome: ChromeLaunchOutcome
    public let warnings: [ChromeLaunchWarning]

    public init(outcome: ChromeLaunchOutcome, warnings: [ChromeLaunchWarning]) {
        self.outcome = outcome
        self.warnings = warnings
    }
}

/// Errors surfaced when ensuring a Chrome window exists.
public enum ChromeLaunchError: Error, Equatable, Sendable {
    /// No Chrome window with the expected token was detected within the polling window.
    case chromeWindowNotDetected(token: String)
    /// Multiple Chrome windows matched the token (sorted ascending).
    case chromeWindowAmbiguous(token: String, windowIds: [Int])
    /// Google Chrome could not be discovered via Launch Services.
    case chromeNotFound
    /// The `open` command failed to launch Chrome.
    case openFailed(ProcessCommandError)
    /// An AeroSpace command failed during Chrome launch orchestration.
    case aeroSpaceFailed(AeroSpaceCommandError)
}
