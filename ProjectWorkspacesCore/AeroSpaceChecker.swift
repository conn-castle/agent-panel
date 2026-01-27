import Foundation

/// Configuration state for AeroSpace.
enum AeroSpaceConfigState {
    case ambiguous
    case existing(path: URL)
    case missing
}

/// Resolved AeroSpace config paths.
struct AeroSpaceConfigPaths {
    let userConfigURL: URL
    let userDisplayPath: String
    let xdgConfigURL: URL
    let xdgDisplayPath: String
}

/// Status of the AeroSpace server connection.
struct AeroSpaceServerStatus {
    let isConnected: Bool
    let configPath: String?
    let findings: [DoctorFinding]
}

/// Checks AeroSpace-related requirements for Doctor.
struct AeroSpaceChecker {
    static let aerospaceAppPath = "/Applications/AeroSpace.app"
    static let homebrewPaths = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew"
    ]
    static let safeConfigMarker = "# Managed by ProjectWorkspaces."
    static let safeConfigContents = """
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
    private let commandRunner: CommandRunning
    private let aerospaceBinaryResolver: AeroSpaceBinaryResolving
    private let environment: EnvironmentProviding
    private let dateProvider: DateProviding

    /// Creates an AeroSpace checker with the provided dependencies.
    /// - Parameters:
    ///   - paths: File system paths for ProjectWorkspaces.
    ///   - fileSystem: File system accessor.
    ///   - commandRunner: Command runner for CLI checks.
    ///   - aerospaceBinaryResolver: Resolver for the AeroSpace CLI executable.
    ///   - environment: Environment provider for XDG config resolution.
    ///   - dateProvider: Date provider for timestamps.
    init(
        paths: ProjectWorkspacesPaths,
        fileSystem: FileSystem,
        commandRunner: CommandRunning,
        aerospaceBinaryResolver: AeroSpaceBinaryResolving,
        environment: EnvironmentProviding,
        dateProvider: DateProviding
    ) {
        self.paths = paths
        self.fileSystem = fileSystem
        self.commandRunner = commandRunner
        self.aerospaceBinaryResolver = aerospaceBinaryResolver
        self.environment = environment
        self.dateProvider = dateProvider
    }

    /// Checks if AeroSpace.app exists.
    /// - Returns: True if AeroSpace.app is found.
    func appExists() -> Bool {
        let appURL = URL(fileURLWithPath: Self.aerospaceAppPath, isDirectory: true)
        return fileSystem.directoryExists(at: appURL)
    }

    /// Resolves Homebrew's executable path.
    /// - Returns: Homebrew URL if found.
    func resolveHomebrew() -> URL? {
        for path in Self.homebrewPaths {
            let url = URL(fileURLWithPath: path, isDirectory: false)
            if fileSystem.isExecutableFile(at: url) {
                return url
            }
        }
        return nil
    }

    /// Resolves the AeroSpace CLI executable.
    /// - Returns: Result containing the executable URL or resolution error.
    func resolveCLI() -> Result<URL, AeroSpaceBinaryResolutionError> {
        aerospaceBinaryResolver.resolve()
    }

    /// Builds the AeroSpace app finding.
    /// - Parameter appExists: Whether the app was found.
    /// - Returns: Finding for app discovery.
    func aerospaceAppFinding(appExists: Bool) -> [DoctorFinding] {
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

    /// Builds the AeroSpace CLI finding.
    /// - Parameter resolution: Result of CLI resolution.
    /// - Returns: Finding for CLI discovery.
    func aerospaceCliFinding(
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

    /// Builds the Homebrew finding.
    /// - Parameter homebrewURL: Resolved Homebrew path.
    /// - Returns: Finding for Homebrew availability.
    func homebrewFinding(homebrewURL: URL?) -> DoctorFinding {
        guard let homebrewURL else {
            return DoctorFinding(
                severity: .fail,
                title: "Homebrew not found",
                bodyLines: [
                    "Fix: Install Homebrew (required for ProjectWorkspaces) and re-run Doctor."
                ]
            )
        }
        return DoctorFinding(
            severity: .pass,
            title: "Homebrew found at: \(homebrewURL.path)"
        )
    }

    /// Installs AeroSpace via Homebrew.
    /// - Returns: Finding for install result.
    func installAeroSpaceViaHomebrew() -> DoctorFinding {
        guard let homebrewURL = resolveHomebrew() else {
            return homebrewFinding(homebrewURL: nil)
        }

        let cliResolution = resolveCLI()
        if appExists(), (try? cliResolution.get()) != nil {
            return DoctorFinding(
                severity: .pass,
                title: "AeroSpace already installed"
            )
        }

        do {
            let result = try commandRunner.run(
                command: homebrewURL,
                arguments: ["install", "--cask", "nikitabobko/tap/aerospace"],
                environment: nil,
                workingDirectory: nil
            )
            if result.exitCode == 0 {
                return DoctorFinding(
                    severity: .pass,
                    title: "Installed AeroSpace via Homebrew",
                    bodyLines: ["Next: Run Doctor again to verify."]
                )
            }
            return DoctorFinding(
                severity: .fail,
                title: "Homebrew install failed",
                detail: result.stderr.isEmpty ? result.stdout : result.stderr,
                fix: "Fix the Homebrew error above and re-run Doctor."
            )
        } catch {
            return DoctorFinding(
                severity: .fail,
                title: "Homebrew install failed",
                detail: String(describing: error),
                fix: "Fix the Homebrew error above and re-run Doctor."
            )
        }
    }

    /// Resolves AeroSpace config paths.
    /// - Returns: Resolved config paths.
    func resolveAeroSpaceConfigPaths() -> AeroSpaceConfigPaths {
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

    /// Resolves XDG_CONFIG_HOME.
    /// - Returns: Resolved XDG config home URL.
    private func resolvedXdgConfigHome() -> URL {
        if let raw = environment.value(forKey: "XDG_CONFIG_HOME")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            let expanded = (raw as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }

        return paths.homeDirectory.appendingPathComponent(".config", isDirectory: true)
    }

    /// Resolves the AeroSpace config state.
    /// - Parameter paths: Resolved config paths.
    /// - Returns: Config state.
    func resolveAeroSpaceConfigState(paths: AeroSpaceConfigPaths) -> AeroSpaceConfigState {
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

    /// Builds the AeroSpace config finding.
    /// - Parameters:
    ///   - state: Config state.
    ///   - paths: Resolved config paths.
    /// - Returns: Finding for config status.
    func aerospaceConfigFinding(
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

    /// Checks the AeroSpace server status.
    /// - Parameters:
    ///   - executable: Resolved AeroSpace executable URL.
    ///   - appExists: Whether the app was found.
    /// - Returns: Server status including findings.
    func checkAeroSpaceServer(executable: URL, appExists: Bool) -> AeroSpaceServerStatus {
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

    /// Queries the AeroSpace config path.
    /// - Parameter executable: Resolved AeroSpace executable URL.
    /// - Returns: Config path if available.
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

    /// Retries querying the AeroSpace config path.
    /// - Parameter executable: Resolved AeroSpace executable URL.
    /// - Returns: Config path if available after retries.
    private func retryAeroSpaceConfigPath(executable: URL) -> String? {
        for _ in 0..<Self.aerospaceServerRetryCount {
            if let path = queryAeroSpaceConfigPath(executable: executable) {
                return path
            }
            Thread.sleep(forTimeInterval: Self.aerospaceServerRetryDelaySeconds)
        }
        return nil
    }

    /// Checks AeroSpace workspace switching.
    /// - Parameter executable: Resolved AeroSpace executable URL.
    /// - Returns: Findings for workspace switching.
    func checkAerospaceWorkspaceSwitch(executable: URL) -> [DoctorFinding] {
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

    /// Result of a Doctor check.
    private enum DoctorCheckResult<Success> {
        case success(Success)
        case failure(DoctorFinding)
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

    /// Outcome of a command execution.
    private enum CommandOutcome {
        case success(CommandResult)
        case failure(String)
    }

    /// Runs a command and returns the result or a formatted failure detail.
    /// - Parameters:
    ///   - executable: Executable file URL.
    ///   - arguments: Arguments to pass to the executable.
    /// - Returns: Command result or a failure detail string.
    private func runCommand(executable: URL, arguments: [String]) -> CommandOutcome {
        do {
            let result = try commandRunner.run(
                command: executable,
                arguments: arguments,
                environment: nil,
                workingDirectory: nil
            )
            if result.exitCode == 0 {
                return .success(result)
            }
            return .failure(result.failureDetail(prefix: "Command failed"))
        } catch {
            return .failure("Command failed to launch: \(error)")
        }
    }

    /// Runs an AeroSpace CLI action and returns a single finding.
    /// - Parameters:
    ///   - arguments: CLI arguments to pass to aerospace.
    ///   - successTitle: Title to use on success (omit to skip success finding).
    ///   - failureTitle: Title to use on failure.
    ///   - failureFix: Fix line to use on failure.
    ///   - failureSeverity: Severity for failure finding.
    /// - Returns: A finding describing the action result.
    func runAeroSpaceCommandAction(
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

    /// Checks if the safe config is installed at the given URL.
    /// - Parameter url: URL to check.
    /// - Returns: True if the safe config marker is found.
    func isSafeConfigInstalled(at url: URL) -> Bool {
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

    /// Installs the safe AeroSpace config.
    /// - Parameter configPaths: Resolved config paths.
    /// - Returns: Finding for the install result.
    func installSafeConfig(configPaths: AeroSpaceConfigPaths) -> DoctorFinding? {
        let tempURL = URL(fileURLWithPath: configPaths.userConfigURL.path + ".tmp.\(ProcessInfo.processInfo.processIdentifier)")
        let data = Data(Self.safeConfigContents.utf8)
        do {
            try fileSystem.writeFile(at: tempURL, data: data)
            try fileSystem.syncFile(at: tempURL)
            try fileSystem.moveItem(at: tempURL, to: configPaths.userConfigURL)
        } catch {
            return DoctorFinding(
                severity: .fail,
                title: "Failed to install safe AeroSpace config",
                detail: String(describing: error),
                fix: "Ensure your home directory is writable and retry."
            )
        }

        guard isSafeConfigInstalled(at: configPaths.userConfigURL) else {
            return DoctorFinding(
                severity: .fail,
                title: "Safe AeroSpace config install verification failed",
                fix: "Ensure ~/.aerospace.toml starts with '# Managed by ProjectWorkspaces.'"
            )
        }

        return nil
    }

    /// Uninstalls the safe AeroSpace config.
    /// - Parameter configPaths: Resolved config paths.
    /// - Returns: Findings for the uninstall result.
    func uninstallSafeConfig(configPaths: AeroSpaceConfigPaths) -> [DoctorFinding] {
        guard isSafeConfigInstalled(at: configPaths.userConfigURL) else {
            return [
                DoctorFinding(
                    severity: .pass,
                    title: "",
                    bodyLines: [
                        "INFO  AeroSpace config appears user-managed; ProjectWorkspaces will not modify it."
                    ]
                )
            ]
        }

        let backupURL = URL(
            fileURLWithPath: configPaths.userConfigURL.path
                + ".projectworkspaces.bak.\(backupTimestamp())"
        )

        do {
            try fileSystem.moveItem(at: configPaths.userConfigURL, to: backupURL)
        } catch {
            return [
                DoctorFinding(
                    severity: .fail,
                    title: "Failed to back up safe AeroSpace config",
                    detail: String(describing: error),
                    fix: "Ensure ~/.aerospace.toml is writable and retry."
                )
            ]
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

        return findings
    }

    /// Generates a backup timestamp.
    /// - Returns: Formatted timestamp string.
    private func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: dateProvider.now())
    }
}
