import Foundation

/// Executes AeroSpace CLI commands with a timeout.
public protocol AeroSpaceCommandRunning {
    /// Executes a command and captures stdout/stderr.
    /// - Parameters:
    ///   - executable: Resolved AeroSpace CLI path.
    ///   - arguments: Arguments passed to the command.
    ///   - timeoutSeconds: Maximum time to wait before terminating the process.
    /// - Returns: Command result on success or a structured error.
    func run(
        executable: URL,
        arguments: [String],
        timeoutSeconds: TimeInterval
    ) -> Result<CommandResult, AeroSpaceCommandError>
}

/// Default AeroSpace command runner backed by `Process`.
public struct DefaultAeroSpaceCommandRunner: AeroSpaceCommandRunning {
    /// Creates a default command runner.
    public init() {}

    /// Executes a command and captures stdout/stderr with a timeout.
    /// - Parameters:
    ///   - executable: Resolved AeroSpace CLI path.
    ///   - arguments: Arguments passed to the command.
    ///   - timeoutSeconds: Maximum time to wait before terminating the process.
    /// - Returns: Command result on success or a structured error.
    public func run(
        executable: URL,
        arguments: [String],
        timeoutSeconds: TimeInterval
    ) -> Result<CommandResult, AeroSpaceCommandError> {
        precondition(timeoutSeconds > 0, "timeoutSeconds must be positive")

        let commandLabel = commandDescription(executable: executable, arguments: arguments)
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutLock = NSLock()
        let stderrLock = NSLock()
        var stdoutData = Data()
        var stderrData = Data()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            stdoutLock.lock()
            stdoutData.append(data)
            stdoutLock.unlock()
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            stderrLock.lock()
            stderrData.append(data)
            stderrLock.unlock()
        }

        let terminationSignal = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            terminationSignal.signal()
        }

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            try? stdoutPipe.fileHandleForReading.close()
            try? stderrPipe.fileHandleForReading.close()
            return .failure(
                .executionFailed(
                    .launchFailed(
                        command: commandLabel,
                        underlyingError: String(describing: error)
                    )
                )
            )
        }

        let terminationGraceSeconds: TimeInterval = 1
        let didExitOnTime = terminationSignal.wait(timeout: .now() + timeoutSeconds) == .success
        var didTimeout = false
        var didExit = didExitOnTime

        if !didExitOnTime {
            didTimeout = true
            process.terminate()
            if terminationSignal.wait(timeout: .now() + terminationGraceSeconds) == .success {
                didExit = true
            }
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        if didExit {
            let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            if !remainingStdout.isEmpty {
                stdoutLock.lock()
                stdoutData.append(remainingStdout)
                stdoutLock.unlock()
            }
            let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            if !remainingStderr.isEmpty {
                stderrLock.lock()
                stderrData.append(remainingStderr)
                stderrLock.unlock()
            }
        }
        try? stdoutPipe.fileHandleForReading.close()
        try? stderrPipe.fileHandleForReading.close()

        stdoutLock.lock()
        let stdoutSnapshot = stdoutData
        stdoutLock.unlock()
        stderrLock.lock()
        let stderrSnapshot = stderrData
        stderrLock.unlock()

        let stdout = String(data: stdoutSnapshot, encoding: .utf8) ?? ""
        let stderr = String(data: stderrSnapshot, encoding: .utf8) ?? ""
        let result = CommandResult(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr
        )

        if didTimeout {
            return .failure(
                .timedOut(command: commandLabel, timeoutSeconds: timeoutSeconds, result: result)
            )
        }

        if result.exitCode != 0 {
            return .failure(.executionFailed(.nonZeroExit(command: commandLabel, result: result)))
        }

        return .success(result)
    }

    /// Formats a command description for diagnostics.
    /// - Parameters:
    ///   - executable: Executable URL.
    ///   - arguments: Arguments passed to the executable.
    /// - Returns: Command description string.
    private func commandDescription(executable: URL, arguments: [String]) -> String {
        let command = ([executable.path] + arguments).joined(separator: " ")
        return command.trimmingCharacters(in: .whitespaces)
    }
}

/// Typed wrapper around AeroSpace CLI command execution.
public struct AeroSpaceClient {
    private static let listWindowsFormat =
        "%{window-id} %{workspace} %{app-bundle-id} %{app-name} %{window-title} %{window-layout}"

    private static let readinessProbeArguments = ["list-workspaces", "--focused", "--count"]

    public let executableURL: URL
    private let commandRunner: AeroSpaceCommandRunning
    private let timeoutSeconds: TimeInterval
    private let clock: DateProviding
    private let sleeper: AeroSpaceSleeping
    private let jitterProvider: AeroSpaceJitterProviding
    private let retryPolicy: AeroSpaceRetryPolicy
    private let windowDecoder: AeroSpaceWindowDecoder

    /// Creates a client using a resolved AeroSpace executable.
    /// - Parameters:
    ///   - executableURL: Resolved AeroSpace CLI path.
    ///   - commandRunner: Command runner used for CLI execution.
    ///   - timeoutSeconds: Maximum time allowed for each command.
    public init(
        executableURL: URL,
        commandRunner: AeroSpaceCommandRunning = DefaultAeroSpaceCommandRunner(),
        timeoutSeconds: TimeInterval
    ) {
        self.init(
            executableURL: executableURL,
            commandRunner: commandRunner,
            timeoutSeconds: timeoutSeconds,
            clock: SystemDateProvider(),
            sleeper: SystemAeroSpaceSleeper(),
            jitterProvider: SystemAeroSpaceJitterProvider(),
            retryPolicy: .standard,
            windowDecoder: AeroSpaceWindowDecoder()
        )
    }

    /// Internal initializer with injectable dependencies (testing).
    /// - Parameters:
    ///   - executableURL: Resolved AeroSpace CLI path.
    ///   - commandRunner: Command runner used for CLI execution.
    ///   - timeoutSeconds: Maximum time allowed for each command.
    ///   - clock: Clock used for retry budget tracking.
    ///   - sleeper: Sleeper used to delay between retries.
    ///   - jitterProvider: Provider for retry jitter.
    ///   - retryPolicy: Retry policy settings.
    ///   - windowDecoder: Decoder used for list-windows JSON.
    init(
        executableURL: URL,
        commandRunner: AeroSpaceCommandRunning,
        timeoutSeconds: TimeInterval,
        clock: DateProviding,
        sleeper: AeroSpaceSleeping,
        jitterProvider: AeroSpaceJitterProviding,
        retryPolicy: AeroSpaceRetryPolicy,
        windowDecoder: AeroSpaceWindowDecoder
    ) {
        precondition(timeoutSeconds > 0, "timeoutSeconds must be positive")
        self.executableURL = executableURL
        self.commandRunner = commandRunner
        self.timeoutSeconds = timeoutSeconds
        self.clock = clock
        self.sleeper = sleeper
        self.jitterProvider = jitterProvider
        self.retryPolicy = retryPolicy
        self.windowDecoder = windowDecoder
    }

    /// Creates a client by resolving the AeroSpace CLI once at startup.
    /// - Parameters:
    ///   - resolver: Resolver used to locate the AeroSpace CLI.
    ///   - commandRunner: Command runner used for CLI execution.
    ///   - timeoutSeconds: Maximum time allowed for each command.
    /// - Throws: AeroSpaceBinaryResolutionError when resolution fails.
    public init(
        resolver: AeroSpaceBinaryResolving = DefaultAeroSpaceBinaryResolver(),
        commandRunner: AeroSpaceCommandRunning = DefaultAeroSpaceCommandRunner(),
        timeoutSeconds: TimeInterval
    ) throws {
        let resolution = resolver.resolve()
        switch resolution {
        case .success(let executableURL):
            self.init(
                executableURL: executableURL,
                commandRunner: commandRunner,
                timeoutSeconds: timeoutSeconds
            )
        case .failure(let error):
            throw error
        }
    }

    /// Switches to the provided workspace name.
    /// - Parameter name: Workspace name to activate.
    /// - Returns: Command result or a structured error.
    public func switchWorkspace(_ name: String) -> Result<CommandResult, AeroSpaceCommandError> {
        runCommand(arguments: ["workspace", name])
    }

    /// Returns the currently focused workspace name.
    /// - Returns: Focused workspace name or a structured error.
    public func focusedWorkspace() -> Result<String, AeroSpaceCommandError> {
        switch runCommand(arguments: ["list-workspaces", "--focused"]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            let workspace = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !workspace.isEmpty else {
                return .failure(
                    .unexpectedOutput(
                        command: describeCommand(arguments: ["list-workspaces", "--focused"]),
                        detail: "Focused workspace output was empty."
                    )
                )
            }
            return .success(workspace)
        }
    }

    /// Lists all workspace names.
    /// - Returns: Workspace names or a structured error.
    public func listWorkspaces() -> Result<[String], AeroSpaceCommandError> {
        switch runCommand(arguments: ["list-workspaces"]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            let lines = result.stdout
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return .success(lines)
        }
    }

    /// Checks whether a workspace exists.
    /// - Parameter name: Workspace name to check.
    /// - Returns: True if the workspace exists.
    public func workspaceExists(_ name: String) -> Result<Bool, AeroSpaceCommandError> {
        listWorkspaces().map { $0.contains(name) }
    }

    /// Lists windows for a specific workspace as JSON.
    /// - Parameters:
    ///   - workspace: Workspace name to query.
    ///   - appBundleId: Optional bundle ID filter to reduce output volume.
    /// - Returns: Command result containing JSON output or a structured error.
    public func listWindows(
        workspace: String,
        appBundleId: String? = nil
    ) -> Result<CommandResult, AeroSpaceCommandError> {
        var arguments = [
            "list-windows",
            "--workspace",
            workspace
        ]
        if let appBundleId, !appBundleId.isEmpty {
            arguments.append(contentsOf: ["--app-bundle-id", appBundleId])
        }
        arguments.append(contentsOf: ["--json", "--format", Self.listWindowsFormat])
        return runCommand(arguments: arguments)
    }

    /// Lists windows for a specific workspace as JSON without internal retries.
    /// - Parameters:
    ///   - workspace: Workspace name to query.
    ///   - appBundleId: Optional bundle ID filter to reduce output volume.
    /// - Returns: Command result containing JSON output or a structured error.
    func listWindowsNoRetry(
        workspace: String,
        appBundleId: String? = nil
    ) -> Result<CommandResult, AeroSpaceCommandError> {
        var arguments = [
            "list-windows",
            "--workspace",
            workspace
        ]
        if let appBundleId, !appBundleId.isEmpty {
            arguments.append(contentsOf: ["--app-bundle-id", appBundleId])
        }
        arguments.append(contentsOf: ["--json", "--format", Self.listWindowsFormat])
        return runCommandNoRetry(arguments: arguments)
    }

    /// Lists windows across all workspaces as JSON.
    /// Note: Use only for token-based matching of ProjectWorkspaces-owned windows.
    /// - Returns: Command result containing JSON output or a structured error.
    public func listWindowsAll() -> Result<CommandResult, AeroSpaceCommandError> {
        runCommand(
            arguments: [
                "list-windows",
                "--all",
                "--json",
                "--format",
                Self.listWindowsFormat
            ]
        )
    }

    /// Lists windows for a specific workspace as decoded models.
    /// - Parameters:
    ///   - workspace: Workspace name to query.
    ///   - appBundleId: Optional bundle ID filter to reduce output volume.
    /// - Returns: Decoded windows or a structured error.
    public func listWindowsDecoded(
        workspace: String,
        appBundleId: String? = nil
    ) -> Result<[AeroSpaceWindow], AeroSpaceCommandError> {
        switch listWindows(workspace: workspace, appBundleId: appBundleId) {
        case .success(let result):
            return windowDecoder.decodeWindows(from: result.stdout)
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Lists windows for a specific workspace as decoded models without internal retries.
    /// - Parameters:
    ///   - workspace: Workspace name to query.
    ///   - appBundleId: Optional bundle ID filter to reduce output volume.
    /// - Returns: Decoded windows or a structured error.
    func listWindowsDecodedNoRetry(
        workspace: String,
        appBundleId: String? = nil
    ) -> Result<[AeroSpaceWindow], AeroSpaceCommandError> {
        switch listWindowsNoRetry(workspace: workspace, appBundleId: appBundleId) {
        case .success(let result):
            return windowDecoder.decodeWindows(from: result.stdout)
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Lists windows across all workspaces as decoded models.
    /// Note: Use only for token-based matching of ProjectWorkspaces-owned windows.
    /// - Returns: Decoded windows or a structured error.
    public func listWindowsAllDecoded() -> Result<[AeroSpaceWindow], AeroSpaceCommandError> {
        switch listWindowsAll() {
        case .success(let result):
            return windowDecoder.decodeWindows(from: result.stdout)
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Lists the currently focused window as JSON.
    /// - Returns: Command result containing JSON output (typically one window) or a structured error.
    public func listWindowsFocused() -> Result<CommandResult, AeroSpaceCommandError> {
        runCommand(
            arguments: [
                "list-windows",
                "--focused",
                "--json",
                "--format",
                Self.listWindowsFormat
            ]
        )
    }

    /// Lists the currently focused window as JSON without internal retries.
    /// - Returns: Command result containing JSON output or a structured error.
    func listWindowsFocusedNoRetry() -> Result<CommandResult, AeroSpaceCommandError> {
        runCommandNoRetry(
            arguments: [
                "list-windows",
                "--focused",
                "--json",
                "--format",
                Self.listWindowsFormat
            ]
        )
    }

    /// Lists the currently focused window as decoded models.
    /// - Returns: Decoded windows (typically one) or a structured error.
    public func listWindowsFocusedDecoded() -> Result<[AeroSpaceWindow], AeroSpaceCommandError> {
        switch listWindowsFocused() {
        case .success(let result):
            return windowDecoder.decodeWindows(from: result.stdout)
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Lists the currently focused window as decoded models without internal retries.
    /// - Returns: Decoded windows (typically one) or a structured error.
    func listWindowsFocusedDecodedNoRetry() -> Result<[AeroSpaceWindow], AeroSpaceCommandError> {
        switch listWindowsFocusedNoRetry() {
        case .success(let result):
            return windowDecoder.decodeWindows(from: result.stdout)
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Focuses a window by id.
    /// - Parameter windowId: AeroSpace window id to focus.
    /// - Returns: Command result or a structured error.
    public func focusWindow(windowId: Int) -> Result<CommandResult, AeroSpaceCommandError> {
        runCommand(arguments: ["focus", "--window-id", String(windowId)])
    }

    /// Moves a window into the provided workspace.
    /// - Parameters:
    ///   - windowId: AeroSpace window id to move.
    ///   - workspace: Destination workspace name.
    /// - Returns: Command result or a structured error.
    public func moveWindow(windowId: Int, to workspace: String) -> Result<CommandResult, AeroSpaceCommandError> {
        runCommand(arguments: ["move-node-to-workspace", "--window-id", String(windowId), workspace])
    }

    /// Sets a window to floating layout mode.
    /// - Parameter windowId: AeroSpace window id to update.
    /// - Returns: Command result or a structured error.
    public func setFloatingLayout(windowId: Int) -> Result<CommandResult, AeroSpaceCommandError> {
        runCommand(arguments: ["layout", "--window-id", String(windowId), "floating"])
    }

    /// Closes a window by id.
    /// - Parameter windowId: AeroSpace window id to close.
    /// - Returns: Command result or a structured error.
    public func closeWindow(windowId: Int) -> Result<CommandResult, AeroSpaceCommandError> {
        runCommand(arguments: ["close", "--window-id", String(windowId)])
    }

    /// Executes an AeroSpace CLI command with the configured timeout.
    /// - Parameter arguments: Arguments passed to the AeroSpace CLI.
    /// - Returns: Command result or a structured error.
    private func runCommand(arguments: [String]) -> Result<CommandResult, AeroSpaceCommandError> {
        runCommandWithRetry(arguments: arguments)
    }

    private func runCommandNoRetry(arguments: [String]) -> Result<CommandResult, AeroSpaceCommandError> {
        commandRunner.run(
            executable: executableURL,
            arguments: arguments,
            timeoutSeconds: timeoutSeconds
        )
    }

    private func runCommandWithRetry(arguments: [String]) -> Result<CommandResult, AeroSpaceCommandError> {
        var context = RetryContext(
            commandDescription: describeCommand(arguments: arguments),
            probeDescription: describeCommand(arguments: Self.readinessProbeArguments),
            startTime: clock.now(),
            delaySeconds: retryPolicy.initialDelaySeconds
        )

        while true {
            let outcome = commandRunner.run(
                executable: executableURL,
                arguments: arguments,
                timeoutSeconds: timeoutSeconds
            )

            switch outcome {
            case .success:
                return outcome
            case .failure(let error):
                switch error {
                case .executionFailed(let execError):
                    switch execError {
                    case .launchFailed:
                        return .failure(error)
                    case .nonZeroExit(_, let result):
                        context.lastCommandResult = result
                        let probeOutcome = runReadinessProbe()
                        switch probeOutcome {
                        case .success:
                            return .failure(error)
                        case .failure(let probeError):
                            guard case .executionFailed(.nonZeroExit(_, let probeResult)) = probeError else {
                                return .failure(probeError)
                            }
                            context.lastProbeResult = probeResult

                            if let budgetExceededError = checkBudgetExceeded(context: context, fallbackError: error) {
                                return .failure(budgetExceededError)
                            }

                            let remainingBudget = retryPolicy.totalCapSeconds - clock.now().timeIntervalSince(context.startTime)
                            let sleepSeconds = min(jitteredDelay(baseDelay: context.delaySeconds), remainingBudget)
                            sleeper.sleep(seconds: sleepSeconds)

                            if let budgetExceededError = checkBudgetExceeded(context: context, fallbackError: error) {
                                return .failure(budgetExceededError)
                            }

                            context.delaySeconds = min(context.delaySeconds * retryPolicy.backoffMultiplier, retryPolicy.maxDelaySeconds)
                            context.attempt += 1
                        }
                    }
                case .timedOut:
                    return .failure(error)
                case .decodingFailed, .notReady, .unexpectedOutput:
                    return .failure(error)
                }
            }
        }
    }

    /// Checks if the retry budget is exceeded and returns the appropriate error if so.
    private func checkBudgetExceeded(
        context: RetryContext,
        fallbackError: AeroSpaceCommandError
    ) -> AeroSpaceCommandError? {
        let elapsed = clock.now().timeIntervalSince(context.startTime)
        let budgetExceeded = context.attempt >= retryPolicy.maxAttempts || elapsed >= retryPolicy.totalCapSeconds

        guard budgetExceeded else {
            return nil
        }

        return buildNotReadyError(
            timeoutSeconds: retryPolicy.totalCapSeconds,
            commandDescription: context.commandDescription,
            probeDescription: context.probeDescription,
            lastCommandResult: context.lastCommandResult,
            lastProbeResult: context.lastProbeResult,
            fallbackError: fallbackError
        )
    }

    private func runReadinessProbe() -> Result<CommandResult, AeroSpaceCommandError> {
        commandRunner.run(
            executable: executableURL,
            arguments: Self.readinessProbeArguments,
            timeoutSeconds: timeoutSeconds
        )
    }

    private func describeCommand(arguments: [String]) -> String {
        ([executableURL.path] + arguments).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    private func jitteredDelay(baseDelay: TimeInterval) -> TimeInterval {
        let jitterRange = baseDelay * retryPolicy.jitterFraction
        let jitterUnit = (jitterProvider.nextUnit() * 2.0) - 1.0
        let jittered = baseDelay + (jitterRange * jitterUnit)
        return max(0, jittered)
    }

    private func buildNotReadyError(
        timeoutSeconds: TimeInterval,
        commandDescription: String,
        probeDescription: String,
        lastCommandResult: CommandResult?,
        lastProbeResult: CommandResult?,
        fallbackError: AeroSpaceCommandError
    ) -> AeroSpaceCommandError {
        guard let lastCommandResult, let lastProbeResult else {
            return fallbackError
        }
        let notReady = AeroSpaceNotReady(
            timeoutSeconds: timeoutSeconds,
            lastCommandDescription: commandDescription,
            lastCommand: lastCommandResult,
            lastProbeDescription: probeDescription,
            lastProbe: lastProbeResult
        )
        return .notReady(notReady)
    }
}
