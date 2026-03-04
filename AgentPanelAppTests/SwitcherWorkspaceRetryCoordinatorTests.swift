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

