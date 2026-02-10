import XCTest
@testable import AgentPanelCore

/// Mock command runner that records all calls and returns scripted results.
///
/// Call sites append `(executable, arguments)` tuples to `calls` and receive
/// the next result from `results` in FIFO order. If `results` is exhausted
/// the mock returns a generic failure so the test notices.
private final class MockCommandRunner: CommandRunning {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
    }

    var calls: [Call] = []
    var results: [Result<ApCommandResult, ApCoreError>] = []

    func run(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval?,
        workingDirectory: String?
    ) -> Result<ApCommandResult, ApCoreError> {
        calls.append(Call(executable: executable, arguments: arguments))
        guard !results.isEmpty else {
            return .failure(ApCoreError(message: "MockCommandRunner: no results left"))
        }
        return results.removeFirst()
    }
}

/// Stub app discovery that always reports AeroSpace as not installed.
/// The fallback tests don't need app discovery.
private struct StubAppDiscovery: AppDiscovering {
    func applicationURL(bundleIdentifier: String) -> URL? { nil }
    func applicationURL(named appName: String) -> URL? { nil }
    func bundleIdentifier(forApplicationAt url: URL) -> String? { nil }
}

// MARK: - focusWorkspace fallback

final class AeroSpaceFocusWorkspaceFallbackTests: XCTestCase {

    func testFocusWorkspaceSucceedsWithSummonWorkspace() {
        let runner = MockCommandRunner()
        runner.results = [
            // summon-workspace succeeds
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.focusWorkspace(name: "ap-test")

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls[0].arguments, ["summon-workspace", "ap-test"])
    }

    func testFocusWorkspaceFallsBackToWorkspaceOnIncompatibility() {
        let runner = MockCommandRunner()
        runner.results = [
            // summon-workspace fails with compatibility error
            .success(ApCommandResult(exitCode: 1, stdout: "", stderr: "unknown command: summon-workspace")),
            // workspace fallback succeeds
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.focusWorkspace(name: "ap-test")

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertEqual(runner.calls[0].arguments, ["summon-workspace", "ap-test"])
        XCTAssertEqual(runner.calls[1].arguments, ["workspace", "ap-test"])
    }

    func testFocusWorkspaceDoesNotFallBackOnOperationalError() {
        let runner = MockCommandRunner()
        runner.results = [
            // summon-workspace fails with an operational error (not a compatibility issue)
            .success(ApCommandResult(exitCode: 1, stdout: "", stderr: "workspace 'ap-test' not found"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.focusWorkspace(name: "ap-test")

        XCTAssertTrue(result.isFailure)
        // Should NOT have attempted the fallback
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls[0].arguments, ["summon-workspace", "ap-test"])
    }
}

// MARK: - listWindowsForApp fallback

final class AeroSpaceListWindowsFallbackTests: XCTestCase {

    func testListWindowsForAppSucceedsWithGlobalSearch() {
        let runner = MockCommandRunner()
        runner.results = [
            // Global list-windows succeeds
            .success(ApCommandResult(
                exitCode: 0,
                stdout: "42||com.microsoft.VSCode||ap-test||AP:test - main.swift",
                stderr: ""
            ))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.listWindowsForApp(bundleId: "com.microsoft.VSCode")

        switch result {
        case .success(let windows):
            XCTAssertEqual(windows.count, 1)
            XCTAssertEqual(windows[0].windowId, 42)
        case .failure(let error):
            XCTFail("Expected success but got: \(error.message)")
        }
        XCTAssertEqual(runner.calls.count, 1)
        // Global search: no --monitor flag
        XCTAssertFalse(runner.calls[0].arguments.contains("--monitor"))
    }

    func testListWindowsForAppFallsBackToFocusedMonitorOnIncompatibility() {
        let runner = MockCommandRunner()
        runner.results = [
            // Global search fails — AeroSpace requires --monitor/--focused/--all/--workspace
            .success(ApCommandResult(exitCode: 1, stdout: "", stderr: "Mandatory option is not specified (--focused|--all|--monitor|--workspace)")),
            // Fallback to focused monitor succeeds
            .success(ApCommandResult(
                exitCode: 0,
                stdout: "42||com.microsoft.VSCode||ap-test||AP:test - main.swift",
                stderr: ""
            ))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.listWindowsForApp(bundleId: "com.microsoft.VSCode")

        switch result {
        case .success(let windows):
            XCTAssertEqual(windows.count, 1)
        case .failure(let error):
            XCTFail("Expected success but got: \(error.message)")
        }
        XCTAssertEqual(runner.calls.count, 2)
        // Second call should include --monitor focused
        XCTAssertTrue(runner.calls[1].arguments.contains("--monitor"))
        XCTAssertTrue(runner.calls[1].arguments.contains("focused"))
    }

    func testListWindowsForAppDoesNotFallBackOnOperationalError() {
        let runner = MockCommandRunner()
        runner.results = [
            // Global search fails with an operational error
            .success(ApCommandResult(exitCode: 1, stdout: "", stderr: "permission denied"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.listWindowsForApp(bundleId: "com.microsoft.VSCode")

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 1)
    }
}

// MARK: - moveWindowToWorkspace fallback

final class AeroSpaceMoveWindowFallbackTests: XCTestCase {

    func testMoveWindowSucceedsWithFocusFollows() {
        let runner = MockCommandRunner()
        runner.results = [
            // move-node-to-workspace --focus-follows-window succeeds
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.moveWindowToWorkspace(workspace: "ap-test", windowId: 42, focusFollows: true)

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertTrue(runner.calls[0].arguments.contains("--focus-follows-window"))
    }

    func testMoveWindowFallsBackToPlainMoveOnIncompatibility() {
        let runner = MockCommandRunner()
        runner.results = [
            // --focus-follows-window not supported
            .success(ApCommandResult(exitCode: 1, stdout: "", stderr: "unknown option '--focus-follows-window'")),
            // Plain move succeeds
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.moveWindowToWorkspace(workspace: "ap-test", windowId: 42, focusFollows: true)

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertTrue(runner.calls[0].arguments.contains("--focus-follows-window"))
        XCTAssertFalse(runner.calls[1].arguments.contains("--focus-follows-window"))
    }

    func testMoveWindowDoesNotFallBackOnOperationalError() {
        let runner = MockCommandRunner()
        runner.results = [
            // --focus-follows-window command fails with an operational error
            .success(ApCommandResult(exitCode: 1, stdout: "", stderr: "window 42 not found"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.moveWindowToWorkspace(workspace: "ap-test", windowId: 42, focusFollows: true)

        XCTAssertTrue(result.isFailure)
        // Should NOT have attempted the fallback
        XCTAssertEqual(runner.calls.count, 1)
    }

    func testMoveWindowWithoutFocusFollowsSkipsFallbackPath() {
        let runner = MockCommandRunner()
        runner.results = [
            // Plain move succeeds (no --focus-follows-window attempted)
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.moveWindowToWorkspace(workspace: "ap-test", windowId: 42, focusFollows: false)

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertFalse(runner.calls[0].arguments.contains("--focus-follows-window"))
    }
}

// MARK: - Result helpers

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
}
