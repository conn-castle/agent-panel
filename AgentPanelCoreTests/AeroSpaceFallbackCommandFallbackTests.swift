import XCTest
@testable import AgentPanelCore

final class AeroSpaceAppPathTests: XCTestCase {
    func testAppPathPrefersLaunchServicesResult() {
        let discovery = FallbackStubBundleURLAppDiscovery(
            bundleURL: URL(fileURLWithPath: "/Applications/Custom/AeroSpace.app", isDirectory: true)
        )
        let fileSystem = FallbackStubLegacyDirectoryFileSystem(existingDirectories: [])
        let aero = ApAeroSpace(commandRunner: FallbackMockCommandRunner(), appDiscovery: discovery, fileSystem: fileSystem)

        XCTAssertEqual(aero.appPath, "/Applications/Custom/AeroSpace.app")
    }

    func testAppPathFallsBackToLegacyDirectoryWhenLaunchServicesHasNoMatch() {
        let discovery = FallbackStubBundleURLAppDiscovery(bundleURL: nil)
        let fileSystem = FallbackStubLegacyDirectoryFileSystem(existingDirectories: ["/Applications/AeroSpace.app"])
        let aero = ApAeroSpace(commandRunner: FallbackMockCommandRunner(), appDiscovery: discovery, fileSystem: fileSystem)

        XCTAssertEqual(aero.appPath, "/Applications/AeroSpace.app")
        XCTAssertTrue(aero.isAppInstalled())
    }

    func testAppPathReturnsNilWhenNoInstallLocationExists() {
        let discovery = FallbackStubBundleURLAppDiscovery(bundleURL: nil)
        let fileSystem = FallbackStubLegacyDirectoryFileSystem(existingDirectories: [])
        let aero = ApAeroSpace(commandRunner: FallbackMockCommandRunner(), appDiscovery: discovery, fileSystem: fileSystem)

        XCTAssertNil(aero.appPath)
        XCTAssertFalse(aero.isAppInstalled())
    }
}

// MARK: - focusWorkspace fallback

final class AeroSpaceFocusWorkspaceFallbackTests: XCTestCase {

    func testFocusWorkspaceSucceedsWithSummonWorkspace() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            // summon-workspace succeeds
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.focusWorkspace(name: "ap-test")

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls[0].arguments, ["summon-workspace", "ap-test"])
    }

    func testFocusWorkspaceFallsBackToWorkspaceOnIncompatibility() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            // summon-workspace fails with compatibility error
            .success(ApCommandResult(exitCode: 1, stdout: "", stderr: "unknown command: summon-workspace")),
            // workspace fallback succeeds
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.focusWorkspace(name: "ap-test")

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertEqual(runner.calls[0].arguments, ["summon-workspace", "ap-test"])
        XCTAssertEqual(runner.calls[1].arguments, ["workspace", "ap-test"])
    }

    func testFocusWorkspaceDoesNotFallBackOnOperationalError() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            // summon-workspace fails with an operational error (not a compatibility issue)
            .success(ApCommandResult(exitCode: 1, stdout: "", stderr: "workspace 'ap-test' not found"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.focusWorkspace(name: "ap-test")

        XCTAssertTrue(result.isFailure)
        // Should NOT have attempted the fallback
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls[0].arguments, ["summon-workspace", "ap-test"])
    }

    func testFocusWorkspaceRejectsEmptyName() {
        let runner = FallbackMockCommandRunner()
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.focusWorkspace(name: "   ")

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 0)
    }

    func testFocusWorkspaceFallbackPropagatesRunnerFailure() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 1, stdout: "", stderr: "unknown command: summon-workspace")),
            .failure(ApCoreError(category: .command, message: "workspace command failed"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.focusWorkspace(name: "ap-test")

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertEqual(runner.calls[1].arguments, ["workspace", "ap-test"])
    }

    func testFocusWorkspaceFallbackReturnsFailureOnNonZeroExit() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 1, stdout: "", stderr: "unknown command: summon-workspace")),
            .success(ApCommandResult(exitCode: 2, stdout: "", stderr: "workspace missing"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.focusWorkspace(name: "ap-test")

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertEqual(runner.calls[1].arguments, ["workspace", "ap-test"])
    }
}

// MARK: - listWindowsForApp fallback

final class AeroSpaceListWindowsFallbackTests: XCTestCase {

    func testListWindowsForAppSucceedsWithGlobalSearch() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            // Global list-windows succeeds
            .success(ApCommandResult(
                exitCode: 0,
                stdout: "42||com.microsoft.VSCode||ap-test||AP:test - main.swift",
                stderr: ""
            ))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

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
        let runner = FallbackMockCommandRunner()
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
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

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
        let runner = FallbackMockCommandRunner()
        runner.results = [
            // Global search fails with an operational error
            .success(ApCommandResult(exitCode: 1, stdout: "", stderr: "permission denied"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.listWindowsForApp(bundleId: "com.microsoft.VSCode")

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 1)
    }

    func testListWindowsForAppPropagatesRunnerFailureWithoutFallback() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .failure(ApCoreError(category: .command, message: "runner unavailable"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.listWindowsForApp(bundleId: "com.microsoft.VSCode")

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 1)
    }
}

// MARK: - moveWindowToWorkspace fallback

final class AeroSpaceMoveWindowFallbackTests: XCTestCase {

    func testMoveWindowSucceedsWithFocusFollows() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            // move-node-to-workspace --focus-follows-window succeeds
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.moveWindowToWorkspace(workspace: "ap-test", windowId: 42, focusFollows: true)

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertTrue(runner.calls[0].arguments.contains("--focus-follows-window"))
    }

    func testMoveWindowFallsBackToPlainMoveOnIncompatibility() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            // --focus-follows-window not supported
            .success(ApCommandResult(exitCode: 1, stdout: "", stderr: "unknown option '--focus-follows-window'")),
            // Plain move succeeds
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.moveWindowToWorkspace(workspace: "ap-test", windowId: 42, focusFollows: true)

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertTrue(runner.calls[0].arguments.contains("--focus-follows-window"))
        XCTAssertFalse(runner.calls[1].arguments.contains("--focus-follows-window"))
    }

    func testMoveWindowDoesNotFallBackOnOperationalError() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            // --focus-follows-window command fails with an operational error
            .success(ApCommandResult(exitCode: 1, stdout: "", stderr: "window 42 not found"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.moveWindowToWorkspace(workspace: "ap-test", windowId: 42, focusFollows: true)

        XCTAssertTrue(result.isFailure)
        // Should NOT have attempted the fallback
        XCTAssertEqual(runner.calls.count, 1)
    }

    func testMoveWindowWithoutFocusFollowsSkipsFallbackPath() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            // Plain move succeeds (no --focus-follows-window attempted)
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.moveWindowToWorkspace(workspace: "ap-test", windowId: 42, focusFollows: false)

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertFalse(runner.calls[0].arguments.contains("--focus-follows-window"))
    }

    func testMoveWindowRejectsEmptyWorkspaceName() {
        let runner = FallbackMockCommandRunner()
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.moveWindowToWorkspace(workspace: " ", windowId: 42, focusFollows: false)

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 0)
    }

    func testMoveWindowRejectsNonPositiveWindowId() {
        let runner = FallbackMockCommandRunner()
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.moveWindowToWorkspace(workspace: "ap-test", windowId: 0, focusFollows: false)

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 0)
    }

    func testMoveWindowFocusFollowsPropagatesRunnerFailure() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .failure(ApCoreError(category: .command, message: "runner failed"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.moveWindowToWorkspace(workspace: "ap-test", windowId: 42, focusFollows: true)

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertTrue(runner.calls[0].arguments.contains("--focus-follows-window"))
    }

    func testMoveWindowWithoutFocusFollowsPropagatesRunnerFailure() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .failure(ApCoreError(category: .command, message: "runner failed"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.moveWindowToWorkspace(workspace: "ap-test", windowId: 42, focusFollows: false)

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 1)
    }

    func testMoveWindowWithoutFocusFollowsFailsOnNonZeroExit() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 5, stdout: "", stderr: "bad move"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.moveWindowToWorkspace(workspace: "ap-test", windowId: 42, focusFollows: false)

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 1)
    }
}

