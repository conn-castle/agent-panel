import XCTest

@testable import AgentPanelCore

extension ProjectManagerFocusTests {
    // MARK: - Exit fails when stack empty

    func testExitToNonProjectFailsWhenStackEmpty() {
        let aero = FocusAeroSpaceStub()
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true)
        ])

        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        switch manager.exitToNonProjectWindow() {
        case .success:
            XCTFail("Expected noPreviousWindow failure")
        case .failure(let error):
            XCTAssertEqual(error, .noPreviousWindow)
        }
    }

    // MARK: - Exit restores most recent non-project focus when stack is empty

    func testExitToNonProjectUsesMostRecentNonProjectFocusWhenStackEmpty() {
        let aero = FocusAeroSpaceStub()
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true)
        ])
        aero.focusedWindowResult = .success(
            ApWindow(windowId: 321, appBundleId: "com.apple.Safari", workspace: "main", windowTitle: "Safari")
        )
        aero.focusWindowSuccessIds = [321]
        registerWindow(aero: aero, windowId: 321, appBundleId: "com.apple.Safari", workspace: "main", windowTitle: "Safari")

        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        // Simulate previously observed non-project focus without pushing stack entries.
        XCTAssertEqual(manager.captureCurrentFocus()?.windowId, 321)
        aero.focusedWindowResult = .failure(ApCoreError(message: "no focus"))

        switch manager.exitToNonProjectWindow() {
        case .success:
            XCTAssertTrue(aero.focusedWindowIds.contains(321), "Should restore most recent non-project window")
        case .failure(let error):
            XCTFail("Expected success but got: \(error)")
        }
    }

    func testExitToNonProjectRestoresOlderThanRetryAgeCandidateWhenStillValid() {
        let aero = FocusAeroSpaceStub()
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true)
        ])
        aero.focusWindowSuccessIds = [99]
        registerWindow(aero: aero, windowId: 99, appBundleId: "com.apple.Safari", workspace: "main", windowTitle: "Safari")

        let oldCaptureDate = Date().addingTimeInterval(-11 * 60)
        let oldEntry = FocusHistoryEntry(
            windowId: 99,
            appBundleId: "com.apple.Safari",
            workspace: "main",
            capturedAt: oldCaptureDate
        )
        let manager = makeFocusManager(
            aerospace: aero,
            preloadedFocusHistoryState: FocusHistoryState(
                version: FocusHistoryStore.currentVersion,
                stack: [oldEntry],
                mostRecent: oldEntry
            )
        )
        loadTestConfig(manager: manager)

        switch manager.exitToNonProjectWindow() {
        case .success:
            XCTAssertTrue(aero.focusedWindowIds.contains(99))
        case .failure(let error):
            XCTFail("Expected success but got: \(error)")
        }
    }

    func testExitToNonProjectSkipsAppMismatch() {
        let aero = FocusAeroSpaceStub()
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true)
        ])
        registerWindow(aero: aero, windowId: 99, appBundleId: "com.apple.Terminal", workspace: "main", windowTitle: "Terminal")

        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        let focus = CapturedFocus(windowId: 99, appBundleId: "com.apple.Safari", workspace: "main")
        manager.pushFocusForTest(focus)

        let result = manager.exitToNonProjectWindow()
        if case .success = result {
            XCTFail("Expected noPreviousWindow due to app mismatch")
        }
        if case .failure(let error) = result {
            XCTAssertEqual(error, .noPreviousWindow)
        }
        XCTAssertFalse(aero.focusedWindowIds.contains(99), "Should not focus app-mismatched window")
    }

    // MARK: - Project-to-project switch does not push (via selectProject)

    func testSelectProjectFromProjectWorkspaceDoesNotPush() async {
        let aero = FocusAeroSpaceStub()
        configureForActivation(aero: aero, projectId: "beta")

        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager, projects: [
            testProject(id: "alpha"),
            testProject(id: "beta")
        ])

        // Activate beta with preCapturedFocus from project alpha workspace
        let preFocus = CapturedFocus(windowId: 50, appBundleId: "com.microsoft.VSCode", workspace: "ap-alpha")
        let result = await manager.selectProject(projectId: "beta", preCapturedFocus: preFocus)
        switch result {
        case .failure(let error):
            XCTFail("Expected activation success but got: \(error)")
            return
        case .success:
            break
        }

        // Stack should be empty — project workspace was filtered by real push path
        switch manager.exitToNonProjectWindow() {
        case .success:
            XCTFail("Expected noPreviousWindow (stack should be empty)")
        case .failure(let error):
            XCTAssertEqual(error, .noPreviousWindow)
        }
    }

    // MARK: - Z → A → B → exit → Z (exit project space semantic, via selectProject)

    func testSelectProjectFromProjectWorkspaceThenExitRestoresZ() async {
        let aero = FocusAeroSpaceStub()
        configureForActivation(aero: aero, projectId: "beta")
        aero.focusWindowSuccessIds.insert(99) // for exit restoration
        registerWindow(aero: aero, windowId: 99, appBundleId: "com.apple.Safari", workspace: "main", windowTitle: "Safari")

        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager, projects: [
            testProject(id: "alpha"),
            testProject(id: "beta")
        ])

        // Push Z (non-project window) — known baseline before entering project space
        let focusZ = CapturedFocus(windowId: 99, appBundleId: "com.apple.Safari", workspace: "main")
        manager.pushFocusForTest(focusZ)

        // Activate beta from project alpha workspace — ap-alpha preCapturedFocus
        // should be filtered by selectProject's real push logic
        let preFocus = CapturedFocus(windowId: 50, appBundleId: "com.microsoft.VSCode", workspace: "ap-alpha")
        let result = await manager.selectProject(projectId: "beta", preCapturedFocus: preFocus)
        switch result {
        case .failure(let error):
            XCTFail("Expected activation success but got: \(error)")
            return
        case .success:
            break
        }

        // Exit from project B → should restore Z (window 99), not A (window 50)
        switch manager.exitToNonProjectWindow() {
        case .success:
            XCTAssertTrue(aero.focusedWindowIds.contains(99), "Should restore to Z (window 99)")
            XCTAssertFalse(aero.focusedWindowIds.contains(50), "Should not have tried to focus project A window")
        case .failure(let error):
            XCTFail("Expected success but got: \(error)")
        }
    }

    // MARK: - Multiple non-project entries across entry/exit cycles

    func testMultipleNonProjectEntriesThenReenter() {
        let aero = FocusAeroSpaceStub()
        aero.focusWindowSuccessIds = [99, 88]
        registerWindow(aero: aero, windowId: 99, appBundleId: "com.apple.Safari", workspace: "main", windowTitle: "Safari")
        registerWindow(aero: aero, windowId: 88, appBundleId: "com.apple.Terminal", workspace: "main", windowTitle: "Terminal")

        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        // Cycle 1: push Z, close (pop Z)
        let focusZ = CapturedFocus(windowId: 99, appBundleId: "com.apple.Safari", workspace: "main")
        manager.pushFocusForTest(focusZ)
        _ = manager.closeProject(projectId: "test")
        XCTAssertTrue(aero.focusedWindowIds.contains(99))

        // Cycle 2: push Y, close (pop Y)
        aero.focusedWindowIds = []
        let focusY = CapturedFocus(windowId: 88, appBundleId: "com.apple.Terminal", workspace: "main")
        manager.pushFocusForTest(focusY)
        _ = manager.closeProject(projectId: "test")
        XCTAssertTrue(aero.focusedWindowIds.contains(88))
    }

    // MARK: - Close → reopen → exit (the key bug scenario)

    func testCloseThenReopenThenExitStillWorks() {
        let aero = FocusAeroSpaceStub()
        aero.focusWindowSuccessIds = [99, 88]
        registerWindow(aero: aero, windowId: 99, appBundleId: "com.apple.Safari", workspace: "main", windowTitle: "Safari")
        registerWindow(aero: aero, windowId: 88, appBundleId: "com.apple.Terminal", workspace: "main", windowTitle: "Terminal")

        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        // First cycle: push X, close (pop X)
        let focusX = CapturedFocus(windowId: 99, appBundleId: "com.apple.Safari", workspace: "main")
        manager.pushFocusForTest(focusX)
        _ = manager.closeProject(projectId: "test")

        // Second cycle: push Y, exit
        aero.focusedWindowIds = []
        let focusY = CapturedFocus(windowId: 88, appBundleId: "com.apple.Terminal", workspace: "main")
        manager.pushFocusForTest(focusY)

        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true)
        ])
        switch manager.exitToNonProjectWindow() {
        case .success:
            XCTAssertTrue(aero.focusedWindowIds.contains(88))
        case .failure(let error):
            XCTFail("Expected success but got: \(error)")
        }
    }

    // MARK: - Nil pre-captured focus (best-effort restore, via selectProject)

    func testSelectProjectWithNilPreCapturedFocusSucceeds() async {
        let aero = FocusAeroSpaceStub()
        configureForActivation(aero: aero, projectId: "test")

        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        let result = await manager.selectProject(projectId: "test", preCapturedFocus: nil)
        switch result {
        case .success:
            break
        case .failure(let error):
            XCTFail("Expected activation success with nil preCapturedFocus but got: \(error)")
        }

        // Exit should fail with noPreviousWindow because no focus was pushed
        switch manager.exitToNonProjectWindow() {
        case .success:
            XCTFail("Expected noPreviousWindow (no focus was pushed for nil preCapturedFocus)")
        case .failure(let error):
            XCTAssertEqual(error, .noPreviousWindow)
        }
    }

    func testSelectProjectWithNilPreCapturedFocusUsesExistingHistoryForExit() async {
        let aero = FocusAeroSpaceStub()
        configureForActivation(aero: aero, projectId: "test")
        aero.focusWindowSuccessIds.insert(99)
        registerWindow(
            aero: aero,
            windowId: 99,
            appBundleId: "com.apple.Safari",
            workspace: "main",
            windowTitle: "Safari"
        )

        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        manager.pushFocusForTest(CapturedFocus(
            windowId: 99,
            appBundleId: "com.apple.Safari",
            workspace: "main"
        ))

        let result = await manager.selectProject(projectId: "test", preCapturedFocus: nil)
        switch result {
        case .success:
            break
        case .failure(let error):
            XCTFail("Expected activation success with nil preCapturedFocus but got: \(error)")
        }

        switch manager.exitToNonProjectWindow() {
        case .failure(let error):
            XCTFail("Expected exit to restore existing focus history, got: \(error)")
        case .success:
            XCTAssertTrue(aero.focusedWindowIds.contains(99))
        }
    }

}
