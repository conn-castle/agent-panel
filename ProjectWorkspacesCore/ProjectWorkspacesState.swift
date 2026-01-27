import Foundation

/// Managed window ids for a single project.
public struct ManagedWindowState: Codable, Equatable, Sendable {
    public var ideWindowId: Int?
    public var chromeWindowId: Int?

    /// Creates a managed window state payload.
    /// - Parameters:
    ///   - ideWindowId: Managed IDE window id.
    ///   - chromeWindowId: Managed Chrome window id.
    public init(ideWindowId: Int? = nil, chromeWindowId: Int? = nil) {
        self.ideWindowId = ideWindowId
        self.chromeWindowId = chromeWindowId
    }
}

/// Versioned state cache for ProjectWorkspaces activation.
public struct ProjectWorkspacesState: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public var projects: [String: ManagedWindowState]

    /// Creates a state cache payload.
    /// - Parameters:
    ///   - version: Schema version.
    ///   - projects: Managed window state keyed by project id.
    public init(version: Int = ProjectWorkspacesState.currentVersion, projects: [String: ManagedWindowState] = [:]) {
        self.version = version
        self.projects = projects
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case projects
    }

    /// Decodes state with default fallbacks for missing fields.
    /// - Parameter decoder: Decoder for the state payload.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .version) ?? ProjectWorkspacesState.currentVersion
        let projects = try container.decodeIfPresent([String: ManagedWindowState].self, forKey: .projects) ?? [:]
        self.init(version: version, projects: projects)
    }
}

/// State store errors for read/write operations.
public enum ProjectWorkspacesStateStoreError: Error, Equatable, Sendable {
    case readFailed(path: String, detail: String)
    case backupFailed(path: String, detail: String)
    case encodeFailed(detail: String)
    case writeFailed(path: String, detail: String)
}

/// Result of loading activation state.
public struct ProjectWorkspacesStateLoadResult: Equatable, Sendable {
    public let state: ProjectWorkspacesState
    public let warnings: [ActivationWarning]

    /// Creates a load result payload.
    /// - Parameters:
    ///   - state: Loaded or default state.
    ///   - warnings: Warnings emitted while loading state.
    public init(state: ProjectWorkspacesState, warnings: [ActivationWarning]) {
        self.state = state
        self.warnings = warnings
    }
}

/// Protocol for reading and writing ProjectWorkspaces state.
public protocol ProjectWorkspacesStateStoring {
    /// Loads activation state from disk.
    /// - Returns: Loaded state with warnings or a structured error.
    func load() -> Result<ProjectWorkspacesStateLoadResult, ProjectWorkspacesStateStoreError>

    /// Persists activation state to disk.
    /// - Parameter state: State payload to persist.
    /// - Returns: Success or a structured error.
    func save(state: ProjectWorkspacesState) -> Result<Void, ProjectWorkspacesStateStoreError>
}

/// Default state store backed by the file system.
public struct ProjectWorkspacesStateStore: ProjectWorkspacesStateStoring {
    private let paths: ProjectWorkspacesPaths
    private let fileSystem: FileSystem
    private let logger: ProjectWorkspacesLogging
    private let dateProvider: DateProviding

    /// Creates a state store.
    /// - Parameters:
    ///   - paths: ProjectWorkspaces paths.
    ///   - fileSystem: File system accessor.
    ///   - logger: Logger for recovery warnings.
    ///   - dateProvider: Date provider for backup names.
    public init(
        paths: ProjectWorkspacesPaths = .defaultPaths(),
        fileSystem: FileSystem = DefaultFileSystem(),
        logger: ProjectWorkspacesLogging = ProjectWorkspacesLogger(),
        dateProvider: DateProviding = SystemDateProvider()
    ) {
        self.paths = paths
        self.fileSystem = fileSystem
        self.logger = logger
        self.dateProvider = dateProvider
    }

    /// Loads activation state from disk.
    public func load() -> Result<ProjectWorkspacesStateLoadResult, ProjectWorkspacesStateStoreError> {
        let stateURL = paths.stateFile
        guard fileSystem.fileExists(at: stateURL) else {
            return .success(ProjectWorkspacesStateLoadResult(state: ProjectWorkspacesState(), warnings: []))
        }

        let data: Data
        do {
            data = try fileSystem.readFile(at: stateURL)
        } catch {
            return .failure(.readFailed(path: stateURL.path, detail: String(describing: error)))
        }

        do {
            let decoded = try JSONDecoder().decode(ProjectWorkspacesState.self, from: data)
            return .success(ProjectWorkspacesStateLoadResult(state: decoded, warnings: []))
        } catch {
            let backupURL = backupURL(for: stateURL)
            do {
                try fileSystem.moveItem(at: stateURL, to: backupURL)
            } catch {
                return .failure(.backupFailed(path: backupURL.path, detail: String(describing: error)))
            }

            let warning = ActivationWarning.stateRecovered(backupPath: backupURL.path)
            _ = logger.log(
                event: "state.recovered",
                level: .warn,
                message: "State was unreadable; moved to backup.",
                context: ["backupPath": backupURL.path]
            )
            return .success(ProjectWorkspacesStateLoadResult(state: ProjectWorkspacesState(), warnings: [warning]))
        }
    }

    /// Persists activation state to disk.
    public func save(state: ProjectWorkspacesState) -> Result<Void, ProjectWorkspacesStateStoreError> {
        let stateURL = paths.stateFile
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let data: Data
        do {
            data = try encoder.encode(state)
        } catch {
            return .failure(.encodeFailed(detail: String(describing: error)))
        }

        do {
            try fileSystem.createDirectory(at: stateURL.deletingLastPathComponent())
            try fileSystem.writeFile(at: stateURL, data: data)
            try fileSystem.syncFile(at: stateURL)
        } catch {
            return .failure(.writeFailed(path: stateURL.path, detail: String(describing: error)))
        }

        return .success(())
    }

    private func backupURL(for stateURL: URL) -> URL {
        let timestamp = backupTimestamp(from: dateProvider.now())
        let backupName = "state.json.bak.\(timestamp)"
        return stateURL.deletingLastPathComponent().appendingPathComponent(backupName, isDirectory: false)
    }

    private func backupTimestamp(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
