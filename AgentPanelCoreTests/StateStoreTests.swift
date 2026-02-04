import Foundation
import Testing

@testable import AgentPanelCore

@Suite("StateStore Tests")
struct StateStoreTests {
    // MARK: - Test Helpers

    private func makeTestDataPaths() -> DataPaths {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentpanel-tests-\(UUID().uuidString)")
        return DataPaths(homeDirectory: tempDir)
    }

    private func makeFixedDateProvider(date: Date) -> DateProviding {
        FixedDateProvider(date: date)
    }

    // MARK: - Load Tests

    @Test("Load returns empty state when no file exists")
    func loadReturnsEmptyStateWhenNoFile() {
        let dataStore = makeTestDataPaths()
        let store = StateStore(dataStore: dataStore)

        let result = store.load()

        switch result {
        case .success(let state):
            #expect(state.version == AppState.currentVersion)
            #expect(state.lastLaunchedAt == nil)
            #expect(state.focusHistory.isEmpty)
        case .failure(let error):
            Issue.record("Expected success but got error: \(error)")
        }
    }

    @Test("Load returns saved state")
    func loadReturnsSavedState() throws {
        let dataStore = makeTestDataPaths()
        let store = StateStore(dataStore: dataStore)
        let now = Date()

        var state = AppState()
        state.lastLaunchedAt = now
        state.focusHistory = [
            FocusEvent.projectActivated(projectId: "test-project", timestamp: now)
        ]

        // Save then load
        let saveResult = store.save(state)
        guard case .success = saveResult else {
            Issue.record("Expected save to succeed but got: \(saveResult)")
            return
        }

        let loadResult = store.load()
        switch loadResult {
        case .success(let loaded):
            #expect(loaded.version == AppState.currentVersion)
            #expect(loaded.lastLaunchedAt != nil)
            #expect(loaded.focusHistory.count == 1)
            #expect(loaded.focusHistory[0].projectId == "test-project")
        case .failure(let error):
            Issue.record("Expected success but got error: \(error)")
        }
    }

    @Test("Load fails for newer version")
    func loadFailsForNewerVersion() throws {
        let dataStore = makeTestDataPaths()
        let fileSystem = DefaultFileSystem()

        // Write state with a future version directly
        let futureState = """
        {
          "version": 999,
          "lastLaunchedAt": null,
          "focusHistory": []
        }
        """
        let stateDir = dataStore.stateFile.deletingLastPathComponent()
        try fileSystem.createDirectory(at: stateDir)
        try fileSystem.writeFile(at: dataStore.stateFile, data: Data(futureState.utf8))

        let store = StateStore(dataStore: dataStore)
        let result = store.load()

        switch result {
        case .success:
            Issue.record("Expected failure for newer version")
        case .failure(let error):
            #expect(error == .newerVersion(found: 999, supported: AppState.currentVersion))
        }
    }

    @Test("Load fails for corrupted JSON")
    func loadFailsForCorruptedJson() throws {
        let dataStore = makeTestDataPaths()
        let fileSystem = DefaultFileSystem()

        // Write invalid JSON
        let stateDir = dataStore.stateFile.deletingLastPathComponent()
        try fileSystem.createDirectory(at: stateDir)
        try fileSystem.writeFile(at: dataStore.stateFile, data: Data("not valid json".utf8))

        let store = StateStore(dataStore: dataStore)
        let result = store.load()

        switch result {
        case .success:
            Issue.record("Expected failure for corrupted JSON")
        case .failure(let error):
            if case .corruptedState = error {
                // Expected
            } else {
                Issue.record("Expected corruptedState error but got: \(error)")
            }
        }
    }

    // MARK: - Save with Pruning Tests

    @Test("Save with FocusHistoryStore prunes old events")
    func saveWithPruningRemovesOldEvents() throws {
        let now = Date()
        let dataStore = makeTestDataPaths()
        let focusStore = FocusHistoryStore(dateProvider: makeFixedDateProvider(date: now))
        let stateStore = StateStore(dataStore: dataStore)

        var state = AppState()
        // Add an old event that should be pruned (31 days old)
        state.focusHistory = [
            FocusEvent.projectActivated(
                projectId: "old",
                timestamp: now.addingTimeInterval(-31 * 24 * 60 * 60)
            ),
            FocusEvent.projectActivated(
                projectId: "current",
                timestamp: now
            )
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
