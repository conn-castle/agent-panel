import Foundation

/// Errors reported when screen metrics cannot be resolved.
public enum ScreenMetricsError: Error, Equatable, Sendable {
    case invalidScreenIndex(Int)
    case unavailable(String)
}

/// Provides screen metrics needed by activation layout steps.
public protocol ScreenMetricsProviding {
    /// Returns the visible width in points for the given 1-based screen index.
    /// - Parameter screenIndex1Based: 1-based index into the system screen list.
    /// - Returns: Visible width in points or a structured error.
    func visibleWidth(screenIndex1Based: Int) -> Result<Double, ScreenMetricsError>
}
