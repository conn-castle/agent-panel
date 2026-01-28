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

    /// Returns true when a window title contains this token followed by a word boundary.
    /// - Parameter windowTitle: Window title to evaluate.
    /// - Returns: True when the token is followed by a non-word character or the end of the string.
    public func matches(windowTitle: String) -> Bool {
        var searchRange = windowTitle.startIndex..<windowTitle.endIndex
        while let matchRange = windowTitle.range(of: value, range: searchRange) {
            if matchRange.upperBound == windowTitle.endIndex {
                return true
            }
            let nextCharacter = windowTitle[matchRange.upperBound]
            if !nextCharacter.isLetter && !nextCharacter.isNumber && nextCharacter != "_" {
                return true
            }
            searchRange = matchRange.upperBound..<windowTitle.endIndex
        }
        return false
    }
}
