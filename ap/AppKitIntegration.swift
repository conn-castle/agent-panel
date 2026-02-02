import AppKit
import apcore

/// AppKit-backed running application checker for ap.
struct AppKitRunningApplicationChecker: RunningApplicationChecking {
    /// Creates a running application checker.
    init() {}

    /// Returns true when an application with the given bundle identifier is running.
    func isApplicationRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }
}
