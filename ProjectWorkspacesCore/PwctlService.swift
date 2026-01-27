import Foundation

/// A single project entry returned by `pwctl list`.
public struct PwctlListEntry: Equatable, Sendable {
    public let id: String
    public let name: String
    public let path: String

    /// Creates a list entry for CLI output.
    /// - Parameters:
    ///   - id: Project identifier.
    ///   - name: Human-readable project name.
    ///   - path: Project path on disk.
    public init(id: String, name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }
}

/// Outcome wrapper for `pwctl` operations with optional warnings.
public enum PwctlOutcome<Output> {
    case success(output: Output, warnings: [DoctorFinding])
    case failure(findings: [DoctorFinding])
}

/// Provides CLI-facing operations for `pwctl`.
public struct PwctlService {
    private let paths: ProjectWorkspacesPaths
    private let fileSystem: FileSystem
    private let configLoader: ConfigLoader
    private let activationService: ActivationService

    /// Creates a pwctl service instance.
    /// - Parameters:
    ///   - paths: File system paths for ProjectWorkspaces.
    ///   - fileSystem: File system accessor.
    public init(
        paths: ProjectWorkspacesPaths = .defaultPaths(),
        fileSystem: FileSystem = DefaultFileSystem(),
        activationService: ActivationService? = nil
    ) {
        self.paths = paths
        self.fileSystem = fileSystem
        self.configLoader = ConfigLoader(paths: paths, fileSystem: fileSystem)
        if let activationService {
            self.activationService = activationService
        } else {
            self.activationService = ActivationService(paths: paths, fileSystem: fileSystem)
        }
    }

    /// Returns the list of configured projects for `pwctl list`.
    /// - Returns: CLI output entries or failure findings when config cannot be read.
    public func listProjects() -> PwctlOutcome<[PwctlListEntry]> {
        switch configLoader.load() {
        case .failure(let findings):
            return .failure(findings: findings)
        case .success(let outcome, let warnings):
            guard let config = outcome.config else {
                return .failure(findings: outcome.findings)
            }
            let entries = config.projects.map { project in
                PwctlListEntry(id: project.id, name: project.name, path: project.path)
            }
            return .success(output: entries, warnings: warnings)
        }
    }

    /// Returns the last N lines of the primary log file for `pwctl logs --tail`.
    /// - Parameter lines: Number of lines to return.
    /// - Returns: Log output or failure findings when the log file cannot be read.
    public func tailLogs(lines: Int) -> PwctlOutcome<String> {
        guard lines > 0 else {
            return .failure(findings: [
                DoctorFinding(
                    severity: .fail,
                    title: "Log tail length is invalid",
                    detail: "Requested \(lines) lines.",
                    fix: "Use --tail <n> with a positive integer."
                )
            ])
        }

        let logURL = paths.primaryLogFile
        guard fileSystem.fileExists(at: logURL) else {
            return .failure(findings: [
                DoctorFinding(
                    severity: .fail,
                    title: "Log file missing",
                    detail: logURL.path,
                    fix: "Run ProjectWorkspaces to generate logs, then retry."
                )
            ])
        }

        let data: Data
        do {
            data = try fileSystem.readFile(at: logURL)
        } catch {
            return .failure(findings: [
                DoctorFinding(
                    severity: .fail,
                    title: "Log file could not be read",
                    detail: "\(logURL.path): \(error)",
                    fix: "Check file permissions for the log path."
                )
            ])
        }

        guard let content = String(data: data, encoding: .utf8) else {
            return .failure(findings: [
                DoctorFinding(
                    severity: .fail,
                    title: "Log file is not valid UTF-8",
                    detail: logURL.path,
                    fix: "Regenerate the log file and retry."
                )
            ])
        }

        let tail = tailLines(from: content, count: lines)
        return .success(output: tail, warnings: [])
    }

    /// Activates the project workspace for the provided project id.
    /// - Parameter projectId: Project identifier.
    /// - Returns: Activation outcome with warnings or failure.
    public func activate(projectId: String) -> ActivationOutcome {
        activationService.activate(projectId: projectId)
    }

    /// Returns the last N lines from a log string.
    /// - Parameters:
    ///   - content: Log contents as a string.
    ///   - count: Number of lines to return.
    /// - Returns: A string containing the last N lines.
    private func tailLines(from content: String, count: Int) -> String {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var lines = normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        if normalized.hasSuffix("\n"), let last = lines.last, last.isEmpty {
            lines.removeLast()
        }

        guard !lines.isEmpty else {
            return ""
        }

        if count >= lines.count {
            return lines.joined(separator: "\n")
        }

        return lines.suffix(count).joined(separator: "\n")
    }
}
