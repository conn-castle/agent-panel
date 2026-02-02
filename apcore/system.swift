import Foundation

/// Result of executing an external command.
struct ApCommandResult: Equatable {
    /// Process termination status.
    let exitCode: Int32
    /// Captured standard output.
    let stdout: String
    /// Captured standard error.
    let stderr: String
}

/// Runs external commands using /usr/bin/env for PATH resolution.
struct ApSystemCommandRunner {
    /// Runs the provided executable with arguments.
    /// - Parameters:
    ///   - executable: Executable name to run.
    ///   - arguments: Arguments to pass to the executable.
    /// - Returns: Captured output on success, or an error.
    func run(executable: String, arguments: [String]) -> Result<ApCommandResult, ApCoreError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return .failure(ApCoreError(message: "Failed to launch \(executable): \(error.localizedDescription)"))
        }

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

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

/// Launches new VS Code windows with a tagged window title.
struct ApVSCodeLauncher {
    /// VS Code bundle identifier used for filtering windows.
    static let bundleId = "com.microsoft.VSCode"

    private let commandRunner = ApSystemCommandRunner()

    /// Opens a new VS Code window tagged with the provided identifier.
    /// - Parameter identifier: Identifier embedded in the window title token.
    /// - Returns: Success or an error.
    func open_new_window(identifier: String) -> Result<Void, ApCoreError> {
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
        let workspaceDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/state/project-workspaces/ap/vscode", isDirectory: true)
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

        switch commandRunner.run(executable: "code", arguments: ["--new-window", workspaceURL.path]) {
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
