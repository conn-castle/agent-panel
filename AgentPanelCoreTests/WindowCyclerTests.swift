import XCTest

@testable import AgentPanelCore

final class WindowCyclerTests: XCTestCase {

    // MARK: - Test Stub

    private final class StubAeroSpace: AeroSpaceProviding {
        var focusedWindowResult: Result<ApWindow, ApCoreError> = .failure(ApCoreError(message: "no focus"))
        var windowsByWorkspace: [String: [ApWindow]] = [:]
        var focusWindowCalls: [Int] = []
        var focusWindowResult: Result<Void, ApCoreError> = .success(())

        func focusedWindow() -> Result<ApWindow, ApCoreError> { focusedWindowResult }

        func listWindowsWorkspace(workspace: String) -> Result<[ApWindow], ApCoreError> {
            .success(windowsByWorkspace[workspace] ?? [])
        }

        func focusWindow(windowId: Int) -> Result<Void, ApCoreError> {
            focusWindowCalls.append(windowId)
            return focusWindowResult
        }

        // Unused stubs required by protocol
        func getWorkspaces() -> Result<[String], ApCoreError> { .success([]) }
        func workspaceExists(_ name: String) -> Result<Bool, ApCoreError> { .success(false) }
        func listWorkspacesFocused() -> Result<[String], ApCoreError> { .success([]) }
        func listWorkspacesWithFocus() -> Result<[ApWorkspaceSummary], ApCoreError> { .success([]) }
        func createWorkspace(_ name: String) -> Result<Void, ApCoreError> { .success(()) }
        func closeWorkspace(name: String) -> Result<Void, ApCoreError> { .success(()) }
        func listWindowsForApp(bundleId: String) -> Result<[ApWindow], ApCoreError> { .success([]) }
        func listAllWindows() -> Result<[ApWindow], ApCoreError> { .success([]) }
        func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool) -> Result<Void, ApCoreError> { .success(()) }
        func focusWorkspace(name: String) -> Result<Void, ApCoreError> { .success(()) }
    }

    // MARK: - Helpers

    private func makeWindow(id: Int, workspace: String = "ap-test") -> ApWindow {
        ApWindow(windowId: id, appBundleId: "com.test.app\(id)", workspace: workspace, windowTitle: "Window \(id)")
    }

    private func makeCycler(stub: StubAeroSpace) -> WindowCycler {
        WindowCycler(aerospace: stub)
    }

    // MARK: - Next Direction

    func testCycleFocusNextWrapsAround() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1), makeWindow(id: 2), makeWindow(id: 3)]
        stub.focusedWindowResult = .success(windows[2]) // focused on last
        stub.windowsByWorkspace["ap-test"] = windows

        let cycler = makeCycler(stub: stub)
        let result = cycler.cycleFocus(direction: .next)

        if case .failure(let error) = result { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(stub.focusWindowCalls, [1]) // wraps to first
    }

    func testCycleFocusNextMiddle() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1), makeWindow(id: 2), makeWindow(id: 3)]
        stub.focusedWindowResult = .success(windows[1]) // focused on #2
        stub.windowsByWorkspace["ap-test"] = windows

        let cycler = makeCycler(stub: stub)
        let result = cycler.cycleFocus(direction: .next)

        if case .failure(let error) = result { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(stub.focusWindowCalls, [3]) // moves to #3
    }

    // MARK: - Previous Direction

    func testCycleFocusPreviousWrapsAround() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1), makeWindow(id: 2), makeWindow(id: 3)]
        stub.focusedWindowResult = .success(windows[0]) // focused on first
        stub.windowsByWorkspace["ap-test"] = windows

        let cycler = makeCycler(stub: stub)
        let result = cycler.cycleFocus(direction: .previous)

        if case .failure(let error) = result { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(stub.focusWindowCalls, [3]) // wraps to last
    }

    func testCycleFocusPreviousMiddle() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1), makeWindow(id: 2), makeWindow(id: 3)]
        stub.focusedWindowResult = .success(windows[1]) // focused on #2
        stub.windowsByWorkspace["ap-test"] = windows

        let cycler = makeCycler(stub: stub)
        let result = cycler.cycleFocus(direction: .previous)

        if case .failure(let error) = result { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(stub.focusWindowCalls, [1]) // moves to #1
    }

    // MARK: - Edge Cases

    func testCycleFocusSkipsSingleWindow() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1)]
        stub.focusedWindowResult = .success(windows[0])
        stub.windowsByWorkspace["ap-test"] = windows

        let cycler = makeCycler(stub: stub)
        let result = cycler.cycleFocus(direction: .next)

        if case .failure(let error) = result { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(stub.focusWindowCalls.isEmpty)
    }

    func testCycleFocusSkipsNoWindows() {
        let stub = StubAeroSpace()
        let focused = makeWindow(id: 1)
        stub.focusedWindowResult = .success(focused)
        stub.windowsByWorkspace["ap-test"] = []

        let cycler = makeCycler(stub: stub)
        let result = cycler.cycleFocus(direction: .next)

        if case .failure(let error) = result { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(stub.focusWindowCalls.isEmpty)
    }

    func testCycleFocusHandlesFocusedNotInList() {
        let stub = StubAeroSpace()
        let focused = makeWindow(id: 99) // not in the workspace list
        stub.focusedWindowResult = .success(focused)
        stub.windowsByWorkspace["ap-test"] = [makeWindow(id: 1), makeWindow(id: 2)]

        let cycler = makeCycler(stub: stub)
        let result = cycler.cycleFocus(direction: .next)

        if case .failure(let error) = result { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(stub.focusWindowCalls.isEmpty)
    }

    // MARK: - Error Propagation

    func testCycleFocusFailsWhenFocusedWindowFails() {
        let stub = StubAeroSpace()
        stub.focusedWindowResult = .failure(ApCoreError(message: "no focused window"))

        let cycler = makeCycler(stub: stub)
        let result = cycler.cycleFocus(direction: .next)

        if case .success = result { XCTFail("Expected failure") }
    }

    func testCycleFocusFailsWhenFocusWindowFails() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1), makeWindow(id: 2)]
        stub.focusedWindowResult = .success(windows[0])
        stub.windowsByWorkspace["ap-test"] = windows
        stub.focusWindowResult = .failure(ApCoreError(message: "focus failed"))

        let cycler = makeCycler(stub: stub)
        let result = cycler.cycleFocus(direction: .next)

        if case .success = result { XCTFail("Expected failure") }
    }
}
