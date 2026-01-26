import Foundation

/// Outcome of ensuring a Chrome window exists for a workspace.
public enum ChromeLaunchOutcome: Equatable, Sendable {
    /// A new Chrome window was created.
    case created(windowId: Int)
    /// A single existing Chrome window was already present.
    case existing(windowId: Int)
    /// Multiple Chrome windows already existed in the workspace (sorted ascending).
    case existingMultiple(windowIds: [Int])
}

/// Errors surfaced when ensuring a Chrome window exists.
public enum ChromeLaunchError: Error, Equatable, Sendable {
    /// The expected workspace is not currently focused.
    case workspaceNotFocused(expected: String, actual: String)
    /// No new Chrome window was detected within the polling window.
    case chromeWindowNotDetected(expectedWorkspace: String)
    /// Multiple new Chrome windows were detected when only one was expected (sorted ascending).
    case chromeWindowAmbiguous(newWindowIds: [Int])
    /// A Chrome window launched in a different workspace than expected.
    case chromeLaunchedElsewhere(expectedWorkspace: String, actualWorkspace: String, newWindowId: Int)
    /// Google Chrome could not be discovered via Launch Services.
    case chromeNotFound
    /// The `open` command failed to launch Chrome.
    case openFailed(ProcessCommandError)
    /// An AeroSpace command failed during Chrome launch orchestration.
    case aeroSpaceFailed(AeroSpaceCommandError)
}
