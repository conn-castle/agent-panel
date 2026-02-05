import Foundation

// MARK: - FocusEventKind

/// The kind of focus change that occurred.
public enum FocusEventKind: String, Codable, Sendable, CaseIterable {
    /// A project was activated in the switcher.
    case projectActivated

    /// A project was deactivated (user switched away).
    case projectDeactivated

    /// A window gained focus.
    case windowFocused

    /// A window lost focus (e.g., switcher opened).
    case windowDefocused

    /// The app session started (app launched).
    case sessionStarted

    /// The app session ended (app quit).
    case sessionEnded
}

// MARK: - FocusEvent

/// A focus event in the history log.
///
/// Events are immutable and identified by a stable UUID for correlation
/// across exports and debugging. All timestamps are UTC.
public struct FocusEvent: Codable, Equatable, Sendable, Identifiable {
    /// Stable correlation ID for this event.
    public let id: UUID

    /// The kind of focus change that occurred.
    public let kind: FocusEventKind

    /// UTC timestamp when this event occurred.
    public let timestamp: Date

    /// Project ID if this event relates to a project (from config).
    public let projectId: String?

    /// AeroSpace window ID if applicable.
    public let windowId: Int?

    /// App bundle identifier if applicable.
    public let appBundleId: String?

    /// Extensible context for additional event-specific data.
    public let metadata: [String: String]?

    /// Creates a new focus event.
    ///
    /// - Parameters:
    ///   - id: Stable correlation ID. Defaults to a new UUID.
    ///   - kind: The kind of focus change.
    ///   - timestamp: UTC timestamp. Defaults to current time.
    ///   - projectId: Project ID if applicable.
    ///   - windowId: AeroSpace window ID if applicable.
    ///   - appBundleId: App bundle identifier if applicable.
    ///   - metadata: Additional context for the event.
    public init(
        id: UUID = UUID(),
        kind: FocusEventKind,
        timestamp: Date = Date(),
        projectId: String? = nil,
        windowId: Int? = nil,
        appBundleId: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.kind = kind
        self.timestamp = timestamp
        self.projectId = projectId
        self.windowId = windowId
        self.appBundleId = appBundleId
        self.metadata = metadata
    }
}

// MARK: - FocusEvent Factory Methods

extension FocusEvent {
    /// Creates a project activated event.
    public static func projectActivated(
        projectId: String,
        timestamp: Date = Date(),
        metadata: [String: String]? = nil
    ) -> FocusEvent {
        FocusEvent(
            kind: .projectActivated,
            timestamp: timestamp,
            projectId: projectId,
            metadata: metadata
        )
    }

    /// Creates a project deactivated event.
    public static func projectDeactivated(
        projectId: String,
        timestamp: Date = Date(),
        metadata: [String: String]? = nil
    ) -> FocusEvent {
        FocusEvent(
            kind: .projectDeactivated,
            timestamp: timestamp,
            projectId: projectId,
            metadata: metadata
        )
    }

    /// Creates a window focused event.
    public static func windowFocused(
        windowId: Int,
        appBundleId: String,
        projectId: String? = nil,
        timestamp: Date = Date(),
        metadata: [String: String]? = nil
    ) -> FocusEvent {
        FocusEvent(
            kind: .windowFocused,
            timestamp: timestamp,
            projectId: projectId,
            windowId: windowId,
            appBundleId: appBundleId,
            metadata: metadata
        )
    }

    /// Creates a window defocused event.
    public static func windowDefocused(
        windowId: Int,
        appBundleId: String,
        projectId: String? = nil,
        timestamp: Date = Date(),
        metadata: [String: String]? = nil
    ) -> FocusEvent {
        FocusEvent(
            kind: .windowDefocused,
            timestamp: timestamp,
            projectId: projectId,
            windowId: windowId,
            appBundleId: appBundleId,
            metadata: metadata
        )
    }

    /// Creates a session started event.
    public static func sessionStarted(
        timestamp: Date = Date(),
        metadata: [String: String]? = nil
    ) -> FocusEvent {
        FocusEvent(
            kind: .sessionStarted,
            timestamp: timestamp,
            metadata: metadata
        )
    }

    /// Creates a session ended event.
    public static func sessionEnded(
        timestamp: Date = Date(),
        metadata: [String: String]? = nil
    ) -> FocusEvent {
        FocusEvent(
            kind: .sessionEnded,
            timestamp: timestamp,
            metadata: metadata
        )
    }
}

// MARK: - AppState

/// Persisted application state.
///
/// Schema versioning: The `version` field tracks schema changes. When loading state,
/// if `version` is lower than `AppState.currentVersion`, migrations are applied.
/// If `version` is higher, loading fails (newer state from a future version).
public struct AppState: Codable, Equatable, Sendable {
    /// Current schema version. Increment when making breaking changes.
    public static let currentVersion = 1

    /// Schema version of this state instance.
    public var version: Int

    /// UTC timestamp of the last app launch.
    public var lastLaunchedAt: Date?

    /// Focus event history (append-only log, newest last).
    /// Used for analytics, restore-on-cancel, and influencing switcher ordering.
    public var focusHistory: [FocusEvent]

    /// Creates a new empty state at the current schema version.
    public init() {
        self.version = Self.currentVersion
        self.lastLaunchedAt = nil
        self.focusHistory = []
    }

    /// Creates state with explicit values (for testing).
    public init(
        version: Int,
        lastLaunchedAt: Date?,
        focusHistory: [FocusEvent] = []
    ) {
        self.version = version
        self.lastLaunchedAt = lastLaunchedAt
        self.focusHistory = focusHistory
    }
}

// MARK: - StateStoreError

/// Errors that can occur during state operations.
public enum StateStoreError: Error, Equatable, Sendable {
    /// State file exists but cannot be parsed.
    case corruptedState(detail: String)
    /// State file is from a newer version than this app supports.
    case newerVersion(found: Int, supported: Int)
    /// File system error during read/write.
    case fileSystemError(detail: String)
}

// MARK: - StateStore

/// Persistence layer for application state.
///
/// State is stored as JSON at the path provided by `DataPaths.stateFile`.
/// The store handles schema versioning and migrations.
public struct StateStore {
    private let dataStore: DataPaths
    private let fileSystem: FileSystem
    private let dateProvider: DateProviding

    /// Creates a state store with the given dependencies.
    public init(
        dataStore: DataPaths = .default(),
        fileSystem: FileSystem = DefaultFileSystem(),
        dateProvider: DateProviding = SystemDateProvider()
    ) {
        self.dataStore = dataStore
        self.fileSystem = fileSystem
        self.dateProvider = dateProvider
    }

    // MARK: - Load

    /// Loads state from disk.
    ///
    /// - Returns: The loaded state, or a new empty state if no state file exists.
    /// - Throws: `StateStoreError` if the file exists but cannot be loaded.
    public func load() -> Result<AppState, StateStoreError> {
        let stateFile = dataStore.stateFile

        guard fileSystem.fileExists(at: stateFile) else {
            return .success(AppState())
        }

        let data: Data
        do {
            data = try fileSystem.readFile(at: stateFile)
        } catch {
            return .failure(.fileSystemError(detail: "Failed to read state file: \(error.localizedDescription)"))
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let state: AppState
        do {
            state = try decoder.decode(AppState.self, from: data)
        } catch {
            return .failure(.corruptedState(detail: "Failed to decode state: \(error.localizedDescription)"))
        }

        // Check version compatibility
        if state.version > AppState.currentVersion {
            return .failure(.newerVersion(found: state.version, supported: AppState.currentVersion))
        }

        // Apply migrations if needed
        let migrated = migrate(state: state)

        return .success(migrated)
    }

    // MARK: - Save

    /// Saves state to disk.
    ///
    /// - Parameter state: The state to save.
    /// - Returns: Success or a file system error.
    public func save(_ state: AppState) -> Result<Void, StateStoreError> {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data: Data
        do {
            data = try encoder.encode(state)
        } catch {
            return .failure(.fileSystemError(detail: "Failed to encode state: \(error.localizedDescription)"))
        }

        // Ensure directory exists
        let stateDirectory = dataStore.stateFile.deletingLastPathComponent()
        do {
            try fileSystem.createDirectory(at: stateDirectory)
        } catch {
            return .failure(.fileSystemError(detail: "Failed to create state directory: \(error.localizedDescription)"))
        }

        do {
            try fileSystem.writeFile(at: dataStore.stateFile, data: data)
        } catch {
            return .failure(.fileSystemError(detail: "Failed to write state file: \(error.localizedDescription)"))
        }

        return .success(())
    }

    // MARK: - Migrations

    /// Applies migrations to bring state to the current version.
    private func migrate(state: AppState) -> AppState {
        var migrated = state
        // Future migrations go here:
        // if migrated.version < 2 { ... migrated.version = 2 }
        migrated.version = AppState.currentVersion
        return migrated
    }
}
