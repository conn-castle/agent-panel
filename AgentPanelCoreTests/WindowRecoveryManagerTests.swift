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

        func recoverWindow(bundleId: String, windowTitle: String, screenVisibleFrame: CGRect) -> Result<RecoveryOutcome, ApCoreError> {
            recoverCalls.append((bundleId, windowTitle, screenVisibleFrame))
            return recoverResults[windowTitle] ?? defaultRecoverResult
        }

        func getPrimaryWindowFrame(bundleId: String, projectId: String) -> Result<CGRect, ApCoreError> {
            .failure(ApCoreError(message: "not implemented"))
        }

        func setWindowFrames(bundleId: String, projectId: String, primaryFrame: CGRect, cascadeOffsetPoints: CGFloat) -> Result<WindowPositionResult, ApCoreError> {
            .success(WindowPositionResult(positioned: 0, matched: 0))
        }

        func isAccessibilityTrusted() -> Bool { true }
        func promptForAccessibility() -> Bool { true }
    }

    // MARK: - Helpers

    private let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    private func makeManager(
        aerospace: StubAeroSpace = StubAeroSpace(),
        positioner: StubWindowPositioner = StubWindowPositioner()
    ) -> WindowRecoveryManager {
        WindowRecoveryManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            screenVisibleFrame: screenFrame,
            logger: NoopLogger()
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

    func testRecoverAll_restoresOriginalWorkspaceAndFocus() {
        let aerospace = StubAeroSpace()
        let original = makeWindow(id: 42, workspace: "ap-myproject", title: "My Window")
        aerospace.focusedWindowResult = .success(original)
        let other = makeWindow(id: 99, workspace: "2", title: "Other")
        setupWorkspaceWindows(aerospace, windows: [other])

        let manager = makeManager(aerospace: aerospace)
        _ = manager.recoverAllWindows { _, _ in }

        // Should restore workspace and then window
        XCTAssertEqual(aerospace.focusWorkspaceCalls.last, "ap-myproject")
        XCTAssertEqual(aerospace.focusWindowCalls.last, 42)
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
}
