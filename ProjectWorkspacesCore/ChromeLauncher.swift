import Foundation

/// Creates Chrome windows deterministically for the target workspace.
public struct ChromeLauncher {
    public static let chromeBundleId = "com.google.Chrome"
    public static let chromeAppName = "Google Chrome"
    public static let defaultPollIntervalMs = 200
    public static let defaultPollTimeoutMs = 5000
    public static let defaultWorkspaceProbeTimeoutMs = 800
    public static let defaultFocusedProbeTimeoutMs = 1500
    public static let defaultRefocusDelayMs = 100

    private let aeroSpaceClient: AeroSpaceClient
    private let commandRunner: CommandRunning
    private let appDiscovery: AppDiscovering
    private let sleeper: AeroSpaceSleeping
    private let pollIntervalMs: Int
    private let pollTimeoutMs: Int
    private let workspaceProbeTimeoutMs: Int
    private let focusedProbeTimeoutMs: Int
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
            workspaceProbeTimeoutMs: Self.defaultWorkspaceProbeTimeoutMs,
            focusedProbeTimeoutMs: Self.defaultFocusedProbeTimeoutMs,
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
        workspaceProbeTimeoutMs: Int,
        focusedProbeTimeoutMs: Int,
        refocusDelayMs: Int
    ) {
        precondition(pollIntervalMs > 0, "pollIntervalMs must be positive")
        precondition(pollTimeoutMs > 0, "pollTimeoutMs must be positive")
        precondition(workspaceProbeTimeoutMs > 0, "workspaceProbeTimeoutMs must be positive")
        precondition(focusedProbeTimeoutMs > 0, "focusedProbeTimeoutMs must be positive")
        precondition(refocusDelayMs >= 0, "refocusDelayMs must be non-negative")
        self.aeroSpaceClient = aeroSpaceClient
        self.commandRunner = commandRunner
        self.appDiscovery = appDiscovery
        self.sleeper = sleeper
        self.pollIntervalMs = pollIntervalMs
        self.pollTimeoutMs = pollTimeoutMs
        self.workspaceProbeTimeoutMs = workspaceProbeTimeoutMs
        self.focusedProbeTimeoutMs = focusedProbeTimeoutMs
        self.refocusDelayMs = refocusDelayMs
    }

    /// Ensures a Chrome window exists for the provided workspace using a deterministic token.
    /// Window detection is scoped to the expected workspace.
    /// New windows are created via `open -n` so Chrome honors `--window-name`.
    ///
    /// Refocus only occurs when `ideWindowIdToRefocus` is provided; callers may pass `nil`
    /// to avoid mid-activation focus changes and handle final focus elsewhere.
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
    ) -> Result<ChromeLaunchResult, ChromeLaunchError> {
        var warnings: [ChromeLaunchWarning] = []
        let existingMatchesResult = listChromeWindowsMatching(
            token: windowToken,
            workspace: expectedWorkspaceName
        )
        let existingMatches: [AeroSpaceWindow]
        switch existingMatchesResult {
        case .failure(let error):
            return .failure(error)
        case .success(let matches):
            existingMatches = matches
        }

        if !existingMatches.isEmpty {
            let existingResult = handleExistingMatches(
                existingMatches,
                allowExistingWindows: allowExistingWindows,
                expectedWorkspaceName: expectedWorkspaceName,
                windowToken: windowToken,
                warningSink: { warnings.append($0) }
            )
            switch existingResult {
            case .failure(let error):
                return .failure(error)
            case .success(let outcome):
                return .success(ChromeLaunchResult(outcome: outcome, warnings: warnings))
            }
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
        let timeouts = launchDetectionTimeouts()
        let workspaceOutcome = pollForChromeWindowInWorkspace(
            windowToken: windowToken,
            beforeWindowIds: beforeIds,
            workspace: expectedWorkspaceName,
            timeoutMs: timeouts.workspaceMs,
            warningSink: { warnings.append($0) }
        )

        switch workspaceOutcome {
        case .success(let newWindow):
            let result = finalizeDetectedWindow(
                newWindow,
                expectedWorkspaceName: expectedWorkspaceName,
                ideWindowIdToRefocus: ideWindowIdToRefocus
            )
            return result.map { ChromeLaunchResult(outcome: $0, warnings: warnings) }
        case .failure(let error):
            return .failure(error)
        case .timedOut:
            break
        }

        let focusedPrimaryOutcome = pollForFocusedChromeWindow(
            windowToken: windowToken,
            timeoutMs: timeouts.focusedPrimaryMs
        )
        switch focusedPrimaryOutcome {
        case .success(let focusedWindow):
            let result = finalizeDetectedWindow(
                focusedWindow,
                expectedWorkspaceName: expectedWorkspaceName,
                ideWindowIdToRefocus: ideWindowIdToRefocus
            )
            return result.map { ChromeLaunchResult(outcome: $0, warnings: warnings) }
        case .failure(let error):
            return .failure(error)
        case .timedOut:
            break
        }

        if timeouts.focusedSecondaryMs > 0 {
            let focusedSecondaryOutcome = pollForFocusedChromeWindow(
                windowToken: windowToken,
                timeoutMs: timeouts.focusedSecondaryMs
            )
            switch focusedSecondaryOutcome {
            case .success(let focusedWindow):
                let result = finalizeDetectedWindow(
                    focusedWindow,
                    expectedWorkspaceName: expectedWorkspaceName,
                    ideWindowIdToRefocus: ideWindowIdToRefocus
                )
                return result.map { ChromeLaunchResult(outcome: $0, warnings: warnings) }
            case .failure(let error):
                return .failure(error)
            case .timedOut:
                break
            }
        }

        return .failure(.chromeWindowNotDetected(token: windowToken.value))
    }

    /// Handles tokened Chrome windows that already exist before creation attempts.
    /// - Note: When reuse is disallowed, any existing token match fails to avoid duplicate windows.
    private func handleExistingMatches(
        _ matches: [AeroSpaceWindow],
        allowExistingWindows: Bool,
        expectedWorkspaceName: String,
        windowToken: ProjectWindowToken,
        warningSink: (ChromeLaunchWarning) -> Void
    ) -> Result<ChromeLaunchOutcome, ChromeLaunchError> {
        let existingIds = matches.map { $0.windowId }.sorted()
        if allowExistingWindows {
            if matches.count == 1, let existing = matches.first {
                return .success(.existing(windowId: existing.windowId))
            }
            let selectedId = existingIds[0]
            warningSink(
                .multipleWindows(
                    workspace: expectedWorkspaceName,
                    chosenId: selectedId,
                    extraIds: Array(existingIds.dropFirst())
                )
            )
            return .success(.existing(windowId: selectedId))
        }
        return .failure(.chromeWindowAmbiguous(token: windowToken.value, windowIds: existingIds))
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

    /// Lists Chrome windows that match the provided token in the provided workspace.
    private func listChromeWindowsMatching(
        token: ProjectWindowToken,
        workspace: String
    ) -> Result<[AeroSpaceWindow], ChromeLaunchError> {
        switch aeroSpaceClient.listWindowsDecoded(
            workspace: workspace,
            appBundleId: Self.chromeBundleId
        ) {
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
    private func pollForChromeWindowInWorkspace(
        windowToken: ProjectWindowToken,
        beforeWindowIds: Set<Int>,
        workspace: String,
        timeoutMs: Int,
        warningSink: (ChromeLaunchWarning) -> Void
    ) -> PollOutcome<AeroSpaceWindow, ChromeLaunchError> {
        guard timeoutMs > 0 else {
            return .timedOut
        }
        let pollOutcome: PollOutcome<AeroSpaceWindow, ChromeLaunchError> = Poller.poll(
            intervalMs: pollIntervalMs,
            timeoutMs: timeoutMs,
            sleeper: sleeper
        ) { () -> PollDecision<AeroSpaceWindow, ChromeLaunchError> in
            let windowsResult = listChromeWindowsMatching(
                token: windowToken,
                workspace: workspace
            )
            switch windowsResult {
            case .failure(let error):
                if shouldRetryPoll(error) {
                    return .keepWaiting
                }
                return .failure(error)
            case .success(let windows):
                let newWindows = windows.filter { !beforeWindowIds.contains($0.windowId) }
                if newWindows.count == 1, let newWindow = newWindows.first {
                    return .success(newWindow)
                }
                if newWindows.count > 1 {
                    let ids = newWindows.map { $0.windowId }.sorted()
                    warningSink(
                        .multipleWindows(
                            workspace: workspace,
                            chosenId: ids[0],
                            extraIds: Array(ids.dropFirst())
                        )
                    )
                    return .success(newWindows.sorted { $0.windowId < $1.windowId }[0])
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
            return .timedOut
        }
    }

    private func pollForFocusedChromeWindow(
        windowToken: ProjectWindowToken,
        timeoutMs: Int
    ) -> PollOutcome<AeroSpaceWindow, ChromeLaunchError> {
        guard timeoutMs > 0 else {
            return .timedOut
        }
        let pollOutcome: PollOutcome<AeroSpaceWindow, ChromeLaunchError> = Poller.poll(
            intervalMs: pollIntervalMs,
            timeoutMs: timeoutMs,
            sleeper: sleeper
        ) { () -> PollDecision<AeroSpaceWindow, ChromeLaunchError> in
            switch aeroSpaceClient.listWindowsFocusedDecoded() {
            case .failure(let error):
                if shouldRetryFocusedWindow(error) {
                    return .keepWaiting
                }
                return .failure(.aeroSpaceFailed(error))
            case .success(let windows):
                guard let window = windows.first else {
                    return .keepWaiting
                }
                guard window.appBundleId == Self.chromeBundleId,
                      windowToken.matches(windowTitle: window.windowTitle) else {
                    return .keepWaiting
                }
                return .success(window)
            }
        }

        switch pollOutcome {
        case .success(let window):
            return .success(window)
        case .failure(let error):
            return .failure(error)
        case .timedOut:
            return .timedOut
        }
    }

    private func finalizeDetectedWindow(
        _ window: AeroSpaceWindow,
        expectedWorkspaceName: String,
        ideWindowIdToRefocus: Int?
    ) -> Result<ChromeLaunchOutcome, ChromeLaunchError> {
        if case .failure(let error) = moveWindowIfNeeded(window, to: expectedWorkspaceName) {
            return .failure(error)
        }
        if case .failure(let error) = refocusIdeWindow(ideWindowIdToRefocus) {
            return .failure(error)
        }
        return .success(.created(windowId: window.windowId))
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

    private func shouldRetryPoll(_ error: ChromeLaunchError) -> Bool {
        guard case .aeroSpaceFailed(let aeroError) = error else {
            return false
        }
        return shouldRetryPoll(aeroError)
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
}

private struct LaunchDetectionTimeouts {
    let workspaceMs: Int
    let focusedPrimaryMs: Int
    let focusedSecondaryMs: Int
}
