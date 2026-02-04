import Foundation

// MARK: - Doctor Models

/// Severity level for Doctor findings.
public enum DoctorSeverity: String, CaseIterable, Sendable {
    case pass = "PASS"
    case warn = "WARN"
    case fail = "FAIL"

    /// Sort order for display purposes (failures first).
    public var sortOrder: Int {
        switch self {
        case .fail: return 0
        case .warn: return 1
        case .pass: return 2
        }
    }
}

/// A single Doctor finding rendered in the report.
public struct DoctorFinding: Equatable, Sendable {
    public let severity: DoctorSeverity
    public let title: String
    public let bodyLines: [String]
    public let snippet: String?

    /// Creates a Doctor finding.
    /// - Parameters:
    ///   - severity: PASS, WARN, or FAIL severity.
    ///   - title: Short summary of the finding.
    ///   - detail: Optional detail text for additional context.
    ///   - fix: Optional "Fix:" guidance for the user.
    ///   - bodyLines: Additional lines to render verbatim after the title.
    ///   - snippet: Optional copy/paste snippet to resolve the finding.
    public init(
        severity: DoctorSeverity,
        title: String,
        detail: String? = nil,
        fix: String? = nil,
        bodyLines: [String] = [],
        snippet: String? = nil
    ) {
        self.severity = severity
        self.title = title
        var lines = bodyLines
        if let detail, !detail.isEmpty {
            lines.append("Detail: \(detail)")
        }
        if let fix, !fix.isEmpty {
            lines.append("Fix: \(fix)")
        }
        self.bodyLines = lines
        self.snippet = snippet
    }
}

/// Report metadata rendered in the Doctor header.
public struct DoctorMetadata: Equatable, Sendable {
    public let timestamp: String
    public let agentPanelVersion: String
    public let macOSVersion: String
    public let aerospaceApp: String
    public let aerospaceCli: String

    public init(
        timestamp: String,
        agentPanelVersion: String,
        macOSVersion: String,
        aerospaceApp: String,
        aerospaceCli: String
    ) {
        self.timestamp = timestamp
        self.agentPanelVersion = agentPanelVersion
        self.macOSVersion = macOSVersion
        self.aerospaceApp = aerospaceApp
        self.aerospaceCli = aerospaceCli
    }
}

/// Action availability for Doctor UI buttons.
public struct DoctorActionAvailability: Equatable, Sendable {
    public let canInstallAeroSpace: Bool
    public let canStartAeroSpace: Bool
    public let canReloadAeroSpaceConfig: Bool

    public init(
        canInstallAeroSpace: Bool,
        canStartAeroSpace: Bool,
        canReloadAeroSpaceConfig: Bool
    ) {
        self.canInstallAeroSpace = canInstallAeroSpace
        self.canStartAeroSpace = canStartAeroSpace
        self.canReloadAeroSpaceConfig = canReloadAeroSpaceConfig
    }

    /// Returns a disabled action set.
    public static let none = DoctorActionAvailability(
        canInstallAeroSpace: false,
        canStartAeroSpace: false,
        canReloadAeroSpaceConfig: false
    )
}

/// A structured Doctor report.
public struct DoctorReport: Equatable, Sendable {
    public let metadata: DoctorMetadata
    public let findings: [DoctorFinding]
    public let actions: DoctorActionAvailability

    public init(
        metadata: DoctorMetadata,
        findings: [DoctorFinding],
        actions: DoctorActionAvailability = .none
    ) {
        self.metadata = metadata
        self.findings = findings
        self.actions = actions
    }

    /// Returns true when the report contains any FAIL findings.
    public var hasFailures: Bool {
        findings.contains { $0.severity == .fail }
    }

    /// Renders the report as a human-readable string.
    public func rendered() -> String {
        let indexed = findings.enumerated()
        let sortedFindings = indexed.sorted { lhs, rhs in
            let leftOrder = lhs.element.severity.sortOrder
            let rightOrder = rhs.element.severity.sortOrder
            if leftOrder == rightOrder {
                return lhs.offset < rhs.offset
            }
            return leftOrder < rightOrder
        }.map { $0.element }

        var lines: [String] = []
        lines.append("AgentPanel Doctor Report")
        lines.append("Timestamp: \(metadata.timestamp)")
        lines.append("AgentPanel version: \(metadata.agentPanelVersion)")
        lines.append("macOS version: \(metadata.macOSVersion)")
        lines.append("AeroSpace app: \(metadata.aerospaceApp)")
        lines.append("aerospace CLI: \(metadata.aerospaceCli)")
        lines.append("")

        if sortedFindings.isEmpty {
            lines.append("PASS  no issues found")
        } else {
            for finding in sortedFindings {
                if finding.title.isEmpty {
                    for line in finding.bodyLines {
                        lines.append(line)
                    }
                    continue
                }

                lines.append("\(finding.severity.rawValue)  \(finding.title)")
                for line in finding.bodyLines {
                    lines.append(line)
                }
                if let snippet = finding.snippet, !snippet.isEmpty {
                    lines.append("  Snippet:")
                    lines.append("  ```toml")
                    for line in snippet.split(separator: "\n", omittingEmptySubsequences: false) {
                        lines.append("  \(line)")
                    }
                    lines.append("  ```")
                }
            }
        }

        let countedFindings = sortedFindings.filter { !$0.title.isEmpty }
        let passCount = countedFindings.filter { $0.severity == .pass }.count
        let warnCount = countedFindings.filter { $0.severity == .warn }.count
        let failCount = countedFindings.filter { $0.severity == .fail }.count

        lines.append("")
        lines.append("Summary: \(passCount) PASS, \(warnCount) WARN, \(failCount) FAIL")

        return lines.joined(separator: "\n")
    }
}

// MARK: - Doctor Implementation

/// Checks system requirements and environment for AgentPanel.
public struct Doctor {
    /// VS Code bundle identifier.
    private static let vscodeBundleId = "com.microsoft.VSCode"
    /// Chrome bundle identifier.
    private static let chromeBundleId = "com.google.Chrome"

    private let runningApplicationChecker: RunningApplicationChecking
    private let hotkeyStatusProvider: HotkeyStatusProviding?
    private let dateProvider: DateProviding
    private let aerospace: ApAeroSpace
    private let appDiscovery: AppDiscovering
    private let executableResolver: ExecutableResolver
    private let dataStore: DataPaths

    /// Creates a Doctor instance.
    /// - Parameters:
    ///   - runningApplicationChecker: Running application checker.
    ///   - hotkeyStatusProvider: Optional hotkey status provider.
    ///   - dateProvider: Date provider for timestamps.
    ///   - aerospace: AeroSpace wrapper for checks.
    ///   - appDiscovery: App discovery for checking installed apps.
    ///   - executableResolver: Resolver for checking CLI tools.
    ///   - dataStore: Data store for path checks.
    public init(
        runningApplicationChecker: RunningApplicationChecking,
        hotkeyStatusProvider: HotkeyStatusProviding? = nil,
        dateProvider: DateProviding = SystemDateProvider(),
        aerospace: ApAeroSpace = ApAeroSpace(),
        appDiscovery: AppDiscovering = LaunchServicesAppDiscovery(),
        executableResolver: ExecutableResolver = ExecutableResolver(),
        dataStore: DataPaths = .default()
    ) {
        self.runningApplicationChecker = runningApplicationChecker
        self.hotkeyStatusProvider = hotkeyStatusProvider
        self.dateProvider = dateProvider
        self.aerospace = aerospace
        self.appDiscovery = appDiscovery
        self.executableResolver = executableResolver
        self.dataStore = dataStore
    }

    /// Builds a UTC ISO-8601 timestamp string with fractional seconds.
    /// - Returns: Timestamp string in UTC timezone.
    private func makeUTCTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: dateProvider.now())
    }

    /// Runs all Doctor checks and returns a report.
    public func run() -> DoctorReport {
        var findings: [DoctorFinding] = []

        // Check Homebrew
        if executableResolver.resolve("brew") != nil {
            findings.append(DoctorFinding(
                severity: .pass,
                title: "Homebrew installed"
            ))
        } else {
            findings.append(DoctorFinding(
                severity: .fail,
                title: "Homebrew not found",
                fix: "Install Homebrew from https://brew.sh"
            ))
        }

        // Check AeroSpace app
        var aerospaceAppLabel = "NOT FOUND"
        if aerospace.isAppInstalled() {
            aerospaceAppLabel = aerospace.appPath ?? "FOUND"
            findings.append(DoctorFinding(
                severity: .pass,
                title: "AeroSpace.app installed",
                detail: aerospace.appPath
            ))
        } else {
            findings.append(DoctorFinding(
                severity: .fail,
                title: "AeroSpace.app not found",
                fix: "Install AeroSpace via Homebrew: brew install --cask nikitabobko/tap/aerospace"
            ))
        }

        // Check AeroSpace CLI
        var aerospaceCliLabel = "NOT FOUND"
        if aerospace.isCliAvailable() {
            aerospaceCliLabel = "AVAILABLE"
            findings.append(DoctorFinding(
                severity: .pass,
                title: "aerospace CLI available"
            ))

            // Check AeroSpace compatibility
            switch aerospace.checkCompatibility() {
            case .success:
                findings.append(DoctorFinding(
                    severity: .pass,
                    title: "aerospace CLI compatibility verified"
                ))
            case .failure(let error):
                findings.append(DoctorFinding(
                    severity: .fail,
                    title: "aerospace CLI compatibility issues",
                    detail: error.message
                ))
            }
        } else {
            findings.append(DoctorFinding(
                severity: .fail,
                title: "aerospace CLI not available",
                fix: "Ensure AeroSpace is installed and the CLI is in your PATH."
            ))
        }

        // Check AeroSpace running
        let aerospaceRunning = runningApplicationChecker.isApplicationRunning(bundleIdentifier: "bobko.aerospace")
        if aerospaceRunning {
            findings.append(DoctorFinding(
                severity: .pass,
                title: "AeroSpace is running"
            ))
        } else {
            findings.append(DoctorFinding(
                severity: .warn,
                title: "AeroSpace is not running",
                fix: "Start AeroSpace from Applications or enable 'start-at-login' in ~/.aerospace.toml."
            ))
        }

        // Check AeroSpace config
        let configManager = AeroSpaceConfigManager()
        switch configManager.configStatus() {
        case .managedByAgentPanel:
            findings.append(DoctorFinding(
                severity: .pass,
                title: "AeroSpace config managed by AgentPanel"
            ))
        case .missing:
            findings.append(DoctorFinding(
                severity: .fail,
                title: "AeroSpace config file missing",
                detail: AeroSpaceConfigManager.configPath,
                fix: "Run AgentPanel setup to create a compatible AeroSpace config."
            ))
        case .externalConfig:
            findings.append(DoctorFinding(
                severity: .warn,
                title: "AeroSpace config not managed by AgentPanel",
                detail: "Config exists but was not created by AgentPanel.",
                fix: "AgentPanel may not function correctly. Consider allowing AgentPanel to manage the config."
            ))
        case .unknown:
            findings.append(DoctorFinding(
                severity: .warn,
                title: "Could not read AeroSpace config",
                fix: "Check file permissions on \(AeroSpaceConfigManager.configPath)"
            ))
        }

        // Check VS Code
        if let vscodeURL = appDiscovery.applicationURL(bundleIdentifier: Self.vscodeBundleId) {
            findings.append(DoctorFinding(
                severity: .pass,
                title: "VS Code installed",
                detail: vscodeURL.path
            ))
        } else {
            findings.append(DoctorFinding(
                severity: .warn,
                title: "VS Code not found",
                detail: "Required for IDE window management",
                fix: "Install: brew install --cask visual-studio-code (or configure a custom IDE in the future)"
            ))
        }

        // Check Chrome
        if let chromeURL = appDiscovery.applicationURL(bundleIdentifier: Self.chromeBundleId) {
            findings.append(DoctorFinding(
                severity: .pass,
                title: "Google Chrome installed",
                detail: chromeURL.path
            ))
        } else {
            findings.append(DoctorFinding(
                severity: .warn,
                title: "Google Chrome not found",
                detail: "Required for browser window management",
                fix: "Install: brew install --cask google-chrome (or configure a custom browser in the future)"
            ))
        }

        // Check required directories
        let logsDir = dataStore.logsDirectory
        var isLogsDir = ObjCBool(false)
        if FileManager.default.fileExists(atPath: logsDir.path, isDirectory: &isLogsDir), isLogsDir.boolValue {
            findings.append(DoctorFinding(
                severity: .pass,
                title: "Logs directory exists",
                detail: logsDir.path
            ))
        } else {
            // This is a PASS with note - directory will be created on first log write
            findings.append(DoctorFinding(
                severity: .pass,
                title: "Logs directory will be created on first use",
                detail: logsDir.path
            ))
        }

        // Check AgentPanel config
        switch ConfigLoader.loadDefault() {
        case .failure(let error):
            findings.append(DoctorFinding(
                severity: .fail,
                title: "Config file error",
                detail: error.message
            ))
        case .success(let result):
            if result.config != nil {
                findings.append(DoctorFinding(
                    severity: .pass,
                    title: "Config file parsed successfully"
                ))
            }
            for finding in result.findings {
                findings.append(DoctorFinding(
                    severity: finding.severity == .fail ? .fail : (finding.severity == .warn ? .warn : .pass),
                    title: finding.title,
                    detail: finding.detail,
                    fix: finding.fix
                ))
            }

            // Check agent-layer CLI if any project uses it
            let agentLayerProjects = result.projects.filter { $0.useAgentLayer }
            if !agentLayerProjects.isEmpty {
                if executableResolver.resolve("al") != nil {
                    findings.append(DoctorFinding(
                        severity: .pass,
                        title: "Agent layer CLI (al) installed"
                    ))
                } else {
                    let projectNames = agentLayerProjects.map { $0.id }.joined(separator: ", ")
                    findings.append(DoctorFinding(
                        severity: .fail,
                        title: "Agent layer CLI (al) not found",
                        detail: "Required by: \(projectNames)",
                        fix: "Install: brew install conn-castle/tap/agent-layer (or set useAgentLayer=false for these projects)"
                    ))
                }
            }

            // Check project paths exist and agent-layer if required
            for project in result.projects {
                let pathURL = URL(fileURLWithPath: project.path, isDirectory: true)
                var isDirectory = ObjCBool(false)
                let exists = FileManager.default.fileExists(atPath: pathURL.path, isDirectory: &isDirectory)
                if exists && isDirectory.boolValue {
                    findings.append(DoctorFinding(
                        severity: .pass,
                        title: "Project path exists: \(project.id)",
                        detail: project.path
                    ))

                    // Check agent-layer directory if useAgentLayer is true
                    if project.useAgentLayer {
                        let agentLayerPath = pathURL.appendingPathComponent(".agent-layer", isDirectory: true)
                        var isAgentLayerDir = ObjCBool(false)
                        let agentLayerExists = FileManager.default.fileExists(
                            atPath: agentLayerPath.path,
                            isDirectory: &isAgentLayerDir
                        )
                        if agentLayerExists && isAgentLayerDir.boolValue {
                            findings.append(DoctorFinding(
                                severity: .pass,
                                title: "Agent layer exists: \(project.id)",
                                detail: agentLayerPath.path
                            ))
                        } else {
                            findings.append(DoctorFinding(
                                severity: .warn,
                                title: "Agent layer missing: \(project.id)",
                                detail: "useAgentLayer=true but .agent-layer directory not found",
                                fix: "Create .agent-layer directory in \(project.path) or set useAgentLayer=false"
                            ))
                        }
                    }
                } else {
                    findings.append(DoctorFinding(
                        severity: .fail,
                        title: "Project path missing: \(project.id)",
                        detail: project.path,
                        fix: "Update project.path to an existing directory."
                    ))
                }
            }
        }

        // Check hotkey status if provider available
        if let provider = hotkeyStatusProvider {
            switch provider.hotkeyRegistrationStatus() {
            case .registered:
                findings.append(DoctorFinding(
                    severity: .pass,
                    title: "Hotkey registered (Cmd+Shift+Space)"
                ))
            case .failed(let osStatus):
                findings.append(DoctorFinding(
                    severity: .warn,
                    title: "Hotkey registration failed",
                    detail: "OSStatus: \(osStatus)",
                    fix: "Another application may have claimed Cmd+Shift+Space. Check System Settings > Keyboard > Keyboard Shortcuts."
                ))
            case .none:
                break
            }
        }

        // Check for critical failures that onboarding can fix
        let hasCriticalAeroSpaceFailure = !aerospace.isAppInstalled() || !aerospace.isCliAvailable()
        if hasCriticalAeroSpaceFailure {
            findings.append(DoctorFinding(
                severity: .fail,
                title: "Critical: AeroSpace setup incomplete",
                fix: "Launch AgentPanel.app to run onboarding, or install manually: brew install --cask nikitabobko/tap/aerospace"
            ))
        }

        let metadata = DoctorMetadata(
            timestamp: makeUTCTimestamp(),
            agentPanelVersion: AgentPanel.version,
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            aerospaceApp: aerospaceAppLabel,
            aerospaceCli: aerospaceCliLabel
        )

        let actions = DoctorActionAvailability(
            canInstallAeroSpace: !aerospace.isAppInstalled(),
            canStartAeroSpace: aerospace.isAppInstalled() && !aerospaceRunning,
            canReloadAeroSpaceConfig: aerospaceRunning
        )

        return DoctorReport(metadata: metadata, findings: findings, actions: actions)
    }

    /// Installs AeroSpace via Homebrew and returns an updated report.
    public func installAeroSpace() -> DoctorReport {
        _ = aerospace.installViaHomebrew()
        return run()
    }

    /// Starts AeroSpace and returns an updated report.
    public func startAeroSpace() -> DoctorReport {
        _ = aerospace.start()
        return run()
    }

    /// Reloads the AeroSpace config and returns an updated report.
    public func reloadAeroSpaceConfig() -> DoctorReport {
        _ = aerospace.reloadConfig()
        return run()
    }
}
