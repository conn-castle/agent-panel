import Foundation

// MARK: - State Model

/// A snapshot of a focused window, captured when the switcher is opened.
public struct FocusedWindowEntry: Codable, Equatable, Sendable {
    /// AeroSpace window ID used to restore focus.
    public let windowId: Int
    /// App bundle identifier, used to check if the window still exists.
    public let appBundleId: String
    /// UTC timestamp when this entry was captured.
    public let capturedAt: Date

    public init(windowId: Int, appBundleId: String, capturedAt: Date) {
        self.windowId = windowId
        self.appBundleId = appBundleId
        self.capturedAt = capturedAt
    }
}

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

    /// Stack of recently focused windows (LIFO). Most recent is last.
    /// Used to restore focus when canceling the switcher or closing a project.
    public var focusStack: [FocusedWindowEntry]

    /// Creates a new empty state at the current schema version.
    public init() {
        self.version = Self.currentVersion
        self.lastLaunchedAt = nil
        self.focusStack = []
    }

    /// Creates state with explicit values (for testing or migrations).
    public init(version: Int, lastLaunchedAt: Date?, focusStack: [FocusedWindowEntry]) {
        self.version = version
        self.lastLaunchedAt = lastLaunchedAt
        self.focusStack = focusStack
    }
}

// MARK: - StateStore

/// Errors that can occur during state operations.
public enum StateStoreError: Error, Equatable, Sendable {
    /// State file exists but cannot be parsed.
    case corruptedState(detail: String)
    /// State file is from a newer version than this app supports.
    case newerVersion(found: Int, supported: Int)
    /// File system error during read/write.
    case fileSystemError(detail: String)
}

/// Persistence layer for application state.
///
/// State is stored as JSON at the path provided by `DataPaths.stateFile`.
/// The store handles:
/// - Schema versioning and migrations
/// - Focus stack size limits (max 20 entries)
/// - Pruning stale entries (older than 7 days)
public struct StateStore {
    /// Maximum number of entries in the focus stack.
    public static let maxFocusStackSize = 20

    /// Maximum age for focus stack entries (7 days).
    public static let maxFocusStackAge: TimeInterval = 7 * 24 * 60 * 60

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
    /// The state is pruned before saving (removes stale focus stack entries).
    ///
    /// - Parameter state: The state to save.
    /// - Returns: Success or a file system error.
    public func save(_ state: AppState) -> Result<Void, StateStoreError> {
        // Prune before saving
        let pruned = prune(state: state)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data: Data
        do {
            data = try encoder.encode(pruned)
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

    // MARK: - Focus Stack Operations

    /// Pushes a focused window onto the stack.
    ///
    /// - Parameters:
    ///   - window: The window to push.
    ///   - state: The current state.
    /// - Returns: Updated state with the window pushed.
    public func pushFocus(window: FocusedWindowEntry, state: AppState) -> AppState {
        var updated = state
        updated.focusStack.append(window)

        // Enforce size limit (remove oldest if over limit)
        if updated.focusStack.count > Self.maxFocusStackSize {
            updated.focusStack.removeFirst(updated.focusStack.count - Self.maxFocusStackSize)
        }

        return updated
    }

    /// Pops the most recently focused window from the stack.
    ///
    /// - Parameter state: The current state.
    /// - Returns: Tuple of (popped window or nil, updated state).
    public func popFocus(state: AppState) -> (FocusedWindowEntry?, AppState) {
        var updated = state
        let popped = updated.focusStack.popLast()
        return (popped, updated)
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

    // MARK: - Pruning

    /// Prunes stale entries from the focus stack.
    ///
    /// Removes entries that are:
    /// - Older than 7 days
    /// - Beyond the max stack size (keeps most recent)
    ///
    /// Note: Pruning for non-existent windows should be done by the caller
    /// since it requires checking with AeroSpace, which this layer doesn't access.
    private func prune(state: AppState) -> AppState {
        var pruned = state
        let now = dateProvider.now()
        let cutoff = now.addingTimeInterval(-Self.maxFocusStackAge)

        // Remove entries older than 7 days
        pruned.focusStack = pruned.focusStack.filter { $0.capturedAt > cutoff }

        // Enforce size limit (keep most recent)
        if pruned.focusStack.count > Self.maxFocusStackSize {
            pruned.focusStack = Array(pruned.focusStack.suffix(Self.maxFocusStackSize))
        }

        return pruned
    }

    /// Prunes entries for windows that no longer exist.
    ///
    /// - Parameters:
    ///   - state: The current state.
    ///   - existingWindowIds: Set of window IDs that currently exist.
    /// - Returns: Updated state with dead window entries removed.
    public func pruneDeadWindows(state: AppState, existingWindowIds: Set<Int>) -> AppState {
        var pruned = state
        pruned.focusStack = pruned.focusStack.filter { existingWindowIds.contains($0.windowId) }
        return pruned
    }
}
