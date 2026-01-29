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
    private let logger: ProjectWorkspacesLogging
    private let sleeper: AeroSpaceSleeping
    private let pollIntervalMs: Int
    private let pollTimeoutMs: Int
    private let workspaceProbeTimeoutMs: Int
    private let focusedProbeTimeoutMs: Int

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
        pollTimeoutMs: Int = 5000,
        workspaceProbeTimeoutMs: Int = 800,
        focusedProbeTimeoutMs: Int = 1500,
        aeroSpaceTimeoutSeconds: TimeInterval = 2
    ) {
        precondition(pollIntervalMs > 0, "pollIntervalMs must be positive")
        precondition(pollTimeoutMs > 0, "pollTimeoutMs must be positive")
        precondition(workspaceProbeTimeoutMs > 0, "workspaceProbeTimeoutMs must be positive")
        precondition(focusedProbeTimeoutMs > 0, "focusedProbeTimeoutMs must be positive")
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
        self.logger = logger
        self.sleeper = SystemAeroSpaceSleeper()
        self.pollIntervalMs = pollIntervalMs
        self.pollTimeoutMs = pollTimeoutMs
        self.workspaceProbeTimeoutMs = workspaceProbeTimeoutMs
        self.focusedProbeTimeoutMs = focusedProbeTimeoutMs
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
        logger: ProjectWorkspacesLogging,
        sleeper: AeroSpaceSleeping,
        pollIntervalMs: Int,
        pollTimeoutMs: Int,
        workspaceProbeTimeoutMs: Int,
        focusedProbeTimeoutMs: Int
    ) {
        precondition(pollIntervalMs > 0, "pollIntervalMs must be positive")
        precondition(pollTimeoutMs > 0, "pollTimeoutMs must be positive")
        precondition(workspaceProbeTimeoutMs > 0, "workspaceProbeTimeoutMs must be positive")
        precondition(focusedProbeTimeoutMs > 0, "focusedProbeTimeoutMs must be positive")
        self.configLoader = configLoader
        self.aeroSpaceBinaryResolver = aeroSpaceBinaryResolver
        self.aeroSpaceCommandRunner = aeroSpaceCommandRunner
        self.aeroSpaceTimeoutSeconds = aeroSpaceTimeoutSeconds
        self.ideLauncher = ideLauncher
        self.chromeLauncherFactory = chromeLauncherFactory
        self.ideAppResolver = ideAppResolver
        self.logger = logger
        self.sleeper = sleeper
        self.pollIntervalMs = pollIntervalMs
        self.pollTimeoutMs = pollTimeoutMs
        self.workspaceProbeTimeoutMs = workspaceProbeTimeoutMs
        self.focusedProbeTimeoutMs = focusedProbeTimeoutMs
    }

    /// Activates the project workspace for the given project id.
    /// - Parameters:
    ///   - projectId: Project identifier to activate.
    ///   - focusIdeWindow: Whether to focus the IDE window at the end of activation.
    ///   - switchWorkspace: Whether to switch to the project workspace during activation.
    /// - Returns: Activation outcome with warnings or failure.
    public func activate(
        projectId: String,
        focusIdeWindow: Bool = true,
        switchWorkspace: Bool = true
    ) -> ActivationOutcome {
        let context = ActivationContext(
            projectId: projectId,
            shouldFocusIdeWindow: focusIdeWindow,
            shouldSwitchWorkspace: switchWorkspace
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
        // Step 1: Resolve AeroSpace binary
        guard let client = resolveAeroSpaceClient(context) else {
            return context.finalize(logger: logger)
        }

        let chromeLauncher = chromeLauncherFactory(client)

        // Step 2: Load and validate config
        guard let (config, project) = loadConfigAndProject(context) else {
            return context.finalize(logger: logger)
        }

        // Step 3: Switch to workspace (if enabled)
        if context.shouldSwitchWorkspace {
            guard switchToWorkspace(client: client, context: context) else {
                return context.finalize(logger: logger)
            }
        }

        // Step 4: Resolve IDE identity
        guard let ideIdentity = resolveIdeIdentity(project: project, ideConfig: config.ide, context: context) else {
            return context.finalize(logger: logger)
        }

        // Step 5: Ensure IDE window exists
        guard let ideWindowId = ensureIdeWindow(
            client: client,
            project: project,
            ideConfig: config.ide,
            ideIdentity: ideIdentity,
            context: context
        ) else {
            return context.finalize(logger: logger)
        }
        context.ideWindowId = ideWindowId

        // Step 6: Ensure Chrome window exists
        guard let chromeWindowId = ensureChromeWindow(
            client: client,
            chromeLauncher: chromeLauncher,
            project: project,
            globalChromeUrls: config.global.globalChromeUrls,
            ideWindowId: ideWindowId,
            context: context
        ) else {
            return context.finalize(logger: logger)
        }
        context.chromeWindowId = chromeWindowId

        // Step 7: Set floating layout for both windows
        guard setFloatingLayouts(client: client, ideWindowId: ideWindowId, chromeWindowId: chromeWindowId, context: context) else {
            return context.finalize(logger: logger)
        }

        // Step 8: Focus IDE window
        if context.shouldFocusIdeWindow {
            guard focusIdeWindow(client: client, ideWindowId: ideWindowId, context: context) else {
                return context.finalize(logger: logger)
            }
        }

        // Success
        let report = ActivationReport(
            projectId: context.projectId,
            workspaceName: context.workspaceName,
            ideWindowId: ideWindowId,
            chromeWindowId: chromeWindowId,
            ideBundleId: context.ideBundleId
        )
        context.outcome = .success(report: report, warnings: context.warnings)
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
    ) -> Int? {
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
    ) -> Int? {
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
            return selectedWindow.windowId
        }

        switch ideLauncher.launch(project: project, ideConfig: ideConfig) {
        case .failure(let error):
            context.outcome = .failure(error: .ideLaunchFailed(error))
            return nil
        case .success(let success):
            context.warnings.append(contentsOf: success.warnings.map { .ideLaunchWarning($0) })
        }

        return detectNewTokenIdeWindow(
            client: client,
            token: token,
            identity: ideIdentity,
            beforeIds: Set(existingMatches.map { $0.windowId }),
            context: context
        )
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
        let timeouts = launchDetectionTimeouts()
        let workspaceOutcome = pollForTokenIdeWindowInWorkspace(
            client: client,
            token: token,
            identity: identity,
            beforeIds: beforeIds,
            workspaceName: context.workspaceName,
            timeoutMs: timeouts.workspaceMs,
            context: context
        )

        switch workspaceOutcome {
        case .success(let window):
            return finalizeIdeWindow(window, client: client, context: context)
        case .failure(let error):
            context.outcome = .failure(error: error)
            return nil
        case .timedOut:
            break
        }

        let focusedPrimaryOutcome = pollForFocusedTokenIdeWindow(
            client: client,
            token: token,
            identity: identity,
            timeoutMs: timeouts.focusedPrimaryMs
        )

        switch focusedPrimaryOutcome {
        case .success(let window):
            return finalizeIdeWindow(window, client: client, context: context)
        case .failure(let error):
            context.outcome = .failure(error: error)
            return nil
        case .timedOut:
            break
        }

        if timeouts.focusedSecondaryMs > 0 {
            let focusedSecondaryOutcome = pollForFocusedTokenIdeWindow(
                client: client,
                token: token,
                identity: identity,
                timeoutMs: timeouts.focusedSecondaryMs
            )
            switch focusedSecondaryOutcome {
            case .success(let window):
                return finalizeIdeWindow(window, client: client, context: context)
            case .failure(let error):
                context.outcome = .failure(error: error)
                return nil
            case .timedOut:
                break
            }
        }

        if context.outcome == nil {
            context.outcome = .failure(error: .ideWindowTokenNotDetected(token: token.value))
        }
        return nil
    }

    private func pollForTokenIdeWindowInWorkspace(
        client: AeroSpaceClient,
        token: ProjectWindowToken,
        identity: IdeIdentity,
        beforeIds: Set<Int>,
        workspaceName: String,
        timeoutMs: Int,
        context: ActivationContext
    ) -> PollOutcome<AeroSpaceWindow, ActivationError> {
        guard timeoutMs > 0 else {
            return .timedOut
        }
        return Poller.poll(
            intervalMs: pollIntervalMs,
            timeoutMs: timeoutMs,
            sleeper: sleeper
        ) { () -> PollDecision<AeroSpaceWindow, ActivationError> in
            let appBundleId = identity.bundleId?.isEmpty == false ? identity.bundleId : nil
            switch client.listWindowsDecoded(
                workspace: workspaceName,
                appBundleId: appBundleId
            ) {
            case .failure(let error):
                if shouldRetryPoll(error) {
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
    }

    private func pollForFocusedTokenIdeWindow(
        client: AeroSpaceClient,
        token: ProjectWindowToken,
        identity: IdeIdentity,
        timeoutMs: Int
    ) -> PollOutcome<AeroSpaceWindow, ActivationError> {
        guard timeoutMs > 0 else {
            return .timedOut
        }
        return Poller.poll(
            intervalMs: pollIntervalMs,
            timeoutMs: timeoutMs,
            sleeper: sleeper
        ) { () -> PollDecision<AeroSpaceWindow, ActivationError> in
            switch client.listWindowsFocusedDecoded() {
            case .failure(let error):
                if shouldRetryFocusedWindow(error) {
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

    // MARK: - Step 7: Chrome Window

    private func ensureChromeWindow(
        client: AeroSpaceClient,
        chromeLauncher: ChromeLaunching,
        project: ProjectConfig,
        globalChromeUrls: [String],
        ideWindowId _: Int,
        context: ActivationContext
    ) -> Int? {
        let chromeResult = chromeLauncher.ensureWindow(
            expectedWorkspaceName: context.workspaceName,
            windowToken: context.windowToken,
            globalChromeUrls: globalChromeUrls,
            project: project,
            ideWindowIdToRefocus: nil,
            allowExistingWindows: true
        )

        switch chromeResult {
        case .failure(let error):
            context.outcome = .failure(error: .chromeLaunchFailed(error))
            return nil
        case .success(let result):
            if !result.warnings.isEmpty {
                let activationWarnings = result.warnings.map { warning in
                    switch warning {
                    case .multipleWindows(let workspace, let chosenId, let extraIds):
                        return ActivationWarning.multipleWindows(
                            kind: .chrome,
                            workspace: workspace,
                            chosenId: chosenId,
                            extraIds: extraIds
                        )
                    }
                }
                context.warnings.append(contentsOf: activationWarnings)
            }
            switch result.outcome {
            case .created(let windowId), .existing(let windowId):
                return windowId
            }
        }
    }

    // MARK: - Step 8: Floating Layout

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

    private func launchDetectionTimeouts() -> LaunchDetectionTimeouts {
        let overallTimeoutMs = pollTimeoutMs
        let workspaceMs = min(workspaceProbeTimeoutMs, max(1, overallTimeoutMs / 2))
        let remainingMs = max(0, overallTimeoutMs - workspaceMs)
        let focusedPrimaryMs = min(focusedProbeTimeoutMs, remainingMs)
        let focusedSecondaryMs = max(0, remainingMs - focusedPrimaryMs)
        return LaunchDetectionTimeouts(
            workspaceMs: workspaceMs,
            focusedPrimaryMs: focusedPrimaryMs,
            focusedSecondaryMs: focusedSecondaryMs
        )
    }

    private func shouldRetryPoll(_ error: AeroSpaceCommandError) -> Bool {
        switch error {
        case .timedOut, .notReady:
            return true
        case .launchFailed, .decodingFailed, .unexpectedOutput, .nonZeroExit:
            return false
        }
    }

    private func shouldRetryFocusedWindow(_ error: AeroSpaceCommandError) -> Bool {
        switch error {
        case .nonZeroExit(let command, _):
            return command.contains("list-windows --focused")
        case .unexpectedOutput(let command, _):
            return command.contains("list-windows --focused")
        case .timedOut, .notReady:
            return true
        case .launchFailed, .decodingFailed:
            return false
        }
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

private struct LaunchDetectionTimeouts {
    let workspaceMs: Int
    let focusedPrimaryMs: Int
    let focusedSecondaryMs: Int
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
        case .failure:
            outcomeLabel = "fail"
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

        return logger.log(
            event: "activation",
            level: outcomeLabel == "fail" ? .error : (outcomeLabel == "warn" ? .warn : .info),
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
