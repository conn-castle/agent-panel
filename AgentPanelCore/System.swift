import Foundation

// MARK: - Executable Resolution

/// Resolves executable names to full paths for GUI app environments.
///
/// GUI applications on macOS do not inherit the user's shell PATH environment.
/// This resolver checks standard installation paths and falls back to a login
/// shell `which` lookup for non-standard locations.
public struct ExecutableResolver {
    /// Standard search paths for macOS executables.
    public static let standardSearchPaths: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/opt/homebrew/sbin",
        "/usr/local/sbin",
        "/usr/sbin",
        "/sbin"
    ]

    private let fileSystem: FileSystem
    private let searchPaths: [String]

    /// Creates an executable resolver.
    /// - Parameters:
    ///   - fileSystem: File system accessor for existence and executable checks.
    ///   - searchPaths: Paths to search for executables.
    public init(
        fileSystem: FileSystem = DefaultFileSystem(),
        searchPaths: [String] = ExecutableResolver.standardSearchPaths
    ) {
        self.fileSystem = fileSystem
        self.searchPaths = searchPaths
    }

    /// Resolves an executable name to its full path.
    /// - Parameter name: Executable name (e.g., "brew", "aerospace", "code").
    /// - Returns: Full path to executable, or nil if not found.
    public func resolve(_ name: String) -> String? {
        // If already an absolute path, verify it exists and is executable
        if name.hasPrefix("/") {
            let url = URL(fileURLWithPath: name)
            if fileSystem.isExecutableFile(at: url) {
                return name
            }
            return nil
        }

        // Search standard paths
        for searchPath in searchPaths {
            let candidatePath = "\(searchPath)/\(name)"
            let candidateURL = URL(fileURLWithPath: candidatePath)
            if fileSystem.isExecutableFile(at: candidateURL) {
                return candidatePath
            }
        }

        // Fallback: try login shell which
        return resolveViaLoginShell(name)
    }

    /// Falls back to login shell `which` for non-standard locations.
    /// - Parameter name: Executable name to resolve.
    /// - Returns: Full path from login shell, or nil if not found.
    private func resolveViaLoginShell(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // Use login shell (-l) to get full PATH, non-interactive (-c) for command
        process.arguments = ["-l", "-c", "which \(name)"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                return nil
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return nil
            }

            let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? nil : path
        } catch {
            return nil
        }
    }
}

// MARK: - Command Execution

/// Result of executing an external command.
public struct ApCommandResult: Equatable, Sendable {
    /// Process termination status.
    public let exitCode: Int32
    /// Captured standard output.
    public let stdout: String
    /// Captured standard error.
    public let stderr: String

    /// Creates a new command result.
    /// - Parameters:
    ///   - exitCode: Process termination status.
    ///   - stdout: Captured standard output.
    ///   - stderr: Captured standard error.
    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Runs external commands with executable path resolution for GUI environments.
public struct ApSystemCommandRunner {
    private let executableResolver: ExecutableResolver

    /// Creates a command runner with the default executable resolver.
    /// - Parameter executableResolver: Resolver for finding executable paths.
    public init(executableResolver: ExecutableResolver = ExecutableResolver()) {
        self.executableResolver = executableResolver
    }

    /// Runs the provided executable with arguments.
    /// - Parameters:
    ///   - executable: Executable name to run.
    ///   - arguments: Arguments to pass to the executable.
    ///   - timeoutSeconds: Timeout in seconds. Defaults to 5s. Pass nil to wait indefinitely.
    /// - Returns: Captured output on success, or an error.
    public func run(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval? = 5
    ) -> Result<ApCommandResult, ApCoreError> {
        // Resolve executable path for GUI environment
        guard let executablePath = executableResolver.resolve(executable) else {
            return .failure(ApCoreError(
                category: .command,
                message: "Executable not found: \(executable)",
                detail: "Searched: \(ExecutableResolver.standardSearchPaths.joined(separator: ", "))"
            ))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Collect output concurrently to avoid pipe buffer deadlock.
        // If we wait for termination before reading, and the process writes
        // more than the pipe buffer size (~64KB), it will block and never terminate.
        var stdoutData = Data()
        var stderrData = Data()
        let dataLock = NSLock()

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading

        stdoutHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                dataLock.lock()
                stdoutData.append(data)
                dataLock.unlock()
            }
        }

        stderrHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                dataLock.lock()
                stderrData.append(data)
                dataLock.unlock()
            }
        }

        let completion = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completion.signal() }

        do {
            try process.run()
        } catch {
            // Clean up handlers
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
            return .failure(ApCoreError(message: "Failed to launch \(executable): \(error.localizedDescription)"))
        }

        // Wait for process with optional timeout
        let didTimeout: Bool
        if let timeoutSeconds = timeoutSeconds {
            let waitResult = completion.wait(timeout: .now() + timeoutSeconds)
            didTimeout = waitResult == .timedOut
            if didTimeout {
                process.terminate()
                _ = completion.wait(timeout: .now() + 1)
            }
        } else {
            completion.wait()
            didTimeout = false
        }

        // Clean up handlers and read any remaining data
        stdoutHandle.readabilityHandler = nil
        stderrHandle.readabilityHandler = nil

        // Read any final data that may have arrived
        dataLock.lock()
        stdoutData.append(stdoutHandle.readDataToEndOfFile())
        stderrData.append(stderrHandle.readDataToEndOfFile())
        dataLock.unlock()

        if didTimeout {
            return .failure(
                ApCoreError(
                    message: "Command timed out after \(timeoutSeconds!)s: \(executable) \(arguments.joined(separator: " "))"
                )
            )
        }

        guard let stdout = String(data: stdoutData, encoding: .utf8) else {
            return .failure(ApCoreError(message: "Command output was not valid UTF-8 (stdout)."))
        }

        guard let stderr = String(data: stderrData, encoding: .utf8) else {
            return .failure(ApCoreError(message: "Command output was not valid UTF-8 (stderr)."))
        }

        return .success(
            ApCommandResult(
                exitCode: process.terminationStatus,
                stdout: stdout,
                stderr: stderr
            )
        )
    }
}

// MARK: - IDE Launchers

/// Launches new VS Code windows with a tagged window title.
struct ApVSCodeLauncher {
    /// VS Code bundle identifier used for filtering windows.
    static let bundleId = "com.microsoft.VSCode"

    private let dataStore: DataPaths
    private let commandRunner: ApSystemCommandRunner

    /// Creates a VS Code launcher.
    /// - Parameters:
    ///   - dataStore: Data store for workspace file paths.
    ///   - commandRunner: Command runner for launching VS Code.
    init(dataStore: DataPaths = .default(), commandRunner: ApSystemCommandRunner = ApSystemCommandRunner()) {
        self.dataStore = dataStore
        self.commandRunner = commandRunner
    }

    /// Opens a new VS Code window tagged with the provided identifier.
    /// - Parameter identifier: Identifier embedded in the window title token.
    /// - Returns: Success or an error.
    func openNewWindow(identifier: String) -> Result<Void, ApCoreError> {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(ApCoreError(message: "Identifier cannot be empty."))
        }
        if trimmed.contains("/") {
            return .failure(ApCoreError(message: "Identifier cannot contain '/'."))
        }

        // VS Code expands these placeholders in window.title:
        // - ${dirty}: indicator for unsaved changes in the active editor
        // - ${activeEditorShort}: short name of the active file
        // - ${separator}: VS Code's configured title separator
        // - ${rootName}: workspace folder name
        // - ${appName}: application name
        // We prefix the title with "AP:<identifier>" so we can detect/move the correct window later.
        let windowTitle = "\(ApIdeToken.prefix)\(trimmed) - ${dirty}${activeEditorShort}${separator}${rootName}${separator}${appName}"
        let workspaceDirectory = dataStore.vscodeWorkspaceDirectory
        let workspaceURL = workspaceDirectory.appendingPathComponent("\(trimmed).code-workspace")

        let payload: [String: Any] = [
            "folders": [],
            "settings": ["window.title": windowTitle]
        ]

        do {
            try FileManager.default.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: workspaceURL, options: [.atomic])
        } catch {
            return .failure(ApCoreError(message: "Failed to write workspace file: \(error.localizedDescription)"))
        }

        switch commandRunner.run(executable: "code", arguments: ["--new-window", workspaceURL.path], timeoutSeconds: 10) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                let trimmedStderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = trimmedStderr.isEmpty ? "" : "\n\(trimmedStderr)"
                return .failure(
                    ApCoreError(message: "code failed with exit code \(result.exitCode).\(suffix)")
                )
            }
            return .success(())
        }
    }
}

/// Launches new Chrome windows with a tagged window title.
struct ApChromeLauncher {
    /// Chrome bundle identifier used for filtering windows.
    static let bundleId = "com.google.Chrome"

    private let commandRunner = ApSystemCommandRunner()

    /// Opens a new Chrome window tagged with the provided identifier.
    /// - Parameter identifier: Identifier embedded in the window title token.
    /// - Returns: Success or an error.
    func openNewWindow(identifier: String) -> Result<Void, ApCoreError> {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(ApCoreError(message: "Identifier cannot be empty."))
        }
        if trimmed.contains("/") {
            return .failure(ApCoreError(message: "Identifier cannot contain '/'."))
        }

        let windowTitle = ApChromeLauncher.escapeForAppleScriptString("\(ApIdeToken.prefix)\(trimmed)")
        let script = [
            "tell application \"Google Chrome\"",
            "activate",
            "set newWindow to make new window",
            "set URL of active tab of newWindow to \"https://example.com\"",
            "set given name of newWindow to \"\(windowTitle)\"",
            "end tell"
        ]

        switch commandRunner.run(executable: "osascript", arguments: ApChromeLauncher.scriptArguments(lines: script), timeoutSeconds: 10) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                let trimmedStderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = trimmedStderr.isEmpty ? "" : "\n\(trimmedStderr)"
                return .failure(
                    ApCoreError(
                        message: "osascript failed with exit code \(result.exitCode).\(suffix)"
                    )
                )
            }
            return .success(())
        }
    }

    /// Builds osascript arguments for a list of script lines.
    /// - Parameter lines: AppleScript lines to execute.
    /// - Returns: Arguments for osascript.
    private static func scriptArguments(lines: [String]) -> [String] {
        var args: [String] = []
        for line in lines {
            args.append("-e")
            args.append(line)
        }
        return args
    }

    /// Escapes a string for insertion into a double-quoted AppleScript string.
    /// - Parameter value: Raw value.
    /// - Returns: Escaped string.
    private static func escapeForAppleScriptString(_ value: String) -> String {
        var escaped = value
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        return escaped
    }
}
