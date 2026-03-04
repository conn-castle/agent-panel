//
//  SwitcherCoordinatorTests.swift
//  AgentPanelAppTests
//
//  Tests for SwitcherWorkspaceRetryCoordinator and SwitcherOperationCoordinator.
//  Validates retry logic, session guards, operation callbacks, and guard resets.
//

import XCTest

@testable import AgentPanel
@testable import AgentPanelAppKit
@testable import AgentPanelCore

// MARK: - SwitcherWorkspaceRetryCoordinator Tests

final class SwitcherWorkspaceRetryCoordinatorTests: XCTestCase {

    // MARK: - Helpers

    private func makeProjectManager(
        aerospace: CoordinatorTestAeroSpaceStub,
        logger: CoordinatorTestRecordingLogger,
        fileSystem: CoordinatorTestInMemoryFileSystem
    ) -> ProjectManager {
        let recencyFilePath = URL(fileURLWithPath: "/recency.json", isDirectory: false)
        let focusHistoryFilePath = URL(fileURLWithPath: "/focus-history.json", isDirectory: false)
        let chromeTabsDir = URL(fileURLWithPath: "/chrome-tabs", isDirectory: true)

        return ProjectManager(
            aerospace: aerospace,
            ideLauncher: CoordinatorTestIdeLauncherStub(),
            agentLayerIdeLauncher: CoordinatorTestIdeLauncherStub(),
            chromeLauncher: CoordinatorTestChromeLauncherStub(),
            chromeTabStore: ChromeTabStore(directory: chromeTabsDir, fileSystem: fileSystem),
            chromeTabCapture: CoordinatorTestTabCaptureStub(),
            gitRemoteResolver: CoordinatorTestGitRemoteStub(),
            logger: logger,
            recencyFilePath: recencyFilePath,
            focusHistoryFilePath: focusHistoryFilePath,
            fileSystem: fileSystem,
            windowPollTimeout: 0.5,
            windowPollInterval: 0.05
        )
    }

    /// Fast retry interval for tests — avoids multi-second real-timer waits.
    private static let testRetryInterval: TimeInterval = 0.05

    private func makeRetryCoordinator(
        aerospace: CoordinatorTestAeroSpaceStub,
        logger: CoordinatorTestRecordingLogger
    ) -> (SwitcherWorkspaceRetryCoordinator, SwitcherSession) {
        let fileSystem = CoordinatorTestInMemoryFileSystem()
        let manager = makeProjectManager(aerospace: aerospace, logger: logger, fileSystem: fileSystem)
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: "test", name: "Test", path: "/tmp/test", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))
        let session = SwitcherSession(logger: logger)
        session.begin(origin: .hotkey)
        let coordinator = SwitcherWorkspaceRetryCoordinator(
            projectManager: manager,
            session: session,
            retryIntervalSeconds: Self.testRetryInterval
        )
        return (coordinator, session)
    }

    // MARK: - Tests

    func testScheduleRetryTriggersOnRetrySucceededWhenWorkspaceStateSucceeds() {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()
        aerospace.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true)
        ])

        let (coordinator, _) = makeRetryCoordinator(aerospace: aerospace, logger: logger)

        let succeededExpectation = expectation(description: "onRetrySucceeded called")
        coordinator.onRetrySucceeded = { state in
            XCTAssertEqual(state.activeProjectId, "test")
            XCTAssertTrue(state.openProjectIds.contains("test"))
            succeededExpectation.fulfill()
        }
        coordinator.onRetryExhausted = { _ in
            XCTFail("onRetryExhausted should not be called when workspace state succeeds")
        }

        coordinator.scheduleRetry()

        waitForExpectations(timeout: 2.0)
    }

    func testCancelRetryPreventsCallbacks() {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()
        aerospace.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true)
        ])

        let (coordinator, _) = makeRetryCoordinator(aerospace: aerospace, logger: logger)

        coordinator.onRetrySucceeded = { _ in
            XCTFail("onRetrySucceeded should not be called after cancelRetry")
        }
        coordinator.onRetryExhausted = { _ in
            XCTFail("onRetryExhausted should not be called after cancelRetry")
        }

        coordinator.scheduleRetry()
        coordinator.cancelRetry()

        // Wait long enough that the timer would have fired if not cancelled.
        let noCallbackExpectation = expectation(description: "no callbacks fire")
        noCallbackExpectation.isInverted = true
        waitForExpectations(timeout: 0.5)
    }

    func testRetryExhaustedAfterMaxAttempts() {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()
        // Always fail workspace state queries so retries accumulate.
        aerospace.workspacesWithFocusResult = .failure(ApCoreError(message: "circuit breaker open"))

        let (coordinator, _) = makeRetryCoordinator(aerospace: aerospace, logger: logger)

        let exhaustedExpectation = expectation(description: "onRetryExhausted called")
        coordinator.onRetrySucceeded = { _ in
            XCTFail("onRetrySucceeded should not be called when all retries fail")
        }
        coordinator.onRetryExhausted = { error in
            if case .aeroSpaceError(let detail) = error {
                XCTAssertTrue(detail.contains("circuit breaker open"))
            } else {
                XCTFail("Expected aeroSpaceError, got \(error)")
            }
            exhaustedExpectation.fulfill()
        }

        coordinator.scheduleRetry()

        // maxAttempts=5, interval=0.05s — completes in ~0.25s.
        waitForExpectations(timeout: 2.0)

        // Verify log entries confirm exhaustion.
        let exhaustedLogs = logger.entriesSnapshot().filter { $0.event == "switcher.workspace_retry.exhausted" }
        XCTAssertEqual(exhaustedLogs.count, 1)
    }

    func testStaleSessionTimerIsIgnored() {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()
        aerospace.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true)
        ])

        let (coordinator, session) = makeRetryCoordinator(aerospace: aerospace, logger: logger)

        coordinator.onRetrySucceeded = { _ in
            XCTFail("onRetrySucceeded should not fire for a stale session timer")
        }
        coordinator.onRetryExhausted = { _ in
            XCTFail("onRetryExhausted should not fire for a stale session timer")
        }

        coordinator.scheduleRetry()

        // Simulate session change: end the current session and begin a new one.
        // This changes session.sessionId, making the timer's captured sessionId stale.
        session.end(reason: .toggle)
        session.begin(origin: .hotkey)

        // Wait long enough for the timer tick to fire and be rejected.
        let noCallbackExpectation = expectation(description: "stale timer callbacks ignored")
        noCallbackExpectation.isInverted = true
        waitForExpectations(timeout: 0.5)
    }

    func testScheduleRetryResetsCountOnReSchedule() {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()

        // First: fail, then switch to success after a short delay.
        aerospace.workspacesWithFocusResult = .failure(ApCoreError(message: "transient"))

        let (coordinator, _) = makeRetryCoordinator(aerospace: aerospace, logger: logger)

        // Schedule and let one failure tick occur, then reschedule with success.
        coordinator.scheduleRetry()

        // After 0.15s (a few ticks at 0.05s), change the stub to succeed and reschedule.
        let rescheduledExpectation = expectation(description: "rescheduled retry succeeds")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            aerospace.workspacesWithFocusResult = .success([
                ApWorkspaceSummary(workspace: "ap-test", isFocused: true)
            ])
            coordinator.onRetrySucceeded = { state in
                XCTAssertEqual(state.activeProjectId, "test")
                rescheduledExpectation.fulfill()
            }
            coordinator.scheduleRetry()
        }

        waitForExpectations(timeout: 2.0)
    }
}

// MARK: - SwitcherOperationCoordinator Tests

@MainActor
final class SwitcherOperationCoordinatorTests: XCTestCase {

    // MARK: - Helpers

    private func makeProjectManager(
        aerospace: CoordinatorTestAeroSpaceStub,
        logger: CoordinatorTestRecordingLogger,
        fileSystem: CoordinatorTestInMemoryFileSystem = CoordinatorTestInMemoryFileSystem()
    ) -> ProjectManager {
        let recencyFilePath = URL(fileURLWithPath: "/recency.json", isDirectory: false)
        let focusHistoryFilePath = URL(fileURLWithPath: "/focus-history.json", isDirectory: false)
        let chromeTabsDir = URL(fileURLWithPath: "/chrome-tabs", isDirectory: true)

        return ProjectManager(
            aerospace: aerospace,
            ideLauncher: CoordinatorTestIdeLauncherStub(),
            agentLayerIdeLauncher: CoordinatorTestIdeLauncherStub(),
            chromeLauncher: CoordinatorTestChromeLauncherStub(),
            chromeTabStore: ChromeTabStore(directory: chromeTabsDir, fileSystem: fileSystem),
            chromeTabCapture: CoordinatorTestTabCaptureStub(),
            gitRemoteResolver: CoordinatorTestGitRemoteStub(),
            logger: logger,
            recencyFilePath: recencyFilePath,
            focusHistoryFilePath: focusHistoryFilePath,
            fileSystem: fileSystem,
            windowPollTimeout: 0.5,
            windowPollInterval: 0.05
        )
    }

    private func makeOperationCoordinator(
        aerospace: CoordinatorTestAeroSpaceStub,
        logger: CoordinatorTestRecordingLogger
    ) -> (SwitcherOperationCoordinator, ProjectManager) {
        let fileSystem = CoordinatorTestInMemoryFileSystem()
        let manager = makeProjectManager(aerospace: aerospace, logger: logger, fileSystem: fileSystem)
        let session = SwitcherSession(logger: logger)
        session.begin(origin: .hotkey)
        let coordinator = SwitcherOperationCoordinator(projectManager: manager, session: session)
        return (coordinator, manager)
    }

    // MARK: - handleProjectSelection

    func testHandleProjectSelectionSetsIsActivatingThenResetsOnSuccess() async {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()

        let projectId = "alpha"
        let workspace = "ap-\(projectId)"
        let chromeWindow = ApWindow(
            windowId: 100,
            appBundleId: ApChromeLauncher.bundleId,
            workspace: workspace,
            windowTitle: "AP:\(projectId) - Chrome"
        )
        let ideWindow = ApWindow(
            windowId: 101,
            appBundleId: ApVSCodeLauncher.bundleId,
            workspace: workspace,
            windowTitle: "AP:\(projectId) - VS Code"
        )

        aerospace.windowsByBundleId[ApChromeLauncher.bundleId] = [chromeWindow]
        aerospace.windowsByBundleId[ApVSCodeLauncher.bundleId] = [ideWindow]
        aerospace.windowsByWorkspace[workspace] = [chromeWindow, ideWindow]
        aerospace.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: workspace, isFocused: true)
        ])
        aerospace.focusedWindowResult = .success(ideWindow)
        aerospace.focusWindowSuccessIds = [ideWindow.windowId]
        aerospace.allWindows = [chromeWindow, ideWindow]

        let (coordinator, manager) = makeOperationCoordinator(aerospace: aerospace, logger: logger)
        let project = ProjectConfig(id: projectId, name: "Alpha", path: "/tmp/alpha", color: "blue", useAgentLayer: false)
        manager.loadTestConfig(Config(projects: [project], chrome: ChromeConfig()))

        var controlsEnabledHistory: [Bool] = []
        coordinator.onSetControlsEnabled = { enabled in
            controlsEnabledHistory.append(enabled)
        }

        var dismissReason: SwitcherDismissReason?
        coordinator.onDismiss = { reason in
            dismissReason = reason
        }

        var focusedIdeWindowId: Int?
        coordinator.onFocusIdeWindow = { windowId in
            focusedIdeWindowId = windowId
        }

        let capturedFocus = CapturedFocus(windowId: 77, appBundleId: "com.apple.Terminal", workspace: "main")

        // isActivating should be false before selection.
        XCTAssertFalse(coordinator.isActivating)

        let completionExpectation = expectation(description: "project selection completes")
        logger.onLog = { entry in
            if entry.event == "project_manager.select.completed" {
                completionExpectation.fulfill()
            }
        }

        coordinator.handleProjectSelection(project, capturedFocus: capturedFocus)

        // isActivating should be true immediately after calling handleProjectSelection.
        XCTAssertTrue(coordinator.isActivating)

        await fulfillment(of: [completionExpectation], timeout: 5.0)

        // After completion, isActivating should be reset to false.
        XCTAssertFalse(coordinator.isActivating)

        // Controls should have been disabled then re-enabled.
        XCTAssertEqual(controlsEnabledHistory, [false, true])

        // Dismiss should have been called with .projectSelected.
        XCTAssertEqual(dismissReason, .projectSelected)

        // IDE window should have been focused.
        XCTAssertEqual(focusedIdeWindowId, ideWindow.windowId)
    }

    func testHandleProjectSelectionReportsErrorAndCallsOnOperationFailedOnFailure() async {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()

        let (coordinator, manager) = makeOperationCoordinator(aerospace: aerospace, logger: logger)
        let project = ProjectConfig(id: "bad", name: "Bad Project", path: "/tmp/bad", color: "red", useAgentLayer: false)
        // Load config WITHOUT the project to trigger projectNotFound.
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: "other", name: "Other", path: "/tmp/other", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        var statusMessages: [(String, StatusLevel)] = []
        coordinator.onSetStatus = { message, level in
            statusMessages.append((message, level))
        }

        var operationFailedContext: ErrorContext?
        coordinator.onOperationFailed = { context in
            operationFailedContext = context
        }

        var searchFieldFocusRestored = false
        coordinator.onRestoreSearchFieldFocus = {
            searchFieldFocusRestored = true
        }

        var dismissCalled = false
        coordinator.onDismiss = { _ in
            dismissCalled = true
        }

        let failureExpectation = expectation(description: "project selection fails")
        logger.onLog = { entry in
            if entry.event == "switcher.project.activation_failed" {
                failureExpectation.fulfill()
            }
        }

        coordinator.handleProjectSelection(project, capturedFocus: nil)

        await fulfillment(of: [failureExpectation], timeout: 5.0)

        // isActivating should be reset after failure.
        XCTAssertFalse(coordinator.isActivating)

        // onOperationFailed should have been called.
        XCTAssertNotNil(operationFailedContext)
        XCTAssertEqual(operationFailedContext?.trigger, "activation")
        XCTAssertEqual(operationFailedContext?.category, .command)

        // Status should show an error.
        let errorStatuses = statusMessages.filter { $0.1 == .error }
        XCTAssertFalse(errorStatuses.isEmpty, "Expected at least one error status message")

        // Search field focus should be restored.
        XCTAssertTrue(searchFieldFocusRestored)

        // Dismiss should NOT have been called on failure.
        XCTAssertFalse(dismissCalled)
    }

    // MARK: - handleExitToNonProject

    func testHandleExitToNonProjectGuardsAgainstDoubleFire() async {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()

        let projectId = "test"
        let nonProjectWindow = ApWindow(
            windowId: 42,
            appBundleId: "com.apple.Terminal",
            workspace: "main",
            windowTitle: "Terminal"
        )
        aerospace.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-\(projectId)", isFocused: true)
        ])
        aerospace.allWindows = [nonProjectWindow]
        aerospace.focusWindowSuccessIds = [nonProjectWindow.windowId]
        aerospace.focusedWindowResult = .failure(ApCoreError(message: "no focus"))

        let (coordinator, manager) = makeOperationCoordinator(aerospace: aerospace, logger: logger)
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Test", path: "/tmp/test", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))
        manager.pushFocusForTest(CapturedFocus(
            windowId: nonProjectWindow.windowId,
            appBundleId: nonProjectWindow.appBundleId,
            workspace: nonProjectWindow.workspace
        ))

        var dismissCallCount = 0
        coordinator.onDismiss = { _ in
            dismissCallCount += 1
        }

        let exitExpectation = expectation(description: "exit succeeds")
        logger.onLog = { entry in
            if entry.event == "switcher.exit_to_previous.succeeded" {
                exitExpectation.fulfill()
            }
        }

        // Fire twice before the first async operation completes.
        coordinator.handleExitToNonProject(fromShortcut: false, hasBackActionRow: true)
        coordinator.handleExitToNonProject(fromShortcut: false, hasBackActionRow: true)

        await fulfillment(of: [exitExpectation], timeout: 3.0)

        // Guard should prevent second invocation from running.
        XCTAssertEqual(dismissCallCount, 1, "handleExitToNonProject should guard against double-fire")
    }

    func testHandleExitToNonProjectCallsOnDismissOnSuccess() async {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()

        let projectId = "test"
        let nonProjectWindow = ApWindow(
            windowId: 42,
            appBundleId: "com.apple.Terminal",
            workspace: "main",
            windowTitle: "Terminal"
        )
        aerospace.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-\(projectId)", isFocused: true)
        ])
        aerospace.allWindows = [nonProjectWindow]
        aerospace.focusWindowSuccessIds = [nonProjectWindow.windowId]
        aerospace.focusedWindowResult = .failure(ApCoreError(message: "no focus"))

        let (coordinator, manager) = makeOperationCoordinator(aerospace: aerospace, logger: logger)
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Test", path: "/tmp/test", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))
        manager.pushFocusForTest(CapturedFocus(
            windowId: nonProjectWindow.windowId,
            appBundleId: nonProjectWindow.appBundleId,
            workspace: nonProjectWindow.workspace
        ))

        var dismissReason: SwitcherDismissReason?
        coordinator.onDismiss = { reason in
            dismissReason = reason
        }

        var controlsEnabledHistory: [Bool] = []
        coordinator.onSetControlsEnabled = { enabled in
            controlsEnabledHistory.append(enabled)
        }

        let exitExpectation = expectation(description: "exit to non-project succeeds")
        logger.onLog = { entry in
            if entry.event == "switcher.exit_to_previous.succeeded" {
                exitExpectation.fulfill()
            }
        }

        coordinator.handleExitToNonProject(fromShortcut: false, hasBackActionRow: true)

        await fulfillment(of: [exitExpectation], timeout: 3.0)

        XCTAssertEqual(dismissReason, .exitedToNonProject)
        XCTAssertEqual(controlsEnabledHistory, [false, true])
        XCTAssertFalse(coordinator.isExitingToNonProject, "Guard should be reset after completion")
    }

    func testHandleExitToNonProjectBeepsWhenNoBackActionRowFromShortcut() {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()
        let (coordinator, _) = makeOperationCoordinator(aerospace: aerospace, logger: logger)

        var dismissCalled = false
        coordinator.onDismiss = { _ in
            dismissCalled = true
        }

        // No back action row and from shortcut: should beep and return immediately.
        coordinator.handleExitToNonProject(fromShortcut: true, hasBackActionRow: false)

        XCTAssertFalse(dismissCalled)
        XCTAssertFalse(coordinator.isExitingToNonProject, "Guard should not be set when hasBackActionRow is false")
    }

    // MARK: - handleRecoverProjectFromShortcut

    func testHandleRecoverProjectFromShortcutWithNilFocusSetsStatusAndBeeps() {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()
        let (coordinator, _) = makeOperationCoordinator(aerospace: aerospace, logger: logger)

        var statusMessages: [(String, StatusLevel)] = []
        coordinator.onSetStatus = { message, level in
            statusMessages.append((message, level))
        }

        coordinator.handleRecoverProjectFromShortcut(capturedFocus: nil)

        // Should set warning status.
        let warningStatuses = statusMessages.filter { $0.1 == .warning }
        XCTAssertFalse(warningStatuses.isEmpty, "Expected a warning status when capturedFocus is nil")
        XCTAssertTrue(warningStatuses.first?.0.contains("unavailable") == true)

        // Should log the skip event.
        let skipLogs = logger.entriesSnapshot().filter { $0.event == "switcher.recover_project.skipped" }
        XCTAssertEqual(skipLogs.count, 1)
    }

    func testHandleRecoverProjectFromShortcutWithoutCallbackSetsStatusAndBeeps() {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()
        let (coordinator, _) = makeOperationCoordinator(aerospace: aerospace, logger: logger)

        let focus = CapturedFocus(windowId: 7, appBundleId: "com.apple.Terminal", workspace: "ap-test")
        // Do NOT set onRecoverProjectRequested — it remains nil.

        var statusMessages: [(String, StatusLevel)] = []
        coordinator.onSetStatus = { message, level in
            statusMessages.append((message, level))
        }

        coordinator.handleRecoverProjectFromShortcut(capturedFocus: focus)

        let warningStatuses = statusMessages.filter { $0.1 == .warning }
        XCTAssertFalse(warningStatuses.isEmpty)
        XCTAssertTrue(warningStatuses.first?.0.contains("not available") == true)

        XCTAssertFalse(coordinator.isRecoveringProject, "Guard should not be set when callback is not wired")
    }

    func testHandleRecoverProjectFromShortcutGuardsAgainstConcurrentRecovery() {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()
        let (coordinator, _) = makeOperationCoordinator(aerospace: aerospace, logger: logger)

        let focus = CapturedFocus(windowId: 7, appBundleId: "com.apple.Terminal", workspace: "ap-test")

        var invocationCount = 0
        var pendingCompletion: ((Result<RecoveryResult, ApCoreError>) -> Void)?
        coordinator.onRecoverProjectRequested = { _, completion in
            invocationCount += 1
            pendingCompletion = completion
        }

        coordinator.handleRecoverProjectFromShortcut(capturedFocus: focus)
        coordinator.handleRecoverProjectFromShortcut(capturedFocus: focus)

        XCTAssertEqual(invocationCount, 1, "Recovery should be single-flight")
        XCTAssertTrue(coordinator.isRecoveringProject)

        // Complete recovery.
        pendingCompletion?(.success(RecoveryResult(windowsProcessed: 1, windowsRecovered: 1, errors: [])))
    }

    // MARK: - resetGuards

    func testResetGuardsClearsAllGuardFlags() {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()
        let (coordinator, _) = makeOperationCoordinator(aerospace: aerospace, logger: logger)

        // Manually verify the guards are initially false.
        XCTAssertFalse(coordinator.isActivating)
        XCTAssertFalse(coordinator.isExitingToNonProject)
        XCTAssertFalse(coordinator.isRecoveringProject)

        // Set up the recover callback so we can trigger the guard.
        let focus = CapturedFocus(windowId: 7, appBundleId: "com.apple.Terminal", workspace: "ap-test")
        coordinator.onRecoverProjectRequested = { _, _ in
            // Don't complete — leave the guard set.
        }

        // Trigger isRecoveringProject.
        coordinator.handleRecoverProjectFromShortcut(capturedFocus: focus)
        XCTAssertTrue(coordinator.isRecoveringProject)

        // resetGuards should clear all flags.
        coordinator.resetGuards()

        XCTAssertFalse(coordinator.isActivating)
        XCTAssertFalse(coordinator.isExitingToNonProject)
        XCTAssertFalse(coordinator.isRecoveringProject)
    }

    func testHandleProjectSelectionWithWarnings() async {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()

        let projectId = "alpha"
        let workspace = "ap-\(projectId)"
        let chromeWindow = ApWindow(
            windowId: 100,
            appBundleId: ApChromeLauncher.bundleId,
            workspace: workspace,
            windowTitle: "AP:\(projectId) - Chrome"
        )
        let ideWindow = ApWindow(
            windowId: 101,
            appBundleId: ApVSCodeLauncher.bundleId,
            workspace: workspace,
            windowTitle: "AP:\(projectId) - VS Code"
        )

        aerospace.windowsByBundleId[ApChromeLauncher.bundleId] = [chromeWindow]
        aerospace.windowsByBundleId[ApVSCodeLauncher.bundleId] = [ideWindow]
        aerospace.windowsByWorkspace[workspace] = [chromeWindow, ideWindow]
        aerospace.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: workspace, isFocused: true)
        ])
        aerospace.focusedWindowResult = .success(ideWindow)
        aerospace.focusWindowSuccessIds = [ideWindow.windowId]
        aerospace.allWindows = [chromeWindow, ideWindow]

        let (coordinator, manager) = makeOperationCoordinator(aerospace: aerospace, logger: logger)
        let project = ProjectConfig(id: projectId, name: "Alpha", path: "/tmp/alpha", color: "blue", useAgentLayer: false)
        manager.loadTestConfig(Config(projects: [project], chrome: ChromeConfig()))

        let completionExpectation = expectation(description: "project selection completes")
        logger.onLog = { entry in
            if entry.event == "project_manager.select.completed" {
                completionExpectation.fulfill()
            }
        }

        // Selection without capturedFocus should log a warning.
        coordinator.handleProjectSelection(project, capturedFocus: nil)

        await fulfillment(of: [completionExpectation], timeout: 5.0)

        let warnEntries = logger.entriesSnapshot().filter { $0.event == "switcher.project.selection_without_focus" }
        XCTAssertEqual(warnEntries.count, 1, "Expected warn log for selection without captured focus")
    }

    func testHandleExitToNonProjectReportsErrorOnFailure() async {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()

        // No projects configured and no focus stack means exitToNonProjectWindow will fail.
        aerospace.workspacesWithFocusResult = .success([])
        aerospace.focusedWindowResult = .failure(ApCoreError(message: "no focus"))
        aerospace.allWindows = []

        let (coordinator, manager) = makeOperationCoordinator(aerospace: aerospace, logger: logger)
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: "test", name: "Test", path: "/tmp/test", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        var operationFailedContext: ErrorContext?
        coordinator.onOperationFailed = { context in
            operationFailedContext = context
        }

        var statusMessages: [(String, StatusLevel)] = []
        coordinator.onSetStatus = { message, level in
            statusMessages.append((message, level))
        }

        var refreshCalled = false
        coordinator.onRefreshWorkspaceAndFilter = { _, _ in
            refreshCalled = true
        }

        let failureExpectation = expectation(description: "exit failure reported")
        logger.onLog = { entry in
            if entry.event == "switcher.exit_to_previous.failed" {
                failureExpectation.fulfill()
            }
        }

        coordinator.handleExitToNonProject(fromShortcut: false, hasBackActionRow: true)

        await fulfillment(of: [failureExpectation], timeout: 3.0)

        XCTAssertNotNil(operationFailedContext)
        XCTAssertEqual(operationFailedContext?.trigger, "exitToPrevious")
        XCTAssertFalse(coordinator.isExitingToNonProject, "Guard should be reset after failure")

        let errorStatuses = statusMessages.filter { $0.1 == .error }
        XCTAssertFalse(errorStatuses.isEmpty)

        XCTAssertTrue(refreshCalled, "Workspace should be refreshed on exit failure")
    }
}

// MARK: - Test Infrastructure (duplicated from SwitcherFocusFlowTests, as those are private)

struct CoordinatorTestLogEntryRecord: Equatable {
    let event: String
    let level: LogLevel
    let message: String?
    let context: [String: String]?
}

final class CoordinatorTestRecordingLogger: AgentPanelLogging {
    private let queue = DispatchQueue(label: "com.agentpanel.tests.coordinator.logger")
    private var entries: [CoordinatorTestLogEntryRecord] = []
    var onLog: ((CoordinatorTestLogEntryRecord) -> Void)?

    func log(event: String, level: LogLevel, message: String?, context: [String: String]?) -> Result<Void, LogWriteError> {
        let entry = CoordinatorTestLogEntryRecord(event: event, level: level, message: message, context: context)
        queue.sync {
            entries.append(entry)
        }
        onLog?(entry)
        return .success(())
    }

    func entriesSnapshot() -> [CoordinatorTestLogEntryRecord] {
        queue.sync { entries }
    }
}

final class CoordinatorTestAeroSpaceStub: AeroSpaceProviding {
    var focusedWindowResult: Result<ApWindow, ApCoreError> = .failure(ApCoreError(message: "stub"))
    var focusWindowSuccessIds: Set<Int> = []
    var workspacesWithFocusResult: Result<[ApWorkspaceSummary], ApCoreError> = .success([])
    var focusWorkspaceResult: Result<Void, ApCoreError> = .success(())
    var windowsByBundleId: [String: [ApWindow]] = [:]
    var windowsByWorkspace: [String: [ApWindow]] = [:]
    var allWindows: [ApWindow] = []
    private(set) var focusedWindowIds: [Int] = []
    private(set) var focusedWorkspaces: [String] = []

    func getWorkspaces() -> Result<[String], ApCoreError> { .success([]) }
    func workspaceExists(_ name: String) -> Result<Bool, ApCoreError> { .success(false) }
    func listWorkspacesFocused() -> Result<[String], ApCoreError> { .success([]) }
    func listWorkspacesWithFocus() -> Result<[ApWorkspaceSummary], ApCoreError> { workspacesWithFocusResult }
    func createWorkspace(_ name: String) -> Result<Void, ApCoreError> { .success(()) }
    func closeWorkspace(name: String) -> Result<Void, ApCoreError> { .success(()) }

    func listWindowsForApp(bundleId: String) -> Result<[ApWindow], ApCoreError> {
        .success(windowsByBundleId[bundleId] ?? [])
    }

    func listWindowsWorkspace(workspace: String) -> Result<[ApWindow], ApCoreError> {
        .success(windowsByWorkspace[workspace] ?? [])
    }

    func listAllWindows() -> Result<[ApWindow], ApCoreError> {
        if !allWindows.isEmpty {
            return .success(allWindows)
        }
        var windows: [ApWindow] = []
        var seen: Set<Int> = []
        for list in windowsByWorkspace.values {
            for window in list where !seen.contains(window.windowId) {
                seen.insert(window.windowId)
                windows.append(window)
            }
        }
        for list in windowsByBundleId.values {
            for window in list where !seen.contains(window.windowId) {
                seen.insert(window.windowId)
                windows.append(window)
            }
        }
        return .success(windows)
    }

    func focusedWindow() -> Result<ApWindow, ApCoreError> { focusedWindowResult }

    func focusWindow(windowId: Int) -> Result<Void, ApCoreError> {
        focusedWindowIds.append(windowId)
        guard focusWindowSuccessIds.contains(windowId) else {
            return .failure(ApCoreError(message: "window not found"))
        }
        if case .success(let focused) = focusedWindowResult, focused.windowId == windowId {
            return .success(())
        }
        if let match = windowById(windowId) {
            focusedWindowResult = .success(match)
        } else {
            focusedWindowResult = .success(ApWindow(
                windowId: windowId,
                appBundleId: "com.stub.app",
                workspace: "main",
                windowTitle: "Stub"
            ))
        }
        return .success(())
    }

    func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool) -> Result<Void, ApCoreError> {
        updateWindowWorkspace(windowId: windowId, workspace: workspace)
        return .success(())
    }

    func focusWorkspace(name: String) -> Result<Void, ApCoreError> {
        focusedWorkspaces.append(name)
        return focusWorkspaceResult
    }

    private func windowById(_ windowId: Int) -> ApWindow? {
        if !allWindows.isEmpty {
            return allWindows.first(where: { $0.windowId == windowId })
        }
        for list in windowsByWorkspace.values {
            if let match = list.first(where: { $0.windowId == windowId }) {
                return match
            }
        }
        for list in windowsByBundleId.values {
            if let match = list.first(where: { $0.windowId == windowId }) {
                return match
            }
        }
        return nil
    }

    private func updateWindowWorkspace(windowId: Int, workspace: String) {
        if !allWindows.isEmpty {
            for (index, window) in allWindows.enumerated() where window.windowId == windowId {
                allWindows[index] = ApWindow(
                    windowId: window.windowId,
                    appBundleId: window.appBundleId,
                    workspace: workspace,
                    windowTitle: window.windowTitle
                )
            }
            return
        }

        for (bundleId, list) in windowsByBundleId {
            for (index, window) in list.enumerated() where window.windowId == windowId {
                var updated = list
                updated[index] = ApWindow(
                    windowId: window.windowId,
                    appBundleId: window.appBundleId,
                    workspace: workspace,
                    windowTitle: window.windowTitle
                )
                windowsByBundleId[bundleId] = updated
            }
        }

        for (workspaceName, list) in windowsByWorkspace {
            if let index = list.firstIndex(where: { $0.windowId == windowId }) {
                var updated = list
                let window = updated.remove(at: index)
                windowsByWorkspace[workspaceName] = updated
                var targetList = windowsByWorkspace[workspace] ?? []
                targetList.append(ApWindow(
                    windowId: window.windowId,
                    appBundleId: window.appBundleId,
                    workspace: workspace,
                    windowTitle: window.windowTitle
                ))
                windowsByWorkspace[workspace] = targetList
                return
            }
        }
    }
}

private struct CoordinatorTestIdeLauncherStub: IdeLauncherProviding {
    func openNewWindow(identifier: String, projectPath: String?, remoteAuthority: String?, color: String?) -> Result<Void, ApCoreError> {
        .success(())
    }
}

private struct CoordinatorTestChromeLauncherStub: ChromeLauncherProviding {
    func openNewWindow(identifier: String, initialURLs: [String]) -> Result<Void, ApCoreError> {
        .success(())
    }
}

private struct CoordinatorTestTabCaptureStub: ChromeTabCapturing {
    func captureTabURLs(windowTitle: String) -> Result<[String], ApCoreError> { .success([]) }
}

private struct CoordinatorTestGitRemoteStub: GitRemoteResolving {
    func resolve(projectPath: String) -> String? { nil }
}

final class CoordinatorTestInMemoryFileSystem: FileSystem {
    private var storage: [URL: Data] = [:]
    private var directories: Set<URL> = []

    func fileExists(at url: URL) -> Bool { storage[url] != nil }
    func directoryExists(at url: URL) -> Bool { directories.contains(url) }
    func isExecutableFile(at url: URL) -> Bool { false }

    func readFile(at url: URL) throws -> Data {
        guard let data = storage[url] else {
            throw NSError(domain: "InMemoryFileSystem", code: 1, userInfo: nil)
        }
        return data
    }

    func createDirectory(at url: URL) throws {
        directories.insert(url)
    }

    func fileSize(at url: URL) throws -> UInt64 {
        guard let data = storage[url] else {
            throw NSError(domain: "InMemoryFileSystem", code: 2, userInfo: nil)
        }
        return UInt64(data.count)
    }

    func removeItem(at url: URL) throws {
        storage.removeValue(forKey: url)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        storage[destinationURL] = storage[sourceURL]
        storage.removeValue(forKey: sourceURL)
    }

    func appendFile(at url: URL, data: Data) throws {
        let existing = storage[url] ?? Data()
        var updated = existing
        updated.append(data)
        storage[url] = updated
    }

    func writeFile(at url: URL, data: Data) throws {
        storage[url] = data
    }
}
