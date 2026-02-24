import XCTest
@testable import AgentPanelCore

/// Thread-safe mock command runner that records all calls and returns scripted results.
///
/// Supports two modes:
/// - **FIFO mode** (default): Call sites receive the next result from `results` in FIFO order.
/// - **Keyed mode**: When `keyedResults` is populated, results are returned by matching
///   the first argument (e.g., `"list-workspaces"`) against the key. Use for concurrent tests
///   where call order is non-deterministic.
///
/// Thread-safe for concurrent access via NSLock.
private final class MockCommandRunner: CommandRunning {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
    }

    private let lock = NSLock()
    private(set) var calls: [Call] = []
    var results: [Result<ApCommandResult, ApCoreError>] = []
    var keyedResults: [String: Result<ApCommandResult, ApCoreError>] = [:]

    func run(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval?,
        workingDirectory: String?
    ) -> Result<ApCommandResult, ApCoreError> {
        lock.lock()
        calls.append(Call(executable: executable, arguments: arguments))

        // Keyed mode: match by first argument (command name)
        if !keyedResults.isEmpty, let firstArg = arguments.first,
           let result = keyedResults[firstArg] {
            lock.unlock()
            return result
        }

        // FIFO mode
        guard !results.isEmpty else {
            lock.unlock()
            return .failure(ApCoreError(message: "MockCommandRunner: no results left"))
        }
        let result = results.removeFirst()
        lock.unlock()
        return result
    }
}

/// Stub app discovery that always reports AeroSpace as not installed.
/// The fallback tests don't need app discovery.
private struct StubAppDiscovery: AppDiscovering {
    func applicationURL(bundleIdentifier: String) -> URL? { nil }
    func applicationURL(named appName: String) -> URL? { nil }
    func bundleIdentifier(forApplicationAt url: URL) -> String? { nil }
}

private struct StubBundleURLAppDiscovery: AppDiscovering {
    let bundleURL: URL?

    func applicationURL(bundleIdentifier: String) -> URL? { bundleURL }
    func applicationURL(named appName: String) -> URL? { nil }
    func bundleIdentifier(forApplicationAt url: URL) -> String? { nil }
}

private struct StubLegacyDirectoryFileSystem: FileSystem {
    let existingDirectories: Set<String>

    func fileExists(at url: URL) -> Bool { false }

    func directoryExists(at url: URL) -> Bool {
        existingDirectories.contains(url.path)
    }

    func isExecutableFile(at url: URL) -> Bool { false }
    func readFile(at url: URL) throws -> Data { Data() }
    func createDirectory(at url: URL) throws {}
    func fileSize(at url: URL) throws -> UInt64 { 0 }
    func removeItem(at url: URL) throws {}
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {}
    func appendFile(at url: URL, data: Data) throws {}
    func writeFile(at url: URL, data: Data) throws {}
}

final class AeroSpaceAppPathTests: XCTestCase {
    func testAppPathPrefersLaunchServicesResult() {
        let discovery = StubBundleURLAppDiscovery(
            bundleURL: URL(fileURLWithPath: "/Applications/Custom/AeroSpace.app", isDirectory: true)
        )
        let fileSystem = StubLegacyDirectoryFileSystem(existingDirectories: [])
        let aero = ApAeroSpace(commandRunner: MockCommandRunner(), appDiscovery: discovery, fileSystem: fileSystem)

        XCTAssertEqual(aero.appPath, "/Applications/Custom/AeroSpace.app")
    }

    func testAppPathFallsBackToLegacyDirectoryWhenLaunchServicesHasNoMatch() {
        let discovery = StubBundleURLAppDiscovery(bundleURL: nil)
        let fileSystem = StubLegacyDirectoryFileSystem(existingDirectories: ["/Applications/AeroSpace.app"])
        let aero = ApAeroSpace(commandRunner: MockCommandRunner(), appDiscovery: discovery, fileSystem: fileSystem)

        XCTAssertEqual(aero.appPath, "/Applications/AeroSpace.app")
        XCTAssertTrue(aero.isAppInstalled())
    }

    func testAppPathReturnsNilWhenNoInstallLocationExists() {
        let discovery = StubBundleURLAppDiscovery(bundleURL: nil)
        let fileSystem = StubLegacyDirectoryFileSystem(existingDirectories: [])
        let aero = ApAeroSpace(commandRunner: MockCommandRunner(), appDiscovery: discovery, fileSystem: fileSystem)

        XCTAssertNil(aero.appPath)
        XCTAssertFalse(aero.isAppInstalled())
    }
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

    func testFocusWorkspaceRejectsEmptyName() {
        let runner = MockCommandRunner()
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.focusWorkspace(name: "   ")

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 0)
    }

    func testFocusWorkspaceFallbackPropagatesRunnerFailure() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 1, stdout: "", stderr: "unknown command: summon-workspace")),
            .failure(ApCoreError(category: .command, message: "workspace command failed"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.focusWorkspace(name: "ap-test")

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertEqual(runner.calls[1].arguments, ["workspace", "ap-test"])
    }

    func testFocusWorkspaceFallbackReturnsFailureOnNonZeroExit() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 1, stdout: "", stderr: "unknown command: summon-workspace")),
            .success(ApCommandResult(exitCode: 2, stdout: "", stderr: "workspace missing"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.focusWorkspace(name: "ap-test")

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertEqual(runner.calls[1].arguments, ["workspace", "ap-test"])
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

    func testListWindowsForAppPropagatesRunnerFailureWithoutFallback() {
        let runner = MockCommandRunner()
        runner.results = [
            .failure(ApCoreError(category: .command, message: "runner unavailable"))
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

    func testMoveWindowRejectsEmptyWorkspaceName() {
        let runner = MockCommandRunner()
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.moveWindowToWorkspace(workspace: " ", windowId: 42, focusFollows: false)

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 0)
    }

    func testMoveWindowRejectsNonPositiveWindowId() {
        let runner = MockCommandRunner()
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.moveWindowToWorkspace(workspace: "ap-test", windowId: 0, focusFollows: false)

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 0)
    }

    func testMoveWindowFocusFollowsPropagatesRunnerFailure() {
        let runner = MockCommandRunner()
        runner.results = [
            .failure(ApCoreError(category: .command, message: "runner failed"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.moveWindowToWorkspace(workspace: "ap-test", windowId: 42, focusFollows: true)

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertTrue(runner.calls[0].arguments.contains("--focus-follows-window"))
    }

    func testMoveWindowWithoutFocusFollowsPropagatesRunnerFailure() {
        let runner = MockCommandRunner()
        runner.results = [
            .failure(ApCoreError(category: .command, message: "runner failed"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.moveWindowToWorkspace(workspace: "ap-test", windowId: 42, focusFollows: false)

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 1)
    }

    func testMoveWindowWithoutFocusFollowsFailsOnNonZeroExit() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 5, stdout: "", stderr: "bad move"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.moveWindowToWorkspace(workspace: "ap-test", windowId: 42, focusFollows: false)

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 1)
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

    func testReloadConfigFailsWhenRunnerFails() {
        let runner = MockCommandRunner()
        runner.results = [
            .failure(ApCoreError(category: .command, message: "runner failed"))
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

    func testStartReturnsFailureWhenReadinessTimesOut() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Void, ApCoreError>?
        DispatchQueue.global(qos: .userInitiated).async {
            result = aero.start()
            semaphore.signal()
        }

        let wait = semaphore.wait(timeout: .now() + 15)
        XCTAssertNotEqual(wait, .timedOut)
        switch result {
        case .success:
            XCTFail("Expected startup timeout failure")
        case .failure(let error):
            XCTAssertTrue(error.message.contains("did not become ready"))
        case .none:
            XCTFail("Expected result")
        }
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
        // Use keyed results: concurrent execution means FIFO order is non-deterministic
        runner.keyedResults = [
            "list-workspaces": .success(ApCommandResult(exitCode: 0, stdout: "--all --focused", stderr: "")),
            "list-windows": .success(ApCommandResult(exitCode: 0, stdout: "--monitor --workspace --focused --app-bundle-id --format", stderr: "")),
            "summon-workspace": .success(ApCommandResult(exitCode: 0, stdout: "ok", stderr: "")),
            "move-node-to-workspace": .success(ApCommandResult(exitCode: 0, stdout: "--window-id", stderr: "")),
            "focus": .success(ApCommandResult(exitCode: 0, stdout: "--window-id --boundaries --boundaries-action dfs-next dfs-prev", stderr: "")),
            "close": .success(ApCommandResult(exitCode: 0, stdout: "--window-id", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.checkCompatibility()

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 6)
    }

    func testCheckCompatibilityAcceptsFlagsFromStdoutAndStderr() {
        let runner = MockCommandRunner()
        runner.keyedResults = [
            "list-workspaces": .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "--all --focused")),
            "list-windows": .success(ApCommandResult(exitCode: 0, stdout: "--monitor", stderr: "--workspace --focused --app-bundle-id --format")),
            "summon-workspace": .success(ApCommandResult(exitCode: 0, stdout: "ok", stderr: "")),
            "move-node-to-workspace": .success(ApCommandResult(exitCode: 0, stdout: "--window-id", stderr: "")),
            "focus": .success(ApCommandResult(exitCode: 0, stdout: "--window-id --boundaries dfs-next", stderr: "--boundaries-action dfs-prev")),
            "close": .success(ApCommandResult(exitCode: 0, stdout: "--window-id", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.checkCompatibility()

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 6)
    }

    func testCheckCompatibilityFailsWhenFlagsMissing() {
        let runner = MockCommandRunner()
        runner.keyedResults = [
            "list-workspaces": .success(ApCommandResult(exitCode: 0, stdout: "--all", stderr: "")),
            "list-windows": .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")),
            "summon-workspace": .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")),
            "move-node-to-workspace": .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")),
            "focus": .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")),
            "close": .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
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

    func testCheckCompatibilityFailsWhenHelpCommandRunnerFails() {
        let runner = MockCommandRunner()
        runner.keyedResults = [
            "list-workspaces": .success(ApCommandResult(exitCode: 0, stdout: "--all --focused", stderr: "")),
            "list-windows": .success(ApCommandResult(exitCode: 0, stdout: "--monitor --workspace --focused --app-bundle-id --format", stderr: "")),
            "summon-workspace": .success(ApCommandResult(exitCode: 0, stdout: "ok", stderr: "")),
            "move-node-to-workspace": .success(ApCommandResult(exitCode: 0, stdout: "--window-id", stderr: "")),
            "focus": .success(ApCommandResult(exitCode: 0, stdout: "--window-id --boundaries --boundaries-action dfs-next dfs-prev", stderr: "")),
            "close": .failure(ApCoreError(category: .command, message: "runner failed"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.checkCompatibility()

        XCTAssertTrue(result.isFailure)
        if case .failure(let error) = result {
            XCTAssertTrue(error.detail?.contains("aerospace close --help failed: runner failed") ?? false)
        }
    }

    func testCheckCompatibilityFailsWhenHelpCommandExitsNonZero() {
        let runner = MockCommandRunner()
        runner.keyedResults = [
            "list-workspaces": .success(ApCommandResult(exitCode: 0, stdout: "--all --focused", stderr: "")),
            "list-windows": .success(ApCommandResult(exitCode: 0, stdout: "--monitor --workspace --focused --app-bundle-id --format", stderr: "")),
            "summon-workspace": .success(ApCommandResult(exitCode: 0, stdout: "ok", stderr: "")),
            "move-node-to-workspace": .success(ApCommandResult(exitCode: 0, stdout: "--window-id", stderr: "")),
            "focus": .success(ApCommandResult(exitCode: 0, stdout: "--window-id --boundaries --boundaries-action dfs-next dfs-prev", stderr: "")),
            "close": .success(ApCommandResult(exitCode: 2, stdout: "", stderr: "unknown option"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.checkCompatibility()

        XCTAssertTrue(result.isFailure)
        if case .failure(let error) = result {
            XCTAssertTrue(error.detail?.contains("aerospace close --help failed") ?? false)
        }
    }

    func testCheckCompatibilityFailureDetailIsSorted() {
        let runner = MockCommandRunner()
        // Two commands fail: "close" (alphabetically first) and "list-workspaces"
        runner.keyedResults = [
            "list-workspaces": .success(ApCommandResult(exitCode: 0, stdout: "--all", stderr: "")),
            "list-windows": .success(ApCommandResult(exitCode: 0, stdout: "--monitor --workspace --focused --app-bundle-id --format", stderr: "")),
            "summon-workspace": .success(ApCommandResult(exitCode: 0, stdout: "ok", stderr: "")),
            "move-node-to-workspace": .success(ApCommandResult(exitCode: 0, stdout: "--window-id", stderr: "")),
            "focus": .success(ApCommandResult(exitCode: 0, stdout: "--window-id --boundaries --boundaries-action dfs-next dfs-prev", stderr: "")),
            "close": .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.checkCompatibility()

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            let lines = error.detail?.components(separatedBy: "\n") ?? []
            XCTAssertEqual(lines.count, 2)
            // Sorted: "close" before "list-workspaces"
            XCTAssertTrue(lines[0].contains("close"), "First failure should be 'close' (alphabetical)")
            XCTAssertTrue(lines[1].contains("list-workspaces"), "Second failure should be 'list-workspaces' (alphabetical)")
        }
    }

    func testCheckCompatibilityConcurrentCallsAreAllRecorded() {
        // Run compatibility check multiple times to exercise thread-safety
        for _ in 0..<10 {
            let runner = MockCommandRunner()
            runner.keyedResults = [
                "list-workspaces": .success(ApCommandResult(exitCode: 0, stdout: "--all --focused", stderr: "")),
                "list-windows": .success(ApCommandResult(exitCode: 0, stdout: "--monitor --workspace --focused --app-bundle-id --format", stderr: "")),
                "summon-workspace": .success(ApCommandResult(exitCode: 0, stdout: "ok", stderr: "")),
                "move-node-to-workspace": .success(ApCommandResult(exitCode: 0, stdout: "--window-id", stderr: "")),
                "focus": .success(ApCommandResult(exitCode: 0, stdout: "--window-id --boundaries --boundaries-action dfs-next dfs-prev", stderr: "")),
                "close": .success(ApCommandResult(exitCode: 0, stdout: "--window-id", stderr: ""))
            ]
            let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

            let result = aero.checkCompatibility()

            XCTAssertTrue(result.isSuccess, "Iteration should succeed")
            // All 6 commands should be recorded regardless of execution order
            XCTAssertEqual(runner.calls.count, 6, "All 6 help checks should be recorded")
            let commands = Set(runner.calls.map { $0.arguments.first ?? "" })
            XCTAssertEqual(commands, [
                "list-workspaces", "list-windows", "summon-workspace",
                "move-node-to-workspace", "focus", "close"
            ], "All 6 unique commands should appear")
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

    func testListWorkspacesFocusedFailsWhenRunnerFails() {
        let runner = MockCommandRunner()
        runner.results = [
            .failure(ApCoreError(category: .command, message: "runner failed"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.listWorkspacesFocused()

        XCTAssertTrue(result.isFailure)
    }

    func testListWorkspacesFocusedFailsOnNonZeroExit() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 2, stdout: "", stderr: "bad"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.listWorkspacesFocused()

        XCTAssertTrue(result.isFailure)
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

    func testCreateWorkspacePropagatesWorkspaceExistsFailure() {
        let runner = MockCommandRunner()
        runner.results = [
            // getWorkspaces runner failure
            .failure(ApCoreError(category: .command, message: "runner failed"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.createWorkspace("ap-test")

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls[0].arguments, ["list-workspaces", "--all"])
    }

    func testCreateWorkspaceFailsWhenSummonWorkspaceRunnerFails() {
        let runner = MockCommandRunner()
        runner.results = [
            // list-workspaces --all does not include ap-test
            .success(ApCommandResult(exitCode: 0, stdout: "main\n", stderr: "")),
            // summon-workspace runner fails
            .failure(ApCoreError(category: .command, message: "runner failed"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.createWorkspace("ap-test")

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertEqual(runner.calls[1].arguments, ["summon-workspace", "ap-test"])
    }

    func testCreateWorkspaceFailsWhenSummonWorkspaceNonZeroExit() {
        let runner = MockCommandRunner()
        runner.results = [
            // list-workspaces --all does not include ap-test
            .success(ApCommandResult(exitCode: 0, stdout: "main\n", stderr: "")),
            // summon-workspace returns non-zero
            .success(ApCommandResult(exitCode: 1, stdout: "", stderr: "bad"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.createWorkspace("ap-test")

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 2)
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

    func testCloseWorkspaceFailsOnEmptyName() {
        let runner = MockCommandRunner()
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.closeWorkspace(name: "   ")

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 0)
    }

    func testCloseWorkspaceFailsWhenListWindowsWorkspaceFails() {
        let runner = MockCommandRunner()
        runner.results = [
            .failure(ApCoreError(category: .command, message: "list-windows failed"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.closeWorkspace(name: "ap-test")

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 1)
    }

    func testCloseWorkspaceSucceedsWhenNoWindowsInWorkspace() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.closeWorkspace(name: "ap-test")

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 1)
    }

    func testCloseWorkspaceSucceedsWhenAllWindowsClosed() {
        let runner = MockCommandRunner()
        runner.results = [
            // list-windows in workspace returns 2 windows
            .success(ApCommandResult(exitCode: 0, stdout: "1||app||ap-test||t\n2||app||ap-test||t\n", stderr: "")),
            // close window 1 succeeds
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")),
            // close window 2 succeeds
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.closeWorkspace(name: "ap-test")

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 3)
    }

    func testCloseWorkspaceFailsWhenParsedWindowIdIsNotPositive() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "0||app||ap-test||t\n", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.closeWorkspace(name: "ap-test")

        XCTAssertTrue(result.isFailure)
    }

    func testCloseWorkspaceAggregatesRunnerFailureFromCloseWindow() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "1||app||ap-test||t\n", stderr: "")),
            .failure(ApCoreError(category: .command, message: "close command failed"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.closeWorkspace(name: "ap-test")

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 2)
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

    func testFocusedWindowPropagatesRunnerFailure() {
        let runner = MockCommandRunner()
        runner.results = [
            .failure(ApCoreError(category: .command, message: "runner failed"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.focusedWindow()

        XCTAssertTrue(result.isFailure)
    }

    func testFocusedWindowFailsWhenFocusedQueryExitsNonZero() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 3, stdout: "", stderr: "focused query failed"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.focusedWindow()

        XCTAssertTrue(result.isFailure)
    }

    func testListWindowsFocusedMonitorFailsOnNonZeroExit() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 9, stdout: "", stderr: "bad"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.listWindowsFocusedMonitor()

        XCTAssertTrue(result.isFailure)
    }

    func testListWindowsOnFocusedMonitorFailsWhenRunnerFails() {
        let runner = MockCommandRunner()
        runner.results = [
            .failure(ApCoreError(category: .command, message: "runner failed"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.listWindowsOnFocusedMonitor(appBundleId: "com.app")

        XCTAssertTrue(result.isFailure)
    }

    func testListWindowsOnFocusedMonitorFailsOnNonZeroExit() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 4, stdout: "", stderr: "bad"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.listWindowsOnFocusedMonitor(appBundleId: "com.app")

        XCTAssertTrue(result.isFailure)
    }

    func testListWindowsWorkspaceFailsOnNonZeroExit() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 5, stdout: "", stderr: "bad"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.listWindowsWorkspace(workspace: "main")

        XCTAssertTrue(result.isFailure)
    }

    func testListWindowsFocusedMonitorSkipsEmptyOutputLines() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "\n42||app||main||title\n\n", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.listWindowsFocusedMonitor()

        switch result {
        case .failure(let error):
            XCTFail("Expected success, got: \(error)")
        case .success(let windows):
            XCTAssertEqual(windows.count, 1)
            XCTAssertEqual(windows.first?.windowId, 42)
        }
    }

    func testListWindowsFocusedMonitorFailsWhenWindowIdIsNotInteger() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "abc||app||main||title\n", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.listWindowsFocusedMonitor()

        XCTAssertTrue(result.isFailure)
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

final class AeroSpaceListAllWindowsTests: XCTestCase {
    func testListAllWindowsPropagatesWorkspaceQueryFailure() {
        let runner = MockCommandRunner()
        runner.results = [
            .failure(ApCoreError(category: .command, message: "list-workspaces failed"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.listAllWindows()

        XCTAssertTrue(result.isFailure)
    }

    func testListAllWindowsSkipsWorkspaceFailuresAndAggregatesSuccessfulResults() {
        let runner = MockCommandRunner()
        runner.results = [
            // getWorkspaces
            .success(ApCommandResult(exitCode: 0, stdout: "main\nap-two\n", stderr: "")),
            // listWindowsWorkspace(main)
            .success(ApCommandResult(exitCode: 0, stdout: "1||com.app||main||one\n", stderr: "")),
            // listWindowsWorkspace(ap-two) fails and should be skipped
            .success(ApCommandResult(exitCode: 1, stdout: "", stderr: "workspace unavailable"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.listAllWindows()

        switch result {
        case .failure(let error):
            XCTFail("Expected success, got: \(error)")
        case .success(let windows):
            XCTAssertEqual(windows.count, 1)
            XCTAssertEqual(windows[0].workspace, "main")
        }
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

    func testHealthCheckCompatibilityReturnsCliUnavailableWhenCliMissing() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 1, stdout: "", stderr: "aerospace missing"))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.healthCheckCompatibility()

        XCTAssertEqual(result, .cliUnavailable)
    }

    func testHealthCheckCompatibilityReturnsIncompatibleDetailWhenCompatibilityFails() {
        let runner = MockCommandRunner()
        runner.keyedResults = [
            "--help": .success(ApCommandResult(exitCode: 0, stdout: "usage", stderr: "")),
            "list-workspaces": .success(ApCommandResult(exitCode: 0, stdout: "--all", stderr: "")),
            "list-windows": .success(ApCommandResult(exitCode: 0, stdout: "--monitor --workspace --focused --app-bundle-id --format", stderr: "")),
            "summon-workspace": .success(ApCommandResult(exitCode: 0, stdout: "ok", stderr: "")),
            "move-node-to-workspace": .success(ApCommandResult(exitCode: 0, stdout: "--window-id", stderr: "")),
            "focus": .success(ApCommandResult(exitCode: 0, stdout: "--window-id --boundaries --boundaries-action dfs-next dfs-prev", stderr: "")),
            "close": .success(ApCommandResult(exitCode: 0, stdout: "--window-id", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.healthCheckCompatibility()

        switch result {
        case .incompatible(let detail):
            XCTAssertTrue(detail.contains("list-workspaces"))
        default:
            XCTFail("Expected incompatible result, got \(result)")
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

    func testListWorkspacesWithFocusSkipsEmptyLines() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "\nmain||true\n\n", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.listWorkspacesWithFocus()

        switch result {
        case .failure(let error):
            XCTFail("Expected success, got: \(error)")
        case .success(let summaries):
            XCTAssertEqual(summaries, [ApWorkspaceSummary(workspace: "main", isFocused: true)])
        }
    }

    func testListWorkspacesWithFocusFailsWhenSeparatorMissing() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "main true\n", stderr: ""))
        ]
        let aero = ApAeroSpace(commandRunner: runner, appDiscovery: StubAppDiscovery())

        let result = aero.listWorkspacesWithFocus()

        XCTAssertTrue(result.isFailure)
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
