import Foundation

/// Runs Doctor checks for ProjectWorkspaces.
public struct Doctor {
    private let paths: ProjectWorkspacesPaths
    private let fileSystem: FileSystem
    private let appDiscovery: AppDiscovering
    private let hotkeyChecker: HotkeyChecking
    private let accessibilityChecker: AccessibilityChecking
    private let runningApplicationChecker: RunningApplicationChecking
    private let commandRunner: CommandRunning
    private let aerospaceBinaryResolver: AeroSpaceBinaryResolving
    private let configParser: ConfigParser
    private let environment: EnvironmentProviding
    private let dateProvider: DateProviding
    private let permissionsChecker: PermissionsChecker
    private let appDiscoveryChecker: AppDiscoveryChecker
    private let aeroSpaceChecker: AeroSpaceChecker

    /// Creates a Doctor runner with default dependencies.
    /// - Parameters:
    ///   - paths: File system paths for ProjectWorkspaces.
    ///   - fileSystem: File system accessor.
    ///   - appDiscovery: App discovery implementation.
    ///   - hotkeyChecker: Hotkey availability checker.
    ///   - accessibilityChecker: Accessibility permission checker.
    ///   - hotkeyStatusProvider: Optional provider for the current hotkey registration status.
    ///   - aerospaceBinaryResolver: Resolver for the AeroSpace CLI executable.
    ///   - commandRunner: Command runner used for CLI checks.
    ///   - aeroSpaceCommandRunner: Serialized runner for AeroSpace CLI commands.
    ///   - environment: Environment provider for XDG config resolution.
    ///   - dateProvider: Date provider for timestamps.
    public init(
        paths: ProjectWorkspacesPaths = .defaultPaths(),
        fileSystem: FileSystem = DefaultFileSystem(),
        appDiscovery: AppDiscovering = LaunchServicesAppDiscovery(),
        hotkeyChecker: HotkeyChecking = CarbonHotkeyChecker(),
        accessibilityChecker: AccessibilityChecking,
        runningApplicationChecker: RunningApplicationChecking,
        hotkeyStatusProvider: HotkeyRegistrationStatusProviding? = nil,
        commandRunner: CommandRunning = DefaultCommandRunner(),
        aerospaceBinaryResolver: AeroSpaceBinaryResolving? = nil,
        aeroSpaceCommandRunner: AeroSpaceCommandRunning = AeroSpaceCommandExecutor.shared,
        environment: EnvironmentProviding = ProcessEnvironment(),
        dateProvider: DateProviding = SystemDateProvider()
    ) {
        self.paths = paths
        self.fileSystem = fileSystem
        self.appDiscovery = appDiscovery
        self.hotkeyChecker = hotkeyChecker
        self.accessibilityChecker = accessibilityChecker
        self.runningApplicationChecker = runningApplicationChecker
        self.commandRunner = commandRunner
        if let aerospaceBinaryResolver {
            self.aerospaceBinaryResolver = aerospaceBinaryResolver
        } else {
            self.aerospaceBinaryResolver = DefaultAeroSpaceBinaryResolver(
                fileSystem: fileSystem,
                commandRunner: commandRunner
            )
        }
        self.configParser = ConfigParser()
        self.environment = environment
        self.dateProvider = dateProvider
        self.permissionsChecker = PermissionsChecker(
            accessibilityChecker: accessibilityChecker,
            hotkeyChecker: hotkeyChecker,
            runningApplicationChecker: runningApplicationChecker,
            hotkeyStatusProvider: hotkeyStatusProvider
        )
        self.appDiscoveryChecker = AppDiscoveryChecker(
            fileSystem: fileSystem,
            appDiscovery: appDiscovery
        )
        self.aeroSpaceChecker = AeroSpaceChecker(
            paths: paths,
            fileSystem: fileSystem,
            commandRunner: commandRunner,
            aerospaceBinaryResolver: self.aerospaceBinaryResolver,
            aeroSpaceCommandRunner: aeroSpaceCommandRunner,
            environment: environment,
            dateProvider: dateProvider
        )
    }

    /// Runs Doctor checks and returns a report.
    /// - Returns: A Doctor report with PASS/WARN/FAIL findings.
    public func run() -> DoctorReport {
        buildReport(prependingFindings: [])
    }

    /// Installs AeroSpace via Homebrew and refreshes the report.
    /// - Returns: An updated Doctor report.
    public func installAeroSpace() -> DoctorReport {
        var findings: [DoctorFinding] = []

        let configPaths = aeroSpaceChecker.resolveAeroSpaceConfigPaths()
        let configState = aeroSpaceChecker.resolveAeroSpaceConfigState(paths: configPaths)
        if case .missing = configState {
            if let failureFinding = aeroSpaceChecker.installSafeConfig(configPaths: configPaths) {
                findings.append(failureFinding)
                findings.append(
                    DoctorFinding(
                        severity: .warn,
                        title: "Skipped AeroSpace install because the safe config could not be created",
                        fix: "Resolve the safe config error and retry Install AeroSpace."
                    )
                )
                return buildReport(prependingFindings: findings)
            }

            findings.append(
                DoctorFinding(
                    severity: .pass,
                    title: "Installed safe AeroSpace config at: ~/.aerospace.toml"
                )
            )
        }

        let installFinding = aeroSpaceChecker.installAeroSpaceViaHomebrew()
        findings.append(installFinding)
        return buildReport(prependingFindings: findings)
    }

    /// Attempts to install the safe AeroSpace config when no config exists.
    /// - Returns: An updated Doctor report.
    public func installSafeAeroSpaceConfig() -> DoctorReport {
        let configPaths = aeroSpaceChecker.resolveAeroSpaceConfigPaths()
        let configState = aeroSpaceChecker.resolveAeroSpaceConfigState(paths: configPaths)
        guard case .missing = configState else {
            return run()
        }

        if let failureFinding = aeroSpaceChecker.installSafeConfig(configPaths: configPaths) {
            return buildReport(prependingFindings: [failureFinding])
        }

        return buildReport(prependingFindings: [
            DoctorFinding(
                severity: .pass,
                title: "Installed safe AeroSpace config at: ~/.aerospace.toml",
                bodyLines: ["Next: Start AeroSpace"]
            )
        ])
    }

    /// Runs Doctor with the intent of starting AeroSpace.
    /// - Returns: An updated Doctor report.
    public func startAeroSpace() -> DoctorReport {
        run()
    }

    /// Reloads the AeroSpace config and returns an updated report.
    /// - Returns: An updated Doctor report.
    public func reloadAeroSpaceConfig() -> DoctorReport {
        let actionFinding = aeroSpaceChecker.runAeroSpaceCommandAction(
            arguments: ["reload-config", "--no-gui"],
            successTitle: "Reloaded AeroSpace config",
            failureTitle: "AeroSpace config reload failed",
            failureFix: "Open AeroSpace to review config errors.",
            failureSeverity: .warn
        )
        return buildReport(prependingFindings: actionFinding.map { [$0] } ?? [])
    }

    /// Disables AeroSpace window management as an emergency action.
    /// - Returns: An updated Doctor report.
    public func disableAeroSpace() -> DoctorReport {
        let actionFinding = aeroSpaceChecker.runAeroSpaceCommandAction(
            arguments: ["enable", "off"],
            successTitle: "Disabled AeroSpace window management (all hidden workspaces made visible).",
            failureTitle: "Unable to disable AeroSpace window management",
            failureFix: "Ensure AeroSpace is running and re-run Doctor.",
            failureSeverity: .fail
        )
        return buildReport(prependingFindings: actionFinding.map { [$0] } ?? [])
    }

    /// Uninstalls the safe AeroSpace config when it is ProjectWorkspaces-managed.
    /// - Returns: An updated Doctor report.
    public func uninstallSafeAeroSpaceConfig() -> DoctorReport {
        let configPaths = aeroSpaceChecker.resolveAeroSpaceConfigPaths()
        let findings = aeroSpaceChecker.uninstallSafeConfig(configPaths: configPaths)
        return buildReport(prependingFindings: findings)
    }

    private func buildReport(prependingFindings: [DoctorFinding]) -> DoctorReport {
        let homebrewURL = aeroSpaceChecker.resolveHomebrew()
        let appExists = aeroSpaceChecker.appExists()
        let cliResolution = aeroSpaceChecker.resolveCLI()
        let cliURL = try? cliResolution.get()

        let configPaths = aeroSpaceChecker.resolveAeroSpaceConfigPaths()
        let configState = aeroSpaceChecker.resolveAeroSpaceConfigState(paths: configPaths)
        let safeConfigInstalled = aeroSpaceChecker.isSafeConfigInstalled(at: configPaths.userConfigURL)

        let metadata = DoctorMetadata(
            timestamp: isoTimestamp(for: dateProvider.now()),
            projectWorkspacesVersion: ProjectWorkspacesCore.version,
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            aerospaceApp: appExists ? AeroSpaceChecker.aerospaceAppPath : "NOT FOUND",
            aerospaceCli: cliURL?.path ?? "NOT FOUND"
        )

        var findings: [DoctorFinding] = []
        findings.append(contentsOf: prependingFindings)
        findings.append(aeroSpaceChecker.homebrewFinding(homebrewURL: homebrewURL))
        findings.append(contentsOf: aeroSpaceChecker.aerospaceAppFinding(appExists: appExists))
        findings.append(contentsOf: aeroSpaceChecker.aerospaceCliFinding(resolution: cliResolution))
        findings.append(contentsOf: aeroSpaceChecker.aerospaceConfigFinding(state: configState, paths: configPaths))

        let canInstallSafe: Bool
        let canStart: Bool
        let canReload: Bool
        let isAmbiguous: Bool
        switch configState {
        case .missing:
            canInstallSafe = true
            canStart = false
            canReload = false
            isAmbiguous = false
        case .ambiguous:
            canInstallSafe = false
            canStart = false
            canReload = false
            isAmbiguous = true
        case .existing:
            canInstallSafe = false
            canStart = appExists && cliURL != nil
            canReload = cliURL != nil
            isAmbiguous = false
        }

        let canInstallAeroSpace = homebrewURL != nil && (!appExists || cliURL == nil)
        let actionAvailability = DoctorActionAvailability(
            canInstallAeroSpace: canInstallAeroSpace,
            canInstallSafeAeroSpaceConfig: canInstallSafe,
            canStartAeroSpace: canStart,
            canReloadAeroSpaceConfig: canReload,
            canDisableAeroSpace: cliURL != nil,
            canUninstallSafeAeroSpaceConfig: safeConfigInstalled && !isAmbiguous
        )

        if case .existing = configState, let cliURL {
            let serverStatus = aeroSpaceChecker.checkAeroSpaceServer(executable: cliURL, appExists: appExists)
            findings.append(contentsOf: serverStatus.findings)

            if serverStatus.isConnected {
                findings.append(contentsOf: aeroSpaceChecker.checkAeroSpaceCompatibility(executable: cliURL))
                findings.append(contentsOf: aeroSpaceChecker.checkAerospaceWorkspaceSwitch(executable: cliURL))
            }
        }

        let configURL = paths.configFile
        var configOutcome: ConfigParseOutcome?

        if fileSystem.fileExists(at: configURL) {
            findings.append(
                DoctorFinding(
                    severity: .pass,
                    title: "Config file found",
                    detail: configURL.path
                )
            )

            do {
                let data = try fileSystem.readFile(at: configURL)
                if let toml = String(data: data, encoding: .utf8) {
                    let outcome = configParser.parse(toml: toml)
                    configOutcome = outcome
                    findings.append(contentsOf: outcome.findings)
                    if outcome.config != nil {
                        findings.append(
                            DoctorFinding(
                                severity: .pass,
                                title: "Config parsed and validated"
                            )
                        )
                    }
                } else {
                    findings.append(
                        DoctorFinding(
                            severity: .fail,
                            title: "Config file is not valid UTF-8",
                            fix: "Ensure config.toml is saved as UTF-8 text."
                        )
                    )
                    configOutcome = nil
                }
            } catch {
                findings.append(
                    DoctorFinding(
                        severity: .fail,
                        title: "Config file could not be read",
                        detail: String(describing: error),
                        fix: "Ensure config.toml is readable and retry."
                    )
                )
            }
        } else {
            findings.append(
                DoctorFinding(
                    severity: .fail,
                    title: "Config file missing",
                    detail: configURL.path,
                    fix: "Create config.toml at the expected path (see README for the schema)."
                )
            )
        }

        if let outcome = configOutcome {
            findings.append(contentsOf: checkProjectPaths(projects: outcome.projects))
            findings.append(contentsOf: appDiscoveryChecker.checkApps(outcome: outcome))
        } else {
            findings.append(contentsOf: appDiscoveryChecker.checkApps(outcome: nil))
        }

        findings.append(permissionsChecker.accessibilityFinding())
        findings.append(permissionsChecker.hotkeyFinding())

        return DoctorReport(metadata: metadata, findings: findings, actions: actionAvailability)
    }

    private func isoTimestamp(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// Checks that configured project paths exist on disk.
    /// - Parameter projects: Parsed projects to validate.
    /// - Returns: Findings for missing project paths.
    private func checkProjectPaths(projects: [ProjectConfig]) -> [DoctorFinding] {
        guard !projects.isEmpty else {
            return []
        }

        var missingPaths: [DoctorFinding] = []

        for project in projects {
            let pathURL = URL(fileURLWithPath: project.path, isDirectory: true)
            if !fileSystem.directoryExists(at: pathURL) {
                missingPaths.append(
                    DoctorFinding(
                        severity: .fail,
                        title: "Project path is missing for \(project.id)",
                        detail: project.path,
                        fix: "Update project.path to an existing directory."
                    )
                )
            }
        }

        if missingPaths.isEmpty {
            return [
                DoctorFinding(
                    severity: .pass,
                    title: "All project paths exist",
                    detail: "Checked \(projects.count) project(s)."
                )
            ]
        }

        return missingPaths
    }

}
