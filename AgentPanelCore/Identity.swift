import Foundation

/// AgentPanel version and identifiers.
public enum AgentPanel {
    /// Bundle identifier for the AgentPanel app.
    static let appBundleIdentifier: String = "com.agentpanel.AgentPanel"

    /// Build-time version constant. Must match MARKETING_VERSION in project.yml.
    /// CI preflight verifies these stay in sync.
    static let buildVersion = "0.1.8"

    /// A human-readable version identifier for diagnostic output.
    /// Reads from the app bundle when available (e.g., running as the .app),
    /// falls back to the build-time constant (e.g., running as the CLI tool).
    public static var version: String {
        if let bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           !bundleVersion.isEmpty {
            return bundleVersion
        }
        return buildVersion
    }
}
