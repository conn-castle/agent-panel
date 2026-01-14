import Foundation

/// Runs Doctor checks for ProjectWorkspaces.
public struct Doctor {
    private let paths: ProjectWorkspacesPaths
    private let fileSystem: FileSystem
    private let appDiscovery: AppDiscovering
    private let hotkeyChecker: HotkeyChecking
    private let accessibilityChecker: AccessibilityChecking
    private let commandRunner: CommandRunning
    private let configParser: ConfigParser

    /// Creates a Doctor runner with default dependencies.
    /// - Parameters:
    ///   - paths: File system paths for ProjectWorkspaces.
    ///   - fileSystem: File system accessor.
    ///   - appDiscovery: App discovery implementation.
    ///   - hotkeyChecker: Hotkey availability checker.
    ///   - accessibilityChecker: Accessibility permission checker.
    ///   - commandRunner: Command runner used for CLI checks.
    public init(
        paths: ProjectWorkspacesPaths = .defaultPaths(),
        fileSystem: FileSystem = DefaultFileSystem(),
        appDiscovery: AppDiscovering = LaunchServicesAppDiscovery(),
        hotkeyChecker: HotkeyChecking = CarbonHotkeyChecker(),
        accessibilityChecker: AccessibilityChecking = DefaultAccessibilityChecker(),
        commandRunner: CommandRunning = DefaultCommandRunner()
    ) {
        self.paths = paths
        self.fileSystem = fileSystem
        self.appDiscovery = appDiscovery
        self.hotkeyChecker = hotkeyChecker
        self.accessibilityChecker = accessibilityChecker
        self.commandRunner = commandRunner
        self.configParser = ConfigParser()
    }

    /// Runs Doctor checks and returns a report.
    /// - Returns: A Doctor report with PASS/WARN/FAIL findings.
    public func run() -> DoctorReport {
        var findings: [DoctorFinding] = []
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

        findings.append(contentsOf: checkAerospaceConnectivity())
        findings.append(accessibilityFinding())
        findings.append(hotkeyFinding())

        return DoctorReport(findings: findings)
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

    private enum DoctorCheckResult<Success> {
        case success(Success)
        case failure(DoctorFinding)
    }

    private enum CommandOutcome {
        case success(CommandResult)
        case failure(String)
    }

    /// Checks AeroSpace connectivity by switching to `pw-inbox` and restoring the previous workspace.
    /// - Returns: Findings for AeroSpace CLI resolution and workspace switching behavior.
    private func checkAerospaceConnectivity() -> [DoctorFinding] {
        var findings: [DoctorFinding] = []

        switch resolveAerospaceExecutable() {
        case .failure(let failure):
            return [failure]
        case .success(let executable):
            findings.append(
                DoctorFinding(
                    severity: .pass,
                    title: "AeroSpace CLI resolved",
                    detail: executable.path
                )
            )

            let previousWorkspaceResult = focusedWorkspace(
                executable: executable,
                context: "before switching to pw-inbox"
            )

            switch previousWorkspaceResult {
            case .failure(let failure):
                findings.append(failure)
                return findings
            case .success(let previousWorkspace):
                let switchResult = runCommand(
                    executable: executable,
                    arguments: ["workspace", "pw-inbox"]
                )

                switch switchResult {
                case .failure(let detail):
                    findings.append(
                        DoctorFinding(
                            severity: .fail,
                            title: "AeroSpace failed to switch to pw-inbox",
                            detail: detail,
                            fix: "Ensure AeroSpace is running, then try `aerospace workspace pw-inbox`."
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
                case .failure(let failure):
                    findings.append(failure)
                    return findings
                case .success(let currentWorkspace):
                    if currentWorkspace != "pw-inbox" {
                        findings.append(
                            DoctorFinding(
                                severity: .fail,
                                title: "AeroSpace did not switch to pw-inbox",
                                detail: "Focused workspace is \(currentWorkspace).",
                                fix: "Ensure AeroSpace can switch workspaces, then try `aerospace workspace pw-inbox`."
                            )
                        )
                        return findings
                    }
                }

                findings.append(
                    DoctorFinding(
                        severity: .pass,
                        title: "AeroSpace connectivity check passed",
                        detail: "Switched to pw-inbox and verified focus."
                    )
                )

                if previousWorkspace != "pw-inbox" {
                    let restoreResult = runCommand(
                        executable: executable,
                        arguments: ["workspace", previousWorkspace]
                    )

                    switch restoreResult {
                    case .failure(let detail):
                        findings.append(
                            restoreWarning(previousWorkspace: previousWorkspace, detail: detail)
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
                    case .failure(let failure):
                        findings.append(
                            restoreWarning(
                                previousWorkspace: previousWorkspace,
                                detail: failure.detail ?? "Unable to verify focused workspace."
                            )
                        )
                    case .success(let restoredWorkspace):
                        if restoredWorkspace != previousWorkspace {
                            findings.append(
                                restoreWarning(
                                    previousWorkspace: previousWorkspace,
                                    detail: "Focused workspace is \(restoredWorkspace)."
                                )
                            )
                        }
                    }
                }
            }
        }

        return findings
    }

    /// Resolves the AeroSpace CLI executable using deterministic paths and a controlled `which` lookup.
    /// - Returns: The resolved executable URL or a failure finding.
    private func resolveAerospaceExecutable() -> DoctorCheckResult<URL> {
        let candidatePaths = [
            "/opt/homebrew/bin/aerospace",
            "/usr/local/bin/aerospace"
        ]
        let controlledPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        let searchContext = "Checked /opt/homebrew/bin/aerospace, /usr/local/bin/aerospace, and `which aerospace` with PATH=\(controlledPath)."

        for candidatePath in candidatePaths {
            let candidateURL = URL(fileURLWithPath: candidatePath, isDirectory: false)
            if fileSystem.isExecutableFile(at: candidateURL) {
                return .success(candidateURL)
            }
        }

        let whichURL = URL(fileURLWithPath: "/usr/bin/which", isDirectory: false)

        guard fileSystem.isExecutableFile(at: whichURL) else {
            return .failure(
                DoctorFinding(
                    severity: .fail,
                    title: "AeroSpace CLI not found",
                    detail: "Expected /usr/bin/which to be executable for lookup. \(searchContext)",
                    fix: "Install AeroSpace and ensure the `aerospace` CLI is installed, then re-run pwctl doctor."
                )
            )
        }

        let result: CommandResult
        do {
            result = try commandRunner.run(
                command: whichURL,
                arguments: ["aerospace"],
                environment: ["PATH": controlledPath]
            )
        } catch {
            return .failure(
                DoctorFinding(
                    severity: .fail,
                    title: "AeroSpace CLI not found",
                    detail: "Failed to run /usr/bin/which: \(error). \(searchContext)",
                    fix: "Install AeroSpace and ensure the `aerospace` CLI is installed, then re-run pwctl doctor."
                )
            )
        }

        if result.exitCode != 0 {
            return .failure(
                DoctorFinding(
                    severity: .fail,
                    title: "AeroSpace CLI not found",
                    detail: commandFailureDetail(
                        exitCode: result.exitCode,
                        stdout: result.stdout,
                        stderr: result.stderr,
                        prefix: "which aerospace failed"
                    ) + " " + searchContext,
                    fix: "Install AeroSpace and ensure the `aerospace` CLI is installed, then re-run pwctl doctor."
                )
            )
        }

        let resolvedPath = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedPath.isEmpty else {
            return .failure(
                DoctorFinding(
                    severity: .fail,
                    title: "AeroSpace CLI not found",
                    detail: "which aerospace returned empty output with PATH=\(controlledPath). \(searchContext)",
                    fix: "Install AeroSpace and ensure the `aerospace` CLI is installed, then re-run pwctl doctor."
                )
            )
        }

        let resolvedURL = URL(fileURLWithPath: resolvedPath, isDirectory: false)
        guard fileSystem.isExecutableFile(at: resolvedURL) else {
            return .failure(
                DoctorFinding(
                    severity: .fail,
                    title: "AeroSpace CLI not found",
                    detail: "Resolved path is not executable: \(resolvedPath). \(searchContext)",
                    fix: "Install AeroSpace and ensure the `aerospace` CLI is installed, then re-run pwctl doctor."
                )
            )
        }

        return .success(resolvedURL)
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

    /// Builds a warning finding for restore failures after switching to `pw-inbox`.
    /// - Parameters:
    ///   - previousWorkspace: Workspace name captured before switching.
    ///   - detail: Detail describing the restore failure.
    /// - Returns: A WARN finding instructing manual restoration.
    private func restoreWarning(previousWorkspace: String, detail: String?) -> DoctorFinding {
        let detailText = detail.map { "Previous workspace: \(previousWorkspace). \($0)" }
            ?? "Previous workspace: \(previousWorkspace)."
        return DoctorFinding(
            severity: .warn,
            title: "Doctor changed your AeroSpace workspace to pw-inbox but could not restore the previous workspace.",
            detail: detailText,
            fix: "Manually run `aerospace workspace \(previousWorkspace)`."
        )
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
