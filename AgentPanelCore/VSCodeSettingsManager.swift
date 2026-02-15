import Foundation

/// Manages the `// >>> agent-panel` marker block in `.vscode/settings.json` files.
///
/// This manager injects a window title setting directly into the project's `.vscode/settings.json`.
/// The block is delimited by `// >>> agent-panel` / `// <<< agent-panel` markers,
/// allowing coexistence with other managed blocks (e.g., `// >>> agent-layer`).
struct ApVSCodeSettingsManager {
    private let fileSystem: FileSystem
    private let commandRunner: CommandRunning?

    /// Creates a settings manager.
    /// - Parameters:
    ///   - fileSystem: File system accessor for settings.json I/O.
    ///   - commandRunner: Command runner for SSH remote writes. Pass `nil` if only local writes are needed.
    init(fileSystem: FileSystem = DefaultFileSystem(), commandRunner: CommandRunning? = nil) {
        self.fileSystem = fileSystem
        self.commandRunner = commandRunner
    }

    // MARK: - Block injection (pure function)

    /// Start marker for the agent-panel settings block.
    static let startMarker = "// >>> agent-panel"
    /// End marker for the agent-panel settings block.
    static let endMarker = "// <<< agent-panel"

    /// Injects or replaces the agent-panel block at the top of a JSONC settings file.
    ///
    /// The block is inserted right after the opening `{`. If an existing agent-panel
    /// block is found, it is replaced. When a color is configured, the block includes
    /// a `workbench.colorCustomizations` anchor so Peacock writes its colors in-place
    /// (inside the agent-panel block, safe from agent-layer's `al sync`). Existing
    /// Peacock-written color customizations are preserved across re-injections.
    /// Trailing commas are added only when content follows the block.
    ///
    /// - Parameters:
    ///   - content: Existing file content (JSONC).
    ///   - identifier: Project identifier for the `AP:<id>` window title.
    ///   - color: Optional project color string (named or hex) for VS Code color customizations.
    /// - Returns: Updated file content with the agent-panel block injected, or an error
    ///   if the content has no opening `{`.
    static func injectBlock(into content: String, identifier: String, color: String? = nil) -> Result<String, ApCoreError> {
        let hasStart = content.contains(startMarker)
        let hasEnd = content.contains(endMarker)
        if hasStart != hasEnd {
            return .failure(ApCoreError(
                category: .validation,
                message: """
                Cannot inject settings block: unbalanced agent-panel markers in settings.json.
                Expected both markers:
                \(startMarker)
                \(endMarker)
                Fix the file manually, then retry.
                """
            ))
        }

        // Extract existing colorCustomizations before removing the block
        let existingColorCustomizations = Self.extractColorCustomizations(from: content)

        // Remove existing block if present
        let cleaned = removeExistingBlock(from: content)

        // Find the first `{`
        guard let braceIndex = cleaned.firstIndex(of: "{") else {
            return .failure(ApCoreError(message: "Cannot inject settings block: content has no opening '{'."))
        }

        // Determine whether content follows the block (for trailing-comma decisions)
        let afterBrace = cleaned.index(after: braceIndex)
        let before = String(cleaned[cleaned.startIndex..<afterBrace])
        let after = String(cleaned[afterBrace...])
        let trimmedAfter = after.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasContentAfter = trimmedAfter != "}"

        let windowTitle = "\(ApIdeToken.prefix)\(identifier) - ${dirty}${activeEditorShort}${separator}${rootName}${separator}${appName}"

        // Build property lines without trailing commas
        var properties: [String] = [
            "  \"window.title\": \"\(windowTitle)\""
        ]

        // Add Peacock color and colorCustomizations anchor when a valid color is provided.
        // The colorCustomizations key acts as an in-place anchor so Peacock writes its
        // colors inside the agent-panel block (safe from agent-layer's al sync).
        if let color, let hex = VSCodeColorPalette.peacockColorHex(for: color) {
            properties.append("  \"peacock.color\": \"\(hex)\"")
            let colorValue = existingColorCustomizations ?? "{}"
            properties.append("  \"workbench.colorCustomizations\": \(colorValue)")
        }

        // Add commas: all non-last properties always get one;
        // the last property gets one only if there is content after the block.
        for i in 0..<properties.count {
            let isLast = (i == properties.count - 1)
            if !isLast || hasContentAfter {
                properties[i] = appendCommaToLastLine(of: properties[i])
            }
        }

        var blockLines = [
            "  \(startMarker)",
            "  // Managed by AgentPanel. Do not edit this block manually.",
        ]
        blockLines.append(contentsOf: properties)
        blockLines.append("  \(endMarker)")

        let block = blockLines.joined(separator: "\n")

        if !hasContentAfter {
            // Block is the only content
            return .success("\(before)\n\(block)\n}")
        } else {
            // Content follows the block
            return .success("\(before)\n\(block)\n\(after.drop(while: { $0 == "\n" || $0 == "\r" }))")
        }
    }

    /// Removes an existing agent-panel block (markers + content between them) from the content.
    ///
    /// If the start marker exists but the end marker is missing (unbalanced markers),
    /// returns the content unchanged to prevent data loss.
    private static func removeExistingBlock(from content: String) -> String {
        // Guard: only remove if both markers are present (balanced)
        let hasStart = content.contains(startMarker)
        let hasEnd = content.contains(endMarker)
        guard hasStart && hasEnd else { return content }

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var result: [String] = []
        var insideBlock = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == startMarker {
                insideBlock = true
                continue
            }
            if trimmed == endMarker {
                insideBlock = false
                continue
            }
            if !insideBlock {
                result.append(line)
            }
        }

        return result.joined(separator: "\n")
    }

    /// Extracts the `workbench.colorCustomizations` JSON object value from an existing
    /// agent-panel block, preserving Peacock-written color customizations across re-injections.
    ///
    /// - Parameter content: Full JSONC settings file content.
    /// - Returns: The raw JSON object text (e.g., `{}` or multi-line `{ ... }`), or `nil`
    ///   if no `workbench.colorCustomizations` key exists within the block.
    static func extractColorCustomizations(from content: String) -> String? {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blockLines: [String] = []
        var insideBlock = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == startMarker {
                insideBlock = true
                continue
            }
            if trimmed == endMarker {
                break
            }
            if insideBlock {
                blockLines.append(line)
            }
        }

        guard !blockLines.isEmpty else { return nil }

        let blockText = blockLines.joined(separator: "\n")
        let key = "\"workbench.colorCustomizations\""
        guard let keyRange = blockText.range(of: key) else { return nil }

        // Find the colon after the key, then the opening brace of the JSON object value
        let afterKey = blockText[keyRange.upperBound...]
        guard let colonIndex = afterKey.firstIndex(of: ":") else { return nil }
        let afterColon = blockText[blockText.index(after: colonIndex)...]
        guard let openBrace = afterColon.firstIndex(of: "{") else { return nil }

        // Match braces to find the corresponding closing }
        var depth = 0
        for index in blockText[openBrace...].indices {
            let char = blockText[index]
            if char == "{" { depth += 1 }
            if char == "}" {
                depth -= 1
                if depth == 0 {
                    return String(blockText[openBrace...index])
                }
            }
        }

        return nil
    }

    /// Appends a comma after the last line of a potentially multi-line property string.
    ///
    /// For single-line properties this simply appends `,`. For multi-line values
    /// (e.g., `workbench.colorCustomizations` with Peacock content) the comma is
    /// placed after the closing `}` on the final line.
    private static func appendCommaToLastLine(of text: String) -> String {
        if let lastNewline = text.lastIndex(of: "\n") {
            let prefix = text[text.startIndex...lastNewline]
            let lastLine = text[text.index(after: lastNewline)...]
            return "\(prefix)\(lastLine),"
        }
        return "\(text),"
    }

    // MARK: - Local settings.json write

    /// Writes the agent-panel block into the project's `.vscode/settings.json`.
    ///
    /// Reads the existing file (or defaults to `{}\n` if the file doesn't exist),
    /// injects the block, creates the `.vscode/` directory if needed, and writes the result.
    /// Returns an error if the file exists but cannot be read (e.g., permission denied).
    ///
    /// - Parameters:
    ///   - projectPath: Absolute path to the project directory.
    ///   - identifier: Project identifier for the `AP:<id>` window title.
    ///   - color: Optional project color for VS Code color customizations.
    /// - Returns: Success or an error.
    func writeLocalSettings(projectPath: String, identifier: String, color: String? = nil) -> Result<Void, ApCoreError> {
        let projectURL = URL(fileURLWithPath: projectPath, isDirectory: true)

        // Fail loudly on misconfigured paths. Do not create missing project directories.
        guard fileSystem.directoryExists(at: projectURL) else {
            return .failure(ApCoreError(message: "Project path does not exist or is not a directory: \(projectURL.path)"))
        }

        let vscodeDir = projectURL.appendingPathComponent(".vscode", isDirectory: true)
        let settingsURL = vscodeDir.appendingPathComponent("settings.json", isDirectory: false)

        // Read existing content or default to empty object (file missing only)
        let existingContent: String
        if fileSystem.fileExists(at: settingsURL) {
            do {
                let data = try fileSystem.readFile(at: settingsURL)
                guard let content = String(data: data, encoding: .utf8) else {
                    return .failure(ApCoreError(
                        message: "Failed to decode .vscode/settings.json as UTF-8 at \(settingsURL.path)."
                    ))
                }
                existingContent = content
            } catch {
                return .failure(ApCoreError(
                    message: "Failed to read existing .vscode/settings.json at \(settingsURL.path): \(error.localizedDescription)"
                ))
            }
        } else {
            existingContent = "{}\n"
        }

        let updatedContent: String
        switch Self.injectBlock(into: existingContent, identifier: identifier, color: color) {
        case .failure(let error):
            return .failure(error)
        case .success(let content):
            updatedContent = content
        }

        do {
            try fileSystem.createDirectory(at: vscodeDir)
            guard let data = updatedContent.data(using: .utf8) else {
                return .failure(ApCoreError(message: "Failed to encode settings.json content as UTF-8."))
            }
            try fileSystem.writeFile(at: settingsURL, data: data)
        } catch {
            return .failure(ApCoreError(message: "Failed to write .vscode/settings.json: \(error.localizedDescription)"))
        }

        return .success(())
    }

    // MARK: - Remote settings.json write (SSH)

    /// Writes the agent-panel block into a remote project's `.vscode/settings.json` via SSH.
    ///
    /// Strategy: read existing file via `cat`, inject block, base64-encode, write back via
    /// `base64 -d`. All commands use safe SSH flags (ConnectTimeout, BatchMode, `--` terminator).
    ///
    /// - Parameters:
    ///   - remoteAuthority: VS Code SSH remote authority (e.g., `ssh-remote+user@host`).
    ///   - remotePath: Remote absolute path to the project directory.
    ///   - identifier: Project identifier for the `AP:<id>` window title.
    ///   - color: Optional project color for VS Code color customizations.
    /// - Returns: Success or an error.
    func writeRemoteSettings(
        remoteAuthority: String,
        remotePath: String,
        identifier: String,
        color: String? = nil
    ) -> Result<Void, ApCoreError> {
        guard let commandRunner else {
            return .failure(ApCoreError(message: "Command runner not available for remote settings write"))
        }

        guard let sshTarget = ApSSHHelpers.extractTarget(from: remoteAuthority) else {
            return .failure(ApCoreError(message: "Malformed SSH remote authority: \(remoteAuthority)"))
        }

        let escapedProjectPath = ApSSHHelpers.shellEscape(remotePath)
        let settingsPath = "\(escapedProjectPath)/.vscode/settings.json"

        // Read existing remote settings.json (or default to empty if file missing)
        // Uses `test -f` to distinguish "file missing" from "permission denied" or other errors.
        // Also asserts the remote project directory exists to avoid creating incorrect paths.
        let readCommand = [
            "if [ ! -d \(escapedProjectPath) ]; then echo Remote project path missing: \(escapedProjectPath) 1>&2; exit 1; fi",
            "if [ -f \(settingsPath) ]; then cat \(settingsPath); else echo '{}'; fi"
        ].joined(separator: "; ")
        let readResult = commandRunner.run(
            executable: "ssh",
            arguments: [
                "-o", "ConnectTimeout=5",
                "-o", "BatchMode=yes",
                "--",
                sshTarget,
                readCommand
            ],
            timeoutSeconds: 10
        )

        let existingContent: String
        switch readResult {
        case .failure(let error):
            return .failure(ApCoreError(
                category: .command,
                message: "SSH read failed for remote settings.json: \(sshTarget) \(remotePath)\n\(error.message)"
            ))
        case .success(let result):
            if result.exitCode != 0 {
                let trimmedStderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = trimmedStderr.isEmpty ? "" : "\n\(trimmedStderr)"
                return .failure(ApCoreError(
                    category: .command,
                    message: "SSH read failed with exit code \(result.exitCode): \(sshTarget) \(remotePath)\(suffix)"
                ))
            }
            existingContent = result.stdout
        }

        // Inject block
        let updatedContent: String
        switch Self.injectBlock(into: existingContent, identifier: identifier, color: color) {
        case .failure(let error):
            return .failure(error)
        case .success(let content):
            updatedContent = content
        }

        // Base64-encode and write
        guard let data = updatedContent.data(using: .utf8) else {
            return .failure(ApCoreError(message: "Failed to encode settings.json as UTF-8"))
        }
        let base64 = data.base64EncodedString()

        // Defense-in-depth: base64 output is limited to [A-Za-z0-9+/=] and is safe to embed
        // inside single quotes. Keep this invariant if you change the encoding scheme.
        let writeCommand = "if [ ! -d \(escapedProjectPath) ]; then echo Remote project path missing: \(escapedProjectPath) 1>&2; exit 1; fi && mkdir -p \(escapedProjectPath)/.vscode && echo '\(base64)' | base64 -d > \(settingsPath)"
        let writeResult = commandRunner.run(
            executable: "ssh",
            arguments: [
                "-o", "ConnectTimeout=5",
                "-o", "BatchMode=yes",
                "--",
                sshTarget,
                writeCommand
            ],
            timeoutSeconds: 10
        )

        switch writeResult {
        case .failure(let error):
            return .failure(ApCoreError(
                category: .command,
                message: "SSH write failed for remote settings.json: \(sshTarget) \(remotePath)\n\(error.message)"
            ))
        case .success(let result):
            if result.exitCode != 0 {
                let trimmedStderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = trimmedStderr.isEmpty ? "" : "\n\(trimmedStderr)"
                return .failure(ApCoreError(
                    category: .command,
                    message: "SSH write failed with exit code \(result.exitCode): \(sshTarget) \(remotePath)\(suffix)"
                ))
            }
            return .success(())
        }
    }

    // MARK: - Ensure all settings blocks

    /// Writes the agent-panel settings.json block for all configured projects.
    ///
    /// For local projects, writes directly via the file system.
    /// For SSH projects, writes via SSH (requires `commandRunner` to be set).
    /// Each project is processed independently; failures do not affect other projects.
    ///
    /// - Parameter projects: All configured projects.
    /// - Returns: Per-project results keyed by project ID.
    @discardableResult
    func ensureAllSettingsBlocks(projects: [ProjectConfig]) -> [String: Result<Void, ApCoreError>] {
        var results: [String: Result<Void, ApCoreError>] = [:]

        for project in projects {
            if project.isSSH {
                guard let remote = project.remote else {
                    results[project.id] = .failure(ApCoreError(
                        message: "SSH project \(project.id) missing remote authority"
                    ))
                    continue
                }
                results[project.id] = writeRemoteSettings(
                    remoteAuthority: remote,
                    remotePath: project.path,
                    identifier: project.id,
                    color: project.color
                )
            } else {
                results[project.id] = writeLocalSettings(
                    projectPath: project.path,
                    identifier: project.id,
                    color: project.color
                )
            }
        }

        return results
    }
}

// MARK: - Public Convenience API

/// Proactively ensures the AgentPanel-managed VS Code settings block exists for projects.
///
/// This is a public wrapper around internal settings management logic so the App/CLI can
/// trigger pre-flight settings writes without depending on internal types.
public enum VSCodeSettingsBlocks {
    /// Writes the AgentPanel settings block into `.vscode/settings.json` for all projects.
    ///
    /// - Local projects: Writes via the local file system.
    /// - SSH projects: Writes via SSH (read → inject → base64 → write).
    ///
    /// - Parameter projects: Projects to process.
    /// - Returns: Per-project results keyed by project id.
    @discardableResult
    public static func ensureAll(projects: [ProjectConfig]) -> [String: Result<Void, ApCoreError>] {
        let runner = ApSystemCommandRunner()
        let manager = ApVSCodeSettingsManager(commandRunner: runner)
        return manager.ensureAllSettingsBlocks(projects: projects)
    }
}

// MARK: - Notes

// SSH authority parsing and shell escaping live in `ApSSHHelpers` to keep a single
// source of truth across config validation, Doctor checks, and remote writes.
