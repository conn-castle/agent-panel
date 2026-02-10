import XCTest
@testable import AgentPanelCore

/// Tests for `ApAgentLayerVSCodeLauncher`.
///
/// Verifies:
/// - Workspace file creation with AP:<id> tag
/// - Two-step launch: `al sync` (CWD = project path) then `code --new-window <workspace>`
/// - Error handling: al not found, code not found, empty project path, non-zero exit, partial failure
final class AgentLayerLauncherTests: XCTestCase {

    private var tempDir: URL!
    private var dataStore: DataPaths!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ALLauncherTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        dataStore = DataPaths(homeDirectory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Successful launch

    func testSuccessfulLaunchRunsAlSyncThenCodeNewWindow() {
        let runner = MockALCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")),
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let resolver = makeResolver()
        let launcher = ApAgentLayerVSCodeLauncher(
            dataStore: dataStore,
            commandRunner: runner,
            executableResolver: resolver
        )

        let result = launcher.openNewWindow(identifier: "my-project", projectPath: "/Users/test/project")

        if case .failure(let error) = result {
            XCTFail("Expected success, got failure: \(error.message)")
            return
        }

        XCTAssertEqual(runner.calls.count, 2)

        // Call 0: al sync with CWD = project path
        let syncCall = runner.calls[0]
        XCTAssertTrue(syncCall.executable.hasSuffix("/al"))
        XCTAssertEqual(syncCall.arguments, ["sync"])
        XCTAssertEqual(syncCall.workingDirectory, "/Users/test/project")

        // Call 1: code --new-window <workspace>
        let codeCall = runner.calls[1]
        XCTAssertTrue(codeCall.executable.hasSuffix("/code"))
        XCTAssertEqual(codeCall.arguments[0], "--new-window")
        XCTAssertTrue(codeCall.arguments[1].hasSuffix("my-project.code-workspace"))
        XCTAssertNil(codeCall.workingDirectory)
    }

    // MARK: - Workspace file contents

    func testWorkspaceFileContainsAPTag() {
        let runner = MockALCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")),
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let launcher = ApAgentLayerVSCodeLauncher(
            dataStore: dataStore,
            commandRunner: runner,
            executableResolver: makeResolver()
        )

        _ = launcher.openNewWindow(identifier: "test-proj", projectPath: "/Users/test/project")

        let workspace = readWorkspaceJSON("test-proj")
        XCTAssertNotNil(workspace, "Workspace file should exist")

        let settings = workspace?["settings"] as? [String: String]
        let windowTitle = settings?["window.title"]
        XCTAssertNotNil(windowTitle)
        XCTAssertTrue(windowTitle?.hasPrefix("AP:test-proj") == true,
                       "Window title should start with AP:test-proj, got: \(windowTitle ?? "nil")")
    }

    func testWorkspaceFileContainsCorrectFolderPath() {
        let runner = MockALCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")),
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let launcher = ApAgentLayerVSCodeLauncher(
            dataStore: dataStore,
            commandRunner: runner,
            executableResolver: makeResolver()
        )

        _ = launcher.openNewWindow(identifier: "my-proj", projectPath: "/Users/test/project")

        let workspace = readWorkspaceJSON("my-proj")
        let folders = workspace?["folders"] as? [[String: String]]
        XCTAssertEqual(folders?.first?["path"], "/Users/test/project")
    }

    func testWorkspaceFileHasNoRemoteAuthority() {
        let runner = MockALCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")),
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let launcher = ApAgentLayerVSCodeLauncher(
            dataStore: dataStore,
            commandRunner: runner,
            executableResolver: makeResolver()
        )

        _ = launcher.openNewWindow(identifier: "local-proj", projectPath: "/Users/test/project")

        let workspace = readWorkspaceJSON("local-proj")
        XCTAssertNil(workspace?["remoteAuthority"],
                      "AL workspace should not have remoteAuthority (SSH+AL is mutually exclusive)")
    }

    // MARK: - Error: al not found

    func testAlNotFoundReturnsError() {
        let runner = MockALCommandRunner()
        let resolver = makeResolver(alAvailable: false)
        let launcher = ApAgentLayerVSCodeLauncher(
            dataStore: dataStore,
            commandRunner: runner,
            executableResolver: resolver
        )

        let result = launcher.openNewWindow(identifier: "test", projectPath: "/Users/test/project")

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("al") && error.message.contains("not found"),
                          "Error should mention 'al' not found, got: \(error.message)")
        } else {
            XCTFail("Expected failure when al is not found")
        }

        XCTAssertTrue(runner.calls.isEmpty, "No command should be run if al is not found")
    }

    // MARK: - Error: code not found

    func testCodeNotFoundReturnsError() {
        let runner = MockALCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let resolver = makeResolver(codeAvailable: false)
        let launcher = ApAgentLayerVSCodeLauncher(
            dataStore: dataStore,
            commandRunner: runner,
            executableResolver: resolver
        )

        let result = launcher.openNewWindow(identifier: "test", projectPath: "/Users/test/project")

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("code") && error.message.contains("not found"),
                          "Error should mention 'code' not found, got: \(error.message)")
        } else {
            XCTFail("Expected failure when code is not found")
        }

        // al sync should have run, but code should not
        XCTAssertEqual(runner.calls.count, 1, "Only al sync should run when code is not found")
    }

    // MARK: - Error: nil or empty project path

    func testNilProjectPathReturnsError() {
        let runner = MockALCommandRunner()
        let launcher = ApAgentLayerVSCodeLauncher(
            dataStore: dataStore,
            commandRunner: runner,
            executableResolver: makeResolver()
        )

        let result = launcher.openNewWindow(identifier: "test", projectPath: nil)

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("Project path is required"),
                          "Error should say project path is required, got: \(error.message)")
        } else {
            XCTFail("Expected failure for nil project path")
        }
    }

    func testEmptyProjectPathReturnsError() {
        let runner = MockALCommandRunner()
        let launcher = ApAgentLayerVSCodeLauncher(
            dataStore: dataStore,
            commandRunner: runner,
            executableResolver: makeResolver()
        )

        let result = launcher.openNewWindow(identifier: "test", projectPath: "   ")

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("Project path is required"),
                          "Error should say project path is required, got: \(error.message)")
        } else {
            XCTFail("Expected failure for empty project path")
        }
    }

    // MARK: - Error: al sync non-zero exit code

    func testAlSyncNonZeroExitReturnsErrorWithStderr() {
        let runner = MockALCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 1, stdout: "", stderr: "agent layer isn't initialized"))
        ]
        let launcher = ApAgentLayerVSCodeLauncher(
            dataStore: dataStore,
            commandRunner: runner,
            executableResolver: makeResolver()
        )

        let result = launcher.openNewWindow(identifier: "test", projectPath: "/Users/test/project")

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("al sync failed"), "Error should mention al sync, got: \(error.message)")
            XCTAssertTrue(error.message.contains("exit code 1"), "Error should contain exit code")
            XCTAssertTrue(error.message.contains("agent layer isn't initialized"),
                          "Error should contain stderr")
        } else {
            XCTFail("Expected failure for non-zero exit code")
        }

        XCTAssertEqual(runner.calls.count, 1, "code should not run after al sync failure")
    }

    // MARK: - Error: al sync succeeds but code fails

    func testAlSyncSucceedsButCodeFailsReturnsError() {
        let runner = MockALCommandRunner()
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")),
            .success(ApCommandResult(exitCode: 1, stdout: "", stderr: "code: command not supported"))
        ]
        let launcher = ApAgentLayerVSCodeLauncher(
            dataStore: dataStore,
            commandRunner: runner,
            executableResolver: makeResolver()
        )

        let result = launcher.openNewWindow(identifier: "test", projectPath: "/Users/test/project")

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("code failed"), "Error should mention code, got: \(error.message)")
            XCTAssertTrue(error.message.contains("exit code 1"), "Error should contain exit code")
        } else {
            XCTFail("Expected failure when code exits non-zero")
        }

        XCTAssertEqual(runner.calls.count, 2, "Both al sync and code should have run")
    }

    // MARK: - Error: command runner failure

    func testCommandRunnerFailureReturnsError() {
        let runner = MockALCommandRunner()
        runner.results = [
            .failure(ApCoreError(message: "Command timed out after 30.0s: al"))
        ]
        let launcher = ApAgentLayerVSCodeLauncher(
            dataStore: dataStore,
            commandRunner: runner,
            executableResolver: makeResolver()
        )

        let result = launcher.openNewWindow(identifier: "test", projectPath: "/Users/test/project")

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("timed out"),
                          "Error should contain runner failure message")
        } else {
            XCTFail("Expected failure from command runner")
        }
    }

    // MARK: - Helpers

    private func makeResolver(alAvailable: Bool = true, codeAvailable: Bool = true) -> ExecutableResolver {
        var executablePaths = Set<String>()
        if alAvailable { executablePaths.insert("/usr/local/bin/al") }
        if codeAvailable { executablePaths.insert("/usr/local/bin/code") }
        let stubFS = ALSelectiveFileSystem(executablePaths: executablePaths)
        return ExecutableResolver(
            fileSystem: stubFS,
            searchPaths: ["/usr/local/bin"],
            loginShellFallbackEnabled: false
        )
    }

    private func readWorkspaceJSON(_ identifier: String) -> [String: Any]? {
        let workspaceURL = dataStore.vscodeWorkspaceDirectory
            .appendingPathComponent("\(identifier).code-workspace")
        guard let data = try? Data(contentsOf: workspaceURL) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

// MARK: - Test Doubles

private final class MockALCommandRunner: CommandRunning {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
        let workingDirectory: String?
    }

    var calls: [Call] = []
    var results: [Result<ApCommandResult, ApCoreError>] = []

    func run(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval?,
        workingDirectory: String?
    ) -> Result<ApCommandResult, ApCoreError> {
        calls.append(Call(executable: executable, arguments: arguments, workingDirectory: workingDirectory))
        guard !results.isEmpty else {
            return .failure(ApCoreError(message: "MockALCommandRunner: no results left"))
        }
        return results.removeFirst()
    }
}

private struct ALSelectiveFileSystem: FileSystem {
    let executablePaths: Set<String>

    func fileExists(at url: URL) -> Bool { executablePaths.contains(url.path) }
    func isExecutableFile(at url: URL) -> Bool { executablePaths.contains(url.path) }
    func readFile(at url: URL) throws -> Data { throw NSError(domain: "stub", code: 1) }
    func createDirectory(at url: URL) throws {}
    func fileSize(at url: URL) throws -> UInt64 { 0 }
    func removeItem(at url: URL) throws {}
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {}
    func appendFile(at url: URL, data: Data) throws {}
    func writeFile(at url: URL, data: Data) throws {}
}
