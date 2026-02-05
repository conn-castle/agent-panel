import XCTest
@testable import AgentPanelCLICore
import AgentPanelCore

final class ApCLIRunnerTests: XCTestCase {

    func testVersionCommandOutputsVersion() {
        let output = OutputRecorder()
        let deps = ApCLIDependencies(
            version: { "9.9.9" },
            configLoader: { XCTFail("configLoader should not be called"); return .failure(ConfigError(kind: .fileNotFound, message: "")) },
            coreFactory: { _ in XCTFail("coreFactory should not be called"); return StubCore() },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["--version"])

        XCTAssertEqual(exitCode, ApExitCode.ok.rawValue)
        XCTAssertEqual(output.stdout, ["ap 9.9.9"])
        XCTAssertTrue(output.stderr.isEmpty)
    }

    func testUnknownCommandPrintsUsageAndReturnsUsageExit() {
        let output = OutputRecorder()
        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            configLoader: { .failure(ConfigError(kind: .fileNotFound, message: "unused")) },
            coreFactory: { _ in StubCore() },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["nope"])

        XCTAssertEqual(exitCode, ApExitCode.usage.rawValue)
        XCTAssertEqual(output.stderr.first, "error: unknown command: nope")
        XCTAssertTrue(output.stderr.last?.contains("Usage:") ?? false)
    }

    func testDoctorFailureReturnsFailureExit() {
        let output = OutputRecorder()
        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            configLoader: { .failure(ConfigError(kind: .fileNotFound, message: "unused")) },
            coreFactory: { _ in StubCore() },
            doctorRunner: { makeDoctorReport(hasFailures: true) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["doctor"])

        XCTAssertEqual(exitCode, ApExitCode.failure.rawValue)
        XCTAssertTrue(output.stdout.first?.contains("AgentPanel Doctor Report") ?? false)
    }

    func testListWorkspacesSuccessRunsCoreCommand() {
        let output = OutputRecorder()
        let stubCore = StubCore()
        stubCore.listWorkspacesResult = .success(["ap-test", "ap-demo"])

        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            configLoader: { .success(makeValidConfigLoadResult()) },
            coreFactory: { _ in stubCore },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["list-workspaces"])

        XCTAssertEqual(exitCode, ApExitCode.ok.rawValue)
        XCTAssertTrue(stubCore.listWorkspacesCalled)
        XCTAssertEqual(output.stdout, ["ap-test", "ap-demo"])
        XCTAssertTrue(output.stderr.isEmpty)
    }

    func testListWorkspacesFailurePrintsError() {
        let output = OutputRecorder()
        let stubCore = StubCore()
        stubCore.listWorkspacesResult = .failure(ApCoreError(message: "boom"))

        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            configLoader: { .success(makeValidConfigLoadResult()) },
            coreFactory: { _ in stubCore },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["list-workspaces"])

        XCTAssertEqual(exitCode, ApExitCode.failure.rawValue)
        XCTAssertEqual(output.stderr, ["error: boom"])
    }

    func testConfigLoadFailurePrintsError() {
        let output = OutputRecorder()
        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            configLoader: { .failure(ConfigError(kind: .fileNotFound, message: "config missing")) },
            coreFactory: { _ in StubCore() },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["show-config"])

        XCTAssertEqual(exitCode, ApExitCode.failure.rawValue)
        XCTAssertEqual(output.stderr, ["error: config missing"])
    }

    func testConfigValidationFailurePrintsFirstFail() {
        let output = OutputRecorder()
        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            configLoader: { .success(makeInvalidConfigLoadResult()) },
            coreFactory: { _ in StubCore() },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["show-config"])

        XCTAssertEqual(exitCode, ApExitCode.failure.rawValue)
        XCTAssertEqual(output.stderr, ["error: No [[project]] entries"])
    }

    func testListIdeOutputsTabSeparatedWindows() {
        let output = OutputRecorder()
        let stubCore = StubCore()
        stubCore.listIdeWindowsResult = .success([
            ApWindow(windowId: 1, appBundleId: "com.test.App", workspace: "ws", windowTitle: "Title")
        ])

        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            configLoader: { .success(makeValidConfigLoadResult()) },
            coreFactory: { _ in stubCore },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["list-ide"])

        XCTAssertEqual(exitCode, ApExitCode.ok.rawValue)
        XCTAssertEqual(output.stdout, ["1\tcom.test.App\tws\tTitle"])
    }
}

// MARK: - Test Doubles

private final class OutputRecorder {
    private(set) var stdout: [String] = []
    private(set) var stderr: [String] = []

    var sink: ApCLIOutput {
        ApCLIOutput(
            stdout: { [weak self] line in self?.stdout.append(line) },
            stderr: { [weak self] line in self?.stderr.append(line) }
        )
    }
}

private final class StubCore: ApCoreCommanding {
    var stubConfig: Config = Config(projects: [])
    var config: Config { stubConfig }

    var listWorkspacesCalled = false
    var listWorkspacesResult: Result<[String], ApCoreError> = .success([])
    var listIdeWindowsResult: Result<[ApWindow], ApCoreError> = .success([])

    func listWorkspaces() -> Result<[String], ApCoreError> {
        listWorkspacesCalled = true
        return listWorkspacesResult
    }

    func newWorkspace(name: String) -> Result<Void, ApCoreError> { .success(()) }
    func newIde(identifier: String) -> Result<Void, ApCoreError> { .success(()) }
    func newChrome(identifier: String) -> Result<Void, ApCoreError> { .success(()) }
    func listIdeWindows() -> Result<[ApWindow], ApCoreError> { listIdeWindowsResult }
    func listChromeWindows() -> Result<[ApWindow], ApCoreError> { .success([]) }
    func listWindowsWorkspace(_ workspace: String) -> Result<[ApWindow], ApCoreError> { .success([]) }
    func focusedWindow() -> Result<ApWindow, ApCoreError> {
        .failure(ApCoreError(message: "not implemented"))
    }
    func moveWindowToWorkspace(workspace: String, windowId: Int) -> Result<Void, ApCoreError> { .success(()) }
    func focusWindow(windowId: Int) -> Result<Void, ApCoreError> { .success(()) }
    func closeWorkspace(name: String) -> Result<Void, ApCoreError> { .success(()) }
}

private func makeValidConfigLoadResult() -> ConfigLoadResult {
    let project = ProjectConfig(
        id: "test",
        name: "Test",
        path: "/tmp/test",
        color: "blue",
        useAgentLayer: false
    )
    let config = Config(projects: [project])
    return ConfigLoadResult(config: config, findings: [], projects: config.projects)
}

private func makeInvalidConfigLoadResult() -> ConfigLoadResult {
    let finding = ConfigFinding(
        severity: .fail,
        title: "No [[project]] entries",
        detail: nil,
        fix: nil
    )
    return ConfigLoadResult(config: nil, findings: [finding], projects: [])
}

private func makeDoctorReport(hasFailures: Bool) -> DoctorReport {
    let metadata = DoctorMetadata(
        timestamp: "2024-01-01T00:00:00.000Z",
        agentPanelVersion: "test",
        macOSVersion: "macOS 15.7",
        aerospaceApp: "AVAILABLE",
        aerospaceCli: "AVAILABLE"
    )
    let findings = hasFailures
        ? [DoctorFinding(severity: .fail, title: "Failure")]
        : [DoctorFinding(severity: .pass, title: "Pass")]
    return DoctorReport(metadata: metadata, findings: findings)
}
