import Foundation

/// Runs Doctor checks for ProjectWorkspaces.
public struct Doctor {
    private static let aerospaceAppPath = "/Applications/AeroSpace.app"
    private static let safeConfigMarker = "# Managed by ProjectWorkspaces."
    private static let safeConfigContents = """
    # Managed by ProjectWorkspaces.
    # Purpose: prevent AeroSpace default tiling from affecting all windows.
    # This config intentionally defines no AeroSpace keybindings.
    config-version = 2

    [mode.main.binding]
    # Intentionally empty. ProjectWorkspaces provides the global UX.

    [[on-window-detected]]
    check-further-callbacks = true
    run = 'layout floating'
    """
    private static let aerospaceServerRetryCount = 20
    private static let aerospaceServerRetryDelaySeconds: TimeInterval = 0.25

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

    /// Creates a Doctor runner with default dependencies.
    /// - Parameters:
    ///   - paths: File system paths for ProjectWorkspaces.
    ///   - fileSystem: File system accessor.
    ///   - appDiscovery: App discovery implementation.
    ///   - hotkeyChecker: Hotkey availability checker.
    ///   - accessibilityChecker: Accessibility permission checker.
    ///   - aerospaceBinaryResolver: Resolver for the AeroSpace CLI executable.
    ///   - commandRunner: Command runner used for CLI checks.
    ///   - environment: Environment provider for XDG config resolution.
    ///   - dateProvider: Date provider for timestamps.
    public init(
        paths: ProjectWorkspacesPaths = .defaultPaths(),
        fileSystem: FileSystem = DefaultFileSystem(),
        appDiscovery: AppDiscovering = LaunchServicesAppDiscovery(),
        hotkeyChecker: HotkeyChecking = CarbonHotkeyChecker(),
        accessibilityChecker: AccessibilityChecking = DefaultAccessibilityChecker(),
        runningApplicationChecker: RunningApplicationChecking = DefaultRunningApplicationChecker(),
        commandRunner: CommandRunning = DefaultCommandRunner(),
        aerospaceBinaryResolver: AeroSpaceBinaryResolving? = nil,
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
    }

    /// Runs Doctor checks and returns a report.
    /// - Returns: A Doctor report with PASS/WARN/FAIL findings.
    public func run() -> DoctorReport {
        buildReport(prependingFindings: [])
    }

    /// Attempts to install the safe AeroSpace config when no config exists.
    /// - Returns: An updated Doctor report.
    public func installSafeAeroSpaceConfig() -> DoctorReport {
        let configPaths = resolveAeroSpaceConfigPaths()
        let configState = resolveAeroSpaceConfigState(paths: configPaths)
        guard case .missing = configState else {
            return run()
        }

        let tempURL = URL(fileURLWithPath: configPaths.userConfigURL.path + ".tmp.\(ProcessInfo.processInfo.processIdentifier)")
        let data = Data(Self.safeConfigContents.utf8)
        do {
            try fileSystem.writeFile(at: tempURL, data: data)
            try fileSystem.syncFile(at: tempURL)
            try fileSystem.moveItem(at: tempURL, to: configPaths.userConfigURL)
        } catch {
            return buildReport(prependingFindings: [
                DoctorFinding(
                    severity: .fail,
                    title: "Failed to install safe AeroSpace config",
                    detail: String(describing: error),
                    fix: "Ensure your home directory is writable and retry."
                )
            ])
        }

        guard isSafeConfigInstalled(at: configPaths.userConfigURL) else {
            return buildReport(prependingFindings: [
                DoctorFinding(
                    severity: .fail,
                    title: "Safe AeroSpace config install verification failed",
                    fix: "Ensure ~/.aerospace.toml starts with '# Managed by ProjectWorkspaces.'"
                )
            ])
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
        let actionFinding = runAeroSpaceCommandAction(
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
        let actionFinding = runAeroSpaceCommandAction(
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
        let configPaths = resolveAeroSpaceConfigPaths()
        guard isSafeConfigInstalled(at: configPaths.userConfigURL) else {
            return buildReport(prependingFindings: [
                DoctorFinding(
                    severity: .pass,
                    title: "",
                    bodyLines: [
                        "INFO  AeroSpace config appears user-managed; ProjectWorkspaces will not modify it."
                    ]
                )
            ])
        }

        let backupURL = URL(
            fileURLWithPath: configPaths.userConfigURL.path
                + ".projectworkspaces.bak.\(backupTimestamp())"
        )

        do {
            try fileSystem.moveItem(at: configPaths.userConfigURL, to: backupURL)
        } catch {
            return buildReport(prependingFindings: [
                DoctorFinding(
                    severity: .fail,
                    title: "Failed to back up safe AeroSpace config",
                    detail: String(describing: error),
                    fix: "Ensure ~/.aerospace.toml is writable and retry."
                )
            ])
        }

        var findings: [DoctorFinding] = [
            DoctorFinding(
                severity: .pass,
                title: "Backed up ~/.aerospace.toml to: \(backupURL.path)",
                bodyLines: [
                    "INFO  AeroSpace will now use default config unless you provide your own config."
                ]
            )
        ]

        if let reloadFinding = runAeroSpaceCommandAction(
            arguments: ["reload-config", "--no-gui"],
            successTitle: nil,
            failureTitle: "AeroSpace config reload failed",
            failureFix: "Open AeroSpace to review config errors.",
            failureSeverity: .warn
        ) {
            findings.append(reloadFinding)
        }

        return buildReport(prependingFindings: findings)
    }

    private enum AeroSpaceConfigState {
        case ambiguous
        case existing(path: URL)
        case missing
    }

    private struct AeroSpaceConfigPaths {
        let userConfigURL: URL
        let userDisplayPath: String
        let xdgConfigURL: URL
        let xdgDisplayPath: String
    }

    private struct AeroSpaceServerStatus {
        let isConnected: Bool
        let configPath: String?
        let findings: [DoctorFinding]
    }

    private enum DoctorCheckResult<Success> {
        case success(Success)
        case failure(DoctorFinding)
    }

    private enum CommandOutcome {
        case success(CommandResult)
        case failure(String)
    }

    private func buildReport(prependingFindings: [DoctorFinding]) -> DoctorReport {
        let appURL = URL(fileURLWithPath: Self.aerospaceAppPath, isDirectory: true)
        let appExists = fileSystem.directoryExists(at: appURL)
        let cliResolution = aerospaceBinaryResolver.resolve()
        let cliURL = try? cliResolution.get()

        let configPaths = resolveAeroSpaceConfigPaths()
        let configState = resolveAeroSpaceConfigState(paths: configPaths)
        let safeConfigInstalled = isSafeConfigInstalled(at: configPaths.userConfigURL)

        let metadata = DoctorMetadata(
            timestamp: isoTimestamp(for: dateProvider.now()),
            projectWorkspacesVersion: ProjectWorkspacesCore.version,
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            aerospaceApp: appExists ? appURL.path : "NOT FOUND",
            aerospaceCli: cliURL?.path ?? "NOT FOUND"
        )

        var findings: [DoctorFinding] = []
        findings.append(contentsOf: prependingFindings)
        findings.append(contentsOf: aerospaceAppFinding(appExists: appExists))
        findings.append(contentsOf: aerospaceCliFinding(resolution: cliResolution))
        findings.append(contentsOf: aerospaceConfigFinding(state: configState, paths: configPaths))

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

        let actionAvailability = DoctorActionAvailability(
            canInstallSafeAeroSpaceConfig: canInstallSafe,
            canStartAeroSpace: canStart,
            canReloadAeroSpaceConfig: canReload,
            canDisableAeroSpace: cliURL != nil,
            canUninstallSafeAeroSpaceConfig: safeConfigInstalled && !isAmbiguous
        )

        if case .existing = configState, let cliURL {
            let serverStatus = checkAeroSpaceServer(executable: cliURL, appExists: appExists)
            findings.append(contentsOf: serverStatus.findings)

            if serverStatus.isConnected {
                findings.append(contentsOf: checkAerospaceWorkspaceSwitch(executable: cliURL))
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
            findings.append(contentsOf: checkApps(outcome: outcome))
        } else {
            findings.append(contentsOf: checkApps(outcome: nil))
        }

        findings.append(accessibilityFinding())
        findings.append(hotkeyFinding())

        return DoctorReport(metadata: metadata, findings: findings, actions: actionAvailability)
    }

    private func aerospaceAppFinding(appExists: Bool) -> [DoctorFinding] {
        if appExists {
            return [
                DoctorFinding(
                    severity: .pass,
                    title: "AeroSpace.app found at: \(Self.aerospaceAppPath)"
                )
            ]
        }

        return [
            DoctorFinding(
                severity: .fail,
                title: "AeroSpace.app not found in /Applications",
                bodyLines: [
                    "Fix: Install AeroSpace (recommended: Homebrew cask). Then re-run Doctor."
                ]
            )
        ]
    }

    private func aerospaceCliFinding(
        resolution: Result<URL, AeroSpaceBinaryResolutionError>
    ) -> [DoctorFinding] {
        switch resolution {
        case .success(let executable):
            return [
                DoctorFinding(
                    severity: .pass,
                    title: "aerospace CLI found at: \(executable.path)"
                )
            ]
        case .failure:
            return [
                DoctorFinding(
                    severity: .fail,
                    title: "aerospace CLI not found",
                    bodyLines: [
                        "Fix: Ensure AeroSpace CLI is installed and available. Re-run Doctor."
                    ]
                )
            ]
        }
    }

    private func aerospaceConfigFinding(
        state: AeroSpaceConfigState,
        paths: AeroSpaceConfigPaths
    ) -> [DoctorFinding] {
        switch state {
        case .ambiguous:
            return [
                DoctorFinding(
                    severity: .fail,
                    title: "AeroSpace config is ambiguous (found in more than one location).",
                    bodyLines: [
                        "Detected:",
                        "- \(paths.userDisplayPath)",
                        "- \(paths.xdgDisplayPath)",
                        "Fix: Remove or rename one of the files, then re-run Doctor. ProjectWorkspaces will not pick one automatically."
                    ]
                )
            ]
        case .existing(let location):
            return [
                DoctorFinding(
                    severity: .pass,
                    title: "Existing AeroSpace config detected. ProjectWorkspaces will not modify it.",
                    bodyLines: [
                        "Config location: \(location.path)",
                        "Note: Your AeroSpace config may tile/resize windows. If you don't want that, update your AeroSpace config yourself. ProjectWorkspaces does not change it automatically."
                    ]
                )
            ]
        case .missing:
            return [
                DoctorFinding(
                    severity: .fail,
                    title: "No AeroSpace config found. Starting AeroSpace will load the default tiling config and may resize/tile all windows.",
                    bodyLines: [
                        "Recommended fix: Install the ProjectWorkspaces-safe config which floats all windows by default."
                    ]
                )
            ]
        }
    }

    private func checkAeroSpaceServer(executable: URL, appExists: Bool) -> AeroSpaceServerStatus {
        var findings: [DoctorFinding] = []

        if let configPath = queryAeroSpaceConfigPath(executable: executable) {
            findings.append(
                DoctorFinding(
                    severity: .pass,
                    title: "AeroSpace server is running"
                )
            )
            findings.append(
                DoctorFinding(
                    severity: .pass,
                    title: "AeroSpace loaded config: \(configPath)"
                )
            )
            return AeroSpaceServerStatus(isConnected: true, configPath: configPath, findings: findings)
        }

        let listResult = runCommand(executable: executable, arguments: ["list-workspaces", "--focused"])
        switch listResult {
        case .success:
            break
        case .failure:
            if appExists {
                _ = runCommand(
                    executable: URL(fileURLWithPath: "/usr/bin/open", isDirectory: false),
                    arguments: ["-a", Self.aerospaceAppPath]
                )

                let configPath = retryAeroSpaceConfigPath(executable: executable)
                if let configPath {
                    findings.append(
                        DoctorFinding(
                            severity: .pass,
                            title: "AeroSpace server is running"
                        )
                    )
                    findings.append(
                        DoctorFinding(
                            severity: .pass,
                            title: "AeroSpace loaded config: \(configPath)"
                        )
                    )
                    return AeroSpaceServerStatus(isConnected: true, configPath: configPath, findings: findings)
                }
            }

            findings.append(
                DoctorFinding(
                    severity: .fail,
                    title: "Unable to connect to AeroSpace server",
                    bodyLines: [
                        "Fix: Launch AeroSpace manually and ensure required permissions are granted. Re-run Doctor."
                    ]
                )
            )
            return AeroSpaceServerStatus(isConnected: false, configPath: nil, findings: findings)
        }

        if let configPath = queryAeroSpaceConfigPath(executable: executable) {
            findings.append(
                DoctorFinding(
                    severity: .pass,
                    title: "AeroSpace server is running"
                )
            )
            findings.append(
                DoctorFinding(
                    severity: .pass,
                    title: "AeroSpace loaded config: \(configPath)"
                )
            )
            return AeroSpaceServerStatus(isConnected: true, configPath: configPath, findings: findings)
        }

        findings.append(
            DoctorFinding(
                severity: .fail,
                title: "Unable to connect to AeroSpace server",
                bodyLines: [
                    "Fix: Launch AeroSpace manually and ensure required permissions are granted. Re-run Doctor."
                ]
            )
        )
        return AeroSpaceServerStatus(isConnected: false, configPath: nil, findings: findings)
    }

    private func queryAeroSpaceConfigPath(executable: URL) -> String? {
        let result = runCommand(executable: executable, arguments: ["config", "--config-path"])
        switch result {
        case .success(let output):
            let path = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? nil : path
        case .failure:
            return nil
        }
    }

    private func retryAeroSpaceConfigPath(executable: URL) -> String? {
        for _ in 0..<Self.aerospaceServerRetryCount {
            if let path = queryAeroSpaceConfigPath(executable: executable) {
                return path
            }
            Thread.sleep(forTimeInterval: Self.aerospaceServerRetryDelaySeconds)
        }
        return nil
    }

    private func checkAerospaceWorkspaceSwitch(executable: URL) -> [DoctorFinding] {
        var findings: [DoctorFinding] = []
        let previousWorkspaceResult = focusedWorkspace(
            executable: executable,
            context: "before switching to pw-inbox"
        )

        switch previousWorkspaceResult {
        case .failure:
            findings.append(
                DoctorFinding(
                    severity: .fail,
                    title: "AeroSpace workspace switching failed. ProjectWorkspaces cannot operate safely."
                )
            )
            return findings
        case .success(let previousWorkspace):
            let infoLine = "INFO  Current workspace before test: \(previousWorkspace)"

            let switchResult = runCommand(
                executable: executable,
                arguments: ["workspace", "pw-inbox"]
            )

            switch switchResult {
            case .failure:
                findings.append(
                    DoctorFinding(
                        severity: .fail,
                        title: "AeroSpace workspace switching failed. ProjectWorkspaces cannot operate safely.",
                        bodyLines: [infoLine]
                    )
                )
                return findings
            case .success:
                break
            }

            let focusedAfterSwitch = focusedWorkspace(
                executable: executable,
                context: "after switching to pw-inbox"
            )

            switch focusedAfterSwitch {
            case .failure:
                findings.append(
                    DoctorFinding(
                        severity: .fail,
                        title: "AeroSpace workspace switching failed. ProjectWorkspaces cannot operate safely.",
                        bodyLines: [infoLine]
                    )
                )
                return findings
            case .success(let currentWorkspace):
                if currentWorkspace != "pw-inbox" {
                    findings.append(
                        DoctorFinding(
                            severity: .fail,
                            title: "AeroSpace workspace switching failed. ProjectWorkspaces cannot operate safely.",
                            bodyLines: [infoLine]
                        )
                    )
                    return findings
                }
            }

            findings.append(
                DoctorFinding(
                    severity: .pass,
                    title: "AeroSpace workspace switch succeeded (pw-inbox)",
                    bodyLines: [infoLine]
                )
            )

            if previousWorkspace != "pw-inbox" {
                let restoreResult = runCommand(
                    executable: executable,
                    arguments: ["workspace", previousWorkspace]
                )

                switch restoreResult {
                case .failure:
                    findings.append(
                        DoctorFinding(
                            severity: .warn,
                            title: "Could not restore previous workspace automatically.",
                            bodyLines: ["Fix: Run: aerospace workspace \(previousWorkspace)"]
                        )
                    )
                    return findings
                case .success:
                    break
                }

                let focusedAfterRestore = focusedWorkspace(
                    executable: executable,
                    context: "after restoring previous workspace"
                )

                switch focusedAfterRestore {
                case .failure:
                    findings.append(
                        DoctorFinding(
                            severity: .warn,
                            title: "Could not restore previous workspace automatically.",
                            bodyLines: ["Fix: Run: aerospace workspace \(previousWorkspace)"]
                        )
                    )
                case .success(let restoredWorkspace):
                    if restoredWorkspace != previousWorkspace {
                        findings.append(
                            DoctorFinding(
                                severity: .warn,
                                title: "Could not restore previous workspace automatically.",
                                bodyLines: ["Fix: Run: aerospace workspace \(previousWorkspace)"]
                            )
                        )
                    } else {
                        findings.append(
                            DoctorFinding(
                                severity: .pass,
                                title: "Restored previous workspace: \(previousWorkspace)"
                            )
                        )
                    }
                }
            }
        }

        return findings
    }

    /// Returns the focused AeroSpace workspace name.
    /// - Parameters:
    ///   - executable: Resolved AeroSpace executable URL.
    ///   - context: Description of when the lookup is performed.
    /// - Returns: Focused workspace name or a failure finding.
    private func focusedWorkspace(executable: URL, context: String) -> DoctorCheckResult<String> {
        let arguments = ["list-workspaces", "--focused"]
        let commandLabel = "aerospace \(arguments.joined(separator: " "))"
        let result = runCommand(executable: executable, arguments: arguments)

        switch result {
        case .failure(let detail):
            return .failure(
                DoctorFinding(
                    severity: .fail,
                    title: "AeroSpace focused workspace lookup failed",
                    detail: "Context: \(context). Command: \(commandLabel). \(detail)",
                    fix: "Ensure AeroSpace is running, then try `aerospace list-workspaces --focused`."
                )
            )
        case .success(let output):
            let workspace = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if workspace.isEmpty {
                return .failure(
                    DoctorFinding(
                        severity: .fail,
                        title: "AeroSpace focused workspace output was empty",
                        detail: "Context: \(context). Command: \(commandLabel).",
                        fix: "Ensure AeroSpace is running, then try `aerospace list-workspaces --focused`."
                    )
                )
            }
            return .success(workspace)
        }
    }

    /// Runs a command and returns the result or a formatted failure detail.
    /// - Parameters:
    ///   - executable: Executable file URL.
    ///   - arguments: Arguments to pass to the executable.
    /// - Returns: Command result or a failure detail string.
    private func runCommand(executable: URL, arguments: [String]) -> CommandOutcome {
        do {
            let result = try commandRunner.run(command: executable, arguments: arguments, environment: nil)
            if result.exitCode == 0 {
                return .success(result)
            }
            return .failure(
                commandFailureDetail(
                    exitCode: result.exitCode,
                    stdout: result.stdout,
                    stderr: result.stderr,
                    prefix: "Command failed"
                )
            )
        } catch {
            return .failure("Command failed to launch: \(error)")
        }
    }

    /// Formats command failure details from stdout/stderr and exit status.
    /// - Parameters:
    ///   - exitCode: Process exit status.
    ///   - stdout: Captured standard output.
    ///   - stderr: Captured standard error.
    ///   - prefix: Prefix string to lead the detail text.
    /// - Returns: Formatted failure detail string.
    private func commandFailureDetail(
        exitCode: Int32,
        stdout: String,
        stderr: String,
        prefix: String
    ) -> String {
        var components: [String] = ["\(prefix). Exit code: \(exitCode)"]
        let trimmedStdout = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedStderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedStdout.isEmpty {
            components.append("Stdout: \(trimmedStdout)")
        }
        if !trimmedStderr.isEmpty {
            components.append("Stderr: \(trimmedStderr)")
        }
        return components.joined(separator: " | ")
    }

    /// Runs an AeroSpace CLI action and returns a single finding.
    /// - Parameters:
    ///   - arguments: CLI arguments to pass to aerospace.
    ///   - successTitle: Title to use on success (omit to skip success finding).
    ///   - failureTitle: Title to use on failure.
    ///   - failureFix: Fix line to use on failure.
    /// - Returns: A finding describing the action result.
    private func runAeroSpaceCommandAction(
        arguments: [String],
        successTitle: String?,
        failureTitle: String,
        failureFix: String,
        failureSeverity: DoctorSeverity
    ) -> DoctorFinding? {
        switch aerospaceBinaryResolver.resolve() {
        case .failure:
            return DoctorFinding(
                severity: failureSeverity,
                title: "aerospace CLI not found",
                bodyLines: [
                    "Fix: Ensure AeroSpace CLI is installed and available. Re-run Doctor."
                ]
            )
        case .success(let executable):
            let result = runCommand(executable: executable, arguments: arguments)
            switch result {
            case .success:
                guard let successTitle else {
                    return nil
                }
                return DoctorFinding(severity: .pass, title: successTitle)
            case .failure:
                return DoctorFinding(
                    severity: failureSeverity,
                    title: failureTitle,
                    bodyLines: ["Fix: \(failureFix)"]
                )
            }
        }
    }

    private func resolveAeroSpaceConfigPaths() -> AeroSpaceConfigPaths {
        let userConfigURL = paths.homeDirectory.appendingPathComponent(".aerospace.toml", isDirectory: false)
        let userDisplayPath = "~/.aerospace.toml"

        let xdgHome = resolvedXdgConfigHome()
        let xdgConfigURL = xdgHome
            .appendingPathComponent("aerospace", isDirectory: true)
            .appendingPathComponent("aerospace.toml", isDirectory: false)
        let xdgDisplayPath = xdgConfigURL.path

        return AeroSpaceConfigPaths(
            userConfigURL: userConfigURL,
            userDisplayPath: userDisplayPath,
            xdgConfigURL: xdgConfigURL,
            xdgDisplayPath: xdgDisplayPath
        )
    }

    private func resolvedXdgConfigHome() -> URL {
        if let raw = environment.value(forKey: "XDG_CONFIG_HOME")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            let expanded = (raw as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }

        return paths.homeDirectory.appendingPathComponent(".config", isDirectory: true)
    }

    private func resolveAeroSpaceConfigState(paths: AeroSpaceConfigPaths) -> AeroSpaceConfigState {
        let userExists = fileSystem.fileExists(at: paths.userConfigURL)
        let xdgExists = fileSystem.fileExists(at: paths.xdgConfigURL)

        if userExists && xdgExists {
            return .ambiguous
        }

        if userExists {
            return .existing(path: paths.userConfigURL)
        }

        if xdgExists {
            return .existing(path: paths.xdgConfigURL)
        }

        return .missing
    }

    private func isSafeConfigInstalled(at url: URL) -> Bool {
        guard fileSystem.fileExists(at: url) else {
            return false
        }

        guard let contents = try? fileSystem.readFile(at: url),
              let text = String(data: contents, encoding: .utf8) else {
            return false
        }

        let lines = text.split(whereSeparator: { $0.isNewline })
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }
            return trimmed == Self.safeConfigMarker
        }

        return false
    }

    private func isoTimestamp(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: dateProvider.now())
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

    /// Runs app discovery checks based on the parsed config outcome.
    /// - Parameter outcome: Parsed config outcome or nil when unavailable.
    /// - Returns: Findings for required app discovery.
    private func checkApps(outcome: ConfigParseOutcome?) -> [DoctorFinding] {
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

    /// Builds the accessibility permission finding.
    /// - Returns: Finding for accessibility permission status.
    private func accessibilityFinding() -> DoctorFinding {
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
    private func hotkeyFinding() -> DoctorFinding {
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
