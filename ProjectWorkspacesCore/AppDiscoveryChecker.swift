import Foundation

/// Checks application discovery for required apps (Chrome, IDEs).
struct AppDiscoveryChecker {
    private let fileSystem: FileSystem
    private let appDiscovery: AppDiscovering

    /// Creates an app discovery checker with the provided dependencies.
    /// - Parameters:
    ///   - fileSystem: File system accessor.
    ///   - appDiscovery: Application discovery provider.
    init(
        fileSystem: FileSystem,
        appDiscovery: AppDiscovering
    ) {
        self.fileSystem = fileSystem
        self.appDiscovery = appDiscovery
    }

    /// Runs app discovery checks based on the parsed config outcome.
    /// - Parameter outcome: Parsed config outcome or nil when unavailable.
    /// - Returns: Findings for required app discovery.
    func checkApps(outcome: ConfigParseOutcome?) -> [DoctorFinding] {
        var findings: [DoctorFinding] = []
        let ideConfig = outcome?.ideConfig ?? IdeConfig(vscode: nil, antigravity: nil)
        let ideKinds = outcome?.effectiveIdeKinds ?? []

        findings.append(checkChrome())

        if ideKinds.contains(.vscode) {
            findings.append(
                checkIdeApp(
                    label: "Visual Studio Code",
                    config: ideConfig.vscode,
                    fallbackBundleId: "com.microsoft.VSCode",
                    fallbackAppName: "Visual Studio Code",
                    configSection: "ide.vscode"
                )
            )
        }

        if ideKinds.contains(.antigravity) {
            findings.append(
                checkIdeApp(
                    label: "Antigravity",
                    config: ideConfig.antigravity,
                    fallbackBundleId: nil,
                    fallbackAppName: "Antigravity",
                    configSection: "ide.antigravity"
                )
            )
        }

        return findings
    }

    /// Checks Google Chrome discovery via Launch Services.
    /// - Returns: Finding for Chrome discovery.
    private func checkChrome() -> DoctorFinding {
        let bundleId = "com.google.Chrome"
        if let appURL = appDiscovery.applicationURL(bundleIdentifier: bundleId) {
            return DoctorFinding(
                severity: .pass,
                title: "Google Chrome discovered",
                detail: appURL.path
            )
        }

        if let appURL = appDiscovery.applicationURL(named: "Google Chrome") {
            return DoctorFinding(
                severity: .pass,
                title: "Google Chrome discovered",
                detail: appURL.path
            )
        }

        return DoctorFinding(
            severity: .fail,
            title: "Google Chrome not found",
            fix: "Install Google Chrome so ProjectWorkspaces can create Chrome windows."
        )
    }

    /// Checks app discovery for a supported IDE.
    /// - Parameters:
    ///   - label: Human-readable app name.
    ///   - config: Configured app values, if any.
    ///   - fallbackBundleId: Bundle identifier used for discovery when config is missing.
    ///   - fallbackAppName: App name used for discovery when bundle id is unavailable.
    ///   - configSection: Config section path used for fixes and snippets.
    /// - Returns: Finding for the IDE discovery status.
    private func checkIdeApp(
        label: String,
        config: IdeAppConfig?,
        fallbackBundleId: String?,
        fallbackAppName: String?,
        configSection: String
    ) -> DoctorFinding {
        let configAppPath = config?.appPath
        let configBundleId = config?.bundleId

        var resolvedAppURL: URL?
        var resolvedBundleId: String?

        if let configAppPath {
            let appURL = URL(fileURLWithPath: configAppPath, isDirectory: true)
            if !fileSystem.directoryExists(at: appURL) {
                return DoctorFinding(
                    severity: .fail,
                    title: "\(configSection).appPath does not exist",
                    detail: configAppPath,
                    fix: "Update \(configSection).appPath to a valid .app path."
                )
            }
            resolvedAppURL = appURL
        }

        if let configBundleId {
            guard let appURL = appDiscovery.applicationURL(bundleIdentifier: configBundleId) else {
                return DoctorFinding(
                    severity: .fail,
                    title: "\(configSection).bundleId not found",
                    detail: configBundleId,
                    fix: "Update \(configSection).bundleId to a valid bundle identifier."
                )
            }
            if let resolvedAppURL, resolvedAppURL.standardizedFileURL.path != appURL.standardizedFileURL.path {
                return DoctorFinding(
                    severity: .fail,
                    title: "\(configSection) values disagree",
                    detail: "bundleId resolves to \(appURL.path), but appPath is \(resolvedAppURL.path).",
                    fix: "Ensure \(configSection).appPath and \(configSection).bundleId refer to the same app."
                )
            }
            resolvedAppURL = appURL
            resolvedBundleId = configBundleId
        }

        if resolvedAppURL == nil {
            if let configBundleId {
                resolvedAppURL = appDiscovery.applicationURL(bundleIdentifier: configBundleId)
            } else if let fallbackBundleId {
                resolvedAppURL = appDiscovery.applicationURL(bundleIdentifier: fallbackBundleId)
                if resolvedAppURL != nil {
                    resolvedBundleId = fallbackBundleId
                }
            } else if let fallbackAppName {
                resolvedAppURL = appDiscovery.applicationURL(named: fallbackAppName)
            }
        }

        if resolvedBundleId == nil, let resolvedAppURL {
            resolvedBundleId = appDiscovery.bundleIdentifier(forApplicationAt: resolvedAppURL)
        }

        guard let resolvedAppURL, let resolvedBundleId else {
            return DoctorFinding(
                severity: .fail,
                title: "\(label) not discoverable",
                fix: "Install \(label) or add \(configSection).appPath and \(configSection).bundleId to config.toml."
            )
        }

        let snippet = buildIdeSnippet(section: configSection, appPath: resolvedAppURL.path, bundleId: resolvedBundleId)
        if configAppPath == nil || configBundleId == nil {
            return DoctorFinding(
                severity: .warn,
                title: "\(label) discovered via Launch Services",
                detail: "Missing config values were resolved automatically.",
                fix: "Add the discovered values to config.toml to make them explicit.",
                snippet: snippet
            )
        }

        return DoctorFinding(
            severity: .pass,
            title: "\(label) configured",
            detail: resolvedAppURL.path
        )
    }

    /// Builds a TOML snippet for IDE discovery output.
    /// - Parameters:
    ///   - section: TOML section name.
    ///   - appPath: Resolved app path.
    ///   - bundleId: Resolved bundle identifier.
    /// - Returns: TOML snippet string.
    private func buildIdeSnippet(section: String, appPath: String, bundleId: String) -> String {
        let escapedPath = escapeTomlString(appPath)
        let escapedBundleId = escapeTomlString(bundleId)
        return """
        [\(section)]
        appPath = "\(escapedPath)"
        bundleId = "\(escapedBundleId)"
        """
    }

    /// Escapes a string for TOML string literals.
    /// - Parameter value: String to escape.
    /// - Returns: Escaped string value.
    private func escapeTomlString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
