import Foundation

/// Launches IDEs according to ProjectWorkspaces configuration rules.
public struct IdeLauncher {
    private let paths: ProjectWorkspacesPaths
    private let fileSystem: FileSystem
    private let processRunner: ProcessRunning
    private let environmentProvider: EnvironmentProviding
    private let appResolver: IdeAppResolver
    private let workspaceGenerator: VSCodeWorkspaceGenerator
    private let shimInstaller: VSCodeShimInstaller
    private let cliResolver: VSCodeCLIResolver
    private let environmentBuilder: IdeLaunchEnvironment
    private let logger: ProjectWorkspacesLogging

    /// Creates an IDE launcher.
    /// - Parameters:
    ///   - paths: ProjectWorkspaces filesystem paths.
    ///   - fileSystem: File system accessor.
    ///   - commandRunner: Command runner used to execute shell commands.
    ///   - environment: Environment provider for launch commands.
    ///   - appDiscovery: App discovery provider.
    ///   - permissions: File permissions setter.
    ///   - logger: Logger for warnings and errors.
    public init(
        paths: ProjectWorkspacesPaths = .defaultPaths(),
        fileSystem: FileSystem = DefaultFileSystem(),
        commandRunner: CommandRunning = DefaultCommandRunner(),
        environment: EnvironmentProviding = ProcessEnvironment(),
        appDiscovery: AppDiscovering = LaunchServicesAppDiscovery(),
        permissions: FilePermissionsSetting = DefaultFilePermissions(),
        logger: ProjectWorkspacesLogging = ProjectWorkspacesLogger()
    ) {
        self.paths = paths
        self.fileSystem = fileSystem
        self.processRunner = ProcessRunner(commandRunner: commandRunner)
        self.environmentProvider = environment
        self.appResolver = IdeAppResolver(fileSystem: fileSystem, appDiscovery: appDiscovery)
        self.workspaceGenerator = VSCodeWorkspaceGenerator(paths: paths, fileSystem: fileSystem)
        self.shimInstaller = VSCodeShimInstaller(paths: paths, fileSystem: fileSystem, permissions: permissions)
        self.cliResolver = VSCodeCLIResolver(fileSystem: fileSystem)
        self.environmentBuilder = IdeLaunchEnvironment()
        self.logger = logger
    }

    /// Launches the IDE for the provided project.
    /// - Parameters:
    ///   - project: Project configuration entry.
    ///   - ideConfig: Global IDE configuration.
    /// - Returns: Success with warnings or a failure error.
    public func launch(project: ProjectConfig, ideConfig: IdeConfig) -> Result<IdeLaunchSuccess, IdeLaunchError> {
        let workspaceURLResult = workspaceGenerator.writeWorkspace(for: project)
        let workspaceURL: URL
        switch workspaceURLResult {
        case .failure(let error):
            return .failure(.workspaceGenerationFailed(error))
        case .success(let url):
            workspaceURL = url
        }

        let environment = environmentBuilder.build(
            baseEnvironment: environmentProvider.allValues(),
            project: project,
            ide: project.ide,
            workspaceFile: workspaceURL,
            paths: paths,
            vscodeConfigAppPath: ideConfig.vscode?.appPath,
            vscodeConfigBundleId: ideConfig.vscode?.bundleId
        )

        switch project.ide {
        case .vscode:
            return launchVSCode(project: project, ideConfig: ideConfig, workspaceURL: workspaceURL, environment: environment)
        case .antigravity:
            return launchAntigravity(
                project: project,
                ideConfig: ideConfig,
                workspaceURL: workspaceURL,
                environment: environment
            )
        }
    }

    private func launchVSCode(
        project: ProjectConfig,
        ideConfig: IdeConfig,
        workspaceURL: URL,
        environment: [String: String]
    ) -> Result<IdeLaunchSuccess, IdeLaunchError> {
        let resolutionResult = appResolver.resolve(ide: .vscode, config: ideConfig.vscode)
        let vscodeResolution: IdeAppResolution
        switch resolutionResult {
        case .failure(let error):
            return .failure(.appResolutionFailed(ide: .vscode, error: error))
        case .success(let resolution):
            vscodeResolution = resolution
        }

        let shimResult = shimInstaller.ensureShimInstalled()
        if case .failure(let error) = shimResult {
            return .failure(.shimInstallFailed(error))
        }

        let cliResult = cliResolver.resolveCLIPath(vscodeAppURL: vscodeResolution.appURL)
        let cliURL: URL
        switch cliResult {
        case .failure(let error):
            return .failure(.cliResolutionFailed(error))
        case .success(let url):
            cliURL = url
        }

        let projectRoot = URL(fileURLWithPath: project.path, isDirectory: true)
        var warnings: [IdeLaunchWarning] = []

        if hasIdeCommand(project.ideCommand) {
            let ideCommandResult = processRunner.run(
                executable: URL(fileURLWithPath: "/bin/zsh", isDirectory: false),
                arguments: ["-lc", project.ideCommand],
                environment: environment,
                workingDirectory: projectRoot
            )

            switch ideCommandResult {
            case .success:
                return reuseWorkspace(cliURL: cliURL, workspaceURL: workspaceURL, environment: environment, warnings: warnings)
            case .failure(let error):
                let warning = IdeLaunchWarning.ideCommandFailed(command: "/bin/zsh -lc \(project.ideCommand)", error: error)
                warnings.append(warning)
                logWarning(warning)
                return fallbackOpenVSCode(
                    appURL: vscodeResolution.appURL,
                    workspaceURL: workspaceURL,
                    environment: environment,
                    cliURL: cliURL,
                    warnings: warnings
                )
            }
        }

        if let launcherURL = agentLayerLauncherURL(for: project),
           project.ideUseAgentLayerLauncher {
            let launcherResult = processRunner.run(
                executable: launcherURL,
                arguments: [],
                environment: environment,
                workingDirectory: projectRoot
            )

            switch launcherResult {
            case .success:
                return reuseWorkspace(cliURL: cliURL, workspaceURL: workspaceURL, environment: environment, warnings: warnings)
            case .failure(let error):
                let warning = IdeLaunchWarning.launcherFailed(command: launcherURL.path, error: error)
                warnings.append(warning)
                logWarning(warning)
                return fallbackOpenVSCode(
                    appURL: vscodeResolution.appURL,
                    workspaceURL: workspaceURL,
                    environment: environment,
                    cliURL: cliURL,
                    warnings: warnings
                )
            }
        }

        return fallbackOpenVSCode(
            appURL: vscodeResolution.appURL,
            workspaceURL: workspaceURL,
            environment: environment,
            cliURL: cliURL,
            warnings: warnings
        )
    }

    private func fallbackOpenVSCode(
        appURL: URL,
        workspaceURL: URL,
        environment: [String: String],
        cliURL: URL,
        warnings: [IdeLaunchWarning]
    ) -> Result<IdeLaunchSuccess, IdeLaunchError> {
        let openResult = runCommand(
            executable: URL(fileURLWithPath: "/usr/bin/open", isDirectory: false),
            arguments: ["-a", appURL.path, workspaceURL.path],
            environment: environment,
            workingDirectory: nil
        )

        switch openResult {
        case .failure(let error):
            return .failure(.openFailed(error))
        case .success:
            return reuseWorkspace(cliURL: cliURL, workspaceURL: workspaceURL, environment: environment, warnings: warnings)
        }
    }

    private func reuseWorkspace(
        cliURL: URL,
        workspaceURL: URL,
        environment: [String: String],
        warnings: [IdeLaunchWarning]
    ) -> Result<IdeLaunchSuccess, IdeLaunchError> {
        let reuseResult = runCommand(
            executable: cliURL,
            arguments: ["-r", workspaceURL.path],
            environment: environment,
            workingDirectory: nil
        )

        switch reuseResult {
        case .failure(let error):
            return .failure(.reuseWindowFailed(error))
        case .success:
            return .success(IdeLaunchSuccess(warnings: warnings))
        }
    }

    private func launchAntigravity(
        project: ProjectConfig,
        ideConfig: IdeConfig,
        workspaceURL: URL,
        environment: [String: String]
    ) -> Result<IdeLaunchSuccess, IdeLaunchError> {
        let resolutionResult = appResolver.resolve(ide: .antigravity, config: ideConfig.antigravity)
        let antigravityResolution: IdeAppResolution
        switch resolutionResult {
        case .failure(let error):
            return .failure(.appResolutionFailed(ide: .antigravity, error: error))
        case .success(let resolution):
            antigravityResolution = resolution
        }

        let projectRoot = URL(fileURLWithPath: project.path, isDirectory: true)
        var warnings: [IdeLaunchWarning] = []

        if hasIdeCommand(project.ideCommand) {
            let ideCommandResult = processRunner.run(
                executable: URL(fileURLWithPath: "/bin/zsh", isDirectory: false),
                arguments: ["-lc", project.ideCommand],
                environment: environment,
                workingDirectory: projectRoot
            )

            switch ideCommandResult {
            case .success:
                return .success(IdeLaunchSuccess(warnings: warnings))
            case .failure(let error):
                let warning = IdeLaunchWarning.ideCommandFailed(command: "/bin/zsh -lc \(project.ideCommand)", error: error)
                warnings.append(warning)
                logWarning(warning)
                return fallbackOpenAntigravity(
                    appURL: antigravityResolution.appURL,
                    workspaceURL: workspaceURL,
                    environment: environment,
                    warnings: warnings
                )
            }
        }

        return fallbackOpenAntigravity(
            appURL: antigravityResolution.appURL,
            workspaceURL: workspaceURL,
            environment: environment,
            warnings: warnings
        )
    }

    private func fallbackOpenAntigravity(
        appURL: URL,
        workspaceURL: URL,
        environment: [String: String],
        warnings: [IdeLaunchWarning]
    ) -> Result<IdeLaunchSuccess, IdeLaunchError> {
        let openResult = runCommand(
            executable: URL(fileURLWithPath: "/usr/bin/open", isDirectory: false),
            arguments: ["-a", appURL.path, workspaceURL.path],
            environment: environment,
            workingDirectory: nil
        )

        switch openResult {
        case .failure(let error):
            return .failure(.openFailed(error))
        case .success:
            return .success(IdeLaunchSuccess(warnings: warnings))
        }
    }

    private func hasIdeCommand(_ command: String) -> Bool {
        !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func agentLayerLauncherURL(for project: ProjectConfig) -> URL? {
        guard project.ide == .vscode else {
            return nil
        }
        let projectURL = URL(fileURLWithPath: project.path, isDirectory: true)
        let launcherURL = projectURL
            .appendingPathComponent(".agent-layer", isDirectory: true)
            .appendingPathComponent("open-vscode.command", isDirectory: false)
        guard fileSystem.fileExists(at: launcherURL), fileSystem.isExecutableFile(at: launcherURL) else {
            return nil
        }
        return launcherURL
    }

    private func runCommand(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?
    ) -> Result<CommandResult, ProcessCommandError> {
        processRunner.run(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory
        )
    }

    private func logWarning(_ warning: IdeLaunchWarning) {
        let message: String
        let context: [String: String]

        switch warning {
        case .ideCommandFailed(let command, let error):
            message = "ideCommand failed; falling back"
            context = warningContext(command: command, error: error)
        case .launcherFailed(let command, let error):
            message = "Agent-layer launcher failed; falling back"
            context = warningContext(command: command, error: error)
        }

        _ = logger.log(event: "ide.launch.warning", level: .warn, message: message, context: context)
    }

    private func warningContext(command: String, error: ProcessCommandError) -> [String: String] {
        var context: [String: String] = ["command": command]
        switch error {
        case .launchFailed(_, let underlyingError):
            context["error"] = underlyingError
        case .nonZeroExit(_, let result):
            context["exitCode"] = String(result.exitCode)
            context["stdout"] = result.stdout
            context["stderr"] = result.stderr
        }
        return context
    }
}
