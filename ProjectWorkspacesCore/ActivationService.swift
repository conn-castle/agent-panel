import Foundation

/// Implements Activate(Project) behavior with no window hijacking.
public struct ActivationService {
    private let configLoader: ConfigLoader
    private let aeroSpaceBinaryResolver: AeroSpaceBinaryResolving
    private let aeroSpaceCommandRunner: AeroSpaceCommandRunning
    private let aeroSpaceTimeoutSeconds: TimeInterval
    private let ideLauncher: IdeLaunching
    private let chromeLauncherFactory: (AeroSpaceClient) -> ChromeLaunching
    private let ideAppResolver: IdeAppResolver
    private let layoutCoordinator: LayoutCoordinating
    private let logger: ProjectWorkspacesLogging
    private let sleeper: AeroSpaceSleeping
    private let windowDetectionConfiguration: WindowDetectionConfiguration

    /// Creates an activation service with default dependencies.
    /// - Parameters:
    ///   - paths: File system paths for ProjectWorkspaces.
    ///   - fileSystem: File system accessor.
    ///   - appDiscovery: Application discovery provider.
    ///   - commandRunner: Command runner used for IDE/Chrome launches and CLI resolution.
    ///   - aeroSpaceCommandRunner: Runner used for AeroSpace CLI commands.
    ///   - aeroSpaceBinaryResolver: Optional resolver for the AeroSpace CLI.
    ///   - logger: Logger for activation events.
    ///   - pollIntervalMs: Polling interval for IDE window detection.
    ///   - pollTimeoutMs: Polling timeout for IDE window detection.
    ///   - workspaceProbeTimeoutMs: Short workspace-only probe timeout after launch.
    ///   - focusedProbeTimeoutMs: Initial focused-window probe timeout after launch.
    ///   - aeroSpaceTimeoutSeconds: Timeout for individual AeroSpace commands.
    public init(
        paths: ProjectWorkspacesPaths = .defaultPaths(),
        fileSystem: FileSystem = DefaultFileSystem(),
        appDiscovery: AppDiscovering = LaunchServicesAppDiscovery(),
        commandRunner: CommandRunning = DefaultCommandRunner(),
        aeroSpaceCommandRunner: AeroSpaceCommandRunning = DefaultAeroSpaceCommandRunner(),
        aeroSpaceBinaryResolver: AeroSpaceBinaryResolving? = nil,
        logger: ProjectWorkspacesLogging = ProjectWorkspacesLogger(),
        pollIntervalMs: Int = 200,
        pollTimeoutMs: Int = 10000,
        workspaceProbeTimeoutMs: Int = 800,
        focusedProbeTimeoutMs: Int = 1000,
        aeroSpaceTimeoutSeconds: TimeInterval = 2
    ) {
        let detectionConfiguration = WindowDetectionConfiguration(
            pollIntervalMs: pollIntervalMs,
            pollTimeoutMs: pollTimeoutMs,
            workspaceProbeTimeoutMs: workspaceProbeTimeoutMs,
            focusedProbeTimeoutMs: focusedProbeTimeoutMs
        )
        self.configLoader = ConfigLoader(paths: paths, fileSystem: fileSystem)
        if let aeroSpaceBinaryResolver {
            self.aeroSpaceBinaryResolver = aeroSpaceBinaryResolver
        } else {
            self.aeroSpaceBinaryResolver = DefaultAeroSpaceBinaryResolver(
                fileSystem: fileSystem,
                commandRunner: commandRunner
            )
        }
        self.aeroSpaceCommandRunner = aeroSpaceCommandRunner
        self.aeroSpaceTimeoutSeconds = aeroSpaceTimeoutSeconds
        self.ideLauncher = IdeLauncher(
            paths: paths,
            fileSystem: fileSystem,
            commandRunner: commandRunner,
            environment: ProcessEnvironment(),
            appDiscovery: appDiscovery,
            permissions: DefaultFilePermissions(),
            logger: logger
        )
        self.chromeLauncherFactory = { client in
            ChromeLauncher(
                aeroSpaceClient: client,
                commandRunner: commandRunner,
                appDiscovery: appDiscovery
            )
        }
        self.ideAppResolver = IdeAppResolver(fileSystem: fileSystem, appDiscovery: appDiscovery)
        let resolvedStateStore = StateStore(paths: paths, fileSystem: fileSystem)
        let layoutEngine = LayoutEngine()
        let layoutObserver = LayoutObserver(stateStore: resolvedStateStore, layoutEngine: layoutEngine)
        self.layoutCoordinator = LayoutCoordinator(
            stateStore: resolvedStateStore,
            layoutEngine: layoutEngine,
            windowManager: AccessibilityWindowManager(),
            layoutObserver: layoutObserver,
            logger: logger
        )
        self.logger = logger
        self.sleeper = SystemAeroSpaceSleeper()
        self.windowDetectionConfiguration = detectionConfiguration
    }

    /// Internal initializer for tests.
    init(
        configLoader: ConfigLoader,
        aeroSpaceBinaryResolver: AeroSpaceBinaryResolving,
        aeroSpaceCommandRunner: AeroSpaceCommandRunning,
        aeroSpaceTimeoutSeconds: TimeInterval,
        ideLauncher: IdeLaunching,
        chromeLauncherFactory: @escaping (AeroSpaceClient) -> ChromeLaunching,
        ideAppResolver: IdeAppResolver,
        layoutCoordinator: LayoutCoordinating,
        logger: ProjectWorkspacesLogging,
        sleeper: AeroSpaceSleeping,
        pollIntervalMs: Int,
        pollTimeoutMs: Int,
        workspaceProbeTimeoutMs: Int,
        focusedProbeTimeoutMs: Int
    ) {
        let detectionConfiguration = WindowDetectionConfiguration(
            pollIntervalMs: pollIntervalMs,
            pollTimeoutMs: pollTimeoutMs,
            workspaceProbeTimeoutMs: workspaceProbeTimeoutMs,
            focusedProbeTimeoutMs: focusedProbeTimeoutMs
        )
        self.configLoader = configLoader
        self.aeroSpaceBinaryResolver = aeroSpaceBinaryResolver
        self.aeroSpaceCommandRunner = aeroSpaceCommandRunner
        self.aeroSpaceTimeoutSeconds = aeroSpaceTimeoutSeconds
        self.ideLauncher = ideLauncher
        self.chromeLauncherFactory = chromeLauncherFactory
        self.ideAppResolver = ideAppResolver
        self.layoutCoordinator = layoutCoordinator
        self.logger = logger
        self.sleeper = sleeper
        self.windowDetectionConfiguration = detectionConfiguration
    }

    /// Activates the project workspace for the given project id.
    /// - Parameters:
    ///   - projectId: Project identifier to activate.
    ///   - focusIdeWindow: Whether to focus the IDE window at the end of activation.
    ///   - switchWorkspace: Whether to switch to the project workspace during activation.
    ///   - progress: Optional progress sink for activation milestones.
    ///   - cancellationToken: Optional token used to cancel activation.
    /// - Returns: Activation outcome with warnings or failure.
    public func activate(
        projectId: String,
        focusIdeWindow: Bool = true,
        switchWorkspace: Bool = true,
        progress: ((ActivationProgress) -> Void)? = nil,
        cancellationToken: ActivationCancellationToken? = nil
    ) -> ActivationOutcome {
        let context = ActivationContext(
            projectId: projectId,
            shouldFocusIdeWindow: focusIdeWindow,
            shouldSwitchWorkspace: switchWorkspace,
            progressSink: progress,
            cancellationToken: cancellationToken
        )
        return runActivation(context)
    }

    /// Focuses the provided workspace and IDE window id after activation.
    /// - Parameter report: Activation report that includes workspace and IDE window information.
    /// - Returns: Success or a structured activation error.
    public func focusWorkspaceAndWindow(report: ActivationReport) -> Result<Void, ActivationError> {
        let commandLogs = CommandLogAccumulator()
        let clientResult = makeTracingClient(commandLogs: commandLogs)

        let focusResult: Result<Void, ActivationError>
        switch clientResult {
        case .failure(let error):
            focusResult = .failure(error)
        case .success(let client):
            switch client.switchWorkspace(report.workspaceName) {
            case .failure(let error):
                focusResult = .failure(.aeroSpaceFailed(error))
            case .success:
                switch client.focusWindow(windowId: report.ideWindowId) {
                case .failure(let error):
                    focusResult = .failure(.aeroSpaceFailed(error))
                case .success:
                    focusResult = .success(())
                }
            }
        }

        let outcomeLabel: String
        switch focusResult {
        case .success:
            outcomeLabel = "success"
        case .failure:
            outcomeLabel = "fail"
        }

        let logResult = logFocus(
            report: report,
            outcome: outcomeLabel,
            commandLogs: commandLogs.allLogs
        )
        if case .failure(let error) = logResult, case .success = focusResult {
            return .failure(.logWriteFailed(error))
        }

        return focusResult
    }

    // MARK: - Activation Orchestration

    /// Runs the activation pipeline and returns the final outcome.
    private func runActivation(_ context: ActivationContext) -> ActivationOutcome {
        layoutCoordinator.stopObserving()
        var state = ActivationState()
        let steps: [ActivationStep] = [
            ActivationStep(name: "resolve-aerospace") { context, state in
                guard context.ensureNotCancelled() else { return false }
                guard let client = resolveAeroSpaceClient(context) else { return false }
                state.client = client
                state.chromeLauncher = chromeLauncherFactory(client)
                return true
            },
            ActivationStep(name: "load-config") { context, state in
                guard context.ensureNotCancelled() else { return false }
                guard let (config, project) = loadConfigAndProject(context) else { return false }
                state.config = config
                state.project = project
                return true
            },
            ActivationStep(name: "switch-workspace") { context, state in
                guard context.ensureNotCancelled() else { return false }
                guard let client = state.client else {
                    preconditionFailure("ActivationState missing AeroSpace client")
                }
                if context.shouldSwitchWorkspace {
                    context.reportProgress(.switchingWorkspace(context.workspaceName))
                    guard switchToWorkspace(client: client, context: context) else { return false }
                    context.reportProgress(.switchedWorkspace(context.workspaceName))
                }
                return true
            },
            ActivationStep(name: "resolve-ide-identity") { context, state in
                guard context.ensureNotCancelled() else { return false }
                guard let config = state.config, let project = state.project else {
                    preconditionFailure("ActivationState missing config or project")
                }
                guard let ideIdentity = resolveIdeIdentity(project: project, ideConfig: config.ide, context: context) else {
                    return false
                }
                state.ideIdentity = ideIdentity
                return true
            },
            ActivationStep(name: "prepare-chrome") { context, state in
                guard context.ensureNotCancelled() else { return false }
                guard let config = state.config,
                      let project = state.project,
                      let chromeLauncher = state.chromeLauncher else {
                    preconditionFailure("ActivationState missing config, project, or chrome launcher")
                }
                context.reportProgress(.ensuringChrome)
                let chromeCheck = chromeLauncher.checkExistingWindow(
                    expectedWorkspaceName: context.workspaceName,
                    windowToken: context.windowToken,
                    allowExistingWindows: true
                )
                var chromeState = ChromeLaunchState()
                switch chromeCheck {
                case .found(let result):
                    switch result.outcome {
                    case .existing(let windowId), .created(let windowId):
                        chromeState.existingWindow = ActivatedWindow(windowId: windowId, wasCreated: false)
                    }
                    context.warnings.append(contentsOf: result.warnings.map { .chromeLaunchWarning($0) })
                case .notFound(let existingIds):
                    switch chromeLauncher.launchChrome(
                        expectedWorkspaceName: context.workspaceName,
                        windowToken: context.windowToken,
                        globalChromeUrls: config.global.globalChromeUrls,
                        project: project,
                        existingIds: existingIds,
                        ideWindowIdToRefocus: nil
                    ) {
                    case .success(let token):
                        chromeState.launchToken = token
                    case .failure(let error):
                        context.outcome = .failure(error: .chromeLaunchFailed(error))
                        return false
                    }
                case .error(let error):
                    context.outcome = .failure(error: .chromeLaunchFailed(error))
                    return false
                }
                state.chromeLaunchState = chromeState
                return true
            },
            ActivationStep(name: "ensure-ide") { context, state in
                guard context.ensureNotCancelled() else { return false }
                guard let client = state.client,
                      let project = state.project,
                      let config = state.config,
                      let ideIdentity = state.ideIdentity else {
                    preconditionFailure("ActivationState missing IDE prerequisites")
                }
                context.reportProgress(.ensuringIde)
                guard let ideWindow = ensureIdeWindow(
                    client: client,
                    project: project,
                    ideConfig: config.ide,
                    ideIdentity: ideIdentity,
                    context: context
                ) else {
                    return false
                }
                context.ideWindowId = ideWindow.windowId
                state.ideWindow = ideWindow
                return true
            },
            ActivationStep(name: "detect-chrome") { context, state in
                guard context.ensureNotCancelled() else { return false }
                guard let chromeState = state.chromeLaunchState,
                      let chromeLauncher = state.chromeLauncher else {
                    preconditionFailure("ActivationState missing Chrome launch state")
                }
                let chromeWindow: ActivatedWindow
                if let existing = chromeState.existingWindow {
                    chromeWindow = existing
                } else if let token = chromeState.launchToken {
                    context.reportProgress(.ensuringChrome)
                    var chromeWarnings: [ChromeLaunchWarning] = []
                    let detectResult = chromeLauncher.detectLaunchedWindow(
                        token: token,
                        cancellationToken: context.cancellationToken,
                        warningSink: { chromeWarnings.append($0) }
                    )
                    switch detectResult {
                    case .success(let result):
                        switch result.outcome {
                        case .existing(let windowId), .created(let windowId):
                            chromeWindow = ActivatedWindow(windowId: windowId, wasCreated: true)
                        }
                        context.warnings.append(contentsOf: chromeWarnings.map { .chromeLaunchWarning($0) })
                    case .failure(let error):
                        context.outcome = .failure(error: .chromeLaunchFailed(error))
                        return false
                    }
                } else {
                    context.outcome = .failure(error: .chromeLaunchFailed(.chromeNotFound))
                    return false
                }
                context.chromeWindowId = chromeWindow.windowId
                state.chromeWindow = chromeWindow
                return true
            },
            ActivationStep(name: "float-layouts") { context, state in
                guard context.ensureNotCancelled() else { return false }
                guard let client = state.client,
                      let ideWindow = state.ideWindow,
                      let chromeWindow = state.chromeWindow else {
                    preconditionFailure("ActivationState missing windows for floating layout")
                }
                return setFloatingLayouts(
                    client: client,
                    ideWindowId: ideWindow.windowId,
                    chromeWindowId: chromeWindow.windowId,
                    context: context
                )
            },
            ActivationStep(name: "apply-layout") { context, state in
                guard context.ensureNotCancelled() else { return false }
                guard let client = state.client,
                      let ideWindow = state.ideWindow,
                      let chromeWindow = state.chromeWindow,
                      let config = state.config,
                      let project = state.project else {
                    preconditionFailure("ActivationState missing layout prerequisites")
                }
                context.reportProgress(.applyingLayout)
                let layoutWarnings = layoutCoordinator.applyLayout(
                    projectId: project.id,
                    config: config,
                    ideWindow: ideWindow,
                    chromeWindow: chromeWindow,
                    client: client
                )
                if !layoutWarnings.isEmpty {
                    context.warnings.append(contentsOf: layoutWarnings)
                }
                return true
            },
            ActivationStep(name: "focus-ide") { context, state in
                guard context.ensureNotCancelled() else { return false }
                guard let client = state.client,
                      let ideWindow = state.ideWindow else {
                    preconditionFailure("ActivationState missing IDE window")
                }
                if context.shouldFocusIdeWindow {
                    context.reportProgress(.finishing)
                    guard focusIdeWindow(client: client, ideWindowId: ideWindow.windowId, context: context) else {
                        return false
                    }
                }
                return true
            },
            ActivationStep(name: "finalize") { context, state in
                guard let ideWindow = state.ideWindow,
                      let chromeWindow = state.chromeWindow else {
                    preconditionFailure("ActivationState missing windows for final report")
                }
                let report = ActivationReport(
                    projectId: context.projectId,
                    workspaceName: context.workspaceName,
                    ideWindowId: ideWindow.windowId,
                    chromeWindowId: chromeWindow.windowId,
                    ideBundleId: context.ideBundleId
                )
                context.outcome = .success(report: report, warnings: context.warnings)
                return true
            }
        ]

        for step in steps {
            if !step.run(context, &state) {
                return context.finalize(logger: logger)
            }
        }

        return context.finalize(logger: logger)
    }

    // MARK: - Step 1: AeroSpace Client Resolution

    private func resolveAeroSpaceClient(_ context: ActivationContext) -> AeroSpaceClient? {
        switch makeTracingClient(commandLogs: context.commandLogs) {
        case .failure(let error):
            context.outcome = .failure(error: error)
            return nil
        case .success(let client):
            return client
        }
    }

    private func makeTracingClient(
        commandLogs: CommandLogAccumulator
    ) -> Result<AeroSpaceClient, ActivationError> {
        switch aeroSpaceBinaryResolver.resolve() {
        case .failure(let error):
            return .failure(.aeroSpaceResolutionFailed(error))
        case .success(let executableURL):
            let tracingRunner = TracingAeroSpaceCommandRunner(
                wrapped: aeroSpaceCommandRunner,
                traceSink: { commandLogs.append($0) }
            )
            return .success(
                AeroSpaceClient(
                    executableURL: executableURL,
                    commandRunner: tracingRunner,
                    timeoutSeconds: aeroSpaceTimeoutSeconds
                )
            )
        }
    }

    private func logFocus(
        report: ActivationReport,
        outcome: String,
        commandLogs: [AeroSpaceCommandLog]
    ) -> Result<Void, LogWriteError> {
        let payload = ActivationFocusLogPayload(
            projectId: report.projectId,
            workspaceName: report.workspaceName,
            windowId: report.ideWindowId,
            outcome: outcome,
            aeroSpaceCommands: commandLogs
        )

        let encoder = JSONEncoder()
        let context: [String: String]
        do {
            let data = try encoder.encode(payload)
            let json = String(data: data, encoding: .utf8) ?? "{}"
            context = ["focus": json]
        } catch {
            context = ["focus": "{\"error\":\"Failed to encode focus log payload.\"}"]
        }

        return logger.log(
            event: "activation.focus",
            level: outcome == "fail" ? .error : .info,
            message: nil,
            context: context
        )
    }

    // MARK: - Step 2: Config Loading

    private func loadConfigAndProject(_ context: ActivationContext) -> (Config, ProjectConfig)? {
        let configOutcome = configLoader.load()

        switch configOutcome {
        case .failure(let findings):
            context.outcome = .failure(error: .configFailed(findings: findings))
            return nil
        case .success(let outcome, let configWarnings):
            guard let config = outcome.config else {
                context.outcome = .failure(error: .configFailed(findings: outcome.findings))
                return nil
            }
            context.warnings.append(contentsOf: configWarnings.map { .configWarning($0) })

            guard let project = config.projects.first(where: { $0.id == context.projectId }) else {
                context.outcome = .failure(
                    error: .projectNotFound(
                        projectId: context.projectId,
                        availableProjectIds: config.projects.map { $0.id }
                    )
                )
                return nil
            }
            return (config, project)
        }
    }

    // MARK: - Step 3: Workspace Switch

    private func switchToWorkspace(client: AeroSpaceClient, context: ActivationContext) -> Bool {
        switch client.switchWorkspace(context.workspaceName) {
        case .failure(let error):
            context.outcome = .failure(error: .aeroSpaceFailed(error))
            return false
        case .success:
            return true
        }
    }

    // MARK: - Step 5: IDE Identity Resolution

    private func resolveIdeIdentity(
        project: ProjectConfig,
        ideConfig: IdeConfig,
        context: ActivationContext
    ) -> IdeIdentity? {
        let resolutionResult = ideAppResolver.resolve(ide: project.ide, config: ideConfig.config(for: project.ide))
        switch resolutionResult {
        case .failure(let error):
            context.outcome = .failure(error: .ideLaunchFailed(.appResolutionFailed(ide: project.ide, error: error)))
            return nil
        case .success(let resolution):
            let appName = resolution.appURL.deletingPathExtension().lastPathComponent
            return IdeIdentity(bundleId: resolution.bundleId, appName: appName)
        }
    }

    // MARK: - Step 6: IDE Window

    private func ensureIdeWindow(
        client: AeroSpaceClient,
        project: ProjectConfig,
        ideConfig: IdeConfig,
        ideIdentity: IdeIdentity,
        context: ActivationContext
    ) -> ActivatedWindow? {
        guard context.ensureNotCancelled() else { return nil }
        context.ideBundleId = ideIdentity.bundleId
        return ensureTokenIdeWindow(
            client: client,
            project: project,
            ideConfig: ideConfig,
            ideIdentity: ideIdentity,
            context: context
        )
    }

    private func ensureTokenIdeWindow(
        client: AeroSpaceClient,
        project: ProjectConfig,
        ideConfig: IdeConfig,
        ideIdentity: IdeIdentity,
        context: ActivationContext
    ) -> ActivatedWindow? {
        let token = context.windowToken
        let existingMatchesResult = listTokenIdeWindows(
            client: client,
            token: token,
            identity: ideIdentity,
            workspace: context.workspaceName
        )
        let existingMatches: [AeroSpaceWindow]
        switch existingMatchesResult {
        case .failure(let error):
            context.outcome = .failure(error: error)
            return nil
        case .success(let matches):
            existingMatches = matches
        }

        if !existingMatches.isEmpty {
            let ids = existingMatches.map { $0.windowId }
            let selection = selectWindowId(
                from: ids,
                kind: .ide,
                workspace: context.workspaceName
            )
            if let warning = selection.warning {
                context.warnings.append(warning)
            }
            guard let selectedWindow = existingMatches.first(where: { $0.windowId == selection.selectedId }) else {
                context.outcome = .failure(error: .ideWindowTokenNotDetected(token: token.value))
                return nil
            }
            context.ideWindowLayout = selectedWindow.windowLayout
            if !moveWindowIfNeeded(
                client: client,
                windowId: selectedWindow.windowId,
                currentWorkspace: selectedWindow.workspace,
                targetWorkspace: context.workspaceName,
                context: context
            ) {
                return nil
            }
            return ActivatedWindow(windowId: selectedWindow.windowId, wasCreated: false)
        }

        switch ideLauncher.launch(project: project, ideConfig: ideConfig) {
        case .failure(let error):
            context.outcome = .failure(error: .ideLaunchFailed(error))
            return nil
        case .success(let success):
            context.warnings.append(contentsOf: success.warnings.map { .ideLaunchWarning($0) })
        }

        guard let newWindowId = detectNewTokenIdeWindow(
            client: client,
            token: token,
            identity: ideIdentity,
            beforeIds: Set(existingMatches.map { $0.windowId }),
            context: context
        ) else {
            return nil
        }

        return ActivatedWindow(windowId: newWindowId, wasCreated: true)
    }

    private func listTokenIdeWindows(
        client: AeroSpaceClient,
        token: ProjectWindowToken,
        identity: IdeIdentity,
        workspace: String
    ) -> Result<[AeroSpaceWindow], ActivationError> {
        let appBundleId = identity.bundleId?.isEmpty == false ? identity.bundleId : nil
        switch client.listWindowsDecoded(workspace: workspace, appBundleId: appBundleId) {
        case .failure(let error):
            return .failure(.aeroSpaceFailed(error))
        case .success(let windows):
            let matches = windows.filter { window in
                token.matches(windowTitle: window.windowTitle) && matchesIdentity(window, identity: identity)
            }
            return .success(matches)
        }
    }

    private func detectNewTokenIdeWindow(
        client: AeroSpaceClient,
        token: ProjectWindowToken,
        identity: IdeIdentity,
        beforeIds: Set<Int>,
        context: ActivationContext
    ) -> Int? {
        guard context.ensureNotCancelled() else { return nil }
        let timeouts = windowDetectionConfiguration.timeouts
        let pipeline = windowDetectionConfiguration.pipeline(sleeper: sleeper)
        let detectionOutcome: PollOutcome<AeroSpaceWindow, ActivationError> = pipeline.run(
            timeouts: timeouts,
            workspaceAttempt: {
                self.attemptTokenIdeWindowInWorkspace(
                    client: client,
                    token: token,
                    identity: identity,
                    beforeIds: beforeIds,
                    workspaceName: context.workspaceName,
                    context: context
                )
            },
            focusedAttempt: {
                self.attemptFocusedTokenIdeWindow(
                    client: client,
                    token: token,
                    identity: identity,
                    context: context
                )
            }
        )

        switch detectionOutcome {
        case .success(let window):
            return finalizeIdeWindow(window, client: client, context: context)
        case .failure(let error):
            context.outcome = .failure(error: error)
            return nil
        case .timedOut:
            break
        }

        if context.outcome == nil {
            context.outcome = .failure(error: .ideWindowTokenNotDetected(token: token.value))
        }
        return nil
    }

    private func attemptTokenIdeWindowInWorkspace(
        client: AeroSpaceClient,
        token: ProjectWindowToken,
        identity: IdeIdentity,
        beforeIds: Set<Int>,
        workspaceName: String,
        context: ActivationContext
    ) -> PollDecision<AeroSpaceWindow, ActivationError> {
        if context.isCancelled {
            return .failure(.cancelled)
        }
        let appBundleId = identity.bundleId?.isEmpty == false ? identity.bundleId : nil
        switch client.listWindowsDecodedNoRetry(
            workspace: workspaceName,
            appBundleId: appBundleId
        ) {
        case .failure(let error):
            if WindowDetectionRetryPolicy.shouldRetryPoll(error) {
                return .keepWaiting
            }
            return .failure(.aeroSpaceFailed(error))
        case .success(let windows):
            let matches = windows.filter { window in
                token.matches(windowTitle: window.windowTitle) && matchesIdentity(window, identity: identity)
            }
            let newMatches = matches.filter { !beforeIds.contains($0.windowId) }
            if newMatches.count == 1, let window = newMatches.first {
                return .success(window)
            }
            if newMatches.count > 1 {
                let ids = newMatches.map { $0.windowId }
                let selection = selectWindowId(
                    from: ids,
                    kind: .ide,
                    workspace: workspaceName
                )
                if let warning = selection.warning {
                    context.warnings.append(warning)
                }
                let selected = newMatches.sorted { $0.windowId < $1.windowId }[0]
                return .success(selected)
            }
            return .keepWaiting
        }
    }

    private func attemptFocusedTokenIdeWindow(
        client: AeroSpaceClient,
        token: ProjectWindowToken,
        identity: IdeIdentity,
        context: ActivationContext
    ) -> PollDecision<AeroSpaceWindow, ActivationError> {
        if context.isCancelled {
            return .failure(.cancelled)
        }
        switch client.listWindowsFocusedDecodedNoRetry() {
        case .failure(let error):
            if WindowDetectionRetryPolicy.shouldRetryFocusedWindow(error) {
                return .keepWaiting
            }
            return .failure(.aeroSpaceFailed(error))
        case .success(let windows):
            guard let window = windows.first else {
                return .keepWaiting
            }
            guard token.matches(windowTitle: window.windowTitle),
                  matchesIdentity(window, identity: identity) else {
                return .keepWaiting
            }
            return .success(window)
        }
    }

    private func finalizeIdeWindow(
        _ window: AeroSpaceWindow,
        client: AeroSpaceClient,
        context: ActivationContext
    ) -> Int? {
        context.ideWindowLayout = window.windowLayout
        if !moveWindowIfNeeded(
            client: client,
            windowId: window.windowId,
            currentWorkspace: window.workspace,
            targetWorkspace: context.workspaceName,
            context: context
        ) {
            return nil
        }
        return window.windowId
    }

    // MARK: - Step 7: Floating Layout

    private func setFloatingLayouts(
        client: AeroSpaceClient,
        ideWindowId: Int,
        chromeWindowId: Int,
        context: ActivationContext
    ) -> Bool {
        ensureFloatingLayout(
            client: client,
            windowId: ideWindowId,
            kind: .ide,
            workspaceName: context.workspaceName,
            appBundleId: context.ideBundleId,
            currentLayout: context.ideWindowLayout,
            context: context
        )
        ensureFloatingLayout(
            client: client,
            windowId: chromeWindowId,
            kind: .chrome,
            workspaceName: context.workspaceName,
            appBundleId: ChromeLauncher.chromeBundleId,
            currentLayout: context.chromeWindowLayout,
            context: context
        )
        return true
    }

    // MARK: - Step 9: Focus IDE

    private func focusIdeWindow(client: AeroSpaceClient, ideWindowId: Int, context: ActivationContext) -> Bool {
        switch client.focusWindow(windowId: ideWindowId) {
        case .failure(let error):
            context.outcome = .failure(error: .aeroSpaceFailed(error))
            return false
        case .success:
            return true
        }
    }

    // MARK: - Helpers

    private func matchesIdentity(_ window: AeroSpaceWindow, identity: IdeIdentity) -> Bool {
        if let bundleId = identity.bundleId, !bundleId.isEmpty {
            return window.appBundleId == bundleId
        }
        return window.appName == identity.appName
    }

    private func moveWindowIfNeeded(
        client: AeroSpaceClient,
        windowId: Int,
        currentWorkspace: String,
        targetWorkspace: String,
        context: ActivationContext
    ) -> Bool {
        guard currentWorkspace != targetWorkspace else {
            return true
        }
        switch client.moveWindow(windowId: windowId, to: targetWorkspace) {
        case .success:
            return true
        case .failure(let error):
            context.outcome = .failure(error: .aeroSpaceFailed(error))
            return false
        }
    }

    /// Ensures a window uses floating layout, warning only if the layout remains non-floating.
    private func ensureFloatingLayout(
        client: AeroSpaceClient,
        windowId: Int,
        kind: ActivationWindowKind,
        workspaceName: String,
        appBundleId: String?,
        currentLayout: String?,
        context: ActivationContext
    ) {
        let initialLayout = currentLayout ?? lookupWindowLayout(
            client: client,
            windowId: windowId,
            workspaceName: workspaceName,
            appBundleId: appBundleId
        )
        if let layout = initialLayout, isFloatingLayout(layout) {
            return
        }

        let layoutOutcome = client.setFloatingLayout(windowId: windowId)
        switch layoutOutcome {
        case .success:
            return
        case .failure(let error):
            let updatedLayout = lookupWindowLayout(
                client: client,
                windowId: windowId,
                workspaceName: workspaceName,
                appBundleId: appBundleId
            )
            if let layout = updatedLayout, isFloatingLayout(layout) {
                return
            }
            context.warnings.append(.layoutFailed(kind: kind, windowId: windowId, error: error))
        }
    }

    /// Looks up the layout string for a specific window id in a workspace.
    private func lookupWindowLayout(
        client: AeroSpaceClient,
        windowId: Int,
        workspaceName: String,
        appBundleId: String?
    ) -> String? {
        switch client.listWindowsDecoded(workspace: workspaceName, appBundleId: appBundleId) {
        case .failure:
            return nil
        case .success(let windows):
            return windows.first(where: { $0.windowId == windowId })?.windowLayout
        }
    }

    private func isFloatingLayout(_ layout: String) -> Bool {
        layout.lowercased() == "floating"
    }

    /// Selects the lowest window id and emits a multiple-windows warning when needed.
    /// - Parameters:
    ///   - windowIds: Window IDs to consider (must be non-empty).
    ///   - kind: Window kind for warning context.
    ///   - workspace: Workspace name for warning context.
    /// - Returns: Selected window id with an optional warning.
    private func selectWindowId(
        from windowIds: [Int],
        kind: ActivationWindowKind,
        workspace: String
    ) -> (selectedId: Int, warning: ActivationWarning?) {
        precondition(!windowIds.isEmpty, "windowIds must not be empty")
        let sortedIds = windowIds.sorted()
        let selectedId = sortedIds[0]
        let warningValue = sortedIds.count > 1
            ? ActivationWarning.multipleWindows(
                kind: kind,
                workspace: workspace,
                chosenId: selectedId,
                extraIds: Array(sortedIds.dropFirst())
            )
            : nil
        return (selectedId, warningValue)
    }
}

// MARK: - Internal Types

private struct ActivationStep {
    let name: String
    let run: (ActivationContext, inout ActivationState) -> Bool
}

private struct ChromeLaunchState {
    var existingWindow: ActivatedWindow?
    var launchToken: ChromeLauncher.ChromeLaunchToken?
}

private struct ActivationState {
    var client: AeroSpaceClient?
    var chromeLauncher: ChromeLaunching?
    var config: Config?
    var project: ProjectConfig?
    var ideIdentity: IdeIdentity?
    var chromeLaunchState: ChromeLaunchState?
    var ideWindow: ActivatedWindow?
    var chromeWindow: ActivatedWindow?
}

private struct IdeIdentity: Equatable, Sendable {
    let bundleId: String?
    let appName: String
}

/// Mutable activation state passed through orchestration steps.
/// Uses a class for commandLogs to allow capture in escaping closures.
private final class ActivationContext {
    let projectId: String
    let workspaceName: String
    let shouldFocusIdeWindow: Bool
    let shouldSwitchWorkspace: Bool
    let progressSink: ((ActivationProgress) -> Void)?
    let cancellationToken: ActivationCancellationToken?
    var windowToken: ProjectWindowToken {
        ProjectWindowToken(projectId: projectId)
    }
    var warnings: [ActivationWarning] = []
    let commandLogs: CommandLogAccumulator = CommandLogAccumulator()
    var ideWindowId: Int?
    var chromeWindowId: Int?
    var ideWindowLayout: String?
    var chromeWindowLayout: String?
    var ideBundleId: String?
    var outcome: ActivationOutcome?

    init(projectId: String, shouldFocusIdeWindow: Bool, shouldSwitchWorkspace: Bool) {
        self.projectId = projectId
        self.workspaceName = "pw-\(projectId)"
        self.shouldFocusIdeWindow = shouldFocusIdeWindow
        self.shouldSwitchWorkspace = shouldSwitchWorkspace
        self.progressSink = nil
        self.cancellationToken = nil
    }

    init(
        projectId: String,
        shouldFocusIdeWindow: Bool,
        shouldSwitchWorkspace: Bool,
        progressSink: ((ActivationProgress) -> Void)?,
        cancellationToken: ActivationCancellationToken?
    ) {
        self.projectId = projectId
        self.workspaceName = "pw-\(projectId)"
        self.shouldFocusIdeWindow = shouldFocusIdeWindow
        self.shouldSwitchWorkspace = shouldSwitchWorkspace
        self.progressSink = progressSink
        self.cancellationToken = cancellationToken
    }
}

/// Thread-safe accumulator for command logs that can be captured in escaping closures.
private final class CommandLogAccumulator {
    private var logs: [AeroSpaceCommandLog] = []
    private let lock = NSLock()

    func append(_ log: AeroSpaceCommandLog) {
        lock.lock()
        logs.append(log)
        lock.unlock()
    }

    var allLogs: [AeroSpaceCommandLog] {
        lock.lock()
        let snapshot = logs
        lock.unlock()
        return snapshot
    }
}

extension ActivationContext {
    var isCancelled: Bool {
        cancellationToken?.isCancelled ?? false
    }

    /// Returns false and records a cancelled outcome if cancellation was requested.
    func ensureNotCancelled() -> Bool {
        if isCancelled {
            outcome = .failure(error: .cancelled)
            return false
        }
        return true
    }

    func reportProgress(_ progress: ActivationProgress) {
        progressSink?(progress)
    }

    /// Logs and returns the final activation outcome.
    func finalize(logger: ProjectWorkspacesLogging) -> ActivationOutcome {
        guard let outcome = outcome else {
            preconditionFailure("ActivationContext.finalize called without setting outcome")
        }

        let logResult = logActivation(logger: logger)
        if case .failure(let error) = logResult {
            if case .success = outcome {
                return .failure(error: .logWriteFailed(error))
            }
        }
        return outcome
    }

    private func logActivation(logger: ProjectWorkspacesLogging) -> Result<Void, LogWriteError> {
        guard let outcome = outcome else {
            return .success(())
        }

        let outcomeLabel: String
        switch outcome {
        case .success(_, let warnings):
            outcomeLabel = warnings.isEmpty ? "success" : "warn"
        case .failure(let error):
            if case .cancelled = error {
                outcomeLabel = "cancelled"
            } else {
                outcomeLabel = "fail"
            }
        }

        let payload = ActivationLogPayload(
            projectId: projectId,
            workspaceName: workspaceName,
            outcome: outcomeLabel,
            ideWindowId: ideWindowId,
            chromeWindowId: chromeWindowId,
            warnings: warnings.map { $0.logSummary() },
            aeroSpaceCommands: commandLogs.allLogs
        )

        let encoder = JSONEncoder()
        let context: [String: String]
        do {
            let data = try encoder.encode(payload)
            let json = String(data: data, encoding: .utf8) ?? "{}"
            context = ["activation": json]
        } catch {
            context = ["activation": "{\"error\":\"Failed to encode activation log payload.\"}"]
        }

        let level: LogLevel
        switch outcomeLabel {
        case "fail":
            level = .error
        case "warn", "cancelled":
            level = .warn
        default:
            level = .info
        }

        return logger.log(
            event: "activation",
            level: level,
            message: nil,
            context: context
        )
    }
}

private extension IdeConfig {
    func config(for ide: IdeKind) -> IdeAppConfig? {
        switch ide {
        case .vscode:
            return vscode
        case .antigravity:
            return antigravity
        }
    }
}
