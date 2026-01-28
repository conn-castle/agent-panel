import Foundation

/// Deterministic token used to identify ProjectWorkspaces-owned windows.
public struct ProjectWindowToken: Equatable, Sendable {
    public let value: String

    /// Creates a token for a specific project.
    /// - Parameter projectId: Project identifier included in the token.
    public init(projectId: String) {
        precondition(!projectId.isEmpty, "projectId must not be empty")
        self.value = "PW:\(projectId)"
    }

    /// Returns true when a window title contains this token.
    /// - Parameter windowTitle: Window title to evaluate.
    public func matches(windowTitle: String) -> Bool {
        windowTitle.contains(value)
    }
}
