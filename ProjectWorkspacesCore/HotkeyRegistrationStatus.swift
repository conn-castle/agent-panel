import Foundation

/// Current registration status for the global switcher hotkey.
public enum HotkeyRegistrationStatus: Equatable, Sendable {
    case registered
    case failed(osStatus: Int32)
}

/// Provides the last known hotkey registration status.
public protocol HotkeyRegistrationStatusProviding {
    /// Returns the current hotkey registration status, or nil if unknown.
    func hotkeyRegistrationStatus() -> HotkeyRegistrationStatus?
}
