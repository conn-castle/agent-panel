//
//  FocusHistoryStore.swift
//  AgentPanelCore
//
//  Operations for managing focus event history.
//  Provides recording, querying, pruning, and export functionality.
//

import Foundation

// MARK: - FocusHistoryStore

/// Operations for managing focus event history.
///
/// Focus history is stored as an append-only log in `AppState.focusHistory`.
/// This store provides:
/// - Recording new events
/// - Querying by time range, project, or event kind
/// - Pruning old events to prevent unbounded growth
/// - Exporting history for debugging
public struct FocusHistoryStore {
    /// Maximum number of events to retain in history.
    public static let maxHistorySize = 1000

    /// Maximum age for focus events (30 days).
    public static let maxHistoryAge: TimeInterval = 30 * 24 * 60 * 60

    private let dateProvider: DateProviding

    /// Creates a focus history store with the given dependencies.
    ///
    /// - Parameter dateProvider: Provider for current time. Defaults to system time.
    public init(dateProvider: DateProviding = SystemDateProvider()) {
        self.dateProvider = dateProvider
    }

    // MARK: - Recording

    /// Records a focus event in the history.
    ///
    /// Events are appended to the end of the history (newest last).
    ///
    /// - Parameters:
    ///   - event: The event to record.
    ///   - state: The current app state.
    /// - Returns: Updated state with the event appended.
    public func record(event: FocusEvent, state: AppState) -> AppState {
        var updated = state
        updated.focusHistory.append(event)
        return updated
    }

    // MARK: - Queries

    /// Returns all events in the history, oldest first.
    ///
    /// - Parameter state: The current app state.
    /// - Returns: All focus events.
    public func events(in state: AppState) -> [FocusEvent] {
        state.focusHistory
    }

    /// Returns events since the given date, oldest first.
    ///
    /// - Parameters:
    ///   - since: The cutoff date (inclusive).
    ///   - state: The current app state.
    /// - Returns: Events with timestamp >= since.
    public func events(since: Date, in state: AppState) -> [FocusEvent] {
        state.focusHistory.filter { $0.timestamp >= since }
    }

    /// Returns events for a specific project, oldest first.
    ///
    /// - Parameters:
    ///   - projectId: The project ID to filter by.
    ///   - state: The current app state.
    /// - Returns: Events with matching projectId.
    public func events(forProject projectId: String, in state: AppState) -> [FocusEvent] {
        state.focusHistory.filter { $0.projectId == projectId }
    }

    /// Returns events of a specific kind, oldest first.
    ///
    /// - Parameters:
    ///   - kind: The event kind to filter by.
    ///   - state: The current app state.
    /// - Returns: Events with matching kind.
    public func events(ofKind kind: FocusEventKind, in state: AppState) -> [FocusEvent] {
        state.focusHistory.filter { $0.kind == kind }
    }

    /// Returns the most recent event, if any.
    ///
    /// - Parameter state: The current app state.
    /// - Returns: The most recent event, or nil if history is empty.
    public func mostRecent(in state: AppState) -> FocusEvent? {
        state.focusHistory.last
    }

    /// Returns the most recent event for a project, if any.
    ///
    /// - Parameters:
    ///   - projectId: The project ID to filter by.
    ///   - state: The current app state.
    /// - Returns: The most recent event for the project, or nil.
    public func mostRecent(forProject projectId: String, in state: AppState) -> FocusEvent? {
        state.focusHistory.last { $0.projectId == projectId }
    }

    // MARK: - Pruning

    /// Prunes old events from the history.
    ///
    /// Removes events that are:
    /// - Older than 30 days
    /// - Beyond the max history size (keeps most recent)
    ///
    /// - Parameter state: The current app state.
    /// - Returns: Updated state with pruned history.
    public func prune(state: AppState) -> AppState {
        var pruned = state
        let now = dateProvider.now()
        let cutoff = now.addingTimeInterval(-Self.maxHistoryAge)

        // Remove events older than 30 days
        pruned.focusHistory = pruned.focusHistory.filter { $0.timestamp > cutoff }

        // Enforce size limit (keep most recent)
        if pruned.focusHistory.count > Self.maxHistorySize {
            pruned.focusHistory = Array(pruned.focusHistory.suffix(Self.maxHistorySize))
        }

        return pruned
    }

    // MARK: - Export

    /// Exports the focus history as JSON data.
    ///
    /// The export includes all events with ISO8601 timestamps, formatted
    /// for readability. Useful for debugging and analytics.
    ///
    /// - Parameter state: The current app state.
    /// - Returns: JSON data on success, or an error on encoding failure.
    public func export(state: AppState) -> Result<Data, FocusHistoryExportError> {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(state.focusHistory)
            return .success(data)
        } catch {
            return .failure(.encodingFailed(detail: error.localizedDescription))
        }
    }

    /// Exports the focus history as a JSON string.
    ///
    /// - Parameter state: The current app state.
    /// - Returns: JSON string on success, or an error on encoding/conversion failure.
    public func exportString(state: AppState) -> Result<String, FocusHistoryExportError> {
        switch export(state: state) {
        case .success(let data):
            guard let string = String(data: data, encoding: .utf8) else {
                return .failure(.stringConversionFailed)
            }
            return .success(string)
        case .failure(let error):
            return .failure(error)
        }
    }
}

// MARK: - FocusHistoryExportError

/// Errors that can occur during focus history export.
public enum FocusHistoryExportError: Error, Equatable, Sendable {
    /// JSON encoding failed.
    case encodingFailed(detail: String)
    /// UTF-8 string conversion failed.
    case stringConversionFailed
}

// MARK: - StateStore Integration

extension StateStore {
    /// Saves state to disk, pruning focus history before saving.
    ///
    /// This is the preferred save method. It prunes focus history to prevent
    /// unbounded growth before persisting.
    ///
    /// - Parameters:
    ///   - state: The state to save.
    ///   - focusHistoryStore: The focus history store for pruning.
    /// - Returns: Success or a file system error.
    public func save(
        _ state: AppState,
        prunedWith focusHistoryStore: FocusHistoryStore
    ) -> Result<Void, StateStoreError> {
        let pruned = focusHistoryStore.prune(state: state)
        return save(pruned)
    }
}
