import Foundation
import XCTest
@testable import AgentPanelCore

final class WindowRecoveryManagerTests: XCTestCase {

    // MARK: - Test Doubles

    private struct NoopLogger: AgentPanelLogging {
        func log(event: String, level: LogLevel, message: String?, context: [String: String]?) -> Result<Void, LogWriteError> {
            .success(())
        }
    }

    private final class StubAeroSpace: AeroSpaceProviding {
        var workspaces: [String] = []
        var windowsByWorkspace: [String: Result<[ApWindow], ApCoreError>] = [:]
        var focusedWindowResult: Result<ApWindow, ApCoreError> = .failure(ApCoreError(message: "no focus"))
        var focusWindowCalls: [Int] = []
        var focusWorkspaceCalls: [String] = []
        var moveWindowCalls: [(workspace: String, windowId: Int, focusFollows: Bool)] = []
        var moveWindowResult: Result<Void, ApCoreError> = .success(())
        var focusWindowResult: Result<Void, ApCoreError> = .success(())

        func getWorkspaces() -> Result<[String], ApCoreError> { .success(workspaces) }
        func workspaceExists(_ name: String) -> Result<Bool, ApCoreError> { .success(workspaces.contains(name)) }
        func listWorkspacesFocused() -> Result<[String], ApCoreError> { .success([]) }
        func listWorkspacesWithFocus() -> Result<[ApWorkspaceSummary], ApCoreError> { .success([]) }
        func createWorkspace(_ name: String) -> Result<Void, ApCoreError> { .success(()) }
        func closeWorkspace(name: String) -> Result<Void, ApCoreError> { .success(()) }
        func listWindowsForApp(bundleId: String) -> Result<[ApWindow], ApCoreError> { .success([]) }

        func listWindowsWorkspace(workspace: String) -> Result<[ApWindow], ApCoreError> {
            windowsByWorkspace[workspace] ?? .success([])
        }

        func listAllWindows() -> Result<[ApWindow], ApCoreError> {
            // Aggregate from windowsByWorkspace for consistency
            var all: [ApWindow] = []
            for ws in workspaces {
                if case .success(let windows) = listWindowsWorkspace(workspace: ws) {
                    all.append(contentsOf: windows)
                }
            }
            return .success(all)
        }

        func focusedWindow() -> Result<ApWindow, ApCoreError> {
            focusedWindowResult
        }

        func focusWindow(windowId: Int) -> Result<Void, ApCoreError> {
            focusWindowCalls.append(windowId)
            return focusWindowResult
        }

        func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool) -> Result<Void, ApCoreError> {
            moveWindowCalls.append((workspace, windowId, focusFollows))
            return moveWindowResult
        }

        func focusWorkspace(name: String) -> Result<Void, ApCoreError> {
            focusWorkspaceCalls.append(name)
            return .success(())
        }
    }

    private final class StubWindowPositioner: WindowPositioning {
        var recoverCalls: [(bundleId: String, windowTitle: String, screenFrame: CGRect)] = []
        var recoverResults: [String: Result<RecoveryOutcome, ApCoreError>] = [:] // keyed by windowTitle
        var defaultRecoverResult: Result<RecoveryOutcome, ApCoreError> = .success(.unchanged)
        var setFrameCalls: [(bundleId: String, projectId: String, primaryFrame: CGRect, cascadeOffset: CGFloat)] = []
        var setFrameResults: [String: Result<WindowPositionResult, ApCoreError>] = [:] // keyed by bundleId
        var defaultSetFrameResult: Result<WindowPositionResult, ApCoreError> = .success(WindowPositionResult(positioned: 1, matched: 1))

        func recoverWindow(bundleId: String, windowTitle: String, screenVisibleFrame: CGRect) -> Result<RecoveryOutcome, ApCoreError> {
            recoverCalls.append((bundleId, windowTitle, screenVisibleFrame))
            return recoverResults[windowTitle] ?? defaultRecoverResult
        }

        func getPrimaryWindowFrame(bundleId: String, projectId: String) -> Result<CGRect, ApCoreError> {
            .failure(ApCoreError(message: "not implemented"))
        }

        func setWindowFrames(bundleId: String, projectId: String, primaryFrame: CGRect, cascadeOffsetPoints: CGFloat) -> Result<WindowPositionResult, ApCoreError> {
            setFrameCalls.append((bundleId, projectId, primaryFrame, cascadeOffsetPoints))
            return setFrameResults[bundleId] ?? defaultSetFrameResult
        }

        func isAccessibilityTrusted() -> Bool { true }
        func promptForAccessibility() -> Bool { true }
    }

    private struct StubScreenModeDetector: ScreenModeDetecting {
        var mode: Result<ScreenMode, ApCoreError> = .success(.wide)
        var physicalWidth: Result<Double, ApCoreError> = .success(27.0)
        var visibleFrame: CGRect? = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        func detectMode(containingPoint: CGPoint, threshold: Double) -> Result<ScreenMode, ApCoreError> { mode }
        func physicalWidthInches(containingPoint: CGPoint) -> Result<Double, ApCoreError> { physicalWidth }
        func screenVisibleFrame(containingPoint: CGPoint) -> CGRect? { visibleFrame }
    }

    // MARK: - Helpers

    private let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    private func makeManager(
        aerospace: StubAeroSpace = StubAeroSpace(),
        positioner: StubWindowPositioner = StubWindowPositioner(),
        screenModeDetector: ScreenModeDetecting? = nil,
        layoutConfig: LayoutConfig = LayoutConfig()
    ) -> WindowRecoveryManager {
        WindowRecoveryManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            screenVisibleFrame: screenFrame,
            logger: NoopLogger(),
            screenModeDetector: screenModeDetector,
            layoutConfig: layoutConfig
        )
    }

    private func makeWindow(id: Int, bundleId: String = "com.test.app", workspace: String = "ap-test", title: String = "Test Window") -> ApWindow {
        ApWindow(windowId: id, appBundleId: bundleId, workspace: workspace, windowTitle: title)
    }

    /// Helper: sets up a StubAeroSpace with windows in workspaces (for recoverAll tests).
    private func setupWorkspaceWindows(_ aerospace: StubAeroSpace, windows: [ApWindow]) {
        var byWorkspace: [String: [ApWindow]] = [:]
        var wsSet: Set<String> = []
        for window in windows {
            byWorkspace[window.workspace, default: []].append(window)
            wsSet.insert(window.workspace)
        }
        aerospace.workspaces = Array(wsSet).sorted()
        for (ws, wins) in byWorkspace {
            aerospace.windowsByWorkspace[ws] = .success(wins)
        }
    }

    // MARK: - recoverWorkspaceWindows Tests

    func testRecoverWorkspace_emptyWorkspace_succeeds() {
        let aerospace = StubAeroSpace()
        aerospace.windowsByWorkspace["ap-test"] = .success([])
        let manager = makeManager(aerospace: aerospace)

        let result = manager.recoverWorkspaceWindows(workspace: "ap-test")

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(recovery.windowsProcessed, 0)
        XCTAssertEqual(recovery.windowsRecovered, 0)
        XCTAssertTrue(recovery.errors.isEmpty)
    }

    func testRecoverWorkspace_oversizedWindowRecovered() {
        let aerospace = StubAeroSpace()
        let window = makeWindow(id: 1, title: "Big Window")
        aerospace.windowsByWorkspace["ap-test"] = .success([window])
        aerospace.focusedWindowResult = .success(window)

        let positioner = StubWindowPositioner()
        positioner.recoverResults["Big Window"] = .success(.recovered)

        let manager = makeManager(aerospace: aerospace, positioner: positioner)
        let result = manager.recoverWorkspaceWindows(workspace: "ap-test")

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(recovery.windowsProcessed, 1)
        XCTAssertEqual(recovery.windowsRecovered, 1)
        XCTAssertEqual(positioner.recoverCalls.count, 1)
        XCTAssertEqual(positioner.recoverCalls[0].bundleId, "com.test.app")
        XCTAssertEqual(positioner.recoverCalls[0].windowTitle, "Big Window")
    }

    func testRecoverWorkspace_normalWindowNotRecovered() {
        let aerospace = StubAeroSpace()
        let window = makeWindow(id: 1, title: "Normal Window")
        aerospace.windowsByWorkspace["ap-test"] = .success([window])

        let positioner = StubWindowPositioner()
        positioner.defaultRecoverResult = .success(.unchanged)

        let manager = makeManager(aerospace: aerospace, positioner: positioner)
        let result = manager.recoverWorkspaceWindows(workspace: "ap-test")

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(recovery.windowsProcessed, 1)
        XCTAssertEqual(recovery.windowsRecovered, 0)
    }

    func testRecoverWorkspace_axFailureRecordedAsError() {
        let aerospace = StubAeroSpace()
        let window = makeWindow(id: 1, title: "Broken Window")
        aerospace.windowsByWorkspace["ap-test"] = .success([window])

        let positioner = StubWindowPositioner()
        positioner.recoverResults["Broken Window"] = .failure(ApCoreError(category: .window, message: "AX denied"))

        let manager = makeManager(aerospace: aerospace, positioner: positioner)
        let result = manager.recoverWorkspaceWindows(workspace: "ap-test")

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(recovery.windowsProcessed, 1)
        XCTAssertEqual(recovery.windowsRecovered, 0)
        XCTAssertEqual(recovery.errors.count, 1)
        XCTAssertTrue(recovery.errors[0].contains("AX denied"))
    }

    func testRecoverWorkspace_restoresFocusAfterRecovery() {
        let aerospace = StubAeroSpace()
        let originalWindow = makeWindow(id: 42, title: "My Window")
        aerospace.focusedWindowResult = .success(originalWindow)
        let otherWindow = makeWindow(id: 99, title: "Other")
        aerospace.windowsByWorkspace["ap-test"] = .success([otherWindow])

        let manager = makeManager(aerospace: aerospace)
        _ = manager.recoverWorkspaceWindows(workspace: "ap-test")

        XCTAssertEqual(aerospace.focusWindowCalls.last, 42)
    }

    func testRecoverWorkspace_multipleWindows_allProcessed() {
        let aerospace = StubAeroSpace()
        let w1 = makeWindow(id: 1, title: "Win1")
        let w2 = makeWindow(id: 2, title: "Win2")
        let w3 = makeWindow(id: 3, title: "Win3")
        aerospace.windowsByWorkspace["ap-test"] = .success([w1, w2, w3])

        let positioner = StubWindowPositioner()
        positioner.recoverResults["Win1"] = .success(.recovered)
        positioner.recoverResults["Win2"] = .success(.unchanged)
        positioner.recoverResults["Win3"] = .success(.recovered)

        let manager = makeManager(aerospace: aerospace, positioner: positioner)
        let result = manager.recoverWorkspaceWindows(workspace: "ap-test")

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(recovery.windowsProcessed, 3)
        XCTAssertEqual(recovery.windowsRecovered, 2)
        XCTAssertEqual(positioner.recoverCalls.count, 3)
    }

    func testRecoverWorkspace_unknownWorkspace_succeedsWithZeroProcessed() {
        let aerospace = StubAeroSpace()
        let manager = makeManager(aerospace: aerospace)
        let result = manager.recoverWorkspaceWindows(workspace: "nonexistent")

        // Unknown workspace returns empty window list — success with 0 processed
        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(recovery.windowsProcessed, 0)
    }

    func testRecoverWorkspace_listFailure_returnsError() {
        let aerospace = StubAeroSpace()
        aerospace.windowsByWorkspace["ap-broken"] = .failure(ApCoreError(message: "workspace gone"))
        let manager = makeManager(aerospace: aerospace)

        let result = manager.recoverWorkspaceWindows(workspace: "ap-broken")

        guard case .failure(let error) = result else {
            XCTFail("Expected failure, got \(result)")
            return
        }
        XCTAssertTrue(error.message.contains("workspace gone"))
    }

    func testRecoverWorkspace_focusFailure_surfacedAsError() {
        let aerospace = StubAeroSpace()
        let window = makeWindow(id: 1, title: "Test")
        aerospace.windowsByWorkspace["ap-test"] = .success([window])
        aerospace.focusWindowResult = .failure(ApCoreError(message: "focus denied"))

        let positioner = StubWindowPositioner()
        let manager = makeManager(aerospace: aerospace, positioner: positioner)
        let result = manager.recoverWorkspaceWindows(workspace: "ap-test")

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(recovery.windowsProcessed, 1)
        XCTAssertEqual(recovery.windowsRecovered, 0)
        XCTAssertEqual(recovery.errors.count, 1)
        XCTAssertTrue(recovery.errors[0].contains("Focus failed"))
        // Recovery should NOT be called when focus fails
        XCTAssertEqual(positioner.recoverCalls.count, 0)
    }

    func testRecoverWorkspace_focusesEachWindowBeforeRecovery() {
        let aerospace = StubAeroSpace()
        let w1 = makeWindow(id: 10, title: "A")
        let w2 = makeWindow(id: 20, title: "B")
        aerospace.windowsByWorkspace["ap-test"] = .success([w1, w2])

        let positioner = StubWindowPositioner()
        let manager = makeManager(aerospace: aerospace, positioner: positioner)
        _ = manager.recoverWorkspaceWindows(workspace: "ap-test")

        // Focus calls should include both window IDs (before each recovery)
        XCTAssertTrue(aerospace.focusWindowCalls.contains(10))
        XCTAssertTrue(aerospace.focusWindowCalls.contains(20))
        // Each focus should precede the corresponding recover call
        XCTAssertEqual(positioner.recoverCalls.count, 2)
    }

    func testRecoverWorkspace_notFoundSurfacedAsError() {
        let aerospace = StubAeroSpace()
        let window = makeWindow(id: 1, title: "Ghost")
        aerospace.windowsByWorkspace["ap-test"] = .success([window])

        let positioner = StubWindowPositioner()
        positioner.recoverResults["Ghost"] = .success(.notFound)

        let manager = makeManager(aerospace: aerospace, positioner: positioner)
        let result = manager.recoverWorkspaceWindows(workspace: "ap-test")

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(recovery.windowsProcessed, 1)
        XCTAssertEqual(recovery.windowsRecovered, 0)
        XCTAssertEqual(recovery.errors.count, 1)
        XCTAssertTrue(recovery.errors[0].contains("not found"))
    }

    // MARK: - recoverAllWindows Tests

    func testRecoverAll_emptyWindowList_succeeds() {
        let aerospace = StubAeroSpace()
        // No workspaces at all
        let manager = makeManager(aerospace: aerospace)

        var progressCalls: [(Int, Int)] = []
        let result = manager.recoverAllWindows { current, total in
            progressCalls.append((current, total))
        }

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(recovery.windowsProcessed, 0)
        XCTAssertEqual(recovery.windowsRecovered, 0)
        XCTAssertTrue(progressCalls.isEmpty)
    }

    func testRecoverAll_movesEachWindowToWorkspace1() {
        let aerospace = StubAeroSpace()
        let w1 = makeWindow(id: 10, workspace: "ap-foo", title: "Foo")
        let w2 = makeWindow(id: 20, workspace: "2", title: "Bar")
        setupWorkspaceWindows(aerospace, windows: [w1, w2])
        aerospace.focusedWindowResult = .success(w1)

        let manager = makeManager(aerospace: aerospace)
        _ = manager.recoverAllWindows { _, _ in }

        XCTAssertEqual(aerospace.moveWindowCalls.count, 2)
        XCTAssertEqual(aerospace.moveWindowCalls[0].workspace, "1")
        XCTAssertTrue(aerospace.moveWindowCalls[0].focusFollows)
        XCTAssertEqual(aerospace.moveWindowCalls[1].workspace, "1")
    }

    func testRecoverAll_reportsProgressForEachWindow() {
        let aerospace = StubAeroSpace()
        let windows = [
            makeWindow(id: 1, workspace: "ws1", title: "A"),
            makeWindow(id: 2, workspace: "ws1", title: "B"),
            makeWindow(id: 3, workspace: "ws1", title: "C")
        ]
        setupWorkspaceWindows(aerospace, windows: windows)

        let manager = makeManager(aerospace: aerospace)

        var progressCalls: [(Int, Int)] = []
        _ = manager.recoverAllWindows { current, total in
            progressCalls.append((current, total))
        }

        XCTAssertEqual(progressCalls.count, 3)
        XCTAssertEqual(progressCalls[0].0, 1)
        XCTAssertEqual(progressCalls[0].1, 3)
        XCTAssertEqual(progressCalls[1].0, 2)
        XCTAssertEqual(progressCalls[1].1, 3)
        XCTAssertEqual(progressCalls[2].0, 3)
        XCTAssertEqual(progressCalls[2].1, 3)
    }

    func testRecoverAll_restoresOriginalFocus() {
        let aerospace = StubAeroSpace()
        let original = makeWindow(id: 42, workspace: "ap-myproject", title: "My Window")
        aerospace.focusedWindowResult = .success(original)
        let other = makeWindow(id: 99, workspace: "2", title: "Other")
        setupWorkspaceWindows(aerospace, windows: [other])

        let manager = makeManager(aerospace: aerospace)
        _ = manager.recoverAllWindows { _, _ in }

        // Should restore focus to original window (now on workspace "1")
        XCTAssertEqual(aerospace.focusWindowCalls.last, 42)
        // Should NOT call focusWorkspace — all windows are on "1", restoring
        // the original workspace would briefly switch to an empty workspace
        XCTAssertTrue(aerospace.focusWorkspaceCalls.isEmpty)
    }

    func testRecoverAll_moveFailure_continuesAndRecordsError() {
        let aerospace = StubAeroSpace()
        let windows = [
            makeWindow(id: 1, workspace: "ws1", title: "A"),
            makeWindow(id: 2, workspace: "ws1", title: "B")
        ]
        setupWorkspaceWindows(aerospace, windows: windows)
        aerospace.moveWindowResult = .failure(ApCoreError(message: "move failed"))

        let positioner = StubWindowPositioner()
        let manager = makeManager(aerospace: aerospace, positioner: positioner)

        let result = manager.recoverAllWindows { _, _ in }

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(recovery.windowsProcessed, 2)
        XCTAssertEqual(recovery.errors.count, 2)
        XCTAssertTrue(recovery.errors[0].contains("move failed"))
        // Recovery should not be called when move fails
        XCTAssertEqual(positioner.recoverCalls.count, 0)
    }

    func testRecoverAll_recoveredCountTracksActuallyResized() {
        let aerospace = StubAeroSpace()
        let windows = [
            makeWindow(id: 1, workspace: "ws1", title: "Big"),
            makeWindow(id: 2, workspace: "ws1", title: "Small"),
            makeWindow(id: 3, workspace: "ws1", title: "Medium")
        ]
        setupWorkspaceWindows(aerospace, windows: windows)

        let positioner = StubWindowPositioner()
        positioner.recoverResults["Big"] = .success(.recovered)
        positioner.recoverResults["Small"] = .success(.unchanged)
        positioner.recoverResults["Medium"] = .success(.recovered)

        let manager = makeManager(aerospace: aerospace, positioner: positioner)
        let result = manager.recoverAllWindows { _, _ in }

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(recovery.windowsProcessed, 3)
        XCTAssertEqual(recovery.windowsRecovered, 2)
    }

    func testRecoverAll_passesCorrectScreenFrame() {
        let aerospace = StubAeroSpace()
        let window = makeWindow(id: 1, workspace: "ws1", title: "Win")
        setupWorkspaceWindows(aerospace, windows: [window])

        let positioner = StubWindowPositioner()
        positioner.defaultRecoverResult = .success(.unchanged)

        let manager = makeManager(aerospace: aerospace, positioner: positioner)
        _ = manager.recoverAllWindows { _, _ in }

        XCTAssertEqual(positioner.recoverCalls.count, 1)
        XCTAssertEqual(positioner.recoverCalls[0].screenFrame, screenFrame)
    }

    func testRecoverAll_workspaceListFailure_surfacedAsError() {
        let aerospace = StubAeroSpace()
        aerospace.workspaces = ["ws-ok", "ws-broken"]
        aerospace.windowsByWorkspace["ws-ok"] = .success([makeWindow(id: 1, workspace: "ws-ok", title: "OK")])
        aerospace.windowsByWorkspace["ws-broken"] = .failure(ApCoreError(message: "workspace gone"))

        let manager = makeManager(aerospace: aerospace)
        let result = manager.recoverAllWindows { _, _ in }

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        // Should still process the window from ws-ok
        XCTAssertEqual(recovery.windowsProcessed, 1)
        // But also surface the workspace failure
        XCTAssertTrue(recovery.errors.contains { $0.contains("ws-broken") })
    }

    func testRecoverAll_notFoundSurfacedAsError() {
        let aerospace = StubAeroSpace()
        let window = makeWindow(id: 1, workspace: "ws1", title: "Ghost")
        setupWorkspaceWindows(aerospace, windows: [window])

        let positioner = StubWindowPositioner()
        positioner.recoverResults["Ghost"] = .success(.notFound)

        let manager = makeManager(aerospace: aerospace, positioner: positioner)
        let result = manager.recoverAllWindows { _, _ in }

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(recovery.windowsProcessed, 1)
        XCTAssertEqual(recovery.windowsRecovered, 0)
        XCTAssertEqual(recovery.errors.count, 1)
        XCTAssertTrue(recovery.errors[0].contains("not found"))
    }

    func testRecoverAll_focusesEachWindowBeforeRecovery() {
        let aerospace = StubAeroSpace()
        let w1 = makeWindow(id: 10, workspace: "ws1", title: "A")
        let w2 = makeWindow(id: 20, workspace: "ws1", title: "B")
        setupWorkspaceWindows(aerospace, windows: [w1, w2])

        let positioner = StubWindowPositioner()
        let manager = makeManager(aerospace: aerospace, positioner: positioner)
        _ = manager.recoverAllWindows { _, _ in }

        // Focus calls include the per-window focus (before each recovery)
        XCTAssertTrue(aerospace.focusWindowCalls.contains(10))
        XCTAssertTrue(aerospace.focusWindowCalls.contains(20))
        XCTAssertEqual(positioner.recoverCalls.count, 2)
    }

    // MARK: - Layout-aware Recovery Tests

    func testRecoverWorkspace_projectWorkspace_appliesLayoutForIDEAndChrome() {
        let aerospace = StubAeroSpace()
        let projectId = "myproj"
        let workspace = "ap-\(projectId)"

        let ideWindow = makeWindow(id: 1, bundleId: "com.microsoft.VSCode", workspace: workspace,
                                   title: "AP:\(projectId) - VS Code")
        let chromeWindow = makeWindow(id: 2, bundleId: "com.google.Chrome", workspace: workspace,
                                      title: "AP:\(projectId) - Chrome")
        let otherWindow = makeWindow(id: 3, bundleId: "com.other.App", workspace: workspace,
                                     title: "Other App")
        aerospace.windowsByWorkspace[workspace] = .success([ideWindow, chromeWindow, otherWindow])

        let positioner = StubWindowPositioner()
        let detector = StubScreenModeDetector()
        let manager = makeManager(aerospace: aerospace, positioner: positioner,
                                  screenModeDetector: detector)

        let result = manager.recoverWorkspaceWindows(workspace: workspace)

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }

        // Layout phase should have called setWindowFrames for VS Code and Chrome
        let setBundleIds = positioner.setFrameCalls.map { $0.bundleId }
        XCTAssertTrue(setBundleIds.contains("com.microsoft.VSCode"),
                      "Layout phase should position VS Code windows")
        XCTAssertTrue(setBundleIds.contains("com.google.Chrome"),
                      "Layout phase should position Chrome windows")

        // All setWindowFrames calls should use the correct projectId
        XCTAssertTrue(positioner.setFrameCalls.allSatisfy { $0.projectId == projectId },
                      "All layout calls should use derived projectId")

        // Generic recovery should only run for non-layout windows (the "other" app)
        let genericBundleIds = positioner.recoverCalls.map { $0.bundleId }
        XCTAssertEqual(genericBundleIds, ["com.other.App"],
                      "Generic recovery should skip IDE/Chrome (handled by layout)")

        // Processed = all workspace windows, recovered = layout (2 default) + generic (0 unchanged)
        XCTAssertEqual(recovery.windowsProcessed, 3)
        XCTAssertEqual(recovery.windowsRecovered, 2, "Layout phase positioned 2 windows (default stub result)")
    }

    func testRecoverWorkspace_projectWorkspace_onlyTargetsBundleIdsInWorkspace() {
        let aerospace = StubAeroSpace()
        let workspace = "ap-proj"

        // Only an IDE window in the workspace — no Chrome window
        let ideWindow = makeWindow(id: 1, bundleId: "com.microsoft.VSCode", workspace: workspace,
                                   title: "AP:proj - VS Code")
        aerospace.windowsByWorkspace[workspace] = .success([ideWindow])

        let positioner = StubWindowPositioner()
        let detector = StubScreenModeDetector()
        let manager = makeManager(aerospace: aerospace, positioner: positioner,
                                  screenModeDetector: detector)

        _ = manager.recoverWorkspaceWindows(workspace: workspace)

        // Layout should only call setWindowFrames for VS Code (present in workspace), not Chrome
        let setBundleIds = positioner.setFrameCalls.map { $0.bundleId }
        XCTAssertEqual(setBundleIds, ["com.microsoft.VSCode"],
                      "Layout phase should only target bundle IDs present in the workspace")
        XCTAssertFalse(setBundleIds.contains("com.google.Chrome"),
                       "Chrome is not in workspace — should not be targeted")
    }

    func testRecoverWorkspace_projectWorkspace_noLayoutApps_skipsLayoutPhase() {
        let aerospace = StubAeroSpace()
        let workspace = "ap-proj"

        // Only a non-IDE/Chrome app in the workspace
        let otherWindow = makeWindow(id: 1, bundleId: "com.other.App", workspace: workspace,
                                     title: "Other App")
        aerospace.windowsByWorkspace[workspace] = .success([otherWindow])

        let positioner = StubWindowPositioner()
        let detector = StubScreenModeDetector()
        let manager = makeManager(aerospace: aerospace, positioner: positioner,
                                  screenModeDetector: detector)

        let result = manager.recoverWorkspaceWindows(workspace: workspace)

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }

        // No setWindowFrames calls — no layout-eligible apps
        XCTAssertTrue(positioner.setFrameCalls.isEmpty,
                      "No IDE/Chrome in workspace — layout phase should be skipped")
        // Generic recovery should run for the other app
        XCTAssertEqual(positioner.recoverCalls.count, 1)
        XCTAssertEqual(recovery.windowsProcessed, 1)
    }

    func testRecoverWorkspace_projectWorkspace_noDetector_skipsLayoutPhase() {
        let aerospace = StubAeroSpace()
        let workspace = "ap-proj"
        let window = makeWindow(id: 1, bundleId: "com.microsoft.VSCode", workspace: workspace,
                                title: "AP:proj - VS Code")
        aerospace.windowsByWorkspace[workspace] = .success([window])

        let positioner = StubWindowPositioner()
        // No screenModeDetector — layout phase should be skipped
        let manager = makeManager(aerospace: aerospace, positioner: positioner)

        _ = manager.recoverWorkspaceWindows(workspace: workspace)

        // No setWindowFrames calls — layout phase skipped
        XCTAssertTrue(positioner.setFrameCalls.isEmpty,
                      "Without detector, layout phase should be skipped")
        // Generic recovery should still run
        XCTAssertEqual(positioner.recoverCalls.count, 1)
    }

    func testRecoverWorkspace_nonProjectWorkspace_skipsLayoutPhase() {
        let aerospace = StubAeroSpace()
        let workspace = "main"
        let window = makeWindow(id: 1, bundleId: "com.microsoft.VSCode", workspace: workspace,
                                title: "VS Code")
        aerospace.windowsByWorkspace[workspace] = .success([window])

        let positioner = StubWindowPositioner()
        let detector = StubScreenModeDetector()
        let manager = makeManager(aerospace: aerospace, positioner: positioner,
                                  screenModeDetector: detector)

        _ = manager.recoverWorkspaceWindows(workspace: workspace)

        // No setWindowFrames calls — non-project workspace
        XCTAssertTrue(positioner.setFrameCalls.isEmpty,
                      "Non-project workspace should not trigger layout phase")
        // Generic recovery runs
        XCTAssertEqual(positioner.recoverCalls.count, 1)
    }

    func testRecoverWorkspace_detectorFailure_usesWideFallbackAndWarns() {
        let aerospace = StubAeroSpace()
        let workspace = "ap-proj"
        let ideWindow = makeWindow(id: 1, bundleId: "com.microsoft.VSCode", workspace: workspace,
                                   title: "AP:proj - VS Code")
        aerospace.windowsByWorkspace[workspace] = .success([ideWindow])

        let positioner = StubWindowPositioner()
        var detector = StubScreenModeDetector()
        detector.mode = .failure(ApCoreError(category: .system, message: "EDID broken"))
        detector.physicalWidth = .failure(ApCoreError(category: .system, message: "width unknown"))

        let manager = makeManager(aerospace: aerospace, positioner: positioner,
                                  screenModeDetector: detector)

        let result = manager.recoverWorkspaceWindows(workspace: workspace)

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }

        // Layout should still run (with fallback values)
        XCTAssertFalse(positioner.setFrameCalls.isEmpty,
                       "Layout phase should still run with fallback values")

        // Warnings about detection failures should be surfaced
        XCTAssertTrue(recovery.errors.contains { $0.contains("screen mode") || $0.contains("EDID") },
                      "Detection failure should surface a warning: \(recovery.errors)")
        XCTAssertTrue(recovery.errors.contains { $0.contains("physical width") || $0.contains("width") },
                      "Width failure should surface a warning: \(recovery.errors)")
    }

    func testRecoverWorkspace_projectWorkspace_nonTokenWindowGetsGenericRecovery() {
        let aerospace = StubAeroSpace()
        let projectId = "myproj"
        let workspace = "ap-\(projectId)"

        // Token-matching VS Code window → handled by layout phase
        let tokenWindow = makeWindow(id: 1, bundleId: "com.microsoft.VSCode", workspace: workspace,
                                     title: "AP:\(projectId) - VS Code")
        // Same bundle but NO token (e.g., manually added) → should get generic recovery
        let extraWindow = makeWindow(id: 2, bundleId: "com.microsoft.VSCode", workspace: workspace,
                                     title: "Untitled - Visual Studio Code")
        aerospace.windowsByWorkspace[workspace] = .success([tokenWindow, extraWindow])

        let positioner = StubWindowPositioner()
        let detector = StubScreenModeDetector()
        let manager = makeManager(aerospace: aerospace, positioner: positioner,
                                  screenModeDetector: detector)

        let result = manager.recoverWorkspaceWindows(workspace: workspace)

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }

        // Layout phase should have called setWindowFrames for VS Code (token window)
        let setBundleIds = positioner.setFrameCalls.map { $0.bundleId }
        XCTAssertTrue(setBundleIds.contains("com.microsoft.VSCode"),
                      "Layout phase should position token-matching VS Code window")

        // Generic recovery should run for the extra (non-token) VS Code window
        let genericBundleIds = positioner.recoverCalls.map { $0.bundleId }
        XCTAssertEqual(genericBundleIds, ["com.microsoft.VSCode"],
                       "Non-token VS Code window should get generic recovery")

        // Both windows processed
        XCTAssertEqual(recovery.windowsProcessed, 2)
    }

    func testRecoverAll_doesNotUseLayoutPhase() {
        let aerospace = StubAeroSpace()
        let w1 = makeWindow(id: 1, bundleId: "com.microsoft.VSCode", workspace: "ap-proj",
                            title: "AP:proj - VS Code")
        setupWorkspaceWindows(aerospace, windows: [w1])

        let positioner = StubWindowPositioner()
        let detector = StubScreenModeDetector()
        let manager = makeManager(aerospace: aerospace, positioner: positioner,
                                  screenModeDetector: detector)

        _ = manager.recoverAllWindows { _, _ in }

        // recoverAllWindows should NOT use layout phase
        XCTAssertTrue(positioner.setFrameCalls.isEmpty,
                      "recoverAllWindows must not use layout phase")
        // Generic recovery should run
        XCTAssertEqual(positioner.recoverCalls.count, 1)
    }
}
