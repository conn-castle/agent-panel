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
    private let layoutApplier: LayoutApplying
    private let logger: ProjectWorkspacesLogging
    private let sleeper: AeroSpaceSleeping
    private let pollIntervalMs: Int
    private let pollTimeoutMs: Int

    /// Creates an activation service with default dependencies.
    /// - Parameters:
    ///   - paths: File system paths for ProjectWorkspaces.
    ///   - fileSystem: File system accessor.
    ///   - appDiscovery: Application discovery provider.
    ///   - commandRunner: Command runner used for IDE/Chrome launches and CLI resolution.
    ///   - aeroSpaceCommandRunner: Runner used for AeroSpace CLI commands.
    ///   - aeroSpaceBinaryResolver: Optional resolver for the AeroSpace CLI.
    ///   - layoutApplier: Layout applier (no-op by default).
    ///   - logger: Logger for activation events.
    ///   - pollIntervalMs: Polling interval for IDE window detection.
    ///   - pollTimeoutMs: Polling timeout for IDE window detection.
    ///   - aeroSpaceTimeoutSeconds: Timeout for individual AeroSpace commands.
    public init(
        paths: ProjectWorkspacesPaths = .defaultPaths(),
        fileSystem: FileSystem = DefaultFileSystem(),
        appDiscovery: AppDiscovering = LaunchServicesAppDiscovery(),
        commandRunner: CommandRunning = DefaultCommandRunner(),
        aeroSpaceCommandRunner: AeroSpaceCommandRunning = DefaultAeroSpaceCommandRunner(),
        aeroSpaceBinaryResolver: AeroSpaceBinaryResolving? = nil,
        layoutApplier: LayoutApplying = NoopLayoutApplier(),
        logger: ProjectWorkspacesLogging = ProjectWorkspacesLogger(),
        pollIntervalMs: Int = 200,
        pollTimeoutMs: Int = 5000,
        aeroSpaceTimeoutSeconds: TimeInterval = 2
    ) {
        precondition(pollIntervalMs > 0, "pollIntervalMs must be positive")
        precondition(pollTimeoutMs > 0, "pollTimeoutMs must be positive")
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
        self.layoutApplier = layoutApplier
        self.logger = logger
        self.sleeper = SystemAeroSpaceSleeper()
        self.pollIntervalMs = pollIntervalMs
        self.pollTimeoutMs = pollTimeoutMs
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
        layoutApplier: LayoutApplying,
        logger: ProjectWorkspacesLogging,
        sleeper: AeroSpaceSleeping,
        pollIntervalMs: Int,
        pollTimeoutMs: Int
    ) {
        precondition(pollIntervalMs > 0, "pollIntervalMs must be positive")
        precondition(pollTimeoutMs > 0, "pollTimeoutMs must be positive")
        self.configLoader = configLoader
        self.aeroSpaceBinaryResolver = aeroSpaceBinaryResolver
        self.aeroSpaceCommandRunner = aeroSpaceCommandRunner
        self.aeroSpaceTimeoutSeconds = aeroSpaceTimeoutSeconds
        self.ideLauncher = ideLauncher
        self.chromeLauncherFactory = chromeLauncherFactory
        self.ideAppResolver = ideAppResolver
        self.layoutApplier = layoutApplier
        self.logger = logger
        self.sleeper = sleeper
        self.pollIntervalMs = pollIntervalMs
        self.pollTimeoutMs = pollTimeoutMs
    }

    /// Activates the project workspace for the given project id.
    /// - Parameter projectId: Project identifier to activate.
    /// - Returns: Activation outcome with warnings or failure.
    public func activate(projectId: String) -> ActivationOutcome {
        let context = ActivationContext(projectId: projectId)
        return runActivation(context)
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

        // Step 3: Switch to workspace
        guard switchToWorkspace(client: client, context: context) else {
            return context.finalize(logger: logger)
        }

        // Step 4: Get initial window state
        guard let initialWindows = listWorkspaceWindows(client: client, context: context) else {
            return context.finalize(logger: logger)
        }

        // Step 5: Resolve IDE identity
        guard let ideIdentity = resolveIdeIdentity(project: project, ideConfig: config.ide, context: context) else {
            return context.finalize(logger: logger)
        }

        // Step 6: Ensure IDE window exists
        guard let ideWindowId = ensureIdeWindow(
            client: client,
            project: project,
            ideConfig: config.ide,
            ideIdentity: ideIdentity,
            initialWindows: initialWindows,
            context: context
        ) else {
            return context.finalize(logger: logger)
        }
        context.ideWindowId = ideWindowId

        // Step 7: Ensure Chrome window exists
        guard let chromeWindowId = ensureChromeWindow(
            client: client,
            chromeLauncher: chromeLauncher,
            project: project,
            globalChromeUrls: config.global.globalChromeUrls,
            ideWindowId: ideWindowId,
            initialWindows: initialWindows,
            context: context
        ) else {
            return context.finalize(logger: logger)
        }
        context.chromeWindowId = chromeWindowId

        // Step 8: Set floating layout for both windows
        guard setFloatingLayouts(client: client, ideWindowId: ideWindowId, chromeWindowId: chromeWindowId, context: context) else {
            return context.finalize(logger: logger)
        }

        // Step 9: Apply layout
        applyLayout(project: project, ideWindowId: ideWindowId, chromeWindowId: chromeWindowId, context: context)

        // Step 10: Focus IDE window
        guard focusIdeWindow(client: client, ideWindowId: ideWindowId, context: context) else {
            return context.finalize(logger: logger)
        }

        // Success
        let report = ActivationReport(
            projectId: context.projectId,
            workspaceName: context.workspaceName,
            ideWindowId: ideWindowId,
            chromeWindowId: chromeWindowId
        )
        context.outcome = .success(report: report, warnings: context.warnings)
        return context.finalize(logger: logger)
    }

    // MARK: - Step 1: AeroSpace Client Resolution

    private func resolveAeroSpaceClient(_ context: ActivationContext) -> AeroSpaceClient? {
        switch aeroSpaceBinaryResolver.resolve() {
        case .failure(let error):
            context.outcome = .failure(error: .aeroSpaceResolutionFailed(error))
            return nil
        case .success(let executableURL):
            let tracingRunner = TracingAeroSpaceCommandRunner(
                wrapped: aeroSpaceCommandRunner,
                traceSink: { context.commandLogs.append($0) }
            )
            return AeroSpaceClient(
                executableURL: executableURL,
                commandRunner: tracingRunner,
                timeoutSeconds: aeroSpaceTimeoutSeconds
            )
        }
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

    // MARK: - Step 4: Window Enumeration

    private func listWorkspaceWindows(client: AeroSpaceClient, context: ActivationContext) -> [AeroSpaceWindow]? {
        switch client.listWindowsDecoded(workspace: context.workspaceName) {
        case .failure(let error):
            context.outcome = .failure(error: .aeroSpaceFailed(error))
            return nil
        case .success(let windows):
            return windows
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
        initialWindows: [AeroSpaceWindow],
        context: ActivationContext
    ) -> Int? {
        let existingIdeIds = matchingWindowIds(in: initialWindows, identity: ideIdentity)

        if !existingIdeIds.isEmpty {
            let selectedId = existingIdeIds.sorted().first ?? existingIdeIds[0]
            if existingIdeIds.count > 1 {
                context.warnings.append(.multipleIdeWindows(windowIds: existingIdeIds, selectedWindowId: selectedId))
            }
            return selectedId
        }

        // Need to create IDE window
        guard ensureWorkspaceFocused(client: client, context: context) else {
            return nil
        }

        switch ideLauncher.launch(project: project, ideConfig: ideConfig) {
        case .failure(let error):
            context.outcome = .failure(error: .ideLaunchFailed(error))
            return nil
        case .success(let success):
            context.warnings.append(contentsOf: success.warnings.map { .ideLaunchWarning($0) })
        }

        return detectNewIdeWindow(
            client: client,
            identity: ideIdentity,
            beforeIds: Set(existingIdeIds),
            context: context
        )
    }

    private func detectNewIdeWindow(
        client: AeroSpaceClient,
        identity: IdeIdentity,
        beforeIds: Set<Int>,
        context: ActivationContext
    ) -> Int? {
        let intervalSeconds = TimeInterval(pollIntervalMs) / 1000.0
        let maxAttempts = max(1, Int(ceil(Double(pollTimeoutMs) / Double(pollIntervalMs))) + 1)

        for attempt in 0..<maxAttempts {
            switch client.listWindowsDecoded(workspace: context.workspaceName) {
            case .failure(let error):
                context.outcome = .failure(error: .aeroSpaceFailed(error))
                return nil
            case .success(let windows):
                let afterIds = Set(matchingWindowIds(in: windows, identity: identity))
                let newIds = afterIds.subtracting(beforeIds)
                if !newIds.isEmpty {
                    let sortedNewIds = newIds.sorted()
                    let selected = sortedNewIds.last ?? sortedNewIds[0]
                    if sortedNewIds.count > 1 {
                        context.warnings.append(.multipleIdeWindows(windowIds: sortedNewIds, selectedWindowId: selected))
                    }
                    return selected
                }
            }

            if attempt < maxAttempts - 1 {
                sleeper.sleep(seconds: intervalSeconds)
            }
        }

        context.outcome = .failure(error: .ideWindowNotDetected(expectedWorkspace: context.workspaceName))
        return nil
    }

    // MARK: - Step 7: Chrome Window

    private func ensureChromeWindow(
        client: AeroSpaceClient,
        chromeLauncher: ChromeLaunching,
        project: ProjectConfig,
        globalChromeUrls: [String],
        ideWindowId: Int,
        initialWindows: [AeroSpaceWindow],
        context: ActivationContext
    ) -> Int? {
        var windowsForChrome = initialWindows
        var existingChromeIds = windowsForChrome
            .filter { $0.appBundleId == ChromeLauncher.chromeBundleId }
            .map { $0.windowId }

        if existingChromeIds.isEmpty {
            switch client.listWindowsDecoded(workspace: context.workspaceName) {
            case .failure(let error):
                context.outcome = .failure(error: .aeroSpaceFailed(error))
                return nil
            case .success(let windows):
                windowsForChrome = windows
                existingChromeIds = windowsForChrome
                    .filter { $0.appBundleId == ChromeLauncher.chromeBundleId }
                    .map { $0.windowId }
            }
        }

        if !existingChromeIds.isEmpty {
            let selectedId = existingChromeIds.sorted().first ?? existingChromeIds[0]
            if existingChromeIds.count > 1 {
                context.warnings.append(.multipleChromeWindows(windowIds: existingChromeIds, selectedWindowId: selectedId))
            }
            return selectedId
        }

        // Need to create Chrome window
        guard ensureWorkspaceFocused(client: client, context: context) else {
            return nil
        }

        let chromeResult = chromeLauncher.ensureWindow(
            expectedWorkspaceName: context.workspaceName,
            globalChromeUrls: globalChromeUrls,
            project: project,
            ideWindowIdToRefocus: ideWindowId,
            allowExistingWindows: true
        )

        switch chromeResult {
        case .failure(let error):
            context.outcome = .failure(error: .chromeLaunchFailed(error))
            return nil
        case .success(let outcome):
            switch outcome {
            case .created(let windowId), .existing(let windowId):
                return windowId
            case .existingMultiple(let windowIds):
                let sorted = windowIds.sorted()
                let selected = sorted.first ?? windowIds[0]
                context.warnings.append(.multipleChromeWindows(windowIds: windowIds, selectedWindowId: selected))
                return selected
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
        if case .failure(let error) = client.setFloatingLayout(windowId: ideWindowId) {
            context.outcome = .failure(error: .aeroSpaceFailed(error))
            return false
        }
        if case .failure(let error) = client.setFloatingLayout(windowId: chromeWindowId) {
            context.outcome = .failure(error: .aeroSpaceFailed(error))
            return false
        }
        return true
    }

    // MARK: - Step 9: Layout Application

    private func applyLayout(
        project: ProjectConfig,
        ideWindowId: Int,
        chromeWindowId: Int,
        context: ActivationContext
    ) {
        let layoutOutcome = layoutApplier.applyLayout(
            project: project,
            ideWindowId: ideWindowId,
            chromeWindowId: chromeWindowId
        )
        if case .skipped = layoutOutcome {
            context.warnings.append(.layoutNotApplied)
        }
    }

    // MARK: - Step 10: Focus IDE

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

    private func ensureWorkspaceFocused(client: AeroSpaceClient, context: ActivationContext) -> Bool {
        switch client.focusedWorkspace() {
        case .failure(let error):
            context.outcome = .failure(error: .aeroSpaceFailed(error))
            return false
        case .success(let focused):
            guard focused == context.workspaceName else {
                context.outcome = .failure(error: .workspaceFocusChanged(expected: context.workspaceName, actual: focused))
                return false
            }
            return true
        }
    }

    private func matchingWindowIds(in windows: [AeroSpaceWindow], identity: IdeIdentity) -> [Int] {
        if let bundleId = identity.bundleId, !bundleId.isEmpty {
            return windows
                .filter { $0.appBundleId == bundleId }
                .map { $0.windowId }
        }
        return windows
            .filter { $0.appName == identity.appName }
            .map { $0.windowId }
    }
}

// MARK: - Internal Types

private struct IdeIdentity: Equatable, Sendable {
    let bundleId: String?
    let appName: String
}

/// Mutable activation state passed through orchestration steps.
/// Uses a class for commandLogs to allow capture in escaping closures.
private final class ActivationContext {
    let projectId: String
    let workspaceName: String
    var warnings: [ActivationWarning] = []
    let commandLogs: CommandLogAccumulator = CommandLogAccumulator()
    var ideWindowId: Int?
    var chromeWindowId: Int?
    var outcome: ActivationOutcome?

    init(projectId: String) {
        self.projectId = projectId
        self.workspaceName = "pw-\(projectId)"
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
