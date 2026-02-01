import Foundation

/// Implements Activate(Project) behavior using AeroSpace CLI only.
public struct ActivationService {
    private let configLoader: ConfigLoader
    private let aeroSpaceBinaryResolver: AeroSpaceBinaryResolving
    private let aeroSpaceCommandRunner: AeroSpaceCommandRunning
    private let aeroSpaceTimeoutSeconds: TimeInterval
    private let commandRunner: CommandRunning
    private let ideAppResolver: IdeAppResolver
    private let appDiscovery: AppDiscovering
    private let workspaceGenerator: VSCodeWorkspaceGenerator
    private let stateStore: StateStoring
    private let screenMetricsProvider: ScreenMetricsProviding
    private let logger: ProjectWorkspacesLogging
    private let sleeper: AeroSpaceSleeping
    private let clock: DateProviding
    private let focusTiming: WorkspaceFocusTiming
    private let windowDetectionTiming: WindowDetectionTiming

    /// Creates an activation service with default dependencies.
    /// - Parameters:
    ///   - paths: File system paths for ProjectWorkspaces.
    ///   - fileSystem: File system accessor.
    ///   - appDiscovery: Application discovery provider.
    ///   - aeroSpaceCommandRunner: Serialized runner used for AeroSpace CLI commands.
    ///   - aeroSpaceBinaryResolver: Optional resolver for the AeroSpace CLI.
    ///   - screenMetricsProvider: Provider for visible screen width.
    ///   - logger: Logger for activation events.
    ///   - aeroSpaceTimeoutSeconds: Timeout for individual AeroSpace commands.
    public init(
        paths: ProjectWorkspacesPaths = .defaultPaths(),
        fileSystem: FileSystem = DefaultFileSystem(),
        appDiscovery: AppDiscovering = LaunchServicesAppDiscovery(),
        commandRunner: CommandRunning = DefaultCommandRunner(),
        aeroSpaceCommandRunner: AeroSpaceCommandRunning = AeroSpaceCommandExecutor.shared,
        aeroSpaceBinaryResolver: AeroSpaceBinaryResolving? = nil,
        screenMetricsProvider: ScreenMetricsProviding,
        logger: ProjectWorkspacesLogging = ProjectWorkspacesLogger(),
        aeroSpaceTimeoutSeconds: TimeInterval = 2
    ) {
        self.configLoader = ConfigLoader(paths: paths, fileSystem: fileSystem)
        if let aeroSpaceBinaryResolver {
            self.aeroSpaceBinaryResolver = aeroSpaceBinaryResolver
        } else {
            self.aeroSpaceBinaryResolver = DefaultAeroSpaceBinaryResolver(
                fileSystem: fileSystem,
                commandRunner: DefaultCommandRunner()
            )
        }
        self.aeroSpaceCommandRunner = aeroSpaceCommandRunner
        self.aeroSpaceTimeoutSeconds = aeroSpaceTimeoutSeconds
        self.commandRunner = commandRunner
        self.appDiscovery = appDiscovery
        self.ideAppResolver = IdeAppResolver(fileSystem: fileSystem, appDiscovery: appDiscovery)
        self.workspaceGenerator = VSCodeWorkspaceGenerator(paths: paths, fileSystem: fileSystem)
        self.stateStore = StateStore(paths: paths, fileSystem: fileSystem)
        self.screenMetricsProvider = screenMetricsProvider
        self.logger = logger
        self.sleeper = SystemAeroSpaceSleeper()
        self.clock = SystemDateProvider()
        self.focusTiming = .fixed
        self.windowDetectionTiming = .standard
    }

    /// Internal initializer for tests.
    init(
        configLoader: ConfigLoader,
        aeroSpaceBinaryResolver: AeroSpaceBinaryResolving,
        aeroSpaceCommandRunner: AeroSpaceCommandRunning,
        aeroSpaceTimeoutSeconds: TimeInterval,
        commandRunner: CommandRunning,
        ideAppResolver: IdeAppResolver,
        appDiscovery: AppDiscovering,
        workspaceGenerator: VSCodeWorkspaceGenerator,
        stateStore: StateStoring,
        screenMetricsProvider: ScreenMetricsProviding,
        logger: ProjectWorkspacesLogging,
        sleeper: AeroSpaceSleeping,
        clock: DateProviding,
        focusTiming: WorkspaceFocusTiming,
        windowDetectionTiming: WindowDetectionTiming
    ) {
        self.configLoader = configLoader
        self.aeroSpaceBinaryResolver = aeroSpaceBinaryResolver
        self.aeroSpaceCommandRunner = aeroSpaceCommandRunner
        self.aeroSpaceTimeoutSeconds = aeroSpaceTimeoutSeconds
        self.commandRunner = commandRunner
        self.ideAppResolver = ideAppResolver
        self.appDiscovery = appDiscovery
        self.workspaceGenerator = workspaceGenerator
        self.stateStore = stateStore
        self.screenMetricsProvider = screenMetricsProvider
        self.logger = logger
        self.sleeper = sleeper
        self.clock = clock
        self.focusTiming = focusTiming
        self.windowDetectionTiming = windowDetectionTiming
    }

    /// Activates the project workspace for the given project id.
    /// - Parameters:
    ///   - projectId: Project identifier to activate.
    ///   - focusIdeWindow: Whether to focus the IDE window at the end of activation.
    ///   - switchWorkspace: Whether to switch to the project workspace during activation.
    ///   - progress: Optional progress sink for activation milestones.
    ///   - cancellationToken: Optional token used to cancel activation.
    /// - Returns: Activation outcome.
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
            let switchArgs = ["summon-workspace", report.workspaceName]
            switch client.summonWorkspace(report.workspaceName) {
            case .failure(let error):
                focusResult = .failure(
                    commandFailed(
                        command: client.executableURL.path,
                        arguments: switchArgs,
                        error: error
                    )
                )
            case .success:
                let focusArgs = ["focus", "--window-id", String(report.ideWindowId)]
                switch client.focusWindow(windowId: report.ideWindowId) {
                case .failure(let error):
                    focusResult = .failure(
                        commandFailed(
                            command: client.executableURL.path,
                            arguments: focusArgs,
                            error: error
                        )
                    )
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
        guard context.ensureNotCancelled() else {
            return context.finalize(logger: logger)
        }

        guard let client = resolveAeroSpaceClient(context) else {
            return context.finalize(logger: logger)
        }

        if !ensureAeroSpaceCompatibility(client: client, context: context) {
            return context.finalize(logger: logger)
        }

        guard let (config, project) = loadConfigAndProject(context) else {
            return context.finalize(logger: logger)
        }

        guard let ideIdentity = resolveIdeIdentity(project: project, ideConfig: config.ide, context: context) else {
            return context.finalize(logger: logger)
        }

        let ideBundleId = ideIdentity.bundleId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if ideBundleId.isEmpty {
            context.outcome = .failure(
                error: .commandFailed(
                    command: "ide.resolve",
                    arguments: [],
                    exitCode: nil,
                    stderr: "",
                    detail: "IDE bundle identifier is missing."
                )
            )
            return context.finalize(logger: logger)
        }
        let chromeBundleId = ChromeApp.bundleId

        if context.shouldSwitchWorkspace {
            context.reportProgress(.switchingWorkspace(context.workspaceName))
            if !switchWorkspaceAndConfirm(client: client, context: context) {
                return context.finalize(logger: logger)
            }
        }

        guard var bindingState = loadBindingState(context) else {
            return context.finalize(logger: logger)
        }

        var projectBindings = bindingState.projects[project.id] ?? ProjectBindings()

        guard let allWindows = listAllWindows(client: client, context: context) else {
            return context.finalize(logger: logger)
        }
        var windowMap = Dictionary(uniqueKeysWithValues: allWindows.map { ($0.windowId, $0) })

        let prunedBindings = pruneBindings(projectBindings, windowMap: windowMap)
        projectBindings = normalizeBindings(prunedBindings)

        let hadBoundWindowInWorkspace = hasBoundWindowInWorkspace(
            bindings: projectBindings,
            windowMap: windowMap,
            workspaceName: context.workspaceName
        )

        context.reportProgress(.movingWindows)
        if !moveBoundWindows(
            bindings: projectBindings,
            windowMap: &windowMap,
            workspaceName: context.workspaceName,
            client: client,
            context: context
        ) {
            return context.finalize(logger: logger)
        }

        context.reportProgress(.resolvingWindows)
        if projectBindings.ideBindings.isEmpty {
            guard let newIdeWindow = launchIdeWindow(
                client: client,
                project: project,
                ideIdentity: ideIdentity,
                beforeWindowIds: Set(windowMap.keys),
                context: context
            ) else {
                return context.finalize(logger: logger)
            }
            let binding = WindowBinding(
                windowId: newIdeWindow.windowId,
                appBundleId: ideBundleId,
                role: .ide,
                titleAtBindTime: newIdeWindow.windowTitle
            )
            projectBindings.ideBindings.insert(binding, at: 0)
            windowMap[newIdeWindow.windowId] = newIdeWindow
        }

        if projectBindings.chromeBindings.isEmpty {
            guard let newChromeWindow = launchChromeWindow(
                client: client,
                project: project,
                globalChromeUrls: config.global.globalChromeUrls,
                beforeWindowIds: Set(windowMap.keys),
                context: context
            ) else {
                return context.finalize(logger: logger)
            }
            let binding = WindowBinding(
                windowId: newChromeWindow.windowId,
                appBundleId: chromeBundleId,
                role: .chrome,
                titleAtBindTime: newChromeWindow.windowTitle
            )
            projectBindings.chromeBindings.insert(binding, at: 0)
            windowMap[newChromeWindow.windowId] = newChromeWindow
        }

        if !moveBoundWindows(
            bindings: projectBindings,
            windowMap: &windowMap,
            workspaceName: context.workspaceName,
            client: client,
            context: context
        ) {
            return context.finalize(logger: logger)
        }

        if !confirmWorkspaceFocusedAfterMove(client: client, context: context) {
            return context.finalize(logger: logger)
        }

        guard let primaryIdeId = projectBindings.ideBindings.first?.windowId,
              let primaryChromeId = projectBindings.chromeBindings.first?.windowId else {
            context.outcome = .failure(error: .requiredWindowMissing(appBundleId: ideBundleId))
            return context.finalize(logger: logger)
        }

        context.ideWindowId = primaryIdeId
        context.chromeWindowId = primaryChromeId
        context.ideBundleId = ideBundleId

        if !hadBoundWindowInWorkspace {
            guard let ideWindow = windowMap[primaryIdeId] else {
                context.outcome = .failure(error: .requiredWindowMissing(appBundleId: ideBundleId))
                return context.finalize(logger: logger)
            }
            context.reportProgress(.applyingLayout)
            if !applyCanonicalLayout(
                workspace: context.workspaceName,
                ideWindowId: ideWindow.windowId,
                client: client,
                context: context
            ) {
                return context.finalize(logger: logger)
            }

            context.reportProgress(.resizingIde)
            if !resizeIdeWindow(
                ideWindow: ideWindow,
                client: client,
                context: context
            ) {
                return context.finalize(logger: logger)
            }
        }

        if context.shouldFocusIdeWindow {
            context.reportProgress(.focusingIde)
            if !focusIdeWindow(client: client, ideWindowId: primaryIdeId, context: context) {
                return context.finalize(logger: logger)
            }
        }

        bindingState.projects[project.id] = projectBindings
        if !saveBindingState(bindingState, context: context) {
            return context.finalize(logger: logger)
        }

        context.reportProgress(.finishing)
        let report = ActivationReport(
            projectId: context.projectId,
            workspaceName: context.workspaceName,
            ideWindowId: primaryIdeId,
            chromeWindowId: primaryChromeId,
            ideBundleId: ideBundleId
        )
        context.outcome = .success(report: report)
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
        case .success(let outcome, _):
            guard let config = outcome.config else {
                context.outcome = .failure(error: .configFailed(findings: outcome.findings))
                return nil
            }

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

    // MARK: - Step 3: Compatibility Gate

    /// Ensures the installed AeroSpace CLI supports the required commands.
    /// - Parameters:
    ///   - client: Resolved AeroSpace client.
    ///   - context: Activation context for failure reporting.
    /// - Returns: True when compatibility checks succeed.
    private func ensureAeroSpaceCompatibility(
        client: AeroSpaceClient,
        context: ActivationContext
    ) -> Bool {
        let tracingRunner = TracingAeroSpaceCommandRunner(
            wrapped: aeroSpaceCommandRunner,
            traceSink: { context.commandLogs.append($0) }
        )

        let checks: [[String]] = [
            ["list-workspaces", "--focused"],
            ["list-windows", "--all", "--json"],
            ["focus", "--help"],
            ["move-node-to-workspace", "--help"],
            ["summon-workspace", "--help"]
        ]

        for arguments in checks {
            let commandLabel = ([client.executableURL.path] + arguments).joined(separator: " ")
            let result = tracingRunner.run(
                executable: client.executableURL,
                arguments: arguments,
                timeoutSeconds: aeroSpaceTimeoutSeconds
            )
            if case .failure(let error) = result {
                let details = commandFailureDetails(from: error)
                let stderr = details.stderr.isEmpty ? (details.detail ?? "") : details.stderr
                context.outcome = .failure(
                    error: .aeroSpaceIncompatible(
                        failingCommand: commandLabel,
                        stderr: stderr
                    )
                )
                return false
            }
        }

        return true
    }

    // MARK: - Step 4: State Loading

    /// Loads the persisted binding state or returns a failure outcome.
    /// - Parameter context: Activation context for failure reporting.
    /// - Returns: Loaded state when successful.
    private func loadBindingState(_ context: ActivationContext) -> BindingState? {
        switch stateStore.load() {
        case .failure(let error):
            context.outcome = .failure(error: .stateLoadFailed(detail: String(describing: error)))
            return nil
        case .success(let outcome):
            switch outcome {
            case .missing:
                return BindingState.empty()
            case .loaded(let state):
                return state
            case .recovered(let state, let backupPath):
                _ = logger.log(
                    event: "activation.state.recovered",
                    level: .warn,
                    message: "Recovered corrupt state file",
                    context: ["backup_path": backupPath]
                )
                return state
            }
        }
    }

    /// Saves binding state and records a failure outcome on error.
    /// - Parameters:
    ///   - state: State payload to persist.
    ///   - context: Activation context for failure reporting.
    /// - Returns: True when the save succeeds.
    private func saveBindingState(_ state: BindingState, context: ActivationContext) -> Bool {
        switch stateStore.save(state) {
        case .success:
            return true
        case .failure(let error):
            context.outcome = .failure(error: .stateSaveFailed(detail: String(describing: error)))
            return false
        }
    }

    // MARK: - Step 5: Workspace Switch

    private func switchWorkspaceAndConfirm(client: AeroSpaceClient, context: ActivationContext) -> Bool {
        let switchArgs = ["summon-workspace", context.workspaceName]
        switch client.summonWorkspace(context.workspaceName) {
        case .failure(let error):
            context.outcome = .failure(error: commandFailed(command: client.executableURL.path, arguments: switchArgs, error: error))
            return false
        case .success:
            context.reportProgress(.confirmingWorkspace(context.workspaceName))
            return confirmWorkspaceFocused(client: client, context: context)
        }
    }

    private func confirmWorkspaceFocused(client: AeroSpaceClient, context: ActivationContext) -> Bool {
        let startTime = clock.now()
        var lastFocused = ""
        var didReissue = false

        while true {
            if context.isCancelled {
                context.outcome = .failure(error: .cancelled)
                return false
            }

            let elapsedMs = Int(clock.now().timeIntervalSince(startTime) * 1000)
            if elapsedMs >= focusTiming.deadlineMs {
                context.outcome = .failure(
                    error: .workspaceNotFocused(
                        expected: context.workspaceName,
                        observed: lastFocused,
                        elapsedMs: elapsedMs
                    )
                )
                return false
            }

            switch client.focusedWorkspace() {
            case .failure(let error):
                let args = ["list-workspaces", "--focused", "--format", "%{workspace}"]
                context.outcome = .failure(error: commandFailed(command: client.executableURL.path, arguments: args, error: error))
                return false
            case .success(let focused):
                lastFocused = focused
                if focused == context.workspaceName {
                    return true
                }
            }

            if !didReissue, elapsedMs >= focusTiming.reissueSwitchAfterMs {
                didReissue = true
                _ = client.summonWorkspace(context.workspaceName)
            }

            sleeper.sleep(seconds: TimeInterval(focusTiming.pollIntervalMs) / 1000.0)
        }
    }

    private func confirmWorkspaceFocusedAfterMove(client: AeroSpaceClient, context: ActivationContext) -> Bool {
        let startTime = clock.now()
        var lastFocused = ""

        while true {
            if context.isCancelled {
                context.outcome = .failure(error: .cancelled)
                return false
            }

            let elapsedMs = Int(clock.now().timeIntervalSince(startTime) * 1000)
            if elapsedMs >= focusTiming.postMoveDeadlineMs {
                context.outcome = .failure(
                    error: .workspaceNotFocusedAfterMove(
                        expected: context.workspaceName,
                        observed: lastFocused,
                        elapsedMs: elapsedMs
                    )
                )
                return false
            }

            switch client.focusedWorkspace() {
            case .failure(let error):
                let args = ["list-workspaces", "--focused", "--format", "%{workspace}"]
                context.outcome = .failure(error: commandFailed(command: client.executableURL.path, arguments: args, error: error))
                return false
            case .success(let focused):
                lastFocused = focused
                if focused == context.workspaceName {
                    return true
                }
            }

            sleeper.sleep(seconds: TimeInterval(focusTiming.pollIntervalMs) / 1000.0)
        }
    }

    // MARK: - Step 6: IDE Identity

    private func resolveIdeIdentity(
        project: ProjectConfig,
        ideConfig: IdeConfig,
        context: ActivationContext
    ) -> IdeIdentity? {
        let resolutionResult = ideAppResolver.resolve(ide: project.ide, config: ideConfig.config(for: project.ide))
        switch resolutionResult {
        case .failure(let error):
            context.outcome = .failure(error: .commandFailed(
                command: "ide.resolve",
                arguments: [],
                exitCode: nil,
                stderr: "",
                detail: String(describing: error)
            ))
            return nil
        case .success(let resolution):
            let appName = resolution.appURL.deletingPathExtension().lastPathComponent
            return IdeIdentity(bundleId: resolution.bundleId, appName: appName, appURL: resolution.appURL)
        }
    }

    // MARK: - Step 7: Window Enumeration + Pruning

    /// Lists all windows across all workspaces.
    /// - Parameters:
    ///   - client: AeroSpace client used for the query.
    ///   - context: Activation context for failure reporting.
    /// - Returns: Window list when successful.
    private func listAllWindows(
        client: AeroSpaceClient,
        context: ActivationContext
    ) -> [AeroSpaceWindow]? {
        if context.isCancelled {
            context.outcome = .failure(error: .cancelled)
            return nil
        }

        switch client.listWindowsAllDecoded() {
        case .success(let windows):
            return windows
        case .failure(let error):
            let args = ["list-windows", "--all", "--json"]
            context.outcome = .failure(error: commandFailed(command: client.executableURL.path, arguments: args, error: error))
            return nil
        }
    }

    /// Normalizes bindings by enforcing role consistency, removing duplicate window ids,
    /// and limiting each role to a single primary binding.
    /// - Parameter bindings: Bindings to normalize.
    /// - Returns: Normalized bindings.
    private func normalizeBindings(_ bindings: ProjectBindings) -> ProjectBindings {
        var seen: Set<Int> = []
        var ide: [WindowBinding] = []
        for binding in bindings.ideBindings {
            guard binding.role == .ide else { continue }
            guard !seen.contains(binding.windowId) else { continue }
            seen.insert(binding.windowId)
            ide.append(binding)
            break
        }

        var chrome: [WindowBinding] = []
        for binding in bindings.chromeBindings {
            guard binding.role == .chrome else { continue }
            guard !seen.contains(binding.windowId) else { continue }
            seen.insert(binding.windowId)
            chrome.append(binding)
            break
        }

        return ProjectBindings(ideBindings: ide, chromeBindings: chrome)
    }

    /// Removes stale bindings when the window id is missing or app bundle ids differ.
    /// - Parameters:
    ///   - bindings: Current bindings.
    ///   - windowMap: Map of window id to current window record.
    /// - Returns: Pruned bindings.
    private func pruneBindings(
        _ bindings: ProjectBindings,
        windowMap: [Int: AeroSpaceWindow]
    ) -> ProjectBindings {
        let ide = bindings.ideBindings.filter { binding in
            guard let window = windowMap[binding.windowId] else { return false }
            return window.appBundleId == binding.appBundleId
        }
        let chrome = bindings.chromeBindings.filter { binding in
            guard let window = windowMap[binding.windowId] else { return false }
            return window.appBundleId == binding.appBundleId
        }
        return ProjectBindings(ideBindings: ide, chromeBindings: chrome)
    }

    /// Returns true if any bound window already resides in the target workspace.
    /// - Parameters:
    ///   - bindings: Current bindings.
    ///   - windowMap: Map of window id to current window record.
    ///   - workspaceName: Target workspace name.
    /// - Returns: True if any bound window is already in the target workspace.
    private func hasBoundWindowInWorkspace(
        bindings: ProjectBindings,
        windowMap: [Int: AeroSpaceWindow],
        workspaceName: String
    ) -> Bool {
        let allBindings = bindings.ideBindings + bindings.chromeBindings
        for binding in allBindings {
            if let window = windowMap[binding.windowId],
               window.workspace == workspaceName {
                return true
            }
        }
        return false
    }

    // MARK: - Step 8: Window Moves

    /// Moves all bound windows to the target workspace when needed.
    /// - Parameters:
    ///   - bindings: Current bindings.
    ///   - windowMap: Map of window id to current window record.
    ///   - workspaceName: Target workspace name.
    ///   - client: AeroSpace client for move commands.
    ///   - context: Activation context for failure reporting.
    /// - Returns: True when all moves succeed.
    private func moveBoundWindows(
        bindings: ProjectBindings,
        windowMap: inout [Int: AeroSpaceWindow],
        workspaceName: String,
        client: AeroSpaceClient,
        context: ActivationContext
    ) -> Bool {
        if context.isCancelled {
            context.outcome = .failure(error: .cancelled)
            return false
        }

        let orderedBindings = bindings.ideBindings + bindings.chromeBindings
        for binding in orderedBindings {
            guard var window = windowMap[binding.windowId] else { continue }
            if window.workspace == workspaceName {
                continue
            }
            switch client.moveWindowToWorkspace(windowId: window.windowId, workspace: workspaceName) {
            case .success:
                window = updatedWindow(window, workspace: workspaceName)
                windowMap[window.windowId] = window
            case .failure(let error):
                if let moveError = moveFailed(windowId: window.windowId, workspace: workspaceName, error: error) {
                    context.outcome = .failure(error: moveError)
                } else {
                    let args = ["move-node-to-workspace", "--window-id", String(window.windowId), workspaceName]
                    context.outcome = .failure(error: commandFailed(command: client.executableURL.path, arguments: args, error: error))
                }
                return false
            }
        }
        return true
    }

    // MARK: - Step 9: Window Launch + Detection

    /// Launches the IDE for a project and detects the new window.
    private func launchIdeWindow(
        client: AeroSpaceClient,
        project: ProjectConfig,
        ideIdentity: IdeIdentity,
        beforeWindowIds: Set<Int>,
        context: ActivationContext
    ) -> AeroSpaceWindow? {
        let workspaceURLResult = workspaceGenerator.writeWorkspace(for: project)
        let workspaceURL: URL
        switch workspaceURLResult {
        case .failure(let error):
            context.outcome = .failure(
                error: .commandFailed(
                    command: "ide.workspace",
                    arguments: [],
                    exitCode: nil,
                    stderr: "",
                    detail: String(describing: error)
                )
            )
            return nil
        case .success(let url):
            workspaceURL = url
        }

        let openURL = URL(fileURLWithPath: "/usr/bin/open", isDirectory: false)
        let openArgs = ["-n", "-a", ideIdentity.appURL.path, workspaceURL.path]
        if !runOpenCommand(executable: openURL, arguments: openArgs, context: context) {
            return nil
        }

        let token = ProjectWindowToken(projectId: project.id)
        return detectNewWindow(
            client: client,
            appBundleId: ideIdentity.bundleId ?? "",
            token: token,
            beforeWindowIds: beforeWindowIds,
            context: context
        )
    }

    /// Launches Chrome for a project and detects the new window.
    private func launchChromeWindow(
        client: AeroSpaceClient,
        project: ProjectConfig,
        globalChromeUrls: [String],
        beforeWindowIds: Set<Int>,
        context: ActivationContext
    ) -> AeroSpaceWindow? {
        guard let chromeAppURL = resolveChromeAppURL() else {
            context.outcome = .failure(
                error: .commandFailed(
                    command: "chrome.resolve",
                    arguments: [],
                    exitCode: nil,
                    stderr: "",
                    detail: "Google Chrome could not be resolved."
                )
            )
            return nil
        }

        let token = ProjectWindowToken(projectId: project.id)
        var openArgs = [
            "-n",
            "-a",
            chromeAppURL.path,
            "--args",
            "--new-window",
            "--window-name=\(token.value)"
        ]
        if let profileDirectory = project.chromeProfileDirectory {
            openArgs.append("--profile-directory=\(profileDirectory)")
        }
        let launchUrls = globalChromeUrls + project.chromeUrls
        if !launchUrls.isEmpty {
            openArgs.append(contentsOf: launchUrls)
        }

        let openURL = URL(fileURLWithPath: "/usr/bin/open", isDirectory: false)
        if !runOpenCommand(executable: openURL, arguments: openArgs, context: context) {
            return nil
        }

        return detectNewWindow(
            client: client,
            appBundleId: ChromeApp.bundleId,
            token: token,
            beforeWindowIds: beforeWindowIds,
            context: context
        )
    }

    private func resolveChromeAppURL() -> URL? {
        if let appURL = appDiscovery.applicationURL(bundleIdentifier: ChromeApp.bundleId) {
            return appURL
        }
        return appDiscovery.applicationURL(named: "Google Chrome")
    }

    /// Runs the `open` command and records failures in the activation context.
    private func runOpenCommand(
        executable: URL,
        arguments: [String],
        context: ActivationContext
    ) -> Bool {
        do {
            let result = try commandRunner.run(
                command: executable,
                arguments: arguments,
                environment: nil,
                workingDirectory: nil
            )
            if result.exitCode != 0 {
                context.outcome = .failure(
                    error: .commandFailed(
                        command: executable.path,
                        arguments: arguments,
                        exitCode: Int(result.exitCode),
                        stderr: result.stderr,
                        detail: result.stdout.isEmpty ? nil : result.stdout
                    )
                )
                return false
            }
            return true
        } catch {
            context.outcome = .failure(
                error: .commandFailed(
                    command: executable.path,
                    arguments: arguments,
                    exitCode: nil,
                    stderr: "",
                    detail: String(describing: error)
                )
            )
            return false
        }
    }

    /// Detects a newly launched window using a token and bundle id filter.
    private func detectNewWindow(
        client: AeroSpaceClient,
        appBundleId: String,
        token: ProjectWindowToken,
        beforeWindowIds: Set<Int>,
        context: ActivationContext
    ) -> AeroSpaceWindow? {
        let schedule = PollSchedule(initialIntervalsMs: [], steadyIntervalMs: windowDetectionTiming.pollIntervalMs)
        let outcome: PollOutcome<AeroSpaceWindow, ActivationError> = Poller.poll(
            schedule: schedule,
            timeoutMs: windowDetectionTiming.timeoutMs,
            sleeper: sleeper
        ) {
            if context.isCancelled {
                return .failure(.cancelled)
            }
            switch client.listWindowsAllDecoded() {
            case .failure(let error):
                if WindowDetectionRetryPolicy.shouldRetryPoll(error) {
                    return .keepWaiting
                }
                let args = ["list-windows", "--all", "--json"]
                return .failure(commandFailed(command: client.executableURL.path, arguments: args, error: error))
            case .success(let windows):
                let matches = windows.filter { window in
                    window.appBundleId == appBundleId &&
                        token.matches(windowTitle: window.windowTitle) &&
                        !beforeWindowIds.contains(window.windowId)
                }
                if matches.count == 1, let window = matches.first {
                    return .success(window)
                }
                if matches.count > 1 {
                    return .failure(.ambiguousWindows(appBundleId: appBundleId, count: matches.count))
                }
                return .keepWaiting
            }
        }

        switch outcome {
        case .success(let window):
            return window
        case .failure(let error):
            context.outcome = .failure(error: error)
            return nil
        case .timedOut:
            context.outcome = .failure(error: .requiredWindowMissing(appBundleId: appBundleId))
            return nil
        }
    }

    private func updatedWindow(_ window: AeroSpaceWindow, workspace: String) -> AeroSpaceWindow {
        AeroSpaceWindow(
            windowId: window.windowId,
            workspace: workspace,
            appBundleId: window.appBundleId,
            appName: window.appName,
            windowTitle: window.windowTitle,
            windowLayout: window.windowLayout,
            monitorAppkitNSScreenScreensId: window.monitorAppkitNSScreenScreensId
        )
    }

    // MARK: - Step 7: Layout

    private func applyCanonicalLayout(
        workspace: String,
        ideWindowId: Int,
        client: AeroSpaceClient,
        context: ActivationContext
    ) -> Bool {
        if context.isCancelled {
            context.outcome = .failure(error: .cancelled)
            return false
        }

        switch client.flattenWorkspaceTree(workspace: workspace) {
        case .success:
            break
        case .failure(let error):
            context.outcome = .failure(error: layoutFailed(error: error))
            return false
        }

        switch client.balanceSizes(workspace: workspace) {
        case .success:
            break
        case .failure(let error):
            context.outcome = .failure(error: layoutFailed(error: error))
            return false
        }

        switch client.setLayout(windowId: ideWindowId, layout: .hTiles) {
        case .success:
            return true
        case .failure(let error):
            context.outcome = .failure(error: layoutFailed(error: error))
            return false
        }
    }

    private func resizeIdeWindow(
        ideWindow: AeroSpaceWindow,
        client: AeroSpaceClient,
        context: ActivationContext
    ) -> Bool {
        if context.isCancelled {
            context.outcome = .failure(error: .cancelled)
            return false
        }

        guard let screenIndex = ideWindow.monitorAppkitNSScreenScreensId else {
            context.outcome = .failure(
                error: .screenMetricsUnavailable(
                    screenIndex: 0,
                    detail: "Missing monitor-appkit-nsscreen-screens-id"
                )
            )
            return false
        }

        switch screenMetricsProvider.visibleWidth(screenIndex1Based: screenIndex) {
        case .failure(let error):
            context.outcome = .failure(
                error: .screenMetricsUnavailable(
                    screenIndex: screenIndex,
                    detail: String(describing: error)
                )
            )
            return false
        case .success(let visibleWidth):
            guard visibleWidth > 0 else {
                context.outcome = .failure(
                    error: .screenMetricsUnavailable(
                        screenIndex: screenIndex,
                        detail: "Visible width must be positive"
                    )
                )
                return false
            }

            let ideWidth = computeIdeWidth(visibleWidth: visibleWidth)
            switch client.resizeWidth(windowId: ideWindow.windowId, width: ideWidth) {
            case .success:
                return true
            case .failure(let error):
                context.outcome = .failure(error: resizeFailed(error: error))
                return false
            }
        }
    }

    private func computeIdeWidth(visibleWidth: Double) -> Int {
        let minIde = 800.0
        let minChrome = 500.0
        let target = (0.60 * visibleWidth).rounded()
        let maxIde = visibleWidth - minChrome

        let width: Double
        if maxIde < minIde {
            width = (0.55 * visibleWidth).rounded()
        } else {
            width = min(max(target, minIde), maxIde)
        }

        return max(1, Int(width))
    }

    private func focusIdeWindow(client: AeroSpaceClient, ideWindowId: Int, context: ActivationContext) -> Bool {
        switch client.focusWindow(windowId: ideWindowId) {
        case .success:
            return true
        case .failure(let error):
            let args = ["focus", "--window-id", String(ideWindowId)]
            context.outcome = .failure(error: commandFailed(command: client.executableURL.path, arguments: args, error: error))
            return false
        }
    }

    // MARK: - Error Helpers

    private func commandFailed(
        command: String,
        arguments: [String],
        error: AeroSpaceCommandError
    ) -> ActivationError {
        let details = commandFailureDetails(from: error)
        return .commandFailed(
            command: command,
            arguments: arguments,
            exitCode: details.exitCode,
            stderr: details.stderr,
            detail: details.detail
        )
    }

    private func moveFailed(
        windowId: Int,
        workspace: String,
        error: AeroSpaceCommandError
    ) -> ActivationError? {
        let details = commandFailureDetails(from: error)
        guard let exitCode = details.exitCode else {
            return nil
        }
        return .moveFailed(windowId: windowId, workspace: workspace, exitCode: exitCode, stderr: details.stderr)
    }

    private func layoutFailed(error: AeroSpaceCommandError) -> ActivationError {
        let details = commandFailureDetails(from: error)
        let exitCode = details.exitCode ?? -1
        return .layoutFailed(exitCode: exitCode, stderr: details.stderr)
    }

    private func resizeFailed(error: AeroSpaceCommandError) -> ActivationError {
        let details = commandFailureDetails(from: error)
        let exitCode = details.exitCode ?? -1
        return .resizeFailed(exitCode: exitCode, stderr: details.stderr)
    }

    private func commandFailureDetails(from error: AeroSpaceCommandError) -> CommandFailureDetails {
        switch error {
        case .executionFailed(let execError):
            switch execError {
            case .launchFailed(_, let underlyingError):
                return CommandFailureDetails(exitCode: nil, stderr: "", detail: underlyingError)
            case .nonZeroExit(_, let result):
                return CommandFailureDetails(exitCode: Int(result.exitCode), stderr: result.stderr, detail: nil)
            }
        case .timedOut(_, let timeoutSeconds, let result):
            return CommandFailureDetails(
                exitCode: Int(result.exitCode),
                stderr: result.stderr,
                detail: "Timed out after \(timeoutSeconds)s"
            )
        case .decodingFailed(_, let underlyingError):
            return CommandFailureDetails(exitCode: nil, stderr: "", detail: "Decoding failed: \(underlyingError)")
        case .unexpectedOutput(_, let detail):
            return CommandFailureDetails(exitCode: nil, stderr: "", detail: detail)
        case .notReady(let payload):
            return CommandFailureDetails(
                exitCode: Int(payload.lastCommand.exitCode),
                stderr: payload.lastCommand.stderr,
                detail: "AeroSpace not ready after \(payload.timeoutSeconds)s"
            )
        }
    }
}

struct WorkspaceFocusTiming {
    let pollIntervalMs: Int
    let reissueSwitchAfterMs: Int
    let deadlineMs: Int
    let postMoveDeadlineMs: Int

    static let fixed = WorkspaceFocusTiming(
        pollIntervalMs: 50,
        reissueSwitchAfterMs: 750,
        deadlineMs: 5000,
        postMoveDeadlineMs: 1000
    )
}

/// Polling configuration for detecting newly launched windows.
struct WindowDetectionTiming {
    let pollIntervalMs: Int
    let timeoutMs: Int

    static let standard = WindowDetectionTiming(
        pollIntervalMs: 200,
        timeoutMs: 10_000
    )
}

private struct CommandFailureDetails {
    let exitCode: Int?
    let stderr: String
    let detail: String?
}

private struct IdeIdentity: Equatable, Sendable {
    let bundleId: String?
    let appName: String
    let appURL: URL
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
    let commandLogs: CommandLogAccumulator = CommandLogAccumulator()
    var ideWindowId: Int?
    var chromeWindowId: Int?
    var ideBundleId: String?
    var outcome: ActivationOutcome?

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
        let errorCode: String?
        let errorContext: [String: String]?
        switch outcome {
        case .success:
            outcomeLabel = "success"
            errorCode = nil
            errorContext = nil
        case .failure(let error):
            if case .cancelled = error {
                outcomeLabel = "cancelled"
            } else {
                outcomeLabel = "fail"
            }
            errorCode = error.code
            errorContext = error.logContext
        }

        let payload = ActivationLogPayload(
            projectId: projectId,
            workspaceName: workspaceName,
            outcome: outcomeLabel,
            ideWindowId: ideWindowId,
            chromeWindowId: chromeWindowId,
            errorCode: errorCode,
            errorContext: errorContext,
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
        case "cancelled":
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
