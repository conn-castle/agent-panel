import Foundation

/// Creates Chrome windows deterministically for the focused workspace.
public struct ChromeLauncher {
    public static let chromeBundleId = "com.google.Chrome"
    public static let chromeAppName = "Google Chrome"
    public static let defaultPollIntervalMs = 200
    public static let defaultPollTimeoutMs = 5000
    public static let defaultRefocusDelayMs = 100

    private let aeroSpaceClient: AeroSpaceClient
    private let commandRunner: CommandRunning
    private let appDiscovery: AppDiscovering
    private let sleeper: AeroSpaceSleeping
    private let pollIntervalMs: Int
    private let pollTimeoutMs: Int
    private let refocusDelayMs: Int

    /// Creates a Chrome launcher.
    /// - Parameters:
    ///   - aeroSpaceClient: AeroSpace client used for window enumeration and focus.
    ///   - commandRunner: Command runner used to invoke `open`.
    ///   - appDiscovery: Application discovery provider for Chrome.
    public init(
        aeroSpaceClient: AeroSpaceClient,
        commandRunner: CommandRunning = DefaultCommandRunner(),
        appDiscovery: AppDiscovering = LaunchServicesAppDiscovery()
    ) {
        self.init(
            aeroSpaceClient: aeroSpaceClient,
            commandRunner: commandRunner,
            appDiscovery: appDiscovery,
            sleeper: SystemAeroSpaceSleeper(),
            pollIntervalMs: Self.defaultPollIntervalMs,
            pollTimeoutMs: Self.defaultPollTimeoutMs,
            refocusDelayMs: Self.defaultRefocusDelayMs
        )
    }

    /// Internal initializer for tests and deterministic configuration.
    init(
        aeroSpaceClient: AeroSpaceClient,
        commandRunner: CommandRunning,
        appDiscovery: AppDiscovering,
        sleeper: AeroSpaceSleeping,
        pollIntervalMs: Int,
        pollTimeoutMs: Int,
        refocusDelayMs: Int
    ) {
        precondition(pollIntervalMs > 0, "pollIntervalMs must be positive")
        precondition(pollTimeoutMs > 0, "pollTimeoutMs must be positive")
        precondition(refocusDelayMs >= 0, "refocusDelayMs must be non-negative")
        self.aeroSpaceClient = aeroSpaceClient
        self.commandRunner = commandRunner
        self.appDiscovery = appDiscovery
        self.sleeper = sleeper
        self.pollIntervalMs = pollIntervalMs
        self.pollTimeoutMs = pollTimeoutMs
        self.refocusDelayMs = refocusDelayMs
    }

    /// Ensures a Chrome window exists for the currently focused workspace.
    ///
    /// In Phase 3, refocus only occurs when `ideWindowIdToRefocus` is provided; activation is expected
    /// to supply it when Chrome is created.
    /// - Parameters:
    ///   - expectedWorkspaceName: Workspace that must already be focused.
    ///   - globalChromeUrls: Global URLs to open when creating Chrome.
    ///   - project: Project configuration providing repo and project URLs.
    ///   - ideWindowIdToRefocus: IDE window id to refocus after Chrome creation.
    /// - Returns: Launch outcome or a structured error.
    public func ensureWindow(
        expectedWorkspaceName: String,
        globalChromeUrls: [String],
        project: ProjectConfig,
        ideWindowIdToRefocus: Int?
    ) -> Result<ChromeLaunchOutcome, ChromeLaunchError> {
        switch focusedWorkspace() {
        case .failure(let error):
            return .failure(error)
        case .success(let focusedWorkspace):
            if focusedWorkspace != expectedWorkspaceName {
                return .failure(
                    .workspaceNotFocused(
                        expected: expectedWorkspaceName,
                        actual: focusedWorkspace
                    )
                )
            }
        }

        let workspaceWindowsBefore: [AeroSpaceWindow]
        switch aeroSpaceClient.listWindowsDecoded(workspace: expectedWorkspaceName) {
        case .failure(let error):
            return .failure(.aeroSpaceFailed(error))
        case .success(let windows):
            workspaceWindowsBefore = windows
        }

        let chromeWindowIdsBefore = chromeWindowIds(from: workspaceWindowsBefore)
        if chromeWindowIdsBefore.count == 1, let existing = chromeWindowIdsBefore.first {
            return .success(.existing(windowId: existing))
        }
        if chromeWindowIdsBefore.count > 1 {
            return .success(.existingMultiple(windowIds: chromeWindowIdsBefore.sorted()))
        }

        let allChromeIdsBefore: Set<Int>
        switch aeroSpaceClient.listWindowsAllDecoded() {
        case .failure(let error):
            return .failure(.aeroSpaceFailed(error))
        case .success(let windows):
            allChromeIdsBefore = Set(chromeWindowIds(from: windows))
        }

        guard let chromeAppURL = resolveChromeAppURL() else {
            return .failure(.chromeNotFound)
        }

        let launchUrls = buildLaunchUrls(
            globalChromeUrls: globalChromeUrls,
            project: project
        )

        let openResult = runCommand(
            executable: URL(fileURLWithPath: "/usr/bin/open", isDirectory: false),
            arguments: ["-g", "-a", chromeAppURL.path, "--args", "--new-window"] + launchUrls
        )

        if case .failure(let error) = openResult {
            return .failure(.openFailed(error))
        }

        let beforeWorkspaceIds = Set(chromeWindowIdsBefore)
        let detectionResult = detectNewChromeWindow(
            expectedWorkspaceName: expectedWorkspaceName,
            beforeWorkspaceIds: beforeWorkspaceIds
        )

        switch detectionResult {
        case .success(let newWindowId):
            if case .failure(let error) = refocusIdeWindow(ideWindowIdToRefocus) {
                return .failure(error)
            }
            return .success(.created(windowId: newWindowId))
        case .failure(let error):
            if case .chromeWindowNotDetected = error {
                let fallbackResult = fallbackDetection(
                    expectedWorkspaceName: expectedWorkspaceName,
                    beforeAllChromeIds: allChromeIdsBefore
                )
                switch fallbackResult {
                case .failure(let fallbackError):
                    return .failure(fallbackError)
                case .success(let outcome):
                    switch outcome {
                    case .created(let windowId):
                        if case .failure(let focusError) = refocusIdeWindow(ideWindowIdToRefocus) {
                            return .failure(focusError)
                        }
                        return .success(.created(windowId: windowId))
                    case .existing(let windowId):
                        return .success(.existing(windowId: windowId))
                    case .existingMultiple(let windowIds):
                        return .success(.existingMultiple(windowIds: windowIds))
                    }
                }
            }
            return .failure(error)
        }
    }

    /// Refocuses the IDE window after Chrome creation if a window id was provided.
    private func refocusIdeWindow(_ windowId: Int?) -> Result<Void, ChromeLaunchError> {
        guard let windowId else {
            return .success(())
        }
        let delaySeconds = TimeInterval(refocusDelayMs) / 1000.0
        if delaySeconds > 0 {
            sleeper.sleep(seconds: delaySeconds)
        }
        switch aeroSpaceClient.focusWindow(windowId: windowId) {
        case .success:
            return .success(())
        case .failure(let error):
            return .failure(.aeroSpaceFailed(error))
        }
    }

    /// Fetches the currently focused workspace name.
    private func focusedWorkspace() -> Result<String, ChromeLaunchError> {
        switch aeroSpaceClient.focusedWorkspace() {
        case .failure(let error):
            return .failure(.aeroSpaceFailed(error))
        case .success(let workspace):
            return .success(workspace)
        }
    }

    /// Resolves the Chrome application URL via Launch Services.
    private func resolveChromeAppURL() -> URL? {
        if let appURL = appDiscovery.applicationURL(bundleIdentifier: Self.chromeBundleId) {
            return appURL
        }
        return appDiscovery.applicationURL(named: Self.chromeAppName)
    }

    /// Builds the ordered, de-duplicated URL list for Chrome window creation.
    private func buildLaunchUrls(globalChromeUrls: [String], project: ProjectConfig) -> [String] {
        var ordered: [String] = []
        ordered.append(contentsOf: globalChromeUrls)
        if let repoUrl = project.repoUrl {
            ordered.append(repoUrl)
        }
        ordered.append(contentsOf: project.chromeUrls)

        var seen = Set<String>()
        var deduped: [String] = []
        for url in ordered {
            if seen.insert(url).inserted {
                deduped.append(url)
            }
        }

        if deduped.isEmpty {
            return ["about:blank"]
        }

        return deduped
    }

    /// Extracts Chrome window ids from AeroSpace window metadata.
    private func chromeWindowIds(from windows: [AeroSpaceWindow]) -> [Int] {
        windows
            .filter { $0.appBundleId == Self.chromeBundleId }
            .map { $0.windowId }
    }

    /// Polls the expected workspace for a newly created Chrome window.
    private func detectNewChromeWindow(
        expectedWorkspaceName: String,
        beforeWorkspaceIds: Set<Int>
    ) -> Result<Int, ChromeLaunchError> {
        let intervalSeconds = TimeInterval(pollIntervalMs) / 1000.0
        // Add one attempt to include an immediate check plus the final timeout boundary.
        let maxAttempts = max(1, Int(ceil(Double(pollTimeoutMs) / Double(pollIntervalMs))) + 1)

        for attempt in 0..<maxAttempts {
            let windowsResult = aeroSpaceClient.listWindowsDecoded(workspace: expectedWorkspaceName)
            let windows: [AeroSpaceWindow]
            switch windowsResult {
            case .failure(let error):
                return .failure(.aeroSpaceFailed(error))
            case .success(let decoded):
                windows = decoded
            }

            let chromeIds = Set(chromeWindowIds(from: windows))
            let newIds = chromeIds.subtracting(beforeWorkspaceIds)
            if newIds.count == 1, let newId = newIds.first {
                return .success(newId)
            }
            if newIds.count > 1 {
                return .failure(.chromeWindowAmbiguous(newWindowIds: newIds.sorted()))
            }

            if attempt < maxAttempts - 1 {
                sleeper.sleep(seconds: intervalSeconds)
            }
        }

        return .failure(.chromeWindowNotDetected(expectedWorkspace: expectedWorkspaceName))
    }

    /// Performs a one-time fallback detection across all workspaces after polling timeout.
    private func fallbackDetection(
        expectedWorkspaceName: String,
        beforeAllChromeIds: Set<Int>
    ) -> Result<ChromeLaunchOutcome, ChromeLaunchError> {
        let windowsResult = aeroSpaceClient.listWindowsAllDecoded()
        let windows: [AeroSpaceWindow]
        switch windowsResult {
        case .failure(let error):
            return .failure(.aeroSpaceFailed(error))
        case .success(let decoded):
            windows = decoded
        }

        let chromeWindows = windows.filter { $0.appBundleId == Self.chromeBundleId }
        let afterIds = Set(chromeWindows.map { $0.windowId })
        let newIds = afterIds.subtracting(beforeAllChromeIds)

        if newIds.isEmpty {
            return .failure(.chromeWindowNotDetected(expectedWorkspace: expectedWorkspaceName))
        }

        if newIds.count > 1 {
            return .failure(.chromeWindowAmbiguous(newWindowIds: newIds.sorted()))
        }

        guard let newId = newIds.first,
              let newWindow = chromeWindows.first(where: { $0.windowId == newId }) else {
            return .failure(.chromeWindowNotDetected(expectedWorkspace: expectedWorkspaceName))
        }

        if newWindow.workspace == expectedWorkspaceName {
            return .success(.created(windowId: newId))
        }

        return .failure(
            .chromeLaunchedElsewhere(
                expectedWorkspace: expectedWorkspaceName,
                actualWorkspace: newWindow.workspace,
                newWindowId: newId
            )
        )
    }

    /// Runs a command and converts non-zero exits into `ProcessCommandError`.
    private func runCommand(
        executable: URL,
        arguments: [String]
    ) -> Result<CommandResult, ProcessCommandError> {
        let commandDescription = ([executable.path] + arguments).joined(separator: " ")
        do {
            let result = try commandRunner.run(
                command: executable,
                arguments: arguments,
                environment: nil,
                workingDirectory: nil
            )
            if result.exitCode != 0 {
                return .failure(.nonZeroExit(command: commandDescription, result: result))
            }
            return .success(result)
        } catch {
            return .failure(.launchFailed(command: commandDescription, underlyingError: String(describing: error)))
        }
    }
}
