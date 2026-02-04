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
            #expect(state.focusStack.isEmpty)
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
        state.focusStack = [
            FocusedWindowEntry(windowId: 123, appBundleId: "com.test.app", capturedAt: now)
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
            // Date comparison with tolerance for encoding/decoding
            #expect(loaded.lastLaunchedAt != nil)
            #expect(loaded.focusStack.count == 1)
            #expect(loaded.focusStack[0].windowId == 123)
            #expect(loaded.focusStack[0].appBundleId == "com.test.app")
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
          "focusStack": []
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

    // MARK: - Focus Stack Tests

    @Test("Push adds window to stack")
    func pushAddsWindowToStack() {
        let store = StateStore()
        let state = AppState()
        let entry = FocusedWindowEntry(windowId: 1, appBundleId: "com.test", capturedAt: Date())

        let updated = store.pushFocus(window: entry, state: state)

        #expect(updated.focusStack.count == 1)
        #expect(updated.focusStack[0].windowId == 1)
    }

    @Test("Push enforces max size limit")
    func pushEnforcesMaxSizeLimit() {
        let store = StateStore()
        var state = AppState()

        // Fill stack to max
        for i in 1...StateStore.maxFocusStackSize {
            let entry = FocusedWindowEntry(windowId: i, appBundleId: "com.test", capturedAt: Date())
            state = store.pushFocus(window: entry, state: state)
        }
        #expect(state.focusStack.count == StateStore.maxFocusStackSize)

        // Push one more - should remove oldest
        let extraEntry = FocusedWindowEntry(windowId: 999, appBundleId: "com.test", capturedAt: Date())
        state = store.pushFocus(window: extraEntry, state: state)

        #expect(state.focusStack.count == StateStore.maxFocusStackSize)
        #expect(state.focusStack.first?.windowId == 2) // Oldest (1) removed
        #expect(state.focusStack.last?.windowId == 999) // Newest added
    }

    @Test("Pop returns most recent and removes it")
    func popReturnsMostRecentAndRemovesIt() {
        let store = StateStore()
        var state = AppState()

        let entry1 = FocusedWindowEntry(windowId: 1, appBundleId: "com.test", capturedAt: Date())
        let entry2 = FocusedWindowEntry(windowId: 2, appBundleId: "com.test", capturedAt: Date())
        state = store.pushFocus(window: entry1, state: state)
        state = store.pushFocus(window: entry2, state: state)

        let (popped, updated) = store.popFocus(state: state)

        #expect(popped?.windowId == 2) // Most recent
        #expect(updated.focusStack.count == 1)
        #expect(updated.focusStack[0].windowId == 1)
    }

    @Test("Pop returns nil for empty stack")
    func popReturnsNilForEmptyStack() {
        let store = StateStore()
        let state = AppState()

        let (popped, updated) = store.popFocus(state: state)

        #expect(popped == nil)
        #expect(updated.focusStack.isEmpty)
    }

    // MARK: - Pruning Tests

    @Test("Save prunes entries older than 7 days")
    func savePrunesOldEntries() throws {
        let dataStore = makeTestDataPaths()
        let now = Date()
        let store = StateStore(
            dataStore: dataStore,
            dateProvider: makeFixedDateProvider(date: now)
        )

        var state = AppState()
        // Entry from 8 days ago (should be pruned)
        let oldEntry = FocusedWindowEntry(
            windowId: 1,
            appBundleId: "com.old",
            capturedAt: now.addingTimeInterval(-8 * 24 * 60 * 60)
        )
        // Entry from 1 day ago (should be kept)
        let recentEntry = FocusedWindowEntry(
            windowId: 2,
            appBundleId: "com.recent",
            capturedAt: now.addingTimeInterval(-1 * 24 * 60 * 60)
        )
        state.focusStack = [oldEntry, recentEntry]

        let saveResult = store.save(state)
        guard case .success = saveResult else {
            Issue.record("Expected save to succeed but got: \(saveResult)")
            return
        }

        let loadResult = store.load()
        switch loadResult {
        case .success(let loaded):
            #expect(loaded.focusStack.count == 1)
            #expect(loaded.focusStack[0].windowId == 2)
        case .failure(let error):
            Issue.record("Expected success but got error: \(error)")
        }
    }

    @Test("Prune dead windows removes non-existent windows")
    func pruneDeadWindowsRemovesNonExistent() {
        let store = StateStore()
        var state = AppState()
        state.focusStack = [
            FocusedWindowEntry(windowId: 1, appBundleId: "com.test", capturedAt: Date()),
            FocusedWindowEntry(windowId: 2, appBundleId: "com.test", capturedAt: Date()),
            FocusedWindowEntry(windowId: 3, appBundleId: "com.test", capturedAt: Date())
        ]

        // Only windows 1 and 3 exist
        let existingIds: Set<Int> = [1, 3]
        let pruned = store.pruneDeadWindows(state: state, existingWindowIds: existingIds)

        #expect(pruned.focusStack.count == 2)
        #expect(pruned.focusStack.map(\.windowId) == [1, 3])
    }
}

// MARK: - Test Doubles

private struct FixedDateProvider: DateProviding {
    let date: Date
    func now() -> Date { date }
}
