import AppKit
import ApplicationServices
import ProjectWorkspacesCore

/// AppKit-backed Accessibility permission checker for pwctl.
struct AppKitAccessibilityChecker: AccessibilityChecking {
    init() {}

    func isProcessTrusted() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

/// AppKit-backed running application checker for pwctl.
struct AppKitRunningApplicationChecker: RunningApplicationChecking {
    init() {}

    func isApplicationRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }
}

/// AppKit-backed screen metrics provider for pwctl.
struct AppKitScreenMetricsProvider: ScreenMetricsProviding {
    init() {}

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
