import XCTest

@testable import AgentPanelCore

final class WindowCyclerTests: XCTestCase {

    // MARK: - Test Stub

    private final class StubAeroSpace: AeroSpaceProviding {
        var focusedWindowResult: Result<ApWindow, ApCoreError> = .failure(ApCoreError(message: "no focus"))
        var windowsByWorkspace: [String: [ApWindow]] = [:]
        var listWorkspaceResultOverride: Result<[ApWindow], ApCoreError>?
        var focusWindowCalls: [Int] = []
        var focusWindowResult: Result<Void, ApCoreError> = .success(())

        func focusedWindow() -> Result<ApWindow, ApCoreError> { focusedWindowResult }

        func listWindowsWorkspace(workspace: String) -> Result<[ApWindow], ApCoreError> {
            if let override = listWorkspaceResultOverride {
                return override
            }
            return .success(windowsByWorkspace[workspace] ?? [])
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

    func testCycleFocusFailsWhenListWorkspaceFails() {
        let stub = StubAeroSpace()
        stub.focusedWindowResult = .success(makeWindow(id: 1))
        stub.listWorkspaceResultOverride = .failure(ApCoreError(message: "workspace list failed"))

        let cycler = makeCycler(stub: stub)
        let result = cycler.cycleFocus(direction: .next)

        if case .success = result { XCTFail("Expected failure") }
    }

    // MARK: - Session Start

    func testStartSessionSelectsNextCandidate() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1), makeWindow(id: 2), makeWindow(id: 3)]
        stub.focusedWindowResult = .success(windows[0])
        stub.windowsByWorkspace["ap-test"] = windows

        let cycler = makeCycler(stub: stub)
        let result = cycler.startSession(direction: .next)

        guard case .success(let session?) = result else {
            XCTFail("Expected non-nil session")
            return
        }

        XCTAssertEqual(session.initialWindowId, 1)
        XCTAssertEqual(session.selectedCandidate.windowId, 2)
        XCTAssertEqual(session.candidates.map(\.windowId), [1, 2, 3])
    }

    func testStartSessionSelectsPreviousCandidate() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1), makeWindow(id: 2), makeWindow(id: 3)]
        stub.focusedWindowResult = .success(windows[0])
        stub.windowsByWorkspace["ap-test"] = windows

        let cycler = makeCycler(stub: stub)
        let result = cycler.startSession(direction: .previous)

        guard case .success(let session?) = result else {
            XCTFail("Expected non-nil session")
            return
        }

        XCTAssertEqual(session.initialWindowId, 1)
        XCTAssertEqual(session.selectedCandidate.windowId, 3)
    }

    func testStartSessionReturnsNilForSingleWindow() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1)]
        stub.focusedWindowResult = .success(windows[0])
        stub.windowsByWorkspace["ap-test"] = windows

        let cycler = makeCycler(stub: stub)
        let result = cycler.startSession(direction: .next)

        guard case .success(let session) = result else {
            XCTFail("Expected success")
            return
        }
        XCTAssertNil(session)
    }

    func testStartSessionReturnsNilForNoWindows() {
        let stub = StubAeroSpace()
        stub.focusedWindowResult = .success(makeWindow(id: 1))
        stub.windowsByWorkspace["ap-test"] = []

        let cycler = makeCycler(stub: stub)
        let result = cycler.startSession(direction: .next)

        guard case .success(let session) = result else {
            XCTFail("Expected success")
            return
        }
        XCTAssertNil(session)
    }

    func testStartSessionReturnsNilWhenFocusedNotInList() {
        let stub = StubAeroSpace()
        stub.focusedWindowResult = .success(makeWindow(id: 99))
        stub.windowsByWorkspace["ap-test"] = [makeWindow(id: 1), makeWindow(id: 2)]

        let cycler = makeCycler(stub: stub)
        let result = cycler.startSession(direction: .next)

        guard case .success(let session) = result else {
            XCTFail("Expected success")
            return
        }
        XCTAssertNil(session)
    }

    func testStartSessionFailsWhenFocusedWindowFails() {
        let stub = StubAeroSpace()
        stub.focusedWindowResult = .failure(ApCoreError(message: "no focused window"))

        let cycler = makeCycler(stub: stub)
        let result = cycler.startSession(direction: .next)

        if case .success = result { XCTFail("Expected failure") }
    }

    func testStartSessionFailsWhenListWorkspaceFails() {
        let stub = StubAeroSpace()
        stub.focusedWindowResult = .success(makeWindow(id: 1))
        stub.listWorkspaceResultOverride = .failure(ApCoreError(message: "workspace list failed"))

        let cycler = makeCycler(stub: stub)
        let result = cycler.startSession(direction: .next)

        if case .success = result { XCTFail("Expected failure") }
    }

    // MARK: - Session Advance

    func testAdvanceSelectionWrapsNext() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1), makeWindow(id: 2), makeWindow(id: 3)]
        stub.focusedWindowResult = .success(windows[0])
        stub.windowsByWorkspace["ap-test"] = windows

        let cycler = makeCycler(stub: stub)
        guard case .success(let initial?) = cycler.startSession(direction: .previous) else {
            XCTFail("Expected non-nil session")
            return
        }
        XCTAssertEqual(initial.selectedCandidate.windowId, 3)

        let advanced = cycler.advanceSelection(session: initial, direction: .next)
        XCTAssertEqual(advanced.selectedCandidate.windowId, 1)
    }

    func testAdvanceSelectionWrapsPrevious() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1), makeWindow(id: 2), makeWindow(id: 3)]
        stub.focusedWindowResult = .success(windows[0])
        stub.windowsByWorkspace["ap-test"] = windows

        let cycler = makeCycler(stub: stub)
        guard case .success(let initial?) = cycler.startSession(direction: .next) else {
            XCTFail("Expected non-nil session")
            return
        }
        XCTAssertEqual(initial.selectedCandidate.windowId, 2)

        let advanced = cycler.advanceSelection(session: initial, direction: .previous)
        XCTAssertEqual(advanced.selectedCandidate.windowId, 1)
    }

    // MARK: - Session Commit/Cancel

    func testCommitSelectionFocusesSelectedWindow() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1), makeWindow(id: 2), makeWindow(id: 3)]
        stub.focusedWindowResult = .success(windows[0])
        stub.windowsByWorkspace["ap-test"] = windows

        let cycler = makeCycler(stub: stub)
        guard case .success(let session?) = cycler.startSession(direction: .next) else {
            XCTFail("Expected non-nil session")
            return
        }

        let result = cycler.commitSelection(session: session)
        if case .failure(let error) = result { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(stub.focusWindowCalls, [2])
    }

    func testCommitSelectionFailsWhenFocusFails() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1), makeWindow(id: 2)]
        stub.focusedWindowResult = .success(windows[0])
        stub.windowsByWorkspace["ap-test"] = windows
        stub.focusWindowResult = .failure(ApCoreError(message: "focus failed"))

        let cycler = makeCycler(stub: stub)
        guard case .success(let session?) = cycler.startSession(direction: .next) else {
            XCTFail("Expected non-nil session")
            return
        }

        let result = cycler.commitSelection(session: session)
        if case .success = result { XCTFail("Expected failure") }
    }

    func testCancelSelectionRestoresInitialWindow() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1), makeWindow(id: 2)]
        stub.focusedWindowResult = .success(windows[0])
        stub.windowsByWorkspace["ap-test"] = windows

        let cycler = makeCycler(stub: stub)
        guard case .success(let session?) = cycler.startSession(direction: .next) else {
            XCTFail("Expected non-nil session")
            return
        }

        let result = cycler.cancelSession(session: session)
        if case .failure(let error) = result { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(stub.focusWindowCalls, [1])
    }

    func testCancelSelectionFailsWhenFocusFails() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1), makeWindow(id: 2)]
        stub.focusedWindowResult = .success(windows[0])
        stub.windowsByWorkspace["ap-test"] = windows
        stub.focusWindowResult = .failure(ApCoreError(message: "focus failed"))

        let cycler = makeCycler(stub: stub)
        guard case .success(let session?) = cycler.startSession(direction: .next) else {
            XCTFail("Expected non-nil session")
            return
        }

        let result = cycler.cancelSession(session: session)
        if case .success = result { XCTFail("Expected failure") }
    }

    // MARK: - cycleFocus returns candidate

    func testCycleFocusReturnsFocusedCandidate() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1), makeWindow(id: 2)]
        stub.focusedWindowResult = .success(windows[0])
        stub.windowsByWorkspace["ap-test"] = windows

        let cycler = makeCycler(stub: stub)
        let result = cycler.cycleFocus(direction: .next)

        guard case .success(let candidate?) = result else {
            XCTFail("Expected non-nil candidate")
            return
        }
        XCTAssertEqual(candidate.windowId, 2)
        XCTAssertEqual(candidate.appBundleId, "com.test.app2")
        XCTAssertEqual(candidate.windowTitle, "Window 2")
    }

    func testCycleFocusReturnsNilWhenSingleWindow() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1)]
        stub.focusedWindowResult = .success(windows[0])
        stub.windowsByWorkspace["ap-test"] = windows

        let cycler = makeCycler(stub: stub)
        let result = cycler.cycleFocus(direction: .next)

        guard case .success(let candidate) = result else {
            XCTFail("Expected success")
            return
        }
        XCTAssertNil(candidate, "Should return nil when no cycling occurred")
    }
}
