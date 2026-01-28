import Foundation

/// Outcome of ensuring a Chrome window exists for a workspace.
public enum ChromeLaunchOutcome: Equatable, Sendable {
    /// A new Chrome window was created.
    case created(windowId: Int)
    /// A single existing Chrome window was already present.
    case existing(windowId: Int)
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
