import Foundation

/// AgentPanel version and identifiers.
public enum AgentPanel {
    /// Bundle identifier for the AgentPanel app.
    static let appBundleIdentifier: String = "com.agentpanel.AgentPanel"

    /// A human-readable version identifier for diagnostic output.
    /// Reads from bundle when available, falls back to dev version for CLI.
    public static var version: String {
        if let bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           !bundleVersion.isEmpty {
            return bundleVersion
        }
        return "0.0.0-dev"
    }
}
