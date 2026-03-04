import XCTest

@testable import AgentPanel
@testable import AgentPanelAppKit
@testable import AgentPanelCore

@MainActor
final class SwitcherOperationRecoveryGuardTests: XCTestCase {

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

}
