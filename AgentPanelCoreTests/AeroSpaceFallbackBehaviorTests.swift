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

// MARK: - installViaHomebrew

final class AeroSpaceInstallViaHomebrewTests: XCTestCase {
    func testInstallViaHomebrewSucceedsOnZeroExit() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.installViaHomebrew()

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls[0].executable, "brew")
    }

    func testInstallViaHomebrewFailsOnNonZeroExit() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 1, stdout: "", stderr: "boom"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.installViaHomebrew()

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertEqual(error.category, .command)
            XCTAssertTrue(error.message.contains("brew install --cask nikitabobko/tap/aerospace failed"))
        }
    }

    func testInstallViaHomebrewFailsWhenRunnerFails() {
        let runner = MockCommandRunner()
        runner.results = [
            .failure(ApCoreError(category: .command, message: "runner failed"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.installViaHomebrew()

        XCTAssertTrue(result.isFailure)
    }
}

// MARK: - reloadConfig

final class AeroSpaceReloadConfigTests: XCTestCase {
    func testReloadConfigSucceedsOnZeroExit() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.reloadConfig()

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls[0].arguments, ["reload-config"])
    }

    func testReloadConfigFailsOnNonZeroExit() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 1, stdout: "", stderr: "nope"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.reloadConfig()

        XCTAssertTrue(result.isFailure)
    }
}

// MARK: - start

final class AeroSpaceStartTests: XCTestCase {
    func testStartFailsOnMainThread() {
        let runner = MockCommandRunner()
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.start()

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertEqual(error.category, .command)
            XCTAssertEqual(error.message, "AeroSpace start must run off the main thread.")
        }
        XCTAssertEqual(runner.calls.count, 0)
    }

    func testStartReturnsFailureWhenOpenCommandFails() {
        let runner = MockCommandRunner()
        runner.results = [
            .failure(ApCoreError(category: .command, message: "open failed"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Void, ApCoreError>?
        var ranOnMainThread: Bool?
        DispatchQueue.global(qos: .userInitiated).async {
            ranOnMainThread = Thread.isMainThread
            result = aero.start()
            semaphore.signal()
        }
        let wait = semaphore.wait(timeout: .now() + 5)
        XCTAssertNotEqual(wait, .timedOut)
        XCTAssertEqual(ranOnMainThread, false)

        XCTAssertTrue(result?.isFailure ?? false)
        XCTAssertEqual(runner.calls.first?.executable, "open")
    }

    func testStartReturnsFailureOnNonZeroOpenExit() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 1, stdout: "", stderr: "cannot open"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Void, ApCoreError>?
        var ranOnMainThread: Bool?
        DispatchQueue.global(qos: .userInitiated).async {
            ranOnMainThread = Thread.isMainThread
            result = aero.start()
            semaphore.signal()
        }
        let wait = semaphore.wait(timeout: .now() + 5)
        XCTAssertNotEqual(wait, .timedOut)
        XCTAssertEqual(ranOnMainThread, false)

        XCTAssertTrue(result?.isFailure ?? false)
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls[0].executable, "open")
    }

    func testStartWaitsForReadinessAndSucceeds() {
        let runner = MockCommandRunner()
        runner.results = [
            // open -a AeroSpace succeeds
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")),
            // aerospace --help not ready
            .success(ApCommandResult(exitCode: 1, stdout: "", stderr: "")),
            // aerospace --help ready
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Void, ApCoreError>?
        var ranOnMainThread: Bool?
        DispatchQueue.global(qos: .userInitiated).async {
            ranOnMainThread = Thread.isMainThread
            result = aero.start()
            semaphore.signal()
        }
        let wait = semaphore.wait(timeout: .now() + 5)
        XCTAssertNotEqual(wait, .timedOut)
        XCTAssertEqual(ranOnMainThread, false)

        XCTAssertTrue(result?.isSuccess ?? false)
        XCTAssertEqual(runner.calls.count, 3)
        XCTAssertEqual(runner.calls[0].executable, "open")
        XCTAssertEqual(runner.calls[1].executable, "aerospace")
        XCTAssertEqual(runner.calls[2].executable, "aerospace")
    }
}

// MARK: - isCliAvailable

final class AeroSpaceCliAvailabilityTests: XCTestCase {
    func testIsCliAvailableFalseWhenRunnerFails() {
        let runner = MockCommandRunner()
        runner.results = [
            .failure(ApCoreError(category: .command, message: "no aerospace"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        XCTAssertFalse(aero.isCliAvailable())
    }

    func testIsCliAvailableFalseOnNonZeroExit() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 1, stdout: "", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        XCTAssertFalse(aero.isCliAvailable())
    }

    func testIsCliAvailableTrueOnZeroExit() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "usage", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        XCTAssertTrue(aero.isCliAvailable())
    }
}

// MARK: - checkCompatibility

final class AeroSpaceCompatibilityTests: XCTestCase {
    func testCheckCompatibilitySucceedsWhenAllFlagsPresent() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "--all --focused", stderr: "")),
            .success(ApCommandResult(exitCode: 0, stdout: "--monitor --workspace --focused --app-bundle-id --format", stderr: "")),
            .success(ApCommandResult(exitCode: 0, stdout: "ok", stderr: "")),
            .success(ApCommandResult(exitCode: 0, stdout: "--window-id", stderr: "")),
            .success(ApCommandResult(exitCode: 0, stdout: "--window-id", stderr: "")),
            .success(ApCommandResult(exitCode: 0, stdout: "--window-id", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.checkCompatibility()

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 6)
        XCTAssertEqual(runner.calls[0].arguments, ["list-workspaces", "--help"])
    }

    func testCheckCompatibilityFailsWhenFlagsMissing() {
        let runner = MockCommandRunner()
        runner.results = [
            // list-workspaces missing --focused
            .success(ApCommandResult(exitCode: 0, stdout: "--all", stderr: "")),
            // remaining checks can be empty
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")),
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")),
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")),
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")),
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.checkCompatibility()

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertEqual(error.category, .validation)
            XCTAssertEqual(error.message, "AeroSpace CLI compatibility check failed.")
            XCTAssertNotNil(error.detail)
        }
    }
}

// MARK: - Workspaces parsing

final class AeroSpaceWorkspacesTests: XCTestCase {
    func testListWorkspacesFocusedParsesLines() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "main\n\n ap-one \n", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.listWorkspacesFocused()

        switch result {
        case .failure(let error):
            XCTFail("Expected success, got: \(error)")
        case .success(let workspaces):
            XCTAssertEqual(workspaces, ["main", "ap-one"])
        }
    }

    func testGetWorkspacesFailsOnNonZeroExit() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 2, stdout: "", stderr: "bad"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.getWorkspaces()

        XCTAssertTrue(result.isFailure)
    }

    func testListWorkspacesWithFocusParsesSummaries() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "ap-one||true\nap-two||false\n", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.listWorkspacesWithFocus()

        switch result {
        case .failure(let error):
            XCTFail("Expected success, got: \(error)")
        case .success(let summaries):
            XCTAssertEqual(summaries, [
                ApWorkspaceSummary(workspace: "ap-one", isFocused: true),
                ApWorkspaceSummary(workspace: "ap-two", isFocused: false)
            ])
        }
    }

    func testListWorkspacesWithFocusFailsOnParseError() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "ap-one||maybe\n", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.listWorkspacesWithFocus()

        XCTAssertTrue(result.isFailure)
    }
}

// MARK: - createWorkspace / closeWorkspace

final class AeroSpaceWorkspaceLifecycleTests: XCTestCase {
    func testCreateWorkspaceFailsOnEmptyName() {
        let runner = MockCommandRunner()
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.createWorkspace("   ")

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 0)
    }

    func testCreateWorkspaceFailsWhenAlreadyExists() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "ap-test\n", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.createWorkspace("ap-test")

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 1)
    }

    func testCreateWorkspaceSummonsWhenMissing() {
        let runner = MockCommandRunner()
        runner.results = [
            // list-workspaces --all does not include ap-test
            .success(ApCommandResult(exitCode: 0, stdout: "main\n", stderr: "")),
            // summon-workspace succeeds
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.createWorkspace("ap-test")

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertEqual(runner.calls[1].arguments, ["summon-workspace", "ap-test"])
    }

    func testCloseWorkspaceAggregatesCloseFailures() {
        let runner = MockCommandRunner()
        runner.results = [
            // list-windows in workspace returns 2 windows
            .success(ApCommandResult(exitCode: 0, stdout: "1||app||ap-test||t\n2||app||ap-test||t\n", stderr: "")),
            // close window 1 succeeds
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")),
            // close window 2 fails
            .success(ApCommandResult(exitCode: 1, stdout: "", stderr: "no"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.closeWorkspace(name: "ap-test")

        XCTAssertTrue(result.isFailure)
    }
}

// MARK: - Windows parsing

final class AeroSpaceWindowsTests: XCTestCase {
    func testFocusedWindowSucceedsWhenExactlyOneFocusedWindow() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "42||app||main||title\n", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.focusedWindow()

        switch result {
        case .failure(let error):
            XCTFail("Expected success, got: \(error)")
        case .success(let window):
            XCTAssertEqual(window.windowId, 42)
        }
    }

    func testFocusedWindowFailsWhenZeroWindowsFocused() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.focusedWindow()

        XCTAssertTrue(result.isFailure)
    }

    func testListWindowsFocusedMonitorFailsOnParseError() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "not a window line\n", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.listWindowsFocusedMonitor()

        XCTAssertTrue(result.isFailure)
    }

    func testFocusWindowRejectsNonPositiveWindowId() {
        let runner = MockCommandRunner()
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.focusWindow(windowId: 0)

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 0)
    }

    func testFocusWindowReturnsFailureWhenRunnerFails() {
        let runner = MockCommandRunner()
        runner.results = [
            .failure(ApCoreError(category: .command, message: "runner failed"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.focusWindow(windowId: 42)

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls[0].arguments, ["focus", "--window-id", "42"])
    }

    func testFocusWindowReturnsFailureOnNonZeroExit() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 7, stdout: "", stderr: "bad"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.focusWindow(windowId: 42)

        XCTAssertTrue(result.isFailure)
    }

    func testFocusWindowSucceedsOnZeroExit() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.focusWindow(windowId: 42)

        XCTAssertTrue(result.isSuccess)
    }
}

final class AeroSpaceFocusedMonitorConvenienceTests: XCTestCase {

    func testListVSCodeWindowsOnFocusedMonitorUsesBundleIdFilter() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "1||com.microsoft.VSCode||main||title\n", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.listVSCodeWindowsOnFocusedMonitor()

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertTrue(runner.calls[0].arguments.contains("--app-bundle-id"))
        XCTAssertTrue(runner.calls[0].arguments.contains("com.microsoft.VSCode"))
    }

    func testListChromeWindowsOnFocusedMonitorUsesBundleIdFilter() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "2||com.google.Chrome||main||title\n", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.listChromeWindowsOnFocusedMonitor()

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertTrue(runner.calls[0].arguments.contains("--app-bundle-id"))
        XCTAssertTrue(runner.calls[0].arguments.contains("com.google.Chrome"))
    }
}

final class AeroSpaceHealthWrapperTests: XCTestCase {

    func testHealthInstallViaHomebrewReturnsTrueOnSuccess() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        XCTAssertTrue(aero.healthInstallViaHomebrew())
        XCTAssertEqual(runner.calls.first?.executable, "brew")
    }

    func testHealthInstallViaHomebrewReturnsFalseOnFailure() {
        let runner = MockCommandRunner()
        runner.results = [
            .failure(ApCoreError(category: .command, message: "brew failed"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        XCTAssertFalse(aero.healthInstallViaHomebrew())
    }

    func testHealthReloadConfigReturnsTrueOnSuccessAndFalseOnFailure() {
        do {
            let runner = MockCommandRunner()
            runner.results = [
                .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
            ]
            let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())
            XCTAssertTrue(aero.healthReloadConfig())
        }

        do {
            let runner = MockCommandRunner()
            runner.results = [
                .success(ApCommandResult(exitCode: 1, stdout: "", stderr: "bad"))
            ]
            let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())
            XCTAssertFalse(aero.healthReloadConfig())
        }
    }

    func testHealthStartReturnsFalseOnMainThreadAndTrueOffMainThread() {
        do {
            let runner = MockCommandRunner()
            let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())
            XCTAssertFalse(aero.healthStart())
            XCTAssertEqual(runner.calls.count, 0)
        }

        do {
            let runner = MockCommandRunner()
            runner.results = [
                // open -a AeroSpace succeeds
                .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")),
                // aerospace --help ready
                .success(ApCommandResult(exitCode: 0, stdout: "usage", stderr: ""))
            ]
            let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

            let semaphore = DispatchSemaphore(value: 0)
            var value: Bool?
            DispatchQueue.global(qos: .userInitiated).async {
                value = aero.healthStart()
                semaphore.signal()
            }
            let wait = semaphore.wait(timeout: .now() + 5)
            XCTAssertNotEqual(wait, .timedOut)
            XCTAssertEqual(value, true)
        }
    }
}

final class AeroSpaceWorkspacesWithFocusTests: XCTestCase {

    func testListWorkspacesWithFocusParsesSummaries() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "main||true\nap-one||false\n", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.listWorkspacesWithFocus()

        switch result {
        case .failure(let error):
            XCTFail("Expected success, got: \(error)")
        case .success(let summaries):
            XCTAssertEqual(summaries, [
                ApWorkspaceSummary(workspace: "main", isFocused: true),
                ApWorkspaceSummary(workspace: "ap-one", isFocused: false)
            ])
        }
    }

    func testListWorkspacesWithFocusFailsOnInvalidFocusToken() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "main||maybe\n", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.listWorkspacesWithFocus()

        XCTAssertTrue(result.isFailure)
    }

    func testListWorkspacesWithFocusFailsOnNonZeroExit() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 2, stdout: "", stderr: "bad"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.listWorkspacesWithFocus()

        XCTAssertTrue(result.isFailure)
    }

    func testListWorkspacesWithFocusFailsWhenRunnerFails() {
        let runner = MockCommandRunner()
        runner.results = [
            .failure(ApCoreError(category: .command, message: "runner failed"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.listWorkspacesWithFocus()

        XCTAssertTrue(result.isFailure)
    }
}

final class AeroSpaceWindowParsingErrorBranchTests: XCTestCase {

    func testListWindowsOnFocusedMonitorFailsWhenSecondSeparatorMissing() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "1||com.app\n", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.listWindowsOnFocusedMonitor(appBundleId: "com.app")

        XCTAssertTrue(result.isFailure)
    }

    func testListWindowsOnFocusedMonitorFailsWhenThirdSeparatorMissing() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "1||com.app||main\n", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.listWindowsOnFocusedMonitor(appBundleId: "com.app")

        XCTAssertTrue(result.isFailure)
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
