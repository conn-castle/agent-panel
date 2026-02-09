import XCTest
@testable import AgentPanelCore

// MARK: - Focus Stack Integration Tests

final class ProjectManagerFocusTests: XCTestCase {

    // MARK: - Close restores focus from stack

    func testCloseProjectRestoresFocusFromStack() {
        let aero = FocusAeroSpaceStub()
        aero.focusedWindowResult = .success(ApWindow(
            windowId: 99, appBundleId: "com.apple.Safari", workspace: "main", windowTitle: "Safari"
        ))
        aero.focusWindowSuccessIds = [99]

        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        let captured = manager.captureCurrentFocus()!
        XCTAssertEqual(captured.windowId, 99)
        XCTAssertEqual(captured.workspace, "main")

        manager.pushFocusForTest(captured)

        switch manager.closeProject(projectId: "test") {
        case .success:
            break
        case .failure(let error):
            XCTFail("Expected success but got: \(error)")
        }

        XCTAssertTrue(aero.focusedWindowIds.contains(99), "Should have focused window 99")
    }

    // MARK: - Close with stale focus exhausts gracefully

    func testCloseProjectSkipsStaleFocus() {
        let aero = FocusAeroSpaceStub()
        aero.focusWindowSuccessIds = []

        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        let staleFocus = CapturedFocus(windowId: 42, appBundleId: "com.gone.App", workspace: "main")
        manager.pushFocusForTest(staleFocus)

        switch manager.closeProject(projectId: "test") {
        case .success:
            break
        case .failure(let error):
            XCTFail("Expected success but got: \(error)")
        }
    }

    // MARK: - Exit restores focus from stack

    func testExitToNonProjectRestoresFocusFromStack() {
        let aero = FocusAeroSpaceStub()
        aero.focusWindowSuccessIds = [99]
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true)
        ])

        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        let focus = CapturedFocus(windowId: 99, appBundleId: "com.apple.Safari", workspace: "main")
        manager.pushFocusForTest(focus)

        switch manager.exitToNonProjectWindow() {
        case .success:
            XCTAssertTrue(aero.focusedWindowIds.contains(99))
        case .failure(let error):
            XCTFail("Expected success but got: \(error)")
        }
    }

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

    // MARK: - Activation failure does not rollback push (via selectProject)

    func testActivationFailureDoesNotRollbackPush() async {
        let aero = FocusAeroSpaceStub()
        // Chrome exists but VS Code does not — IDE launch will fail
        let chromeWindow = ApWindow(
            windowId: 100, appBundleId: "com.google.Chrome",
            workspace: "ap-test", windowTitle: "AP:test - Chrome"
        )
        aero.windowsByBundleId["com.google.Chrome"] = [chromeWindow]
        aero.focusWindowSuccessIds = [99]

        let failingIde = FocusIdeLauncherStub()
        failingIde.result = .failure(ApCoreError(category: .command, message: "IDE launch failed"))

        let manager = makeFocusManager(aerospace: aero, ideLauncher: failingIde)
        loadTestConfig(manager: manager)

        // selectProject pushes preCapturedFocus BEFORE attempting window launch
        let preFocus = CapturedFocus(windowId: 99, appBundleId: "com.apple.Safari", workspace: "main")
        let result = await manager.selectProject(projectId: "test", preCapturedFocus: preFocus)

        // Activation should fail (IDE launch failed)
        switch result {
        case .success:
            XCTFail("Expected activation failure")
        case .failure(let error):
            XCTAssertEqual(error, .ideLaunchFailed(detail: "VS Code launch failed: IDE launch failed"))
        }

        // Push should still be on the stack — verify by closing the project
        switch manager.closeProject(projectId: "test") {
        case .success:
            XCTAssertTrue(aero.focusedWindowIds.contains(99), "Focus should have been restored from stack despite activation failure")
        case .failure(let error):
            XCTFail("Expected close success but got: \(error)")
        }
    }

    // MARK: - selectProject pushes non-project focus (happy path via selectProject)

    func testSelectProjectPushesNonProjectFocus() async {
        let aero = FocusAeroSpaceStub()
        configureForActivation(aero: aero, projectId: "test")
        aero.focusWindowSuccessIds.insert(99) // for close restoration

        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        // selectProject with non-project preCapturedFocus should push it
        let preFocus = CapturedFocus(windowId: 99, appBundleId: "com.apple.Safari", workspace: "main")
        let result = await manager.selectProject(projectId: "test", preCapturedFocus: preFocus)
        switch result {
        case .failure(let error):
            XCTFail("Expected activation success but got: \(error)")
            return
        case .success:
            break
        }

        // Close should restore window 99 (pushed by the real selectProject path)
        switch manager.closeProject(projectId: "test") {
        case .success:
            XCTAssertTrue(aero.focusedWindowIds.contains(99), "Should restore window 99 pushed by selectProject")
        case .failure(let error):
            XCTFail("Expected close success but got: \(error)")
        }
    }

    // MARK: - captureCurrentFocus carries workspace

    func testCapturedFocusCarriesWorkspace() {
        let aero = FocusAeroSpaceStub()
        aero.focusedWindowResult = .success(ApWindow(
            windowId: 7, appBundleId: "com.google.Chrome", workspace: "personal", windowTitle: "Google"
        ))

        let manager = makeFocusManager(aerospace: aero)

        let captured = manager.captureCurrentFocus()
        XCTAssertNotNil(captured)
        XCTAssertEqual(captured?.windowId, 7)
        XCTAssertEqual(captured?.appBundleId, "com.google.Chrome")
        XCTAssertEqual(captured?.workspace, "personal")
    }

    // MARK: - Helpers

    private func testProject(id: String = "test") -> ProjectConfig {
        ProjectConfig(
            id: id,
            name: id.capitalized,
            path: "/\(id)",
            color: "blue",
            useAgentLayer: false,
            chromePinnedTabs: [],
            chromeDefaultTabs: []
        )
    }

    private func loadTestConfig(manager: ProjectManager, projects: [ProjectConfig]? = nil) {
        let config = Config(
            projects: projects ?? [testProject()],
            chrome: ChromeConfig(pinnedTabs: [])
        )
        manager.loadTestConfig(config)
    }

    private func makeFocusManager(
        aerospace: FocusAeroSpaceStub = FocusAeroSpaceStub(),
        ideLauncher: IdeLauncherProviding = FocusIdeLauncherStub(),
        chromeLauncher: ChromeLauncherProviding = FocusChromeLauncherStub()
    ) -> ProjectManager {
        let recencyFilePath = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pm-focus-recency-\(UUID().uuidString).json")
        let chromeTabsDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pm-focus-tabs-\(UUID().uuidString)", isDirectory: true)
        return ProjectManager(
            aerospace: aerospace,
            ideLauncher: ideLauncher,
            chromeLauncher: chromeLauncher,
            chromeTabStore: ChromeTabStore(directory: chromeTabsDir),
            chromeTabCapture: FocusTabCaptureStub(),
            gitRemoteResolver: FocusGitRemoteStub(),
            logger: FocusLoggerStub(),
            recencyFilePath: recencyFilePath
        )
    }

    /// Configures the AeroSpace stub for a successful selectProject activation.
    ///
    /// Sets up tagged Chrome/VS Code windows already in the target workspace,
    /// workspace focus, and focus stability — so selectProject completes the full
    /// activation sequence without launching or moving windows.
    private func configureForActivation(
        aero: FocusAeroSpaceStub,
        projectId: String,
        chromeWindowId: Int = 100,
        ideWindowId: Int = 101
    ) {
        let workspace = "ap-\(projectId)"
        let chromeWindow = ApWindow(
            windowId: chromeWindowId, appBundleId: "com.google.Chrome",
            workspace: workspace, windowTitle: "AP:\(projectId) - Chrome"
        )
        let ideWindow = ApWindow(
            windowId: ideWindowId, appBundleId: "com.microsoft.VSCode",
            workspace: workspace, windowTitle: "AP:\(projectId) - VS Code"
        )

        aero.windowsByBundleId["com.google.Chrome"] = [chromeWindow]
        aero.windowsByBundleId["com.microsoft.VSCode"] = [ideWindow]
        aero.windowsByWorkspace[workspace] = [chromeWindow, ideWindow]
        aero.focusWindowSuccessIds.formUnion([chromeWindowId, ideWindowId])
        aero.focusedWindowResult = .success(ideWindow)
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: workspace, isFocused: true)
        ])
    }
}

// MARK: - Test Doubles

private final class FocusAeroSpaceStub: AeroSpaceProviding {
    var focusedWindowResult: Result<ApWindow, ApCoreError> = .failure(ApCoreError(category: .command, message: "stub"))
    var focusWindowSuccessIds: Set<Int> = []
    var workspacesWithFocusResult: Result<[ApWorkspaceSummary], ApCoreError> = .success([])
    var focusedWindowIds: [Int] = []

    /// Windows returned by `listWindowsForApp(bundleId:)`, keyed by bundle ID.
    var windowsByBundleId: [String: [ApWindow]] = [:]

    /// Windows returned by `listWindowsWorkspace(workspace:)`, keyed by workspace name.
    var windowsByWorkspace: [String: [ApWindow]] = [:]

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
    func focusedWindow() -> Result<ApWindow, ApCoreError> { focusedWindowResult }
    func focusWindow(windowId: Int) -> Result<Void, ApCoreError> {
        focusedWindowIds.append(windowId)
        if focusWindowSuccessIds.contains(windowId) {
            return .success(())
        }
        return .failure(ApCoreError(category: .command, message: "window \(windowId) not found"))
    }
    func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool) -> Result<Void, ApCoreError> { .success(()) }
    func focusWorkspace(name: String) -> Result<Void, ApCoreError> { .success(()) }
}

private final class FocusIdeLauncherStub: IdeLauncherProviding {
    var result: Result<Void, ApCoreError> = .success(())
    func openNewWindow(identifier: String, projectPath: String?) -> Result<Void, ApCoreError> { result }
}

private struct FocusChromeLauncherStub: ChromeLauncherProviding {
    func openNewWindow(identifier: String, initialURLs: [String]) -> Result<Void, ApCoreError> { .success(()) }
}

private final class FocusTabCaptureStub: ChromeTabCapturing {
    func captureTabURLs(windowTitle: String) -> Result<[String], ApCoreError> { .success([]) }
}

private struct FocusGitRemoteStub: GitRemoteResolving {
    func resolve(projectPath: String) -> String? { nil }
}

private struct FocusLoggerStub: AgentPanelLogging {
    func log(event: String, level: LogLevel, message: String?, context: [String: String]?) -> Result<Void, LogWriteError> { .success(()) }
}
