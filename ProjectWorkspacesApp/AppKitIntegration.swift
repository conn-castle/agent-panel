import AppKit
import ApplicationServices
import ProjectWorkspacesCore

/// AppKit-backed Accessibility permission checker.
struct AppKitAccessibilityChecker: AccessibilityChecking {
    /// Creates an Accessibility checker.
    init() {}

    /// Returns true when the current process is trusted for accessibility.
    func isProcessTrusted() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

/// AppKit-backed running application checker.
struct AppKitRunningApplicationChecker: RunningApplicationChecking {
    /// Creates a running application checker.
    init() {}

    /// Returns true when an application with the given bundle identifier is running.
    func isApplicationRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }
}

/// AppKit-backed screen metrics provider.
struct AppKitScreenMetricsProvider: ScreenMetricsProviding {
    /// Creates a screen metrics provider.
    init() {}

    /// Returns the visible width in points for the given 1-based screen index.
    func visibleWidth(screenIndex1Based: Int) -> Result<Double, ScreenMetricsError> {
        let index = screenIndex1Based - 1
        guard index >= 0 else {
            return .failure(.invalidScreenIndex(screenIndex1Based))
        }
        let screens = NSScreen.screens
        guard index < screens.count else {
            return .failure(.invalidScreenIndex(screenIndex1Based))
        }
        return .success(Double(screens[index].visibleFrame.width))
    }
}
