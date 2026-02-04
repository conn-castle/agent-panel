// NOTE: This file is intentionally duplicated in AgentPanelApp/.
// Both targets need AppKit access, but AgentPanelCore cannot import AppKit.
// Keep both copies in sync.

import AppKit

import AgentPanelCore

/// Checks if an application is running using AppKit APIs.
struct AppKitRunningApplicationChecker: RunningApplicationChecking {
    func isApplicationRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }
}
