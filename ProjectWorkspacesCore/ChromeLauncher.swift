import Foundation

/// Creates Chrome windows deterministically for the target workspace.
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

    /// Ensures a Chrome window exists for the provided workspace using a deterministic token.
    /// Cross-workspace scanning is limited to windows that match the token.
    /// New windows are created via `open -n` so Chrome honors `--window-name`.
    ///
    /// Refocus only occurs when `ideWindowIdToRefocus` is provided; activation is expected
    /// to supply it when Chrome is created.
    /// - Parameters:
    ///   - expectedWorkspaceName: Target workspace name.
    ///   - windowToken: Deterministic token used to identify the Chrome window.
    ///   - globalChromeUrls: Global URLs to open when creating Chrome.
    ///   - project: Project configuration providing repo and project URLs.
    ///   - ideWindowIdToRefocus: IDE window id to refocus after Chrome creation.
    ///   - allowExistingWindows: Whether existing Chrome windows should satisfy the request.
    /// - Returns: Launch outcome or a structured error.
    public func ensureWindow(
        expectedWorkspaceName: String,
        windowToken: ProjectWindowToken,
        globalChromeUrls: [String],
        project: ProjectConfig,
        ideWindowIdToRefocus: Int?,
        allowExistingWindows: Bool = true
    ) -> Result<ChromeLaunchOutcome, ChromeLaunchError> {
        let existingMatchesResult = listChromeWindowsMatching(token: windowToken)
        let existingMatches: [AeroSpaceWindow]
        switch existingMatchesResult {
        case .failure(let error):
            return .failure(error)
        case .success(let matches):
            existingMatches = matches
        }

        if !existingMatches.isEmpty {
            let existingIds = existingMatches.map { $0.windowId }.sorted()
            if allowExistingWindows, existingMatches.count == 1, let existing = existingMatches.first {
                if case .failure(let error) = moveWindowIfNeeded(existing, to: expectedWorkspaceName) {
                    return .failure(error)
                }
                return .success(.existing(windowId: existing.windowId))
            }
            return .failure(.chromeWindowAmbiguous(token: windowToken.value, windowIds: existingIds))
        }

        guard let chromeAppURL = resolveChromeAppURL() else {
            return .failure(.chromeNotFound)
        }

        let launchUrls = buildLaunchUrls(
            globalChromeUrls: globalChromeUrls,
            project: project
        )

        var openArguments = [
            "-n",
            "-a",
            chromeAppURL.path,
            "--args",
            "--new-window",
            "--window-name=\(windowToken.value)"
        ]
        if let profileDirectory = project.chromeProfileDirectory {
            openArguments.append("--profile-directory=\(profileDirectory)")
        }
        openArguments.append(contentsOf: launchUrls)

        let openResult = runCommand(
            executable: URL(fileURLWithPath: "/usr/bin/open", isDirectory: false),
            arguments: openArguments
        )

        if case .failure(let error) = openResult {
            return .failure(.openFailed(error))
        }

        let beforeIds = Set(existingMatches.map { $0.windowId })
        let detectionResult = detectNewChromeWindow(
            windowToken: windowToken,
            beforeWindowIds: beforeIds
        )

        switch detectionResult {
        case .success(let newWindow):
            if case .failure(let error) = moveWindowIfNeeded(newWindow, to: expectedWorkspaceName) {
                return .failure(error)
            }
            if case .failure(let error) = refocusIdeWindow(ideWindowIdToRefocus) {
                return .failure(error)
            }
            return .success(.created(windowId: newWindow.windowId))
        case .failure(let error):
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

    /// Lists Chrome windows that match the provided token across all workspaces.
    private func listChromeWindowsMatching(token: ProjectWindowToken) -> Result<[AeroSpaceWindow], ChromeLaunchError> {
        switch aeroSpaceClient.listWindowsAllDecoded() {
        case .failure(let error):
            return .failure(.aeroSpaceFailed(error))
        case .success(let windows):
            let matches = windows.filter {
                $0.appBundleId == Self.chromeBundleId && token.matches(windowTitle: $0.windowTitle)
            }
            return .success(matches)
        }
    }

    /// Moves a window into the expected workspace when needed.
    private func moveWindowIfNeeded(
        _ window: AeroSpaceWindow,
        to workspace: String
    ) -> Result<Void, ChromeLaunchError> {
        guard window.workspace != workspace else {
            return .success(())
        }
        switch aeroSpaceClient.moveWindow(windowId: window.windowId, to: workspace) {
        case .success:
            return .success(())
        case .failure(let error):
            return .failure(.aeroSpaceFailed(error))
        }
    }

    /// Polls the expected workspace for a newly created Chrome window.
    private func detectNewChromeWindow(
        windowToken: ProjectWindowToken,
        beforeWindowIds: Set<Int>
    ) -> Result<AeroSpaceWindow, ChromeLaunchError> {
        let pollOutcome: PollOutcome<AeroSpaceWindow, ChromeLaunchError> = Poller.poll(
            intervalMs: pollIntervalMs,
            timeoutMs: pollTimeoutMs,
            sleeper: sleeper
        ) { () -> PollDecision<AeroSpaceWindow, ChromeLaunchError> in
            let windowsResult = listChromeWindowsMatching(token: windowToken)
            switch windowsResult {
            case .failure(let error):
                return .failure(error)
            case .success(let windows):
                let newWindows = windows.filter { !beforeWindowIds.contains($0.windowId) }
                if newWindows.count == 1, let newWindow = newWindows.first {
                    return .success(newWindow)
                }
                if newWindows.count > 1 {
                    let ids = newWindows.map { $0.windowId }.sorted()
                    return .failure(.chromeWindowAmbiguous(token: windowToken.value, windowIds: ids))
                }
                return .keepWaiting
            }
        }

        switch pollOutcome {
        case .success(let window):
            return .success(window)
        case .failure(let error):
            return .failure(error)
        case .timedOut:
            return .failure(.chromeWindowNotDetected(token: windowToken.value))
        }
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
