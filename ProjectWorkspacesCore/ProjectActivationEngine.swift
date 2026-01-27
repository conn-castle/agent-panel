import Foundation

/// Coordinates end-to-end project activation.
public struct ProjectActivationEngine {
    public static let ideDetectPollIntervalMs = 200
    public static let ideDetectPollTimeoutMs = 5000
    public static let focusVerifyAttempts = 10
    public static let focusVerifyDelayMs = 50

    private let paths: ProjectWorkspacesPaths
    private let fileSystem: FileSystem
    private let configParser: ConfigParser
    private let aeroSpaceResolver: AeroSpaceBinaryResolving
    private let aeroSpaceCommandRunner: AeroSpaceCommandRunning
    private let aeroSpaceTimeoutSeconds: TimeInterval
    private let commandRunner: CommandRunning
    private let appDiscovery: AppDiscovering
    private let ideLauncher: IdeLaunching
    private let chromeLauncherFactory: (AeroSpaceClient, CommandRunning, AppDiscovering) -> ChromeLaunching
    private let stateStore: ProjectWorkspacesStateStoring
    private let displayInfoProvider: DisplayInfoProviding
    private let layoutCalculator: DefaultLayoutCalculator
    private let logger: ProjectWorkspacesLogging
    private let dateProvider: DateProviding
    private let sleeper: AeroSpaceSleeping
    private let logAeroSpaceCommands: Bool
    private let geometryApplierFactory: (AeroSpaceClient, AeroSpaceSleeping) -> WindowGeometryApplying

    /// Creates an activation engine.
    /// - Parameters:
    ///   - paths: ProjectWorkspaces filesystem paths.
    ///   - fileSystem: File system accessor.
    ///   - aeroSpaceResolver: AeroSpace CLI resolver.
    ///   - aeroSpaceCommandRunner: Runner for AeroSpace commands.
    ///   - aeroSpaceTimeoutSeconds: Timeout for AeroSpace commands.
    ///   - commandRunner: Command runner for non-AeroSpace commands.
    ///   - appDiscovery: Launch Services app discovery.
    ///   - ideLauncher: IDE launcher implementation.
    ///   - chromeLauncherFactory: Factory for Chrome launchers tied to an AeroSpace client.
    ///   - stateStore: State store for managed window ids.
    ///   - displayInfoProvider: Display info provider for layout calculations.
    ///   - layoutCalculator: Default layout calculator.
    ///   - logger: Logger used for activation events.
    ///   - dateProvider: Date provider for timestamps and backups.
    ///   - logAeroSpaceCommands: Whether to log AeroSpace command stdout/stderr.
    public init(
        paths: ProjectWorkspacesPaths = .defaultPaths(),
        fileSystem: FileSystem = DefaultFileSystem(),
        aeroSpaceResolver: AeroSpaceBinaryResolving = DefaultAeroSpaceBinaryResolver(),
        aeroSpaceCommandRunner: AeroSpaceCommandRunning = DefaultAeroSpaceCommandRunner(),
        aeroSpaceTimeoutSeconds: TimeInterval = 2,
        commandRunner: CommandRunning = DefaultCommandRunner(),
        appDiscovery: AppDiscovering = LaunchServicesAppDiscovery(),
        ideLauncher: IdeLaunching = IdeLauncher(),
        chromeLauncherFactory: @escaping (AeroSpaceClient, CommandRunning, AppDiscovering) -> ChromeLaunching = { client, runner, discovery in
            ChromeLauncher(aeroSpaceClient: client, commandRunner: runner, appDiscovery: discovery)
        },
        stateStore: ProjectWorkspacesStateStoring? = nil,
        displayInfoProvider: DisplayInfoProviding = SystemDisplayInfoProvider(),
        layoutCalculator: DefaultLayoutCalculator = DefaultLayoutCalculator(),
        logger: ProjectWorkspacesLogging = ProjectWorkspacesLogger(),
        dateProvider: DateProviding = SystemDateProvider(),
        logAeroSpaceCommands: Bool = true
    ) {
        self.init(
            paths: paths,
            fileSystem: fileSystem,
            configParser: ConfigParser(),
            aeroSpaceResolver: aeroSpaceResolver,
            aeroSpaceCommandRunner: aeroSpaceCommandRunner,
            aeroSpaceTimeoutSeconds: aeroSpaceTimeoutSeconds,
            commandRunner: commandRunner,
            appDiscovery: appDiscovery,
            ideLauncher: ideLauncher,
            chromeLauncherFactory: chromeLauncherFactory,
            stateStore: stateStore,
            displayInfoProvider: displayInfoProvider,
            layoutCalculator: layoutCalculator,
            logger: logger,
            dateProvider: dateProvider,
            sleeper: SystemAeroSpaceSleeper(),
            logAeroSpaceCommands: logAeroSpaceCommands,
            geometryApplierFactory: { client, sleeper in
                let focusVerifier = AeroSpaceFocusVerifier(
                    aeroSpaceClient: client,
                    sleeper: sleeper,
                    attempts: ProjectActivationEngine.focusVerifyAttempts,
                    delayMs: ProjectActivationEngine.focusVerifyDelayMs
                )
                return AXWindowGeometryApplier(focusController: client, focusVerifier: focusVerifier)
            }
        )
    }

    /// Internal initializer with injected dependencies (tests).
    init(
        paths: ProjectWorkspacesPaths,
        fileSystem: FileSystem,
        configParser: ConfigParser,
        aeroSpaceResolver: AeroSpaceBinaryResolving,
        aeroSpaceCommandRunner: AeroSpaceCommandRunning,
        aeroSpaceTimeoutSeconds: TimeInterval,
        commandRunner: CommandRunning,
        appDiscovery: AppDiscovering,
        ideLauncher: IdeLaunching,
        chromeLauncherFactory: @escaping (AeroSpaceClient, CommandRunning, AppDiscovering) -> ChromeLaunching,
        stateStore: ProjectWorkspacesStateStoring?,
        displayInfoProvider: DisplayInfoProviding,
        layoutCalculator: DefaultLayoutCalculator,
        logger: ProjectWorkspacesLogging,
        dateProvider: DateProviding,
        sleeper: AeroSpaceSleeping,
        logAeroSpaceCommands: Bool,
        geometryApplierFactory: @escaping (AeroSpaceClient, AeroSpaceSleeping) -> WindowGeometryApplying
    ) {
        self.paths = paths
        self.fileSystem = fileSystem
        self.configParser = configParser
        self.aeroSpaceResolver = aeroSpaceResolver
        self.aeroSpaceCommandRunner = aeroSpaceCommandRunner
        self.aeroSpaceTimeoutSeconds = aeroSpaceTimeoutSeconds
        self.commandRunner = commandRunner
        self.appDiscovery = appDiscovery
        self.ideLauncher = ideLauncher
        self.chromeLauncherFactory = chromeLauncherFactory
        self.stateStore = stateStore ?? ProjectWorkspacesStateStore(
            paths: paths,
            fileSystem: fileSystem,
            logger: logger,
            dateProvider: dateProvider
        )
        self.displayInfoProvider = displayInfoProvider
        self.layoutCalculator = layoutCalculator
        self.logger = logger
        self.dateProvider = dateProvider
        self.sleeper = sleeper
        self.logAeroSpaceCommands = logAeroSpaceCommands
        self.geometryApplierFactory = geometryApplierFactory
    }

    /// Activates a project by id.
    /// - Parameter projectId: Project identifier.
    /// - Returns: Activation outcome or failure error.
    public func activate(projectId: String) -> Result<ActivationOutcome, ActivationError> {
        let configOutcome = loadConfig()
        let config: Config
        let ideConfig: IdeConfig
        let projects: [ProjectConfig]
        switch configOutcome {
        case .failure(let error):
            logResult(level: .error, projectId: projectId, workspaceName: nil, warnings: [], error: error)
            return .failure(error)
        case .success(let outcome):
            guard let parsedConfig = outcome.config else {
                let error = ActivationError.configInvalid(findings: outcome.findings)
                logResult(level: .error, projectId: projectId, workspaceName: nil, warnings: [], error: error)
                return .failure(error)
            }
            config = parsedConfig
            ideConfig = outcome.ideConfig
            projects = outcome.projects
        }

        guard let project = projects.first(where: { $0.id == projectId }) else {
            let error = ActivationError.projectNotFound(projectId: projectId)
            logResult(level: .error, projectId: projectId, workspaceName: nil, warnings: [], error: error)
            return .failure(error)
        }

        let workspaceName = "pw-\(project.id)"
        let aeroSpaceClient: AeroSpaceClient
        switch buildAeroSpaceClient(projectId: projectId, workspaceName: workspaceName) {
        case .failure(let error):
            logResult(level: .error, projectId: projectId, workspaceName: workspaceName, warnings: [], error: error)
            return .failure(error)
        case .success(let client):
            aeroSpaceClient = client
        }

        let chromeLauncher = chromeLauncherFactory(aeroSpaceClient, commandRunner, appDiscovery)
        let geometryApplier = geometryApplierFactory(aeroSpaceClient, sleeper)

        var warnings: [ActivationWarning] = []

        switch stateStore.load() {
        case .failure(let error):
            let activationError = ActivationError.stateReadFailed(path: paths.stateFile.path, detail: String(describing: error))
            logResult(level: .error, projectId: projectId, workspaceName: workspaceName, warnings: warnings, error: activationError)
            return .failure(activationError)
        case .success(let loadResult):
            warnings.append(contentsOf: loadResult.warnings)
            for warning in loadResult.warnings {
                logWarning(warning, projectId: projectId, workspaceName: workspaceName)
            }
            var state = loadResult.state

            switch aeroSpaceClient.switchWorkspace(workspaceName) {
            case .failure(let error):
                let activationError = ActivationError.aeroSpaceFailed(error)
                logResult(level: .error, projectId: projectId, workspaceName: workspaceName, warnings: warnings, error: activationError)
                return .failure(activationError)
            case .success:
                break
            }

            let ideBundleIdResult = resolveIdeBundleId(project: project, ideConfig: ideConfig)
            let ideBundleId: String
            switch ideBundleIdResult {
            case .failure(let error):
                logResult(level: .error, projectId: projectId, workspaceName: workspaceName, warnings: warnings, error: error)
                return .failure(error)
            case .success(let bundleId):
                ideBundleId = bundleId
            }

            let managedState = state.projects[project.id] ?? ManagedWindowState()
            let ideResolutionResult = ensureIdeWindow(
                project: project,
                ideConfig: ideConfig,
                ideBundleId: ideBundleId,
                workspaceName: workspaceName,
                managedWindowId: managedState.ideWindowId,
                aeroSpaceClient: aeroSpaceClient,
                warnings: &warnings
            )

            let ideResolution: WindowResolution
            switch ideResolutionResult {
            case .failure(let error):
                logResult(level: .error, projectId: projectId, workspaceName: workspaceName, warnings: warnings, error: error)
                return .failure(error)
            case .success(let result):
                ideResolution = result
            }

            state.projects[project.id, default: ManagedWindowState()].ideWindowId = ideResolution.windowId
            switch stateStore.save(state: state) {
            case .failure(let error):
                let activationError = ActivationError.stateWriteFailed(path: paths.stateFile.path, detail: String(describing: error))
                logResult(level: .error, projectId: projectId, workspaceName: workspaceName, warnings: warnings, error: activationError)
                return .failure(activationError)
            case .success:
                break
            }

            let chromeResolutionResult = ensureChromeWindow(
                project: project,
                globalChromeUrls: config.global.globalChromeUrls,
                workspaceName: workspaceName,
                managedWindowId: state.projects[project.id]?.chromeWindowId,
                ideWindowIdToRefocus: ideResolution.windowId,
                chromeLauncher: chromeLauncher,
                aeroSpaceClient: aeroSpaceClient,
                warnings: &warnings
            )

            let chromeResolution: WindowResolution
            switch chromeResolutionResult {
            case .failure(let error):
                logResult(level: .error, projectId: projectId, workspaceName: workspaceName, warnings: warnings, error: error)
                return .failure(error)
            case .success(let result):
                chromeResolution = result
            }

            state.projects[project.id, default: ManagedWindowState()].chromeWindowId = chromeResolution.windowId
            switch stateStore.save(state: state) {
            case .failure(let error):
                let activationError = ActivationError.stateWriteFailed(path: paths.stateFile.path, detail: String(describing: error))
                logResult(level: .error, projectId: projectId, workspaceName: workspaceName, warnings: warnings, error: activationError)
                return .failure(activationError)
            case .success:
                break
            }

            enforceFloating(
                ideWindowId: ideResolution.windowId,
                chromeWindowId: chromeResolution.windowId,
                projectId: projectId,
                workspaceName: workspaceName,
                aeroSpaceClient: aeroSpaceClient,
                warnings: &warnings
            )

            let didCreateOrMove = ideResolution.created || ideResolution.moved || chromeResolution.created || chromeResolution.moved
            if didCreateOrMove {
                applyLayoutIfPossible(
                    project: project,
                    displayConfig: config.display,
                    workspaceName: workspaceName,
                    ideWindowId: ideResolution.windowId,
                    chromeWindowId: chromeResolution.windowId,
                    geometryApplier: geometryApplier,
                    warnings: &warnings
                )
            }

            switch aeroSpaceClient.focusWindow(windowId: ideResolution.windowId) {
            case .failure(let error):
                let activationError = ActivationError.finalFocusFailed(error)
                logResult(level: .error, projectId: projectId, workspaceName: workspaceName, warnings: warnings, error: activationError)
                return .failure(activationError)
            case .success:
                break
            }

            let outcome = ActivationOutcome(
                ideWindowId: ideResolution.windowId,
                chromeWindowId: chromeResolution.windowId,
                warnings: warnings
            )
            let logLevel: LogLevel = warnings.isEmpty ? .info : .warn
            logResult(level: logLevel, projectId: projectId, workspaceName: workspaceName, warnings: warnings, error: nil)
            return .success(outcome)
        }
    }

    /// Loads and parses config.toml.
    /// - Returns: Parsed config outcome or a structured activation error.
    private func loadConfig() -> Result<ConfigParseOutcome, ActivationError> {
        let configURL = paths.configFile
        guard fileSystem.fileExists(at: configURL) else {
            return .failure(.configMissing(path: configURL.path))
        }

        let data: Data
        do {
            data = try fileSystem.readFile(at: configURL)
        } catch {
            return .failure(.configReadFailed(path: configURL.path, detail: String(describing: error)))
        }

        guard let toml = String(data: data, encoding: .utf8) else {
            return .failure(.configReadFailed(path: configURL.path, detail: "Config is not valid UTF-8."))
        }

        let outcome = configParser.parse(toml: toml)
        guard outcome.config != nil else {
            return .failure(.configInvalid(findings: outcome.findings))
        }

        return .success(outcome)
    }

    /// Builds an AeroSpace client with optional command logging.
    /// - Parameters:
    ///   - projectId: Project identifier for logging context.
    ///   - workspaceName: Target workspace for logging context.
    /// - Returns: AeroSpace client or a structured activation error.
    private func buildAeroSpaceClient(projectId: String, workspaceName: String) -> Result<AeroSpaceClient, ActivationError> {
        let resolution = aeroSpaceResolver.resolve()
        let executableURL: URL
        switch resolution {
        case .success(let url):
            executableURL = url
        case .failure(let error):
            return .failure(.aeroSpaceResolutionFailed(error))
        }

        let runner: AeroSpaceCommandRunning
        if logAeroSpaceCommands {
            runner = LoggingAeroSpaceCommandRunner(
                baseRunner: aeroSpaceCommandRunner,
                logger: logger,
                projectId: projectId,
                workspaceName: workspaceName
            )
        } else {
            runner = aeroSpaceCommandRunner
        }

        let client = AeroSpaceClient(
            executableURL: executableURL,
            commandRunner: runner,
            timeoutSeconds: aeroSpaceTimeoutSeconds,
            clock: dateProvider,
            sleeper: sleeper,
            jitterProvider: SystemAeroSpaceJitterProvider(),
            retryPolicy: .standard,
            windowDecoder: AeroSpaceWindowDecoder()
        )
        return .success(client)
    }

    /// Resolves the bundle id for the project's IDE.
    /// - Parameters:
    ///   - project: Project configuration.
    ///   - ideConfig: Global IDE configuration.
    /// - Returns: Bundle id or an activation error.
    private func resolveIdeBundleId(project: ProjectConfig, ideConfig: IdeConfig) -> Result<String, ActivationError> {
        let resolver = IdeAppResolver(fileSystem: fileSystem, appDiscovery: appDiscovery)
        let resolutionResult = resolver.resolve(ide: project.ide, config: ideConfigConfig(for: project, ideConfig: ideConfig))
        switch resolutionResult {
        case .failure(let error):
            return .failure(.ideResolutionFailed(ide: project.ide, error: error))
        case .success(let resolution):
            guard let bundleId = resolution.bundleId, !bundleId.isEmpty else {
                return .failure(.ideBundleIdUnavailable(ide: project.ide, appPath: resolution.appURL.path))
            }
            return .success(bundleId)
        }
    }

    /// Returns the IDE-specific config entry for the project.
    private func ideConfigConfig(for project: ProjectConfig, ideConfig: IdeConfig) -> IdeAppConfig? {
        switch project.ide {
        case .vscode:
            return ideConfig.vscode
        case .antigravity:
            return ideConfig.antigravity
        }
    }

    /// Ensures an IDE window exists in the target workspace.
    private func ensureIdeWindow(
        project: ProjectConfig,
        ideConfig: IdeConfig,
        ideBundleId: String,
        workspaceName: String,
        managedWindowId: Int?,
        aeroSpaceClient: AeroSpaceClient,
        warnings: inout [ActivationWarning]
    ) -> Result<WindowResolution, ActivationError> {
        let helper = WindowResolutionHelper(aeroSpaceClient: aeroSpaceClient)
        return helper.ensureWindow(
            bundleId: ideBundleId,
            workspaceName: workspaceName,
            kind: .ide,
            managedWindowId: managedWindowId,
            projectId: project.id,
            warnings: &warnings,
            recordWarning: recordWarning,
            createWindow: { warnings in
                createIdeWindow(
                    project: project,
                    ideConfig: ideConfig,
                    ideBundleId: ideBundleId,
                    workspaceName: workspaceName,
                    aeroSpaceClient: aeroSpaceClient,
                    warnings: &warnings,
                    allowRetry: true
                )
            }
        )
    }

    /// Launches the IDE and detects the newly created window.
    private func createIdeWindow(
        project: ProjectConfig,
        ideConfig: IdeConfig,
        ideBundleId: String,
        workspaceName: String,
        aeroSpaceClient: AeroSpaceClient,
        warnings: inout [ActivationWarning],
        allowRetry: Bool
    ) -> Result<WindowResolution, ActivationError> {
        let beforeResult = aeroSpaceClient.listWindowsAllDecoded()
        let beforeWindows: [AeroSpaceWindow]
        switch beforeResult {
        case .failure(let error):
            return .failure(.aeroSpaceFailed(error))
        case .success(let windows):
            beforeWindows = windows
        }
        let beforeIds = Set(beforeWindows.filter { $0.appBundleId == ideBundleId }.map { $0.windowId })

        let launchResult = ideLauncher.launch(project: project, ideConfig: ideConfig)
        switch launchResult {
        case .failure(let error):
            return .failure(.ideLaunchFailed(error))
        case .success(let success):
            for warning in success.warnings {
                let activationWarning = ActivationWarning.ideLaunchWarning(warning)
                recordWarning(activationWarning, projectId: project.id, workspaceName: workspaceName, warnings: &warnings)
            }
        }

        let detectionResult = detectNewWindowId(bundleId: ideBundleId, beforeIds: beforeIds, aeroSpaceClient: aeroSpaceClient, ideKind: project.ide)
        let detection: DetectedWindow
        switch detectionResult {
        case .failure(let error):
            return .failure(error)
        case .success(let detected):
            detection = detected
        }

        if detection.workspaceName != workspaceName {
            let moveResult = aeroSpaceClient.moveWindow(windowId: detection.windowId, to: workspaceName)
            switch moveResult {
            case .success:
                return .success(WindowResolution(windowId: detection.windowId, created: true, moved: true))
            case .failure(let error):
                let warning = ActivationWarning.createdElsewhereMoveFailed(
                    kind: .ide,
                    windowId: detection.windowId,
                    actualWorkspace: detection.workspaceName,
                    error: error
                )
                recordWarning(warning, projectId: project.id, workspaceName: workspaceName, warnings: &warnings)
                if allowRetry {
                    return createIdeWindow(
                        project: project,
                        ideConfig: ideConfig,
                        ideBundleId: ideBundleId,
                        workspaceName: workspaceName,
                        aeroSpaceClient: aeroSpaceClient,
                        warnings: &warnings,
                        allowRetry: false
                    )
                }
                return .failure(.aeroSpaceFailed(error))
            }
        }

        return .success(WindowResolution(windowId: detection.windowId, created: true, moved: false))
    }

    /// Ensures a Chrome window exists in the target workspace.
    private func ensureChromeWindow(
        project: ProjectConfig,
        globalChromeUrls: [String],
        workspaceName: String,
        managedWindowId: Int?,
        ideWindowIdToRefocus: Int,
        chromeLauncher: ChromeLaunching,
        aeroSpaceClient: AeroSpaceClient,
        warnings: inout [ActivationWarning]
    ) -> Result<WindowResolution, ActivationError> {
        let helper = WindowResolutionHelper(aeroSpaceClient: aeroSpaceClient)
        return helper.ensureWindow(
            bundleId: ChromeLauncher.chromeBundleId,
            workspaceName: workspaceName,
            kind: .chrome,
            managedWindowId: managedWindowId,
            projectId: project.id,
            warnings: &warnings,
            recordWarning: recordWarning,
            createWindow: { warnings in
                createChromeWindow(
                    project: project,
                    globalChromeUrls: globalChromeUrls,
                    workspaceName: workspaceName,
                    managedWindowId: managedWindowId,
                    ideWindowIdToRefocus: ideWindowIdToRefocus,
                    chromeLauncher: chromeLauncher,
                    aeroSpaceClient: aeroSpaceClient,
                    warnings: &warnings,
                    allowRetry: true
                )
            }
        )
    }

    /// Creates a Chrome window and recovers from created-elsewhere cases.
    private func createChromeWindow(
        project: ProjectConfig,
        globalChromeUrls: [String],
        workspaceName: String,
        managedWindowId: Int?,
        ideWindowIdToRefocus: Int,
        chromeLauncher: ChromeLaunching,
        aeroSpaceClient: AeroSpaceClient,
        warnings: inout [ActivationWarning],
        allowRetry: Bool
    ) -> Result<WindowResolution, ActivationError> {
        let chromeResult = chromeLauncher.ensureWindow(
            expectedWorkspaceName: workspaceName,
            globalChromeUrls: globalChromeUrls,
            project: project,
            ideWindowIdToRefocus: ideWindowIdToRefocus
        )

        switch chromeResult {
        case .success(let outcome):
            switch outcome {
            case .created(let windowId):
                return .success(WindowResolution(windowId: windowId, created: true, moved: false))
            case .existing(let windowId):
                return .success(WindowResolution(windowId: windowId, created: false, moved: false))
            case .existingMultiple(let windowIds):
                let sortedIds = windowIds.sorted()
                let helper = WindowResolutionHelper(aeroSpaceClient: aeroSpaceClient)
                let selection = helper.selectFromIds(sortedIds, managedWindowId: managedWindowId, kind: .chrome, workspaceName: workspaceName)
                if let warning = selection.warning {
                    recordWarning(warning, projectId: project.id, workspaceName: workspaceName, warnings: &warnings)
                }
                return .success(WindowResolution(windowId: selection.windowId, created: false, moved: false))
            }
        case .failure(let error):
            switch error {
            case .chromeLaunchedElsewhere(_, let actualWorkspace, let newWindowId):
                let moveResult = aeroSpaceClient.moveWindow(windowId: newWindowId, to: workspaceName)
                switch moveResult {
                case .success:
                    return .success(WindowResolution(windowId: newWindowId, created: true, moved: true))
                case .failure(let moveError):
                    let warning = ActivationWarning.createdElsewhereMoveFailed(
                        kind: .chrome,
                        windowId: newWindowId,
                        actualWorkspace: actualWorkspace,
                        error: moveError
                    )
                    recordWarning(warning, projectId: project.id, workspaceName: workspaceName, warnings: &warnings)
                    if allowRetry {
                        return createChromeWindow(
                            project: project,
                            globalChromeUrls: globalChromeUrls,
                            workspaceName: workspaceName,
                            managedWindowId: managedWindowId,
                            ideWindowIdToRefocus: ideWindowIdToRefocus,
                            chromeLauncher: chromeLauncher,
                            aeroSpaceClient: aeroSpaceClient,
                            warnings: &warnings,
                            allowRetry: false
                        )
                    }
                    return .failure(.chromeLaunchFailed(error))
                }
            default:
                return .failure(.chromeLaunchFailed(error))
            }
        }
    }

    /// Enforces floating layout for the selected windows.
    private func enforceFloating(
        ideWindowId: Int,
        chromeWindowId: Int,
        projectId: String,
        workspaceName: String,
        aeroSpaceClient: AeroSpaceClient,
        warnings: inout [ActivationWarning]
    ) {
        if case .failure(let error) = aeroSpaceClient.setFloatingLayout(windowId: ideWindowId) {
            let warning = ActivationWarning.floatingFailed(kind: .ide, windowId: ideWindowId, error: error)
            recordWarning(warning, projectId: projectId, workspaceName: workspaceName, warnings: &warnings)
        }
        if case .failure(let error) = aeroSpaceClient.setFloatingLayout(windowId: chromeWindowId) {
            let warning = ActivationWarning.floatingFailed(kind: .chrome, windowId: chromeWindowId, error: error)
            recordWarning(warning, projectId: projectId, workspaceName: workspaceName, warnings: &warnings)
        }
    }

    /// Applies default layout when created or moved windows need geometry.
    private func applyLayoutIfPossible(
        project: ProjectConfig,
        displayConfig: DisplayConfig,
        workspaceName: String,
        ideWindowId: Int,
        chromeWindowId: Int,
        geometryApplier: WindowGeometryApplying,
        warnings: inout [ActivationWarning]
    ) {
        guard let displayInfo = displayInfoProvider.mainDisplayInfo() else {
            let warning = ActivationWarning.layoutSkipped(.screenUnavailable)
            recordWarning(warning, projectId: project.id, workspaceName: workspaceName, warnings: &warnings)
            return
        }

        let layout = layoutCalculator.layout(for: displayInfo, ultrawideMinWidthPx: displayConfig.ultrawideMinWidthPx)

        let ideOutcome = geometryApplier.apply(frame: layout.ideFrame, toWindowId: ideWindowId, inWorkspace: workspaceName)
        handleGeometryOutcome(
            outcome: ideOutcome,
            kind: .ide,
            windowId: ideWindowId,
            projectId: project.id,
            workspaceName: workspaceName,
            warnings: &warnings
        )

        let chromeOutcome = geometryApplier.apply(frame: layout.chromeFrame, toWindowId: chromeWindowId, inWorkspace: workspaceName)
        handleGeometryOutcome(
            outcome: chromeOutcome,
            kind: .chrome,
            windowId: chromeWindowId,
            projectId: project.id,
            workspaceName: workspaceName,
            warnings: &warnings
        )
    }

    /// Converts geometry outcomes into warnings.
    private func handleGeometryOutcome(
        outcome: WindowGeometryOutcome,
        kind: ActivationWindowKind,
        windowId: Int,
        projectId: String,
        workspaceName: String,
        warnings: inout [ActivationWarning]
    ) {
        switch outcome {
        case .applied:
            break
        case .skipped(let reason):
            let warning = ActivationWarning.layoutSkipped(reason)
            recordWarning(warning, projectId: projectId, workspaceName: workspaceName, warnings: &warnings)
        case .failed(let error):
            let warning = ActivationWarning.layoutFailed(kind: kind, windowId: windowId, error: error)
            recordWarning(warning, projectId: projectId, workspaceName: workspaceName, warnings: &warnings)
        }
    }

    /// Detects a newly created IDE window by bundle id.
    private func detectNewWindowId(
        bundleId: String,
        beforeIds: Set<Int>,
        aeroSpaceClient: AeroSpaceClient,
        ideKind: IdeKind
    ) -> Result<DetectedWindow, ActivationError> {
        let intervalSeconds = TimeInterval(Self.ideDetectPollIntervalMs) / 1000.0
        let maxAttempts = max(1, Int(ceil(Double(Self.ideDetectPollTimeoutMs) / Double(Self.ideDetectPollIntervalMs))) + 1)
        var lastWindows: [AeroSpaceWindow] = []

        for attempt in 0..<maxAttempts {
            let allResult = aeroSpaceClient.listWindowsAllDecoded()
            switch allResult {
            case .failure(let error):
                return .failure(.aeroSpaceFailed(error))
            case .success(let windows):
                lastWindows = windows
            }

            let afterIds = Set(lastWindows.filter { $0.appBundleId == bundleId }.map { $0.windowId })
            let newIds = afterIds.subtracting(beforeIds)

            if newIds.count == 1, let newId = newIds.first {
                if let window = lastWindows.first(where: { $0.windowId == newId }) {
                    return .success(DetectedWindow(windowId: newId, workspaceName: window.workspace))
                }
                return .failure(.ideWindowNotDetected(ide: ideKind))
            }

            if newIds.count > 1 {
                return .failure(.ideWindowAmbiguous(newWindowIds: newIds.sorted()))
            }

            if attempt < maxAttempts - 1 {
                sleeper.sleep(seconds: intervalSeconds)
            }
        }

        return .failure(.ideWindowNotDetected(ide: ideKind))
    }

    /// Records and logs a warning.
    private func recordWarning(
        _ warning: ActivationWarning,
        projectId: String,
        workspaceName: String,
        warnings: inout [ActivationWarning]
    ) {
        warnings.append(warning)
        logWarning(warning, projectId: projectId, workspaceName: workspaceName)
    }

    /// Logs a structured activation warning.
    private func logWarning(_ warning: ActivationWarning, projectId: String, workspaceName: String) {
        var context: [String: String] = [
            "projectId": projectId,
            "workspace": workspaceName
        ]
        let message: String

        switch warning {
        case .multipleWindows(let kind, let workspace, let chosenId, let extraIds):
            message = "Multiple \(kind.rawValue) windows in workspace; using \(chosenId)."
            context["workspace"] = workspace
            context["chosenId"] = String(chosenId)
            context["extraIds"] = extraIds.map(String.init).joined(separator: ",")
        case .floatingFailed(let kind, let windowId, let error):
            message = "Failed to set floating layout for \(kind.rawValue) window."
            context["windowId"] = String(windowId)
            context["error"] = String(describing: error)
        case .moveFailed(let kind, let windowId, let workspace, let error):
            message = "Failed to move managed \(kind.rawValue) window."
            context["workspace"] = workspace
            context["windowId"] = String(windowId)
            context["error"] = String(describing: error)
        case .createdElsewhereMoveFailed(let kind, let windowId, let actualWorkspace, let error):
            message = "Failed to move newly created \(kind.rawValue) window from \(actualWorkspace)."
            context["windowId"] = String(windowId)
            context["actualWorkspace"] = actualWorkspace
            context["error"] = String(describing: error)
        case .ideLaunchWarning(let warning):
            message = "IDE launch warning."
            switch warning {
            case .ideCommandFailed(let command, let error):
                context["command"] = command
                context["error"] = String(describing: error)
            case .launcherFailed(let command, let error):
                context["command"] = command
                context["error"] = String(describing: error)
            }
        case .layoutSkipped(let reason):
            message = "Layout skipped."
            switch reason {
            case .screenUnavailable:
                context["reason"] = "screen_unavailable"
            case .focusNotVerified(let expectedId, let expectedWorkspace, let actualId, let actualWorkspace):
                context["reason"] = "focus_not_verified"
                context["expectedWindowId"] = String(expectedId)
                context["expectedWorkspace"] = expectedWorkspace
                context["actualWindowId"] = actualId.map(String.init)
                context["actualWorkspace"] = actualWorkspace
            }
        case .layoutFailed(let kind, let windowId, let error):
            message = "Layout apply failed for \(kind.rawValue)."
            context["windowId"] = String(windowId)
            context["error"] = String(describing: error)
        case .stateRecovered(let backupPath):
            message = "State was unreadable; recovered with backup."
            context["backupPath"] = backupPath
        }

        _ = logger.log(event: "activation.warning", level: .warn, message: message, context: context)
    }

    /// Logs the final activation result.
    private func logResult(
        level: LogLevel,
        projectId: String,
        workspaceName: String?,
        warnings: [ActivationWarning],
        error: ActivationError?
    ) {
        var context: [String: String] = [
            "projectId": projectId,
            "warningsCount": String(warnings.count)
        ]
        if let workspaceName {
            context["workspace"] = workspaceName
        }
        if let error {
            context["error"] = error.message
        }
        _ = logger.log(event: "activation.result", level: level, message: nil, context: context)
    }
}

private struct DetectedWindow {
    let windowId: Int
    let workspaceName: String
}
