import Foundation

/// Outcome of attempting to apply a layout.
public enum LayoutApplyOutcome: Equatable, Sendable {
    case applied
    case skipped(reason: LayoutSkipReason)
}

/// Reasons a layout was skipped.
public enum LayoutSkipReason: Equatable, Sendable {
    case notImplemented
    case screenUnavailable
    case focusNotVerified(
        expectedWindowId: Int,
        expectedWorkspace: String,
        actualWindowId: Int?,
        actualWorkspace: String?
    )
}

/// Applies layout geometry to IDE and Chrome windows.
public protocol LayoutApplying {
    /// Applies layout for the provided project windows.
    /// - Parameters:
    ///   - project: Project configuration.
    ///   - ideWindowId: IDE window id.
    ///   - chromeWindowId: Chrome window id.
    /// - Returns: Layout application outcome.
    func applyLayout(
        project: ProjectConfig,
        ideWindowId: Int,
        chromeWindowId: Int
    ) -> LayoutApplyOutcome
}

/// No-op layout applier used before Phase 6.
public struct NoopLayoutApplier: LayoutApplying {
    /// Creates a no-op layout applier.
    public init() {}

    /// Skips layout application with a not-implemented outcome.
    public func applyLayout(
        project: ProjectConfig,
        ideWindowId: Int,
        chromeWindowId: Int
    ) -> LayoutApplyOutcome {
        let _ = project
        let _ = ideWindowId
        let _ = chromeWindowId
        return .skipped(reason: .notImplemented)
    }
}
