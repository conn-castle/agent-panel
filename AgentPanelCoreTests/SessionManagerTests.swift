import Foundation
import Testing

@testable import AgentPanelCore

@Suite("SessionManager Tests")
struct SessionManagerTests {
    // MARK: - Test Helpers

    private func makeTestDataPaths() -> DataPaths {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentpanel-tests-\(UUID().uuidString)")
        return DataPaths(homeDirectory: tempDir)
    }

    private func makeSessionManager(
        dataStore: DataPaths? = nil,
        focusOperations: FocusOperationsProviding? = nil
    ) -> SessionManager {
        let dataPaths = dataStore ?? makeTestDataPaths()
        let stateStore = StateStore(dataStore: dataPaths)
        let focusHistoryStore = FocusHistoryStore()
        let logger = MockLogger()
        return SessionManager(
            stateStore: stateStore,
            focusHistoryStore: focusHistoryStore,
            logger: logger,
            focusOperations: focusOperations
        )
    }

    // MARK: - Session Lifecycle Tests

    @Test("Session started records event with version")
    func sessionStartedRecordsEvent() {
        let manager = makeSessionManager()

        manager.sessionStarted(version: "1.0.0")

        let history = manager.focusHistory
        #expect(history.count == 1)
        #expect(history[0].kind == .sessionStarted)
        #expect(history[0].metadata?["version"] == "1.0.0")
    }

    @Test("Session ended records event")
    func sessionEndedRecordsEvent() {
        let manager = makeSessionManager()
        manager.sessionStarted(version: "1.0.0")

        manager.sessionEnded()

        let history = manager.focusHistory
        #expect(history.count == 2)
        #expect(history[1].kind == .sessionEnded)
    }

    @Test("Session ended reloads state before recording")
    func sessionEndedReloadsState() {
        let dataPaths = makeTestDataPaths()

        // Create first manager and record some events
        let manager1 = makeSessionManager(dataStore: dataPaths)
        manager1.sessionStarted(version: "1.0.0")
        manager1.projectActivated(projectId: "test-project")

        // Create second manager (simulating the same app) that would have stale state
        let manager2 = makeSessionManager(dataStore: dataPaths)

        // Session end should reload state first
        manager2.sessionEnded()

        // Verify by loading with a third manager
        let manager3 = makeSessionManager(dataStore: dataPaths)
        let history = manager3.focusHistory

        // Should have: sessionStarted, projectActivated, sessionEnded
        #expect(history.count == 3)
        #expect(history[0].kind == .sessionStarted)
        #expect(history[1].kind == .projectActivated)
        #expect(history[2].kind == .sessionEnded)
    }

    // MARK: - Focus Capture/Restore Tests

    @Test("Capture current focus returns CapturedFocus when window available")
    func captureCurrentFocusReturnsCapture() {
        let mockFocus = MockFocusOperations(
            capturedFocusResult: CapturedFocus(
                windowId: 42,
                appBundleId: "com.example.app"
            )
        )
        let manager = makeSessionManager(focusOperations: mockFocus)

        let captured = manager.captureCurrentFocus()

        #expect(captured != nil)
        #expect(captured?.windowId == 42)
        #expect(captured?.appBundleId == "com.example.app")
    }

    @Test("Capture current focus records windowDefocused event")
    func captureCurrentFocusRecordsEvent() {
        let mockFocus = MockFocusOperations(
            capturedFocusResult: CapturedFocus(
                windowId: 42,
                appBundleId: "com.example.app"
            )
        )
        let manager = makeSessionManager(focusOperations: mockFocus)

        _ = manager.captureCurrentFocus()

        let history = manager.focusHistory
        #expect(history.count == 1)
        #expect(history[0].kind == .windowDefocused)
        #expect(history[0].windowId == 42)
        #expect(history[0].appBundleId == "com.example.app")
    }

    @Test("Capture current focus returns nil when no focus operations")
    func captureCurrentFocusReturnsNilWithoutOperations() {
        let manager = makeSessionManager(focusOperations: nil)

        let captured = manager.captureCurrentFocus()

        #expect(captured == nil)
    }

    @Test("Capture current focus returns nil when no window focused")
    func captureCurrentFocusReturnsNilWhenNoWindow() {
        let mockFocus = MockFocusOperations(capturedFocusResult: nil)
        let manager = makeSessionManager(focusOperations: mockFocus)

        let captured = manager.captureCurrentFocus()

        #expect(captured == nil)
    }

    @Test("Restore focus succeeds when window can be focused")
    func restoreFocusSucceeds() {
        let mockFocus = MockFocusOperations(restoreFocusResult: true)
        let manager = makeSessionManager(focusOperations: mockFocus)

        let captured = CapturedFocus(windowId: 42, appBundleId: "com.example.app")
        let success = manager.restoreFocus(captured)

        #expect(success)
        #expect(mockFocus.lastRestoredFocus?.windowId == 42)
    }

    @Test("Restore focus records windowFocused event on success")
    func restoreFocusRecordsEventOnSuccess() {
        let mockFocus = MockFocusOperations(restoreFocusResult: true)
        let manager = makeSessionManager(focusOperations: mockFocus)

        let captured = CapturedFocus(windowId: 42, appBundleId: "com.example.app")
        _ = manager.restoreFocus(captured)

        let history = manager.focusHistory
        #expect(history.count == 1)
        #expect(history[0].kind == .windowFocused)
        #expect(history[0].windowId == 42)
    }

    @Test("Restore focus returns false when window cannot be focused")
    func restoreFocusFails() {
        let mockFocus = MockFocusOperations(restoreFocusResult: false)
        let manager = makeSessionManager(focusOperations: mockFocus)

        let captured = CapturedFocus(windowId: 42, appBundleId: "com.example.app")
        let success = manager.restoreFocus(captured)

        #expect(!success)
    }

    @Test("Restore focus does not record event on failure")
    func restoreFocusNoEventOnFailure() {
        let mockFocus = MockFocusOperations(restoreFocusResult: false)
        let manager = makeSessionManager(focusOperations: mockFocus)

        let captured = CapturedFocus(windowId: 42, appBundleId: "com.example.app")
        _ = manager.restoreFocus(captured)

        let history = manager.focusHistory
        #expect(history.isEmpty)
    }

    @Test("Restore focus returns false without focus operations")
    func restoreFocusFailsWithoutOperations() {
        let manager = makeSessionManager(focusOperations: nil)

        let captured = CapturedFocus(windowId: 42, appBundleId: "com.example.app")
        let success = manager.restoreFocus(captured)

        #expect(!success)
    }

    // MARK: - Project Event Tests

    @Test("Project activated records event")
    func projectActivatedRecordsEvent() {
        let manager = makeSessionManager()

        manager.projectActivated(projectId: "my-project")

        let history = manager.focusHistory
        #expect(history.count == 1)
        #expect(history[0].kind == .projectActivated)
        #expect(history[0].projectId == "my-project")
    }

    @Test("Project deactivated records event")
    func projectDeactivatedRecordsEvent() {
        let manager = makeSessionManager()

        manager.projectDeactivated(projectId: "my-project")

        let history = manager.focusHistory
        #expect(history.count == 1)
        #expect(history[0].kind == .projectDeactivated)
        #expect(history[0].projectId == "my-project")
    }

    // MARK: - Focus History Access Tests

    @Test("Recent focus history returns newest first")
    func recentFocusHistoryNewestFirst() {
        let manager = makeSessionManager()
        manager.projectActivated(projectId: "first")
        manager.projectActivated(projectId: "second")
        manager.projectActivated(projectId: "third")

        let recent = manager.recentFocusHistory(count: 2)

        #expect(recent.count == 2)
        #expect(recent[0].projectId == "third")
        #expect(recent[1].projectId == "second")
    }

    @Test("Recent project activations returns only project activated events")
    func recentProjectActivationsFiltersEvents() {
        let manager = makeSessionManager()
        manager.sessionStarted(version: "1.0.0")
        manager.projectActivated(projectId: "alpha")
        manager.projectDeactivated(projectId: "alpha")
        manager.projectActivated(projectId: "beta")

        let recent = manager.recentProjectActivations(count: 10)

        #expect(recent.count == 2)
        #expect(recent[0].projectId == "beta")
        #expect(recent[1].projectId == "alpha")
    }

    // MARK: - Set Focus Operations Tests

    @Test("Set focus operations enables capture")
    func setFocusOperationsEnablesCapture() {
        let manager = makeSessionManager(focusOperations: nil)

        // Initially no capture possible
        #expect(manager.captureCurrentFocus() == nil)

        // Set focus operations
        let mockFocus = MockFocusOperations(
            capturedFocusResult: CapturedFocus(
                windowId: 42,
                appBundleId: "com.example.app"
            )
        )
        manager.setFocusOperations(mockFocus)

        // Now capture should work
        let captured = manager.captureCurrentFocus()
        #expect(captured != nil)
        #expect(captured?.windowId == 42)
    }

    // MARK: - Persistence Tests

    @Test("Events are persisted across manager instances")
    func eventsArePersistedAcrossInstances() {
        let dataPaths = makeTestDataPaths()

        // First manager records events
        let manager1 = makeSessionManager(dataStore: dataPaths)
        manager1.sessionStarted(version: "1.0.0")
        manager1.projectActivated(projectId: "test-project")

        // Second manager should see the events
        let manager2 = makeSessionManager(dataStore: dataPaths)
        let history = manager2.focusHistory

        #expect(history.count == 2)
        #expect(history[0].kind == .sessionStarted)
        #expect(history[1].kind == .projectActivated)
        #expect(history[1].projectId == "test-project")
    }
}

// MARK: - Test Doubles

private final class MockFocusOperations: FocusOperationsProviding {
    let capturedFocusResult: CapturedFocus?
    let restoreFocusResult: Bool
    private(set) var lastRestoredFocus: CapturedFocus?

    init(
        capturedFocusResult: CapturedFocus? = nil,
        restoreFocusResult: Bool = true
    ) {
        self.capturedFocusResult = capturedFocusResult
        self.restoreFocusResult = restoreFocusResult
    }

    func captureCurrentFocus() -> CapturedFocus? {
        capturedFocusResult
    }

    func restoreFocus(_ focus: CapturedFocus) -> Bool {
        lastRestoredFocus = focus
        return restoreFocusResult
    }
}

private final class MockLogger: AgentPanelLogging {
    private(set) var loggedEvents: [(event: String, level: LogLevel, message: String?, context: [String: String]?)] = []

    @discardableResult
    func log(
        event: String,
        level: LogLevel,
        message: String?,
        context: [String: String]?
    ) -> Result<Void, LogWriteError> {
        loggedEvents.append((event, level, message, context))
        return .success(())
    }
}
