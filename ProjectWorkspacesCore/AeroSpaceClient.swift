import Foundation

/// Errors surfaced when executing AeroSpace CLI commands.
public enum AeroSpaceCommandError: Error, Equatable, Sendable {
    case launchFailed(command: String, underlyingError: String)
    case nonZeroExit(command: String, result: CommandResult)
    case timedOut(command: String, timeoutSeconds: TimeInterval, result: CommandResult)
}

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
                .launchFailed(
                    command: commandLabel,
                    underlyingError: String(describing: error)
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
            return .failure(.nonZeroExit(command: commandLabel, result: result))
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
    public let executableURL: URL
    private let commandRunner: AeroSpaceCommandRunning
    private let timeoutSeconds: TimeInterval

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
        precondition(timeoutSeconds > 0, "timeoutSeconds must be positive")
        self.executableURL = executableURL
        self.commandRunner = commandRunner
        self.timeoutSeconds = timeoutSeconds
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

    /// Lists windows for a specific workspace as JSON.
    /// - Parameter workspace: Workspace name to query.
    /// - Returns: Command result containing JSON output or a structured error.
    public func listWindows(workspace: String) -> Result<CommandResult, AeroSpaceCommandError> {
        runCommand(arguments: ["list-windows", "--workspace", workspace, "--json"])
    }

    /// Lists windows across all workspaces as JSON.
    /// - Returns: Command result containing JSON output or a structured error.
    public func listWindowsAll() -> Result<CommandResult, AeroSpaceCommandError> {
        runCommand(arguments: ["list-windows", "--all", "--json"])
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
        runCommand(arguments: ["layout", "floating", "--window-id", String(windowId)])
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
        commandRunner.run(
            executable: executableURL,
            arguments: arguments,
            timeoutSeconds: timeoutSeconds
        )
    }
}
