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

    func testCloseProjectUsesMostRecentNonProjectFocusWhenStackEmpty() {
        let aero = FocusAeroSpaceStub()
        aero.focusedWindowResult = .success(
            ApWindow(windowId: 777, appBundleId: "com.apple.Terminal", workspace: "main", windowTitle: "Terminal")
        )
        aero.focusWindowSuccessIds = [777]

        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        XCTAssertEqual(manager.captureCurrentFocus()?.windowId, 777)

        switch manager.closeProject(projectId: "test") {
        case .success:
            XCTAssertTrue(aero.focusedWindowIds.contains(777), "Should restore most recent non-project window")
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

        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        // Simulate previously observed non-project focus without pushing stack entries.
        XCTAssertEqual(manager.captureCurrentFocus()?.windowId, 321)

        switch manager.exitToNonProjectWindow() {
        case .success:
            XCTAssertTrue(aero.focusedWindowIds.contains(321), "Should restore most recent non-project window")
        case .failure(let error):
            XCTFail("Expected success but got: \(error)")
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

    // MARK: - Workspace fallback when focus stack exhausted

    func testCloseProjectFallsBackToNonProjectWorkspaceWhenStackEmpty() {
        let aero = FocusAeroSpaceStub()
        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        // Non-project workspaces available; no focus stack entries
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true),
            ApWorkspaceSummary(workspace: "1", isFocused: false),
            ApWorkspaceSummary(workspace: "personal", isFocused: false)
        ])
        let fallbackWindow = ApWindow(
            windowId: 401,
            appBundleId: "com.apple.Terminal",
            workspace: "1",
            windowTitle: "Terminal"
        )
        aero.windowsByWorkspace["1"] = [fallbackWindow]
        aero.focusWindowSuccessIds = [fallbackWindow.windowId]

        let result = manager.closeProject(projectId: "test")

        if case .failure = result { XCTFail("Expected close to succeed") }
        XCTAssertEqual(aero.focusedWorkspaces.last, "1", "Should fall back to first non-project workspace")
        XCTAssertTrue(
            aero.focusedWindowIds.contains(fallbackWindow.windowId),
            "Workspace fallback should focus a concrete non-project window"
        )
    }

    func testCloseProjectLogsExhaustedWhenOnlyProjectWorkspaces() {
        let aero = FocusAeroSpaceStub()
        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        // Only project workspaces — no fallback possible
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true),
            ApWorkspaceSummary(workspace: "ap-other", isFocused: false)
        ])

        let result = manager.closeProject(projectId: "test")

        // Close still succeeds (focus restoration is non-fatal)
        if case .failure = result { XCTFail("Expected close to succeed") }
        // No non-project workspace was focused
        XCTAssertTrue(aero.focusedWorkspaces.isEmpty, "Should not attempt to focus a project workspace as fallback")
    }

    func testExitFallsBackToNonProjectWorkspaceWhenStackEmpty() {
        let aero = FocusAeroSpaceStub()
        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        // Currently in a project workspace with non-project workspaces available
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true),
            ApWorkspaceSummary(workspace: "main", isFocused: false)
        ])
        let fallbackWindow = ApWindow(
            windowId: 402,
            appBundleId: "com.apple.Safari",
            workspace: "main",
            windowTitle: "Safari"
        )
        aero.windowsByWorkspace["main"] = [fallbackWindow]
        aero.focusWindowSuccessIds = [fallbackWindow.windowId]

        let result = manager.exitToNonProjectWindow()

        if case .failure = result { XCTFail("Expected exit to succeed via workspace fallback") }
        XCTAssertEqual(aero.focusedWorkspaces.last, "main")
        XCTAssertTrue(
            aero.focusedWindowIds.contains(fallbackWindow.windowId),
            "Workspace fallback should focus a concrete non-project window"
        )
    }

    func testExitFailsWhenNoNonProjectWorkspace() {
        let aero = FocusAeroSpaceStub()
        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        // Only project workspaces
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true)
        ])

        let result = manager.exitToNonProjectWindow()

        if case .success = result { XCTFail("Expected exit to fail when no non-project workspace") }
        if case .failure(let error) = result {
            XCTAssertEqual(error, .noPreviousWindow)
        }
    }

    // MARK: - Launcher selection (useAgentLayer)

    func testSelectProjectUsesAgentLayerLauncherWhenUseAgentLayerTrue() async {
        let aero = FocusAeroSpaceStub()
        let directLauncher = FocusIdeLauncherStub()
        // AL launcher injects VS Code window into aero when called (simulates launch)
        let alLauncher = FocusIdeLauncherStub()
        alLauncher.onLaunch = { identifier in
            let workspace = "ap-\(identifier)"
            let ideWindow = ApWindow(
                windowId: 101, appBundleId: "com.microsoft.VSCode",
                workspace: workspace, windowTitle: "AP:\(identifier) - VS Code"
            )
            aero.windowsByBundleId["com.microsoft.VSCode"] = [ideWindow]
            aero.windowsByWorkspace[workspace] = (aero.windowsByWorkspace[workspace] ?? []) + [ideWindow]
        }

        let manager = makeFocusManagerWithSeparateLaunchers(
            aerospace: aero,
            ideLauncher: directLauncher,
            agentLayerIdeLauncher: alLauncher
        )

        let project = ProjectConfig(
            id: "al-project",
            name: "AL Project",
            path: "/Users/test/al-project",
            color: "blue",
            useAgentLayer: true,
            chromePinnedTabs: [],
            chromeDefaultTabs: []
        )
        loadTestConfig(manager: manager, projects: [project])
        // Only set up Chrome window — VS Code must be launched via AL launcher
        configureForActivationChromeOnly(aero: aero, projectId: "al-project")

        let focus = CapturedFocus(windowId: 50, appBundleId: "com.apple.Finder", workspace: "main")
        let result = await manager.selectProject(projectId: "al-project", preCapturedFocus: focus)

        XCTAssertTrue(alLauncher.called, "Agent Layer launcher should have been called")
        XCTAssertFalse(directLauncher.called, "Direct launcher should NOT have been called")
        if case .failure(let error) = result {
            XCTFail("Expected activation to succeed, got: \(error)")
        }
    }

    func testSelectProjectUsesDirectLauncherWhenUseAgentLayerFalse() async {
        let aero = FocusAeroSpaceStub()
        let alLauncher = FocusIdeLauncherStub()
        // Direct launcher injects VS Code window into aero when called (simulates launch)
        let directLauncher = FocusIdeLauncherStub()
        directLauncher.onLaunch = { identifier in
            let workspace = "ap-\(identifier)"
            let ideWindow = ApWindow(
                windowId: 101, appBundleId: "com.microsoft.VSCode",
                workspace: workspace, windowTitle: "AP:\(identifier) - VS Code"
            )
            aero.windowsByBundleId["com.microsoft.VSCode"] = [ideWindow]
            aero.windowsByWorkspace[workspace] = (aero.windowsByWorkspace[workspace] ?? []) + [ideWindow]
        }

        let manager = makeFocusManagerWithSeparateLaunchers(
            aerospace: aero,
            ideLauncher: directLauncher,
            agentLayerIdeLauncher: alLauncher
        )

        let project = testProject(id: "normal-project")
        loadTestConfig(manager: manager, projects: [project])
        // Only set up Chrome window — VS Code must be launched via direct launcher
        configureForActivationChromeOnly(aero: aero, projectId: "normal-project")

        let focus = CapturedFocus(windowId: 50, appBundleId: "com.apple.Finder", workspace: "main")
        let result = await manager.selectProject(projectId: "normal-project", preCapturedFocus: focus)

        XCTAssertTrue(directLauncher.called, "Direct launcher should have been called")
        XCTAssertFalse(alLauncher.called, "Agent Layer launcher should NOT have been called")
        if case .failure(let error) = result {
            XCTFail("Expected activation to succeed, got: \(error)")
        }
    }

    // MARK: - Chrome initial URLs (cold start)

    func testSelectProjectLaunchesChromeWithColdStartURLsWhenNoSnapshotExists() async {
        let aero = FocusAeroSpaceStub()
        let chromeLauncher = FocusChromeLauncherRecordingStub()

        let ideLauncher = FocusIdeLauncherStub()

        let projectId = "test"
        let workspace = "ap-\(projectId)"
        let chromeWindow = ApWindow(
            windowId: 100,
            appBundleId: "com.google.Chrome",
            workspace: workspace,
            windowTitle: "AP:\(projectId) - Chrome"
        )
        let ideWindow = ApWindow(
            windowId: 101,
            appBundleId: "com.microsoft.VSCode",
            workspace: workspace,
            windowTitle: "AP:\(projectId) - VS Code"
        )

        chromeLauncher.onLaunch = { identifier in
            aero.windowsByBundleId["com.google.Chrome"] = [chromeWindow]
            aero.windowsByWorkspace[workspace] = (aero.windowsByWorkspace[workspace] ?? []) + [chromeWindow]
        }
        ideLauncher.onLaunch = { identifier in
            aero.windowsByBundleId["com.microsoft.VSCode"] = [ideWindow]
            aero.windowsByWorkspace[workspace] = (aero.windowsByWorkspace[workspace] ?? []) + [ideWindow]
        }

        aero.focusWindowSuccessIds.formUnion([100, 101])
        aero.focusedWindowResult = .success(ideWindow)
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: workspace, isFocused: true)
        ])

        let manager = makeFocusManagerWithSeparateLaunchers(
            aerospace: aero,
            ideLauncher: ideLauncher,
            agentLayerIdeLauncher: ideLauncher,
            chromeLauncher: chromeLauncher
        )

        let project = ProjectConfig(
            id: projectId,
            name: "Test",
            path: "/test",
            color: "blue",
            useAgentLayer: false,
            chromePinnedTabs: ["https://project-pinned.com"],
            chromeDefaultTabs: ["https://project-default.com"]
        )
        let config = Config(
            projects: [project],
            chrome: ChromeConfig(
                pinnedTabs: ["https://global-pinned.com"],
                defaultTabs: ["https://global-default.com"],
                openGitRemote: false
            )
        )
        manager.loadTestConfig(config)

        let preFocus = CapturedFocus(windowId: 50, appBundleId: "com.apple.Finder", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        if case .failure(let error) = result {
            XCTFail("Expected activation success but got: \(error)")
        }

        XCTAssertEqual(chromeLauncher.calls.count, 1)
        XCTAssertEqual(chromeLauncher.calls[0].identifier, projectId)
        XCTAssertEqual(chromeLauncher.calls[0].initialURLs, [
            "https://global-pinned.com",
            "https://project-pinned.com",
            "https://global-default.com",
            "https://project-default.com"
        ])
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
            agentLayerIdeLauncher: ideLauncher,
            chromeLauncher: chromeLauncher,
            chromeTabStore: ChromeTabStore(directory: chromeTabsDir),
            chromeTabCapture: FocusTabCaptureStub(),
            gitRemoteResolver: FocusGitRemoteStub(),
            logger: FocusLoggerStub(),
            recencyFilePath: recencyFilePath
        )
    }

    private func makeFocusManagerWithSeparateLaunchers(
        aerospace: FocusAeroSpaceStub = FocusAeroSpaceStub(),
        ideLauncher: IdeLauncherProviding = FocusIdeLauncherStub(),
        agentLayerIdeLauncher: IdeLauncherProviding = FocusIdeLauncherStub(),
        chromeLauncher: ChromeLauncherProviding = FocusChromeLauncherStub()
    ) -> ProjectManager {
        let recencyFilePath = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pm-focus-recency-\(UUID().uuidString).json")
        let chromeTabsDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pm-focus-tabs-\(UUID().uuidString)", isDirectory: true)
        return ProjectManager(
            aerospace: aerospace,
            ideLauncher: ideLauncher,
            agentLayerIdeLauncher: agentLayerIdeLauncher,
            chromeLauncher: chromeLauncher,
            chromeTabStore: ChromeTabStore(directory: chromeTabsDir),
            chromeTabCapture: FocusTabCaptureStub(),
            gitRemoteResolver: FocusGitRemoteStub(),
            logger: FocusLoggerStub(),
            recencyFilePath: recencyFilePath
        )
    }

    /// Configures AeroSpace stub with Chrome window only (no VS Code).
    ///
    /// Used by launcher-selection tests where VS Code must be launched (not pre-existing).
    /// Sets up Chrome, workspace focus, and focus stability for the IDE window (101).
    private func configureForActivationChromeOnly(
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

        // Chrome exists; VS Code does NOT (launcher must create it via onLaunch callback)
        aero.windowsByBundleId["com.google.Chrome"] = [chromeWindow]
        aero.windowsByWorkspace[workspace] = [chromeWindow]
        aero.focusWindowSuccessIds.formUnion([chromeWindowId, ideWindowId])
        aero.focusedWindowResult = .success(ideWindow)
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: workspace, isFocused: true)
        ])
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
    func listAllWindows() -> Result<[ApWindow], ApCoreError> { .success([]) }
    func focusedWindow() -> Result<ApWindow, ApCoreError> { focusedWindowResult }
    func focusWindow(windowId: Int) -> Result<Void, ApCoreError> {
        focusedWindowIds.append(windowId)
        if focusWindowSuccessIds.contains(windowId) {
            return .success(())
        }
        return .failure(ApCoreError(category: .command, message: "window \(windowId) not found"))
    }
    private(set) var focusedWorkspaces: [String] = []
    var focusWorkspaceResult: Result<Void, ApCoreError> = .success(())

    func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool) -> Result<Void, ApCoreError> { .success(()) }
    func focusWorkspace(name: String) -> Result<Void, ApCoreError> {
        focusedWorkspaces.append(name)
        return focusWorkspaceResult
    }
}

private final class FocusIdeLauncherStub: IdeLauncherProviding {
    var result: Result<Void, ApCoreError> = .success(())
    private(set) var called = false
    /// Optional callback invoked on launch — used to inject windows into AeroSpace stub.
    var onLaunch: ((String) -> Void)?

    func openNewWindow(identifier: String, projectPath: String?, remoteAuthority: String?, color: String?) -> Result<Void, ApCoreError> {
        called = true
        onLaunch?(identifier)
        return result
    }
}

private struct FocusChromeLauncherStub: ChromeLauncherProviding {
    func openNewWindow(identifier: String, initialURLs: [String]) -> Result<Void, ApCoreError> { .success(()) }
}

private final class FocusChromeLauncherRecordingStub: ChromeLauncherProviding {
    private(set) var calls: [(identifier: String, initialURLs: [String])] = []
    var onLaunch: ((String) -> Void)?

    func openNewWindow(identifier: String, initialURLs: [String]) -> Result<Void, ApCoreError> {
        calls.append((identifier: identifier, initialURLs: initialURLs))
        onLaunch?(identifier)
        return .success(())
    }
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
