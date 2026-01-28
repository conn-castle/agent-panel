import Foundation

/// Checks system permissions required by ProjectWorkspaces.
struct PermissionsChecker {
    private let accessibilityChecker: AccessibilityChecking
    private let hotkeyChecker: HotkeyChecking
    private let runningApplicationChecker: RunningApplicationChecking
    private let hotkeyStatusProvider: HotkeyRegistrationStatusProviding?

    /// Creates a permissions checker with the provided dependencies.
    /// - Parameters:
    ///   - accessibilityChecker: Accessibility permission checker.
    ///   - hotkeyChecker: Hotkey availability checker.
    ///   - runningApplicationChecker: Running application checker.
    ///   - hotkeyStatusProvider: Optional provider for the current hotkey registration status.
    init(
        accessibilityChecker: AccessibilityChecking,
        hotkeyChecker: HotkeyChecking,
        runningApplicationChecker: RunningApplicationChecking,
        hotkeyStatusProvider: HotkeyRegistrationStatusProviding? = nil
    ) {
        self.accessibilityChecker = accessibilityChecker
        self.hotkeyChecker = hotkeyChecker
        self.runningApplicationChecker = runningApplicationChecker
        self.hotkeyStatusProvider = hotkeyStatusProvider
    }

    /// Builds the accessibility permission finding.
    /// - Returns: Finding for accessibility permission status.
    func accessibilityFinding() -> DoctorFinding {
        if accessibilityChecker.isProcessTrusted() {
            return DoctorFinding(
                severity: .pass,
                title: "Accessibility permission granted",
                detail: "Current process is trusted for accessibility."
            )
        }

        return DoctorFinding(
            severity: .fail,
            title: "Accessibility permission missing",
            fix: "Enable Accessibility permission for ProjectWorkspaces.app in System Settings."
        )
    }

    /// Builds the hotkey availability finding.
    /// - Returns: Finding for Cmd+Shift+Space registration status.
    func hotkeyFinding() -> DoctorFinding {
        if let status = hotkeyStatusProvider?.hotkeyRegistrationStatus() {
            switch status {
            case .registered:
                return DoctorFinding(
                    severity: .pass,
                    title: "Cmd+Shift+Space hotkey is registered"
                )
            case .failed(let errorCode):
                return DoctorFinding(
                    severity: .fail,
                    title: "Cmd+Shift+Space hotkey cannot be registered",
                    detail: "OSStatus: \(errorCode)",
                    fix: "Unassign Cmd+Shift+Space in conflicting apps and restart ProjectWorkspaces."
                )
            }
        }

        if runningApplicationChecker.isApplicationRunning(bundleIdentifier: ProjectWorkspacesCore.appBundleIdentifier) {
            return DoctorFinding(
                severity: .pass,
                title: "Cmd+Shift+Space hotkey check skipped",
                detail: "ProjectWorkspaces agent is running; hotkey is managed by the app."
            )
        }

        let result = hotkeyChecker.checkCommandShiftSpace()
        if result.isAvailable {
            return DoctorFinding(
                severity: .pass,
                title: "Cmd+Shift+Space hotkey is available"
            )
        }

        let detail: String?
        if let errorCode = result.errorCode {
            detail = "OSStatus: \(errorCode)"
        } else {
            detail = nil
        }

        return DoctorFinding(
            severity: .fail,
            title: "Cmd+Shift+Space hotkey cannot be registered",
            detail: detail,
            fix: "Close other apps using Cmd+Shift+Space or adjust their shortcuts, then try again."
        )
    }
}
