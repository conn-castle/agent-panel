import AppKit

import apcore

/// Result of the onboarding check.
enum OnboardingResult {
    /// Setup is complete, app can continue.
    case ready
    /// User declined setup, app should quit.
    case declined
}

/// Handles first-launch setup for AgentPanel.
/// Ensures AeroSpace is installed and configured before the app runs.
struct Onboarding {
    private let logger: AgentPanelLogging
    private let aerospace: ApAeroSpace
    private let configManager: AeroSpaceConfigManager

    /// Creates an onboarding handler.
    /// - Parameter logger: Logger for diagnostic events.
    init(logger: AgentPanelLogging) {
        self.logger = logger
        self.aerospace = ApAeroSpace()
        self.configManager = AeroSpaceConfigManager()
    }

    /// Performs onboarding if needed.
    /// - Returns: `.ready` if setup is complete, `.declined` if user chose to quit.
    func runIfNeeded() -> OnboardingResult {
        let needsAeroSpaceInstall = !aerospace.isAppInstalled()
        let needsConfigSetup = configManager.configStatus() != .managedByAgentPanel

        // If everything is set up, no onboarding needed
        guard needsAeroSpaceInstall || needsConfigSetup else {
            log(event: "onboarding.skipped", context: ["reason": "already_configured"])
            return .ready
        }

        log(
            event: "onboarding.required",
            context: [
                "needs_aerospace": needsAeroSpaceInstall ? "true" : "false",
                "needs_config": needsConfigSetup ? "true" : "false"
            ]
        )

        let userAccepted = showAlert(needsAeroSpaceInstall: needsAeroSpaceInstall)

        guard userAccepted else {
            log(event: "onboarding.declined")
            return .declined
        }

        log(event: "onboarding.accepted")

        if performSetup(needsAeroSpaceInstall: needsAeroSpaceInstall) {
            return .ready
        } else {
            return .declined
        }
    }

    /// Shows the onboarding alert asking user for permission.
    private func showAlert(needsAeroSpaceInstall: Bool) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "AgentPanel requires AeroSpace"

        if needsAeroSpaceInstall {
            alert.informativeText = """
                AeroSpace is a window manager that AgentPanel uses to organize your workspace. \
                AgentPanel will install it via Homebrew and configure it automatically.

                AgentPanel cannot run without AeroSpace installed. \
                If you choose Quit, the app will close.
                """
        } else {
            alert.informativeText = """
                AgentPanel needs to configure AeroSpace to work correctly. \
                Your existing AeroSpace config will be backed up.

                AgentPanel cannot run without a compatible AeroSpace configuration. \
                If you choose Quit, the app will close.
                """
        }

        alert.addButton(withTitle: needsAeroSpaceInstall ? "Install & Continue" : "Configure & Continue")
        alert.addButton(withTitle: "Quit")

        let response = alert.runModal()
        return response == .alertFirstButtonReturn
    }

    /// Performs the actual setup: install AeroSpace and/or write config.
    private func performSetup(needsAeroSpaceInstall: Bool) -> Bool {
        // Install AeroSpace if needed
        if needsAeroSpaceInstall {
            log(event: "onboarding.installing_aerospace")
            switch aerospace.installViaHomebrew() {
            case .failure(let error):
                log(event: "onboarding.install_failed", context: ["error": error.message])
                showErrorAlert(message: "Failed to install AeroSpace: \(error.message)")
                return false
            case .success:
                log(event: "onboarding.aerospace_installed")
            }
        }

        // Write safe config
        log(event: "onboarding.writing_config")
        switch configManager.writeSafeConfig() {
        case .failure(let error):
            log(event: "onboarding.config_failed", context: ["error": error.message])
            showErrorAlert(message: "Failed to write AeroSpace config: \(error.message)")
            return false
        case .success:
            log(event: "onboarding.config_written")
        }

        // Start AeroSpace
        log(event: "onboarding.starting_aerospace")
        switch aerospace.start() {
        case .failure(let error):
            log(event: "onboarding.start_failed", context: ["error": error.message])
            // Not fatal - AeroSpace might already be running or will start later
        case .success:
            log(event: "onboarding.aerospace_started")
        }

        log(event: "onboarding.completed")
        return true
    }

    /// Shows an error alert when setup fails.
    private func showErrorAlert(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Setup Failed"
        alert.informativeText = "\(message)\n\nAgentPanel will now quit."
        alert.addButton(withTitle: "Quit")
        alert.runModal()
    }

    /// Logs an onboarding event.
    private func log(event: String, context: [String: String]? = nil) {
        _ = logger.log(event: event, level: .info, message: nil, context: context)
    }
}
