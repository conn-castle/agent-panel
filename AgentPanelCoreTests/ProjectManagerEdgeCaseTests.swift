import Foundation
import XCTest
@testable import AgentPanelCore

/// Tests targeting uncovered branches in ProjectManager for coverage improvement.
/// Covers: selectProject move branches, Chrome fallback launch failure, captureCurrentFocus failure,
/// focusWorkspace failure, fallbackToNonProjectWorkspace edge cases, resolveInitialURLs snapshot
/// load failure and git remote, captureWindowPositions screen mode failure and save failure,
/// positionWindows IDE/Chrome set failures, matchType id infix path, saveRecency encode/directory
/// failures.
final class ProjectManagerEdgeCaseTests: XCTestCase {

    // MARK: - selectProject: Chrome window needs moving to workspace

    func testSelectProjectMovesWindowsToWorkspaceWhenNotAlreadyThere() async {
        let projectId = "proj"
        let workspace = "ap-\(projectId)"
        let aero = EdgeAeroSpaceStub()

        let chromeWindow = ApWindow(windowId: 100, appBundleId: "com.google.Chrome",
                                    workspace: "other", windowTitle: "AP:\(projectId) - Chrome")
        let ideWindow = ApWindow(windowId: 101, appBundleId: "com.microsoft.VSCode",
                                 workspace: "other", windowTitle: "AP:\(projectId) - VS Code")

        aero.windowsByBundleId["com.google.Chrome"] = [chromeWindow]
        aero.windowsByBundleId["com.microsoft.VSCode"] = [ideWindow]
        aero.windowsByWorkspace[workspace] = [chromeWindow, ideWindow]
        aero.focusWindowResult = .success(())
        aero.focusedWindowResult = .success(ideWindow)
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: workspace, isFocused: true)
        ])

        let manager = makeManager(aerospace: aero)
        loadConfig(manager, projectId: projectId)

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }

        // Both windows should have been moved
        XCTAssertTrue(aero.movedWindows.contains { $0.windowId == 100 && $0.workspace == workspace })
        XCTAssertTrue(aero.movedWindows.contains { $0.windowId == 101 && $0.workspace == workspace })
    }

    // MARK: - selectProject: Chrome move fails

    func testSelectProjectFailsWhenChromeMoveToWorkspaceFails() async {
        let projectId = "proj"
        let aero = EdgeAeroSpaceStub()

        let chromeWindow = ApWindow(windowId: 100, appBundleId: "com.google.Chrome",
                                    workspace: "other", windowTitle: "AP:\(projectId) - Chrome")
        let ideWindow = ApWindow(windowId: 101, appBundleId: "com.microsoft.VSCode",
                                 workspace: "ap-\(projectId)", windowTitle: "AP:\(projectId) - VS Code")

        aero.windowsByBundleId["com.google.Chrome"] = [chromeWindow]
        aero.windowsByBundleId["com.microsoft.VSCode"] = [ideWindow]
        aero.moveFailWindowIds = [100]

        let manager = makeManager(aerospace: aero)
        loadConfig(manager, projectId: projectId)

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        if case .success = result { XCTFail("Expected failure from Chrome move") }
        if case .failure(let error) = result {
            XCTAssertEqual(error, .aeroSpaceError(detail: "move failed"))
        }
    }

    // MARK: - selectProject: IDE move fails

    func testSelectProjectFailsWhenIDEMoveToWorkspaceFails() async {
        let projectId = "proj"
        let aero = EdgeAeroSpaceStub()

        let chromeWindow = ApWindow(windowId: 100, appBundleId: "com.google.Chrome",
                                    workspace: "ap-\(projectId)", windowTitle: "AP:\(projectId) - Chrome")
        let ideWindow = ApWindow(windowId: 101, appBundleId: "com.microsoft.VSCode",
                                 workspace: "other", windowTitle: "AP:\(projectId) - VS Code")

        aero.windowsByBundleId["com.google.Chrome"] = [chromeWindow]
        aero.windowsByBundleId["com.microsoft.VSCode"] = [ideWindow]
        aero.moveFailWindowIds = [101]

        let manager = makeManager(aerospace: aero)
        loadConfig(manager, projectId: projectId)

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        if case .success = result { XCTFail("Expected failure from IDE move") }
        if case .failure(let error) = result {
            XCTAssertEqual(error, .aeroSpaceError(detail: "move failed"))
        }
    }

    // MARK: - selectProject: workspace focus timeout

    func testSelectProjectFailsWhenWorkspaceFocusTimesOut() async {
        let projectId = "proj"
        let workspace = "ap-\(projectId)"
        let aero = EdgeAeroSpaceStub()

        let chromeWindow = ApWindow(windowId: 100, appBundleId: "com.google.Chrome",
                                    workspace: workspace, windowTitle: "AP:\(projectId) - Chrome")
        let ideWindow = ApWindow(windowId: 101, appBundleId: "com.microsoft.VSCode",
                                 workspace: workspace, windowTitle: "AP:\(projectId) - VS Code")

        aero.windowsByBundleId["com.google.Chrome"] = [chromeWindow]
        aero.windowsByBundleId["com.microsoft.VSCode"] = [ideWindow]
        aero.windowsByWorkspace[workspace] = [chromeWindow, ideWindow]
        aero.focusWindowResult = .success(())
        // Workspace is never focused
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: workspace, isFocused: false)
        ])

        let manager = makeManager(aerospace: aero)
        loadConfig(manager, projectId: projectId)

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        if case .success = result { XCTFail("Expected workspace focus failure") }
        if case .failure(let error) = result {
            if case .aeroSpaceError(let detail) = error {
                XCTAssertTrue(detail.contains("could not be focused"), "Detail: \(detail)")
            } else {
                XCTFail("Expected aeroSpaceError, got: \(error)")
            }
        }
    }

    // MARK: - selectProject: Chrome launch fails with empty URLs (no retry)

    func testSelectProjectFailsWhenChromeLaunchFailsWithNoURLs() async {
        let projectId = "proj"
        let aero = EdgeAeroSpaceStub()
        // No existing Chrome window — needs launch
        aero.windowsByBundleId["com.google.Chrome"] = []
        let ideWindow = ApWindow(windowId: 101, appBundleId: "com.microsoft.VSCode",
                                 workspace: "ap-\(projectId)", windowTitle: "AP:\(projectId) - VS Code")
        aero.windowsByBundleId["com.microsoft.VSCode"] = [ideWindow]

        let failingChrome = EdgeChromeLauncherFailingStub()
        failingChrome.alwaysFail = true

        let manager = makeManager(aerospace: aero, chromeLauncher: failingChrome)
        // No chrome config → no default tabs → empty URL launch
        loadConfig(manager, projectId: projectId)

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        if case .success = result { XCTFail("Expected Chrome launch failure") }
        if case .failure(let error) = result {
            if case .chromeLaunchFailed = error {
                // expected
            } else {
                XCTFail("Expected chromeLaunchFailed, got: \(error)")
            }
        }
    }

    // MARK: - selectProject: Chrome retry also fails

    func testSelectProjectFailsWhenChromeFallbackRetryAlsoFails() async {
        let projectId = "proj"
        let aero = EdgeAeroSpaceStub()
        aero.windowsByBundleId["com.google.Chrome"] = []
        let ideWindow = ApWindow(windowId: 101, appBundleId: "com.microsoft.VSCode",
                                 workspace: "ap-\(projectId)", windowTitle: "AP:\(projectId) - VS Code")
        aero.windowsByBundleId["com.microsoft.VSCode"] = [ideWindow]

        let failingChrome = EdgeChromeLauncherFailingStub()
        failingChrome.alwaysFail = true

        let manager = makeManager(aerospace: aero, chromeLauncher: failingChrome)
        // Config has default tabs → first launch with URLs fails → retry with empty also fails
        loadConfig(manager, projectId: projectId,
                   chrome: ChromeConfig(defaultTabs: ["https://example.com"]))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        if case .success = result { XCTFail("Expected Chrome fallback launch failure") }
        if case .failure(let error) = result {
            if case .chromeLaunchFailed = error {
                // expected
            } else {
                XCTFail("Expected chromeLaunchFailed, got: \(error)")
            }
        }
    }

    // MARK: - captureCurrentFocus: AeroSpace failure

    func testCaptureCurrentFocusReturnsNilWhenAeroSpaceFails() {
        let aero = EdgeAeroSpaceStub()
        aero.focusedWindowResult = .failure(ApCoreError(message: "no window"))

        let manager = makeManager(aerospace: aero)
        XCTAssertNil(manager.captureCurrentFocus())
    }

    // MARK: - focusWorkspace: failure

    func testFocusWorkspaceReturnsFalseOnFailure() {
        let aero = EdgeAeroSpaceStub()
        aero.focusWorkspaceResult = .failure(ApCoreError(message: "ws gone"))

        let manager = makeManager(aerospace: aero)
        XCTAssertFalse(manager.focusWorkspace(name: "main"))
    }

    // MARK: - fallbackToNonProjectWorkspace: focus failure on candidate

    func testFallbackToNonProjectWorkspaceFocusFailsFallsToEmptyWorkspace() {
        let aero = EdgeAeroSpaceStub()
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true),
            ApWorkspaceSummary(workspace: "main", isFocused: false)
        ])
        // listWindowsWorkspace returns windows for "main"
        aero.windowsByWorkspace["main"] = [
            ApWindow(windowId: 10, appBundleId: "com.app", workspace: "main", windowTitle: "App")
        ]
        // But focusing "main" fails
        aero.focusWorkspaceResult = .failure(ApCoreError(message: "focus failed"))

        let manager = makeManager(aerospace: aero)
        manager.loadTestConfig(Config(projects: [
            ProjectConfig(id: "test", name: "Test", path: "/test", color: "blue", useAgentLayer: false)
        ]))

        // exit should fall through all fallback paths and fail
        let result = manager.exitToNonProjectWindow()
        if case .success = result { XCTFail("Expected noPreviousWindow failure") }
    }

    // MARK: - fallbackToNonProjectWorkspace: all workspaces empty, focuses first

    func testFallbackToNonProjectFocusesFirstEmptyWorkspaceAsLastResort() {
        let aero = EdgeAeroSpaceStub()
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true),
            ApWorkspaceSummary(workspace: "empty-ws", isFocused: false)
        ])
        // No windows in the non-project workspace
        aero.windowsByWorkspace["empty-ws"] = []
        aero.focusWorkspaceResult = .success(())

        let manager = makeManager(aerospace: aero)
        manager.loadTestConfig(Config(projects: [
            ProjectConfig(id: "test", name: "Test", path: "/test", color: "blue", useAgentLayer: false)
        ]))

        // exit should succeed by falling back to empty workspace
        let result = manager.exitToNonProjectWindow()
        if case .failure = result { XCTFail("Expected success via empty workspace fallback") }
        XCTAssertTrue(aero.focusedWorkspaces.contains("empty-ws"))
    }

    // MARK: - resolveInitialURLs: snapshot load failure falls back to cold start

    func testSelectProjectUsesConfigURLsWhenSnapshotLoadFails() async {
        let projectId = "proj"
        let workspace = "ap-\(projectId)"
        let aero = EdgeAeroSpaceStub()

        // Chrome not found — needs launch
        aero.windowsByBundleId["com.google.Chrome"] = []
        let chromeWindow = ApWindow(windowId: 100, appBundleId: "com.google.Chrome",
                                    workspace: workspace, windowTitle: "AP:\(projectId) - Chrome")
        let ideWindow = ApWindow(windowId: 101, appBundleId: "com.microsoft.VSCode",
                                 workspace: workspace, windowTitle: "AP:\(projectId) - VS Code")
        aero.windowsByBundleId["com.microsoft.VSCode"] = [ideWindow]
        aero.windowsByWorkspace[workspace] = [chromeWindow, ideWindow]
        aero.focusWindowResult = .success(())
        aero.focusedWindowResult = .success(ideWindow)
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: workspace, isFocused: true)
        ])

        let recordingChrome = EdgeRecordingChromeLauncher()
        recordingChrome.onLaunch = {
            aero.windowsByBundleId["com.google.Chrome"] = [chromeWindow]
        }

        // Use a corrupt tab store directory so snapshot load fails
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let corruptTabsDir = tmp.appendingPathComponent("corrupt-tabs-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: corruptTabsDir, withIntermediateDirectories: true)
        // Write a corrupt file for this project
        let corruptFile = corruptTabsDir.appendingPathComponent("\(projectId).json")
        try? Data("not json".utf8).write(to: corruptFile, options: .atomic)

        let manager = makeManager(aerospace: aero, chromeLauncher: recordingChrome,
                                  chromeTabsDir: corruptTabsDir)
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Proj", path: "/tmp/proj", color: "blue",
                                     useAgentLayer: false)],
            chrome: ChromeConfig(defaultTabs: ["https://fallback.com"])
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }

        // Chrome should have been launched with cold-start URLs
        XCTAssertEqual(recordingChrome.calls.count, 1)
        XCTAssertTrue(recordingChrome.calls[0].urls.contains("https://fallback.com"))
    }

    // MARK: - resolveInitialURLs: git remote resolution

    func testSelectProjectIncludesGitRemoteURLWhenConfigured() async {
        let projectId = "proj"
        let workspace = "ap-\(projectId)"
        let aero = EdgeAeroSpaceStub()

        aero.windowsByBundleId["com.google.Chrome"] = []
        let chromeWindow = ApWindow(windowId: 100, appBundleId: "com.google.Chrome",
                                    workspace: workspace, windowTitle: "AP:\(projectId) - Chrome")
        let ideWindow = ApWindow(windowId: 101, appBundleId: "com.microsoft.VSCode",
                                 workspace: workspace, windowTitle: "AP:\(projectId) - VS Code")
        aero.windowsByBundleId["com.microsoft.VSCode"] = [ideWindow]
        aero.windowsByWorkspace[workspace] = [chromeWindow, ideWindow]
        aero.focusWindowResult = .success(())
        aero.focusedWindowResult = .success(ideWindow)
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: workspace, isFocused: true)
        ])

        let recordingChrome = EdgeRecordingChromeLauncher()
        recordingChrome.onLaunch = {
            aero.windowsByBundleId["com.google.Chrome"] = [chromeWindow]
        }

        let gitResolver = EdgeGitRemoteStub()
        gitResolver.result = "https://github.com/test/repo"

        let manager = makeManager(aerospace: aero, chromeLauncher: recordingChrome,
                                  gitRemoteResolver: gitResolver)
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Proj", path: "/tmp/proj", color: "blue",
                                     useAgentLayer: false)],
            chrome: ChromeConfig(openGitRemote: true)
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }

        XCTAssertTrue(recordingChrome.calls[0].urls.contains("https://github.com/test/repo"))
    }

    // MARK: - captureWindowPositions: screen mode failure falls back to .wide

    func testCaptureWindowPositionsFallsBackToWideOnScreenModeFailure() {
        let projectId = "proj"
        let positioner = EdgeRecordingPositioner()
        let store = EdgeRecordingPositionStore()
        let aero = EdgeSimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(CGRect(x: 100, y: 100, width: 1200, height: 800))
        positioner.getFrameResults["com.google.Chrome|\(projectId)"] = .success(CGRect(x: 1400, y: 100, width: 1100, height: 800))

        struct FailingModeDetector: ScreenModeDetecting {
            func detectMode(containingPoint point: CGPoint, threshold: Double) -> Result<ScreenMode, ApCoreError> {
                .failure(ApCoreError(category: .system, message: "EDID broken"))
            }
            func physicalWidthInches(containingPoint point: CGPoint) -> Result<Double, ApCoreError> { .success(27.0) }
            func screenVisibleFrame(containingPoint point: CGPoint) -> CGRect? {
                CGRect(x: 0, y: 0, width: 2560, height: 1415)
            }
        }

        let manager = makeManager(aerospace: aero, windowPositioner: positioner,
                                  windowPositionStore: store, screenModeDetector: FailingModeDetector())
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Proj", path: "/tmp/proj", color: "blue", useAgentLayer: false)]
        ))

        _ = manager.closeProject(projectId: projectId)

        XCTAssertEqual(store.saveCalls.count, 1)
        XCTAssertEqual(store.saveCalls[0].mode, .wide, "Should fall back to .wide on detection failure")
    }

    // MARK: - captureWindowPositions: save failure is non-fatal

    func testCaptureWindowPositionsSaveFailureDoesNotBlockClose() {
        let projectId = "proj"
        let positioner = EdgeRecordingPositioner()
        let store = EdgeRecordingPositionStore()
        store.saveResult = .failure(ApCoreError(category: .fileSystem, message: "disk full"))
        let aero = EdgeSimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(CGRect(x: 100, y: 100, width: 1200, height: 800))
        positioner.getFrameResults["com.google.Chrome|\(projectId)"] = .success(CGRect(x: 1400, y: 100, width: 1100, height: 800))

        let detector = EdgeStubScreenModeDetector()

        let manager = makeManager(aerospace: aero, windowPositioner: positioner,
                                  windowPositionStore: store, screenModeDetector: detector)
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Proj", path: "/tmp/proj", color: "blue", useAgentLayer: false)]
        ))

        let result = manager.closeProject(projectId: projectId)
        if case .failure(let error) = result { XCTFail("Close should succeed despite save failure: \(error)") }
    }

    // MARK: - positionWindows: IDE set failure

    func testPositionWindowsReturnsWarningWhenIDESetFails() async {
        let projectId = "proj"
        let positioner = EdgeRecordingPositioner()
        let store = EdgeRecordingPositionStore()
        let detector = EdgeStubScreenModeDetector()
        let aero = EdgeSimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(CGRect(x: 100, y: 100, width: 1200, height: 800))
        positioner.setFrameResults["com.microsoft.VSCode|\(projectId)"] = .failure(ApCoreError(category: .window, message: "AX denied"))

        let manager = makeManager(aerospace: aero, windowPositioner: positioner,
                                  windowPositionStore: store, screenModeDetector: detector)
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Proj", path: "/tmp/proj", color: "blue", useAgentLayer: false)]
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            XCTAssertNotNil(success.layoutWarning)
            XCTAssertTrue(success.layoutWarning?.contains("IDE positioning failed") == true)
        }
    }

    // MARK: - positionWindows: Chrome set failure

    func testPositionWindowsReturnsWarningWhenChromeSetFails() async {
        let projectId = "proj"
        let positioner = EdgeRecordingPositioner()
        let store = EdgeRecordingPositionStore()
        let detector = EdgeStubScreenModeDetector()
        let aero = EdgeSimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(CGRect(x: 100, y: 100, width: 1200, height: 800))
        positioner.setFrameResults["com.google.Chrome|\(projectId)"] = .failure(ApCoreError(category: .window, message: "AX denied"))

        let manager = makeManager(aerospace: aero, windowPositioner: positioner,
                                  windowPositionStore: store, screenModeDetector: detector)
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Proj", path: "/tmp/proj", color: "blue", useAgentLayer: false)]
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            XCTAssertNotNil(success.layoutWarning)
            XCTAssertTrue(success.layoutWarning?.contains("Chrome positioning failed") == true)
        }
    }

    // MARK: - matchType: id infix match

    func testSortedProjectsMatchesIdInfix() {
        let manager = makeManager(aerospace: EdgeAeroSpaceStub())
        manager.loadTestConfig(Config(projects: [
            ProjectConfig(id: "my-calico-project", name: "Calico", path: "/test", color: "blue", useAgentLayer: false),
            ProjectConfig(id: "nomatch", name: "NoMatch", path: "/test2", color: "red", useAgentLayer: false)
        ]))

        // Query "calico" matches id infix for "my-calico-project" (matchType 3)
        // and name prefix for "Calico" (matchType 0)
        let sorted = manager.sortedProjects(query: "calico")
        XCTAssertEqual(sorted.count, 1)
        XCTAssertEqual(sorted[0].id, "my-calico-project")
    }

    // MARK: - closeProject: close workspace fails

    func testCloseProjectFailsWhenCloseWorkspaceFails() {
        let aero = EdgeAeroSpaceStub()
        aero.closeWorkspaceResult = .failure(ApCoreError(message: "ws close failed"))

        let manager = makeManager(aerospace: aero)
        manager.loadTestConfig(Config(projects: [
            ProjectConfig(id: "test", name: "Test", path: "/test", color: "blue", useAgentLayer: false)
        ]))

        let result = manager.closeProject(projectId: "test")
        if case .success = result { XCTFail("Expected failure from workspace close") }
        if case .failure(let error) = result {
            XCTAssertEqual(error, .aeroSpaceError(detail: "ws close failed"))
        }
    }

    // MARK: - closeProject: project not found

    func testCloseProjectFailsWhenProjectNotFound() {
        let manager = makeManager(aerospace: EdgeAeroSpaceStub())
        manager.loadTestConfig(Config(projects: [
            ProjectConfig(id: "test", name: "Test", path: "/test", color: "blue", useAgentLayer: false)
        ]))

        let result = manager.closeProject(projectId: "nonexistent")
        if case .success = result { XCTFail("Expected failure for unknown project") }
        if case .failure(let error) = result {
            XCTAssertEqual(error, .projectNotFound(projectId: "nonexistent"))
        }
    }

    // MARK: - exitToNonProjectWindow: workspaceState failure

    func testExitFailsWhenWorkspaceStateQueryFails() {
        let aero = EdgeAeroSpaceStub()
        aero.workspacesWithFocusResult = .failure(ApCoreError(message: "aero down"))

        let manager = makeManager(aerospace: aero)
        manager.loadTestConfig(Config(projects: []))

        let result = manager.exitToNonProjectWindow()
        if case .success = result { XCTFail("Expected failure") }
        if case .failure(let error) = result {
            XCTAssertEqual(error, .aeroSpaceError(detail: "aero down"))
        }
    }

    // MARK: - exitToNonProjectWindow: no active project

    func testExitFailsWhenNoProjectFocused() {
        let aero = EdgeAeroSpaceStub()
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "main", isFocused: true)
        ])

        let manager = makeManager(aerospace: aero)
        manager.loadTestConfig(Config(projects: []))

        let result = manager.exitToNonProjectWindow()
        if case .success = result { XCTFail("Expected noActiveProject") }
        if case .failure(let error) = result {
            XCTAssertEqual(error, .noActiveProject)
        }
    }

    // MARK: - findWindowByToken: listWindowsForApp fails

    func testSelectProjectLaunchesWindowWhenListWindowsFails() async {
        let projectId = "proj"
        let workspace = "ap-\(projectId)"
        let aero = EdgeAeroSpaceStub()
        aero.listWindowsForAppFailBundleIds = ["com.google.Chrome"]

        let chromeWindow = ApWindow(windowId: 100, appBundleId: "com.google.Chrome",
                                    workspace: workspace, windowTitle: "AP:\(projectId) - Chrome")
        let ideWindow = ApWindow(windowId: 101, appBundleId: "com.microsoft.VSCode",
                                 workspace: workspace, windowTitle: "AP:\(projectId) - VS Code")
        aero.windowsByBundleId["com.microsoft.VSCode"] = [ideWindow]
        aero.windowsByWorkspace[workspace] = [chromeWindow, ideWindow]
        aero.focusWindowResult = .success(())
        aero.focusedWindowResult = .success(ideWindow)
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: workspace, isFocused: true)
        ])

        let recordingChrome = EdgeRecordingChromeLauncher()
        recordingChrome.onLaunch = {
            // Remove failure and add window on second call
            aero.listWindowsForAppFailBundleIds.remove("com.google.Chrome")
            aero.windowsByBundleId["com.google.Chrome"] = [chromeWindow]
        }

        let manager = makeManager(aerospace: aero, chromeLauncher: recordingChrome)
        loadConfig(manager, projectId: projectId)

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }
        XCTAssertEqual(recordingChrome.calls.count, 1, "Chrome should have been launched")
    }

    // MARK: - Helpers

    private func makeManager(
        aerospace: AeroSpaceProviding,
        chromeLauncher: ChromeLauncherProviding = EdgeChromeLauncherStub(),
        chromeTabsDir: URL? = nil,
        gitRemoteResolver: GitRemoteResolving = EdgeGitRemoteStub(),
        windowPositioner: WindowPositioning? = nil,
        windowPositionStore: WindowPositionStoring? = nil,
        screenModeDetector: ScreenModeDetecting? = nil
    ) -> ProjectManager {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let effectiveTabsDir = chromeTabsDir ?? tmp.appendingPathComponent("edge-tabs-\(UUID().uuidString)", isDirectory: true)
        let recencyPath = tmp.appendingPathComponent("edge-recency-\(UUID().uuidString).json")
        return ProjectManager(
            aerospace: aerospace,
            ideLauncher: EdgeIdeLauncherStub(),
            agentLayerIdeLauncher: EdgeIdeLauncherStub(),
            chromeLauncher: chromeLauncher,
            chromeTabStore: ChromeTabStore(directory: effectiveTabsDir),
            chromeTabCapture: EdgeTabCaptureStub(),
            gitRemoteResolver: gitRemoteResolver,
            logger: EdgeLoggerStub(),
            recencyFilePath: recencyPath,
            windowPositioner: windowPositioner,
            windowPositionStore: windowPositionStore,
            screenModeDetector: screenModeDetector
        )
    }

    private func loadConfig(_ manager: ProjectManager, projectId: String,
                            chrome: ChromeConfig = ChromeConfig()) {
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: projectId.capitalized,
                                     path: "/tmp/\(projectId)", color: "blue", useAgentLayer: false)],
            chrome: chrome
        ))
    }
}

// MARK: - Test Doubles

private final class EdgeAeroSpaceStub: AeroSpaceProviding {
    var focusedWindowResult: Result<ApWindow, ApCoreError> = .failure(ApCoreError(message: "stub"))
    var focusWindowResult: Result<Void, ApCoreError> = .success(())
    var workspacesWithFocusResult: Result<[ApWorkspaceSummary], ApCoreError> = .success([])
    var focusWorkspaceResult: Result<Void, ApCoreError> = .success(())
    var closeWorkspaceResult: Result<Void, ApCoreError> = .success(())
    var windowsByBundleId: [String: [ApWindow]] = [:]
    var windowsByWorkspace: [String: [ApWindow]] = [:]
    var moveFailWindowIds: Set<Int> = []
    var listWindowsForAppFailBundleIds: Set<String> = []
    private(set) var movedWindows: [(windowId: Int, workspace: String)] = []
    private(set) var focusedWindowIds: [Int] = []
    private(set) var focusedWorkspaces: [String] = []

    func getWorkspaces() -> Result<[String], ApCoreError> { .success([]) }
    func workspaceExists(_ name: String) -> Result<Bool, ApCoreError> { .success(false) }
    func listWorkspacesFocused() -> Result<[String], ApCoreError> { .success([]) }
    func listWorkspacesWithFocus() -> Result<[ApWorkspaceSummary], ApCoreError> { workspacesWithFocusResult }
    func createWorkspace(_ name: String) -> Result<Void, ApCoreError> { .success(()) }
    func closeWorkspace(name: String) -> Result<Void, ApCoreError> { closeWorkspaceResult }

    func listWindowsForApp(bundleId: String) -> Result<[ApWindow], ApCoreError> {
        if listWindowsForAppFailBundleIds.contains(bundleId) {
            return .failure(ApCoreError(message: "list failed"))
        }
        return .success(windowsByBundleId[bundleId] ?? [])
    }

    func listWindowsWorkspace(workspace: String) -> Result<[ApWindow], ApCoreError> {
        .success(windowsByWorkspace[workspace] ?? [])
    }
    func listAllWindows() -> Result<[ApWindow], ApCoreError> { .success([]) }

    func focusedWindow() -> Result<ApWindow, ApCoreError> { focusedWindowResult }

    func focusWindow(windowId: Int) -> Result<Void, ApCoreError> {
        focusedWindowIds.append(windowId)
        return focusWindowResult
    }

    func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool) -> Result<Void, ApCoreError> {
        movedWindows.append((windowId, workspace))
        if moveFailWindowIds.contains(windowId) {
            return .failure(ApCoreError(message: "move failed"))
        }
        return .success(())
    }

    func focusWorkspace(name: String) -> Result<Void, ApCoreError> {
        focusedWorkspaces.append(name)
        return focusWorkspaceResult
    }
}

private struct EdgeIdeLauncherStub: IdeLauncherProviding {
    func openNewWindow(identifier: String, projectPath: String?, remoteAuthority: String?, color: String?) -> Result<Void, ApCoreError> { .success(()) }
}

private struct EdgeChromeLauncherStub: ChromeLauncherProviding {
    func openNewWindow(identifier: String, initialURLs: [String]) -> Result<Void, ApCoreError> { .success(()) }
}

private final class EdgeChromeLauncherFailingStub: ChromeLauncherProviding {
    var alwaysFail = false

    func openNewWindow(identifier: String, initialURLs: [String]) -> Result<Void, ApCoreError> {
        if alwaysFail { return .failure(ApCoreError(message: "chrome launch failed")) }
        return .success(())
    }
}

private final class EdgeRecordingChromeLauncher: ChromeLauncherProviding {
    private(set) var calls: [(identifier: String, urls: [String])] = []
    var onLaunch: (() -> Void)?

    func openNewWindow(identifier: String, initialURLs: [String]) -> Result<Void, ApCoreError> {
        calls.append((identifier, initialURLs))
        onLaunch?()
        return .success(())
    }
}

private struct EdgeTabCaptureStub: ChromeTabCapturing {
    func captureTabURLs(windowTitle: String) -> Result<[String], ApCoreError> { .success([]) }
}

private final class EdgeGitRemoteStub: GitRemoteResolving {
    var result: String?
    func resolve(projectPath: String) -> String? { result }
}

private struct EdgeLoggerStub: AgentPanelLogging {
    func log(event: String, level: LogLevel, message: String?, context: [String: String]?) -> Result<Void, LogWriteError> { .success(()) }
}

private final class EdgeRecordingPositioner: WindowPositioning {
    var getFrameResults: [String: Result<CGRect, ApCoreError>] = [:]
    var setFrameResults: [String: Result<WindowPositionResult, ApCoreError>] = [:]
    var trusted: Bool = true
    private(set) var setFrameCalls: [(bundleId: String, projectId: String)] = []

    func getPrimaryWindowFrame(bundleId: String, projectId: String) -> Result<CGRect, ApCoreError> {
        let key = "\(bundleId)|\(projectId)"
        return getFrameResults[key] ?? .failure(ApCoreError(category: .window, message: "no stub"))
    }

    func setWindowFrames(bundleId: String, projectId: String, primaryFrame: CGRect, cascadeOffsetPoints: CGFloat) -> Result<WindowPositionResult, ApCoreError> {
        setFrameCalls.append((bundleId, projectId))
        let key = "\(bundleId)|\(projectId)"
        return setFrameResults[key] ?? .success(WindowPositionResult(positioned: 1, matched: 1))
    }

    func recoverWindow(bundleId: String, windowTitle: String, screenVisibleFrame: CGRect) -> Result<RecoveryOutcome, ApCoreError> { .success(.unchanged) }

    func isAccessibilityTrusted() -> Bool { trusted }

    func promptForAccessibility() -> Bool { trusted }
}

private final class EdgeRecordingPositionStore: WindowPositionStoring {
    var loadResults: [String: Result<SavedWindowFrames?, ApCoreError>] = [:]
    private(set) var saveCalls: [(projectId: String, mode: ScreenMode, frames: SavedWindowFrames)] = []
    var saveResult: Result<Void, ApCoreError> = .success(())

    func load(projectId: String, mode: ScreenMode) -> Result<SavedWindowFrames?, ApCoreError> {
        let key = "\(projectId)|\(mode.rawValue)"
        return loadResults[key] ?? .success(nil)
    }

    func save(projectId: String, mode: ScreenMode, frames: SavedWindowFrames) -> Result<Void, ApCoreError> {
        saveCalls.append((projectId, mode, frames))
        return saveResult
    }
}

private struct EdgeStubScreenModeDetector: ScreenModeDetecting {
    func detectMode(containingPoint point: CGPoint, threshold: Double) -> Result<ScreenMode, ApCoreError> { .success(.wide) }
    func physicalWidthInches(containingPoint point: CGPoint) -> Result<Double, ApCoreError> { .success(27.0) }
    func screenVisibleFrame(containingPoint point: CGPoint) -> CGRect? { CGRect(x: 0, y: 0, width: 2560, height: 1415) }
}

/// Simple AeroSpace stub where all windows are already in the target workspace.
private final class EdgeSimpleAeroSpaceStub: AeroSpaceProviding {
    let projectId: String
    init(projectId: String) { self.projectId = projectId }

    private var chromeWindow: ApWindow {
        ApWindow(windowId: 100, appBundleId: "com.google.Chrome",
                 workspace: "ap-\(projectId)", windowTitle: "AP:\(projectId) - Chrome")
    }
    private var ideWindow: ApWindow {
        ApWindow(windowId: 101, appBundleId: "com.microsoft.VSCode",
                 workspace: "ap-\(projectId)", windowTitle: "AP:\(projectId) - VS Code")
    }

    func getWorkspaces() -> Result<[String], ApCoreError> { .success([]) }
    func workspaceExists(_ name: String) -> Result<Bool, ApCoreError> { .success(false) }
    func listWorkspacesFocused() -> Result<[String], ApCoreError> { .success([]) }
    func listWorkspacesWithFocus() -> Result<[ApWorkspaceSummary], ApCoreError> {
        .success([ApWorkspaceSummary(workspace: "ap-\(projectId)", isFocused: true)])
    }
    func createWorkspace(_ name: String) -> Result<Void, ApCoreError> { .success(()) }
    func closeWorkspace(name: String) -> Result<Void, ApCoreError> { .success(()) }
    func listWindowsForApp(bundleId: String) -> Result<[ApWindow], ApCoreError> {
        if bundleId == "com.google.Chrome" { return .success([chromeWindow]) }
        if bundleId == "com.microsoft.VSCode" { return .success([ideWindow]) }
        return .success([])
    }
    func listWindowsWorkspace(workspace: String) -> Result<[ApWindow], ApCoreError> {
        .success([chromeWindow, ideWindow])
    }
    func listAllWindows() -> Result<[ApWindow], ApCoreError> { .success([]) }
    func focusedWindow() -> Result<ApWindow, ApCoreError> { .success(ideWindow) }
    func focusWindow(windowId: Int) -> Result<Void, ApCoreError> { .success(()) }
    func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool) -> Result<Void, ApCoreError> { .success(()) }
    func focusWorkspace(name: String) -> Result<Void, ApCoreError> { .success(()) }
}
