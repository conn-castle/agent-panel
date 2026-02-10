import Foundation

// MARK: - Executable Resolution

/// Resolves executable names to full paths for GUI app environments.
///
/// GUI applications on macOS do not inherit the user's shell PATH environment.
/// This resolver checks standard installation paths and falls back to a login
/// shell `which` lookup for non-standard locations.
struct ExecutableResolver {
    /// Standard search paths for macOS executables.
    static let standardSearchPaths: [String] = [
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
    private let loginShellFallbackEnabled: Bool

    /// Creates an executable resolver.
    /// - Parameters:
    ///   - fileSystem: File system accessor for existence and executable checks.
    ///   - searchPaths: Paths to search for executables.
    ///   - loginShellFallbackEnabled: Whether to fall back to login shell `which` lookup. Default true.
    ///     Set to false in tests to control which executables are "found".
    init(
        fileSystem: FileSystem = DefaultFileSystem(),
        searchPaths: [String] = ExecutableResolver.standardSearchPaths,
        loginShellFallbackEnabled: Bool = true
    ) {
        self.fileSystem = fileSystem
        self.searchPaths = searchPaths
        self.loginShellFallbackEnabled = loginShellFallbackEnabled
    }

    /// Resolves an executable name to its full path.
    /// - Parameter name: Executable name (e.g., "brew", "aerospace", "code").
    /// - Returns: Full path to executable, or nil if not found.
    func resolve(_ name: String) -> String? {
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
        guard loginShellFallbackEnabled else { return nil }
        return resolveViaLoginShell(name)
    }

    /// Resolves the user's login shell PATH.
    ///
    /// Spawns a login shell to load the user's profile and capture the full PATH,
    /// including custom additions like Homebrew, nvm, pyenv, etc. This is needed
    /// because GUI apps inherit a minimal PATH that excludes most user-installed tools.
    ///
    /// - Returns: The full PATH string from the login shell, or nil if resolution
    ///   fails or login shell fallback is disabled.
    func resolveLoginShellPath() -> String? {
        guard loginShellFallbackEnabled else { return nil }
        return runLoginShellCommand("echo $PATH")
    }

    /// Falls back to login shell `which` for non-standard locations.
    ///
    /// GUI apps have a minimal PATH. Using a login shell (`-l`) loads the user's
    /// shell profile (`.zshrc`, `.zprofile`, etc.) to get their full PATH including
    /// custom additions like Homebrew or tool-specific paths.
    ///
    /// - Parameter name: Executable name to resolve.
    /// - Returns: Full path from login shell, or nil if not found.
    private func resolveViaLoginShell(_ name: String) -> String? {
        runLoginShellCommand("which \(name)")
    }

    /// Timeout for login shell commands (seconds).
    /// Protects against slow shell init files (heavy .zshrc plugins, nvm, pyenv, etc.).
    private static let loginShellTimeoutSeconds: TimeInterval = 5

    /// Detects the user's login shell from `$SHELL`, falling back to `/bin/zsh`.
    /// Validates that the value is an absolute path to avoid `Process(executableURL:)` failures.
    private static var loginShellPath: String {
        if let shell = ProcessInfo.processInfo.environment["SHELL"],
           shell.hasPrefix("/") {
            return shell
        }
        return "/bin/zsh"
    }

    /// Runs a command in a login shell and returns the trimmed stdout.
    ///
    /// Uses the user's configured shell (from `$SHELL`) with a bounded timeout
    /// to avoid hangs from slow shell init files.
    private func runLoginShellCommand(_ command: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.loginShellPath)
        process.arguments = ["-l", "-c", command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        let completion = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completion.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }

        let waitResult = completion.wait(timeout: .now() + Self.loginShellTimeoutSeconds)
        if waitResult == .timedOut {
            process.terminate()
            // Give it a moment to clean up
            _ = completion.wait(timeout: .now() + 1)
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return nil
        }

        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
}

// MARK: - Command Execution

/// Result of executing an external command.
struct ApCommandResult: Equatable, Sendable {
    /// Process termination status.
    let exitCode: Int32
    /// Captured standard output.
    let stdout: String
    /// Captured standard error.
    let stderr: String

    /// Creates a new command result.
    /// - Parameters:
    ///   - exitCode: Process termination status.
    ///   - stdout: Captured standard output.
    ///   - stderr: Captured standard error.
    init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Command execution interface for testability.
///
/// Production code uses `ApSystemCommandRunner`; tests can supply a mock.
protocol CommandRunning {
    func run(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval?,
        workingDirectory: String?
    ) -> Result<ApCommandResult, ApCoreError>
}

extension CommandRunning {
    /// Convenience: default timeout, no working directory.
    func run(
        executable: String,
        arguments: [String]
    ) -> Result<ApCommandResult, ApCoreError> {
        run(executable: executable, arguments: arguments, timeoutSeconds: 5, workingDirectory: nil)
    }

    /// Convenience: explicit timeout, no working directory.
    func run(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval?
    ) -> Result<ApCommandResult, ApCoreError> {
        run(executable: executable, arguments: arguments, timeoutSeconds: timeoutSeconds, workingDirectory: nil)
    }
}

/// Runs external commands with executable path resolution for GUI environments.
///
/// Child processes receive an augmented PATH that includes standard Homebrew/system
/// paths and the user's login shell PATH. This ensures tools like `al` (which internally
/// call `code`) can find executables even when launched from a GUI app with a minimal PATH.
struct ApSystemCommandRunner: CommandRunning {
    private let executableResolver: ExecutableResolver
    private let augmentedEnvironment: [String: String]

    /// Creates a command runner with the default executable resolver.
    /// - Parameter executableResolver: Resolver for finding executable paths.
    init(executableResolver: ExecutableResolver = ExecutableResolver()) {
        self.executableResolver = executableResolver
        self.augmentedEnvironment = Self.buildAugmentedEnvironment(resolver: executableResolver)
    }

    /// Builds an environment dictionary with an augmented PATH for child processes.
    ///
    /// PATH is constructed by merging (in order, deduplicated):
    /// 1. Standard search paths (Homebrew ARM/Intel, system)
    /// 2. Login shell PATH (user's full PATH from their shell profile)
    /// 3. Current process PATH (inherited from parent)
    static func buildAugmentedEnvironment(resolver: ExecutableResolver) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let currentPath = env["PATH"] ?? ""

        // Collect all PATH sources
        var allPaths: [String] = []

        // 1. Standard search paths first (ensures Homebrew is always available)
        allPaths.append(contentsOf: ExecutableResolver.standardSearchPaths)

        // 2. Login shell PATH (user's full profile PATH, including custom tools)
        if let shellPath = resolver.resolveLoginShellPath() {
            allPaths.append(contentsOf: shellPath.split(separator: ":").map(String.init))
        }

        // 3. Current process PATH (preserve anything already present)
        allPaths.append(contentsOf: currentPath.split(separator: ":").map(String.init))

        // Deduplicate while preserving order
        var seen = Set<String>()
        let deduped = allPaths.filter { path in
            guard !path.isEmpty else { return false }
            return seen.insert(path).inserted
        }

        env["PATH"] = deduped.joined(separator: ":")
        return env
    }

    /// Runs the provided executable with arguments.
    /// - Parameters:
    ///   - executable: Executable name to run.
    ///   - arguments: Arguments to pass to the executable.
    ///   - timeoutSeconds: Timeout in seconds. Defaults to 5s. Pass nil to wait indefinitely.
    ///   - workingDirectory: Optional working directory for the process.
    /// - Returns: Captured output on success, or an error.
    func run(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval? = 5,
        workingDirectory: String? = nil
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
        process.environment = augmentedEnvironment
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

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

        // Use semaphores to detect when each pipe has reached EOF.
        // This ensures we capture all data even for fast-completing processes.
        let stdoutEOF = DispatchSemaphore(value: 0)
        let stderrEOF = DispatchSemaphore(value: 0)

        stdoutHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                stdoutEOF.signal()
            } else {
                dataLock.lock()
                stdoutData.append(data)
                dataLock.unlock()
            }
        }

        stderrHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                stderrEOF.signal()
            } else {
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
        let timeoutSecondsForMessage: TimeInterval?
        if let timeoutSeconds = timeoutSeconds {
            timeoutSecondsForMessage = timeoutSeconds
            let waitResult = completion.wait(timeout: .now() + timeoutSeconds)
            didTimeout = waitResult == .timedOut
            if didTimeout {
                process.terminate()
                _ = completion.wait(timeout: .now() + 1)
            }
        } else {
            timeoutSecondsForMessage = nil
            completion.wait()
            didTimeout = false
        }

        // Wait for both pipes to reach EOF to ensure all data is captured.
        // This prevents race conditions where fast processes terminate before
        // all output is read by the readabilityHandler.
        // Use a short fixed timeout: once the process exits, pipes should EOF
        // almost immediately. A 2s grace period handles edge cases without
        // doubling the caller's intended timeout.
        let pipeEOFTimeout: DispatchTimeInterval = .seconds(2)
        _ = stdoutEOF.wait(timeout: .now() + pipeEOFTimeout)
        _ = stderrEOF.wait(timeout: .now() + pipeEOFTimeout)

        // Clean up handlers
        stdoutHandle.readabilityHandler = nil
        stderrHandle.readabilityHandler = nil

        if didTimeout {
            let label = timeoutSecondsForMessage.map { "\($0)" } ?? "unknown"
            return .failure(
                ApCoreError(
                    message: "Command timed out after \(label)s: \(executable) \(arguments.joined(separator: " "))"
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

/// Shared IDE token prefix used to tag new IDE windows.
enum ApIdeToken {
    static let prefix = "AP:"
}

/// Launches new VS Code windows with a tagged window title.
///
/// For local projects, injects an `AP:<id>` window title block into the project's
/// `.vscode/settings.json` and opens `code --new-window <projectPath>`.
///
/// For SSH projects, writes settings.json on the remote via SSH, then opens:
/// `code --new-window --remote <authority> <remotePath>`.
///
/// If remote settings.json cannot be written, the launch fails loudly (no workspace fallback).
struct ApVSCodeLauncher {
    /// VS Code bundle identifier used for filtering windows.
    static let bundleId = "com.microsoft.VSCode"

    private let commandRunner: CommandRunning
    private let settingsManager: ApVSCodeSettingsManager

    /// Creates a VS Code launcher.
    /// - Parameters:
    ///   - commandRunner: Command runner for launching VS Code and SSH commands.
    ///   - fileSystem: File system for settings.json I/O.
    ///   - settingsManager: Manager for .vscode/settings.json block injection.
    init(
        commandRunner: CommandRunning = ApSystemCommandRunner(),
        fileSystem: FileSystem = DefaultFileSystem(),
        settingsManager: ApVSCodeSettingsManager? = nil
    ) {
        self.commandRunner = commandRunner
        self.settingsManager = settingsManager ?? ApVSCodeSettingsManager(
            fileSystem: fileSystem,
            commandRunner: commandRunner
        )
    }

    /// Opens a new VS Code window with a tagged title for precise identification.
    ///
    /// - Parameters:
    ///   - identifier: Identifier embedded in the window title as `AP:<identifier>`.
    ///   - projectPath: Optional path to the project folder.
    ///     - Local projects: local absolute path.
    ///     - SSH projects: remote absolute path.
    ///   - remoteAuthority: Optional VS Code SSH remote authority (e.g., `ssh-remote+user@host`).
    ///     When set, requires SSH settings.json write to succeed (no workspace fallback).
    /// - Returns: Success or an error.
    func openNewWindow(
        identifier: String,
        projectPath: String? = nil,
        remoteAuthority: String? = nil
    ) -> Result<Void, ApCoreError> {
        let trimmedId = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else {
            return .failure(ApCoreError(message: "Identifier cannot be empty."))
        }
        if trimmedId.contains("/") {
            return .failure(ApCoreError(message: "Identifier cannot contain '/'."))
        }

        guard let projectPath = projectPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !projectPath.isEmpty else {
            return .failure(ApCoreError(message: "Project path is required for VS Code launch."))
        }

        // Decide strategy
        if let remoteAuthority = remoteAuthority?.trimmingCharacters(in: .whitespacesAndNewlines),
           !remoteAuthority.isEmpty {
            // SSH project
            return openSSHWindow(
                identifier: trimmedId,
                remotePath: projectPath,
                remoteAuthority: remoteAuthority
            )
        }

        // Local project with path: use settings.json
        return openLocalWindow(identifier: trimmedId, projectPath: projectPath)
    }

    // MARK: - Local project

    private func openLocalWindow(
        identifier: String,
        projectPath: String
    ) -> Result<Void, ApCoreError> {
        switch settingsManager.writeLocalSettings(projectPath: projectPath, identifier: identifier) {
        case .failure(let error):
            return .failure(error)
        case .success:
            break
        }

        return launchCode(arguments: ["--new-window", projectPath])
    }

    // MARK: - SSH project

    private func openSSHWindow(
        identifier: String,
        remotePath: String,
        remoteAuthority: String
    ) -> Result<Void, ApCoreError> {
        // Write settings.json on the remote host. Without this, we cannot reliably tag the
        // window title for AeroSpace window identification.
        switch settingsManager.writeRemoteSettings(
            remoteAuthority: remoteAuthority,
            remotePath: remotePath,
            identifier: identifier
        ) {
        case .failure(let error):
            return .failure(error)
        case .success:
            break
        }

        return launchCode(arguments: [
            "--new-window",
            "--remote", remoteAuthority,
            remotePath
        ])
    }

    // MARK: - VS Code launch

    private func launchCode(arguments: [String]) -> Result<Void, ApCoreError> {
        switch commandRunner.run(executable: "code", arguments: arguments, timeoutSeconds: 10) {
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

    private let commandRunner: CommandRunning

    init(commandRunner: CommandRunning = ApSystemCommandRunner()) {
        self.commandRunner = commandRunner
    }

    /// Opens a new Chrome window tagged with the provided identifier.
    /// - Parameters:
    ///   - identifier: Identifier embedded in the window title token.
    ///   - initialURLs: URLs to open in the new window. First URL becomes the active tab,
    ///     remaining URLs open as additional tabs. If empty, opens Chrome's default new tab page.
    /// - Returns: Success or an error.
    func openNewWindow(identifier: String, initialURLs: [String] = []) -> Result<Void, ApCoreError> {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(ApCoreError(message: "Identifier cannot be empty."))
        }
        if trimmed.contains("/") {
            return .failure(ApCoreError(message: "Identifier cannot contain '/'."))
        }

        let windowTitle = ApChromeLauncher.escapeForAppleScriptString("\(ApIdeToken.prefix)\(trimmed)")

        var scriptLines = [
            "tell application \"Google Chrome\"",
            "set newWindow to make new window"
        ]

        if !initialURLs.isEmpty {
            // Set first URL on the active tab (replaces Chrome's default new tab page)
            let firstURL = ApChromeLauncher.escapeForAppleScriptString(initialURLs[0])
            scriptLines.append("set URL of active tab of newWindow to \"\(firstURL)\"")

            // Create additional tabs for remaining URLs
            for url in initialURLs.dropFirst() {
                let escapedURL = ApChromeLauncher.escapeForAppleScriptString(url)
                scriptLines.append("tell newWindow to make new tab with properties {URL:\"\(escapedURL)\"}")
            }
        }

        scriptLines.append("set given name of newWindow to \"\(windowTitle)\"")
        scriptLines.append("end tell")

        switch commandRunner.run(executable: "osascript", arguments: ApChromeLauncher.scriptArguments(lines: scriptLines), timeoutSeconds: 15) {
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

/// Launches VS Code for Agent Layer projects using a two-step approach.
///
/// Used for projects with `useAgentLayer = true`. Injects an `AP:<id>` window title
/// block into the project's `.vscode/settings.json`, then:
/// 1. Runs `al sync` with CWD = project path to regenerate agent layer config.
/// 2. Runs `al vscode --no-sync --new-window` (CWD = project path) to open VS Code with
///    Agent Layer environment variables (including `CODEX_HOME`) configured.
///
/// The agent-panel block coexists with agent-layer's own `// >>> agent-layer` block
/// since `al sync` preserves content outside its markers.
///
/// We intentionally do not pass a positional path to `al vscode`: agent-layer's VS Code
/// launcher appends "." to the `code` args. By setting CWD to the project path, "." maps
/// to the repo root and avoids opening two VS Code windows.
struct ApAgentLayerVSCodeLauncher {
    private let commandRunner: CommandRunning
    private let executableResolver: ExecutableResolver
    private let settingsManager: ApVSCodeSettingsManager

    /// Creates an Agent Layer VS Code launcher.
    /// - Parameters:
    ///   - commandRunner: Command runner for running `al sync` and `al vscode`.
    ///   - executableResolver: Resolver for finding the `al` executable.
    ///   - fileSystem: File system for settings.json I/O.
    ///   - settingsManager: Manager for .vscode/settings.json block injection.
    init(
        commandRunner: CommandRunning = ApSystemCommandRunner(),
        executableResolver: ExecutableResolver = ExecutableResolver(),
        fileSystem: FileSystem = DefaultFileSystem(),
        settingsManager: ApVSCodeSettingsManager? = nil
    ) {
        self.commandRunner = commandRunner
        self.executableResolver = executableResolver
        self.settingsManager = settingsManager ?? ApVSCodeSettingsManager(
            fileSystem: fileSystem,
            commandRunner: commandRunner
        )
    }

    /// Opens a new VS Code window through the Agent Layer.
    ///
    /// - Parameters:
    ///   - identifier: Project identifier embedded in the window title as `AP:<identifier>`.
    ///   - projectPath: Path to the project folder. Required for Agent Layer launch.
    ///   - remoteAuthority: Optional VS Code remote authority. Must be nil for Agent Layer launch.
    /// - Returns: Success or an error with a clear message.
    func openNewWindow(
        identifier: String,
        projectPath: String?,
        remoteAuthority: String? = nil
    ) -> Result<Void, ApCoreError> {
        if let remoteAuthority = remoteAuthority?.trimmingCharacters(in: .whitespacesAndNewlines),
           !remoteAuthority.isEmpty {
            return .failure(ApCoreError(message: "Agent Layer launch does not support SSH remote projects."))
        }

        guard let projectPath = projectPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !projectPath.isEmpty else {
            return .failure(ApCoreError(message: "Project path is required for Agent Layer launch."))
        }

        // Inject AP:<id> window title into .vscode/settings.json
        switch settingsManager.writeLocalSettings(projectPath: projectPath, identifier: identifier) {
        case .failure(let error):
            return .failure(error)
        case .success:
            break
        }

        guard let alPath = executableResolver.resolve("al") else {
            return .failure(ApCoreError(
                category: .command,
                message: "Agent Layer CLI (al) not found.",
                detail: "Install the Agent Layer CLI and ensure it is on your PATH."
            ))
        }

        // Step 1: Sync agent layer config.
        // workingDirectory is required: `al` needs the CWD to find `.agent-layer/` in the project.
        switch commandRunner.run(
            executable: alPath,
            arguments: ["sync"],
            timeoutSeconds: 30,
            workingDirectory: projectPath
        ) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                let trimmedStderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = trimmedStderr.isEmpty ? "" : "\n\(trimmedStderr)"
                return .failure(
                    ApCoreError(message: "al sync failed with exit code \(result.exitCode).\(suffix)")
                )
            }
        }

        // Step 2: Launch VS Code via Agent Layer so `CODEX_HOME` and AL_* env vars are set.
        // We avoid the `al vscode` dual-window bug by not passing a positional path. The
        // agent-layer launcher appends ".", and since we set CWD to projectPath, "." maps to it.
        guard executableResolver.resolve("code") != nil else {
            return .failure(ApCoreError(
                category: .command,
                message: "VS Code CLI (code) not found.",
                detail: "Install VS Code and ensure the 'code' command is on your PATH."
            ))
        }

        switch commandRunner.run(
            executable: alPath,
            arguments: ["vscode", "--no-sync", "--new-window"],
            timeoutSeconds: 10,
            workingDirectory: projectPath
        ) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                let trimmedStderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = trimmedStderr.isEmpty ? "" : "\n\(trimmedStderr)"
                return .failure(
                    ApCoreError(message: "al vscode failed with exit code \(result.exitCode).\(suffix)")
                )
            }
            return .success(())
        }
    }
}
