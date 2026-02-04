import Foundation
import Testing

@testable import AgentPanelCore

@Suite("FocusHistoryStore Tests")
struct FocusHistoryStoreTests {
    // MARK: - Test Helpers

    private func makeFixedDateProvider(date: Date) -> DateProviding {
        FixedDateProvider(date: date)
    }

    private func makeEvent(
        kind: FocusEventKind = .projectActivated,
        timestamp: Date = Date(),
        projectId: String? = nil
    ) -> FocusEvent {
        FocusEvent(
            kind: kind,
            timestamp: timestamp,
            projectId: projectId
        )
    }

    // MARK: - Record Tests

    @Test("Record appends event to history")
    func recordAppendsEvent() {
        let store = FocusHistoryStore()
        let state = AppState()
        let event = makeEvent(projectId: "test-project")

        let updated = store.record(event: event, state: state)

        #expect(updated.focusHistory.count == 1)
        #expect(updated.focusHistory[0].projectId == "test-project")
    }

    @Test("Record preserves existing events")
    func recordPreservesExistingEvents() {
        let store = FocusHistoryStore()
        var state = AppState()
        let event1 = makeEvent(projectId: "first")
        let event2 = makeEvent(projectId: "second")

        state = store.record(event: event1, state: state)
        state = store.record(event: event2, state: state)

        #expect(state.focusHistory.count == 2)
        #expect(state.focusHistory[0].projectId == "first")
        #expect(state.focusHistory[1].projectId == "second")
    }

    // MARK: - Query Tests

    @Test("Events returns all events oldest first")
    func eventsReturnsAllEvents() {
        let store = FocusHistoryStore()
        var state = AppState()
        state.focusHistory = [
            makeEvent(projectId: "a"),
            makeEvent(projectId: "b"),
            makeEvent(projectId: "c")
        ]

        let events = store.events(in: state)

        #expect(events.count == 3)
        #expect(events[0].projectId == "a")
        #expect(events[2].projectId == "c")
    }

    @Test("Events since filters by timestamp")
    func eventsSinceFiltersByTimestamp() {
        let store = FocusHistoryStore()
        let now = Date()
        var state = AppState()
        state.focusHistory = [
            makeEvent(timestamp: now.addingTimeInterval(-100), projectId: "old"),
            makeEvent(timestamp: now.addingTimeInterval(-50), projectId: "middle"),
            makeEvent(timestamp: now, projectId: "new")
        ]

        let events = store.events(since: now.addingTimeInterval(-60), in: state)

        #expect(events.count == 2)
        #expect(events[0].projectId == "middle")
        #expect(events[1].projectId == "new")
    }

    @Test("Events for project filters by projectId")
    func eventsForProjectFiltersByProjectId() {
        let store = FocusHistoryStore()
        var state = AppState()
        state.focusHistory = [
            makeEvent(projectId: "alpha"),
            makeEvent(projectId: "beta"),
            makeEvent(projectId: "alpha"),
            makeEvent(projectId: nil)
        ]

        let events = store.events(forProject: "alpha", in: state)

        #expect(events.count == 2)
        #expect(events.allSatisfy { $0.projectId == "alpha" })
    }

    @Test("Events of kind filters by event kind")
    func eventsOfKindFiltersByKind() {
        let store = FocusHistoryStore()
        var state = AppState()
        state.focusHistory = [
            makeEvent(kind: .projectActivated),
            makeEvent(kind: .windowFocused),
            makeEvent(kind: .projectActivated),
            makeEvent(kind: .sessionStarted)
        ]

        let events = store.events(ofKind: .projectActivated, in: state)

        #expect(events.count == 2)
        #expect(events.allSatisfy { $0.kind == .projectActivated })
    }

    @Test("Most recent returns last event")
    func mostRecentReturnsLastEvent() {
        let store = FocusHistoryStore()
        var state = AppState()
        state.focusHistory = [
            makeEvent(projectId: "first"),
            makeEvent(projectId: "second"),
            makeEvent(projectId: "third")
        ]

        let recent = store.mostRecent(in: state)

        #expect(recent?.projectId == "third")
    }

    @Test("Most recent returns nil for empty history")
    func mostRecentReturnsNilForEmptyHistory() {
        let store = FocusHistoryStore()
        let state = AppState()

        let recent = store.mostRecent(in: state)

        #expect(recent == nil)
    }

    @Test("Most recent for project returns last event for that project")
    func mostRecentForProjectReturnsLastForProject() {
        let store = FocusHistoryStore()
        var state = AppState()
        state.focusHistory = [
            makeEvent(projectId: "alpha"),
            makeEvent(projectId: "beta"),
            makeEvent(projectId: "alpha"),
            makeEvent(projectId: "gamma")
        ]

        let recent = store.mostRecent(forProject: "alpha", in: state)

        #expect(recent?.projectId == "alpha")
        // Should be the second alpha event (index 2), not the first
        #expect(recent?.id == state.focusHistory[2].id)
    }

    // MARK: - Prune Tests

    @Test("Prune removes events older than 30 days")
    func pruneRemovesOldEvents() {
        let now = Date()
        let store = FocusHistoryStore(dateProvider: makeFixedDateProvider(date: now))
        var state = AppState()
        state.focusHistory = [
            // 31 days ago (should be pruned)
            makeEvent(timestamp: now.addingTimeInterval(-31 * 24 * 60 * 60), projectId: "old"),
            // 29 days ago (should be kept)
            makeEvent(timestamp: now.addingTimeInterval(-29 * 24 * 60 * 60), projectId: "recent"),
            // Now (should be kept)
            makeEvent(timestamp: now, projectId: "current")
        ]

        let pruned = store.prune(state: state)

        #expect(pruned.focusHistory.count == 2)
        #expect(pruned.focusHistory[0].projectId == "recent")
        #expect(pruned.focusHistory[1].projectId == "current")
    }

    @Test("Prune enforces max history size keeping most recent")
    func pruneEnforcesMaxSize() {
        let now = Date()
        let store = FocusHistoryStore(dateProvider: makeFixedDateProvider(date: now))
        var state = AppState()

        // Add more events than max size
        let overflowCount = FocusHistoryStore.maxHistorySize + 100
        for i in 0..<overflowCount {
            state.focusHistory.append(makeEvent(
                timestamp: now.addingTimeInterval(Double(i)),
                projectId: "event-\(i)"
            ))
        }

        let pruned = store.prune(state: state)

        #expect(pruned.focusHistory.count == FocusHistoryStore.maxHistorySize)
        // Should keep the most recent events (highest index numbers)
        let firstKeptIndex = overflowCount - FocusHistoryStore.maxHistorySize
        #expect(pruned.focusHistory.first?.projectId == "event-\(firstKeptIndex)")
        #expect(pruned.focusHistory.last?.projectId == "event-\(overflowCount - 1)")
    }

    @Test("Prune does nothing when history is within limits")
    func pruneNoOpWhenWithinLimits() {
        let now = Date()
        let store = FocusHistoryStore(dateProvider: makeFixedDateProvider(date: now))
        var state = AppState()
        state.focusHistory = [
            makeEvent(timestamp: now.addingTimeInterval(-1 * 24 * 60 * 60), projectId: "a"),
            makeEvent(timestamp: now, projectId: "b")
        ]

        let pruned = store.prune(state: state)

        #expect(pruned.focusHistory.count == 2)
    }

    // MARK: - Export Tests

    @Test("Export returns valid JSON")
    func exportReturnsValidJson() throws {
        let store = FocusHistoryStore()
        var state = AppState()
        let timestamp = Date(timeIntervalSince1970: 1704067200) // Fixed timestamp for deterministic test
        state.focusHistory = [
            FocusEvent(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                kind: .projectActivated,
                timestamp: timestamp,
                projectId: "test-project"
            )
        ]

        let result = store.export(state: state)

        switch result {
        case .success(let data):
            let json = String(data: data, encoding: .utf8)
            #expect(json != nil)
            #expect(json!.contains("projectActivated"))
            #expect(json!.contains("test-project"))
            #expect(json!.contains("00000000-0000-0000-0000-000000000001"))
        case .failure(let error):
            Issue.record("Export failed unexpectedly: \(error)")
        }
    }

    @Test("Export returns empty array for empty history")
    func exportReturnsEmptyArrayForEmptyHistory() {
        let store = FocusHistoryStore()
        let state = AppState()

        let result = store.export(state: state)

        switch result {
        case .success(let data):
            let json = String(data: data, encoding: .utf8)
            #expect(json == "[\n\n]")
        case .failure(let error):
            Issue.record("Export failed unexpectedly: \(error)")
        }
    }

    @Test("ExportString returns string representation")
    func exportStringReturnsString() {
        let store = FocusHistoryStore()
        var state = AppState()
        state.focusHistory = [makeEvent(projectId: "string-test")]

        let result = store.exportString(state: state)

        switch result {
        case .success(let string):
            #expect(string.contains("string-test"))
        case .failure(let error):
            Issue.record("ExportString failed unexpectedly: \(error)")
        }
    }

    // MARK: - StateStore Integration Tests

    @Test("StateStore save with FocusHistoryStore prunes history")
    func stateStoreSaveWithPruning() throws {
        let now = Date()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentpanel-tests-\(UUID().uuidString)")
        let dataStore = DataPaths(homeDirectory: tempDir)
        let focusStore = FocusHistoryStore(dateProvider: makeFixedDateProvider(date: now))
        let stateStore = StateStore(
            dataStore: dataStore,
            dateProvider: makeFixedDateProvider(date: now)
        )

        var state = AppState()
        // Add an old event that should be pruned
        state.focusHistory = [
            makeEvent(timestamp: now.addingTimeInterval(-31 * 24 * 60 * 60), projectId: "old"),
            makeEvent(timestamp: now, projectId: "current")
        ]

        let result = stateStore.save(state, prunedWith: focusStore)

        guard case .success = result else {
            Issue.record("Expected save to succeed")
            return
        }

        let loadResult = stateStore.load()
        switch loadResult {
        case .success(let loaded):
            #expect(loaded.focusHistory.count == 1)
            #expect(loaded.focusHistory[0].projectId == "current")
        case .failure(let error):
            Issue.record("Expected load to succeed but got: \(error)")
        }
    }
}

// MARK: - Test Doubles

private struct FixedDateProvider: DateProviding {
    let date: Date
    func now() -> Date { date }
}
