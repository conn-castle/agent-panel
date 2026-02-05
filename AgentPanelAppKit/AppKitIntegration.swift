import AppKit

import AgentPanelCore

/// Checks if an application is running using AppKit APIs.
public struct AppKitRunningApplicationChecker: RunningApplicationChecking {
    public init() {}

    public func isApplicationRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }
}
