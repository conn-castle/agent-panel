import XCTest
@testable import AgentPanelCLICore
@testable import AgentPanelCore

final class ApCLIRunnerTests: XCTestCase {

    func testVersionCommandOutputsVersion() {
        let output = OutputRecorder()
        let deps = ApCLIDependencies(
            version: { "9.9.9" },
            projectManagerFactory: { ProjectManager() },
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
            projectManagerFactory: { ProjectManager() },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["nope"])

        XCTAssertEqual(exitCode, ApExitCode.usage.rawValue)
        XCTAssertEqual(output.stderr.first, "error: unknown command: nope")
        XCTAssertTrue(output.stderr.last?.contains("Usage:") ?? false)
    }

    func testDoctorSuccessReturnsOkExit() {
        let output = OutputRecorder()
        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { ProjectManager() },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["doctor"])

        XCTAssertEqual(exitCode, ApExitCode.ok.rawValue)
        XCTAssertTrue(output.stdout.first?.contains("AgentPanel Doctor Report") ?? false)
    }

    func testDoctorFailureReturnsFailureExit() {
        let output = OutputRecorder()
        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { ProjectManager() },
            doctorRunner: { makeDoctorReport(hasFailures: true) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["doctor"])

        XCTAssertEqual(exitCode, ApExitCode.failure.rawValue)
        XCTAssertTrue(output.stdout.first?.contains("AgentPanel Doctor Report") ?? false)
    }

    func testHelpCommandOutputsUsage() {
        let output = OutputRecorder()
        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { ProjectManager() },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["--help"])

        XCTAssertEqual(exitCode, ApExitCode.ok.rawValue)
        XCTAssertTrue(output.stdout.first?.contains("ap (AgentPanel CLI)") ?? false)
    }

    func testSelectProjectHelpOutputsUsage() {
        let output = OutputRecorder()
        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { ProjectManager() },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["select-project", "--help"])

        XCTAssertEqual(exitCode, ApExitCode.ok.rawValue)
        XCTAssertTrue(output.stdout.first?.contains("select-project") ?? false)
    }

    func testShowConfigSuccessPrintsFormattedConfig() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: ["a", "b"]))

        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["show-config"])

        XCTAssertEqual(exitCode, ApExitCode.ok.rawValue)
        XCTAssertEqual(output.stderr, [])
        XCTAssertEqual(output.stdout.count, 1)
        XCTAssertTrue(output.stdout[0].contains("# AgentPanel Configuration"))
        XCTAssertTrue(output.stdout[0].contains("id = \"a\""))
        XCTAssertTrue(output.stdout[0].contains("id = \"b\""))
    }

    func testShowConfigWithWarningsPrintsWarningsToStderr() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(
            makeConfig(
                projectIds: ["a"],
                warnings: [ConfigFinding(severity: .warn, title: "Deprecated field: foo")]
            )
        )

        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["show-config"])

        XCTAssertEqual(exitCode, ApExitCode.ok.rawValue)
        XCTAssertEqual(output.stderr, ["warning: Deprecated field: foo"])
        XCTAssertEqual(output.stdout.count, 1)
        XCTAssertTrue(output.stdout[0].contains("# AgentPanel Configuration"))
    }

    func testShowConfigFailurePrintsErrorAndReturnsFailureExit() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .failure(.fileNotFound(path: "/tmp/missing"))

        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["show-config"])

        XCTAssertEqual(exitCode, ApExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr.first, "error: Config file not found: /tmp/missing")
    }

    func testShowConfigReadFailedPrintsErrorAndReturnsFailureExit() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .failure(.readFailed(path: "/tmp/config.toml", detail: "permission denied"))

        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["show-config"])

        XCTAssertEqual(exitCode, ApExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr, ["error: Failed to read config at /tmp/config.toml: permission denied"])
    }

    func testShowConfigValidationFailedWithoutFailFindingsUsesGenericMessage() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .failure(.validationFailed(findings: [
            ConfigFinding(severity: .warn, title: "Warning only")
        ]))

        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["show-config"])

        XCTAssertEqual(exitCode, ApExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr.first, "error: Config validation failed")
    }

    func testListProjectsSuccessPrintsProjectLines() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: ["a", "b"]))
        manager.sortedProjectsResult = [
            makeProject(id: "a", name: "Alpha", path: "/p/a"),
            makeProject(id: "b", name: "Beta", path: "/p/b")
        ]

        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["list-projects", "query"])

        XCTAssertEqual(exitCode, ApExitCode.ok.rawValue)
        XCTAssertEqual(output.stderr, [])
        XCTAssertEqual(output.stdout, [
            "a\tAlpha\t/p/a",
            "b\tBeta\t/p/b"
        ])
        XCTAssertEqual(manager.sortedProjectsQueries, ["query"])
    }

    func testListProjectsFailurePrintsErrorAndReturnsFailureExit() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .failure(.parseFailed(detail: "bad toml"))

        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["list-projects"])

        XCTAssertEqual(exitCode, ApExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr.first, "error: Failed to parse config: bad toml")
    }

    func testListProjectsNoQueryUsesEmptyString() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: ["a", "b"]))
        manager.sortedProjectsResult = [
            makeProject(id: "a", name: "Alpha", path: "/p/a"),
            makeProject(id: "b", name: "Beta", path: "/p/b")
        ]

        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["list-projects"])

        XCTAssertEqual(exitCode, ApExitCode.ok.rawValue)
        XCTAssertEqual(output.stderr, [])
        XCTAssertEqual(output.stdout, [
            "a\tAlpha\t/p/a",
            "b\tBeta\t/p/b"
        ])
        XCTAssertEqual(manager.sortedProjectsQueries, [""])
    }

    func testSelectProjectFailsWhenCannotCaptureFocus() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: ["a"]))
        manager.captureCurrentFocusResult = nil

        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["select-project", "a"])

        XCTAssertEqual(exitCode, ApExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr, ["error: Could not capture current focus"])
        XCTAssertEqual(manager.selectProjectCalls.count, 0)
    }

    func testSelectProjectSuccessPrintsWarningIfPresent() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: ["a"]))
        manager.captureCurrentFocusResult = CapturedFocus(windowId: 1, appBundleId: "app", workspace: "main")
        manager.selectProjectResult = .success(ProjectActivationSuccess(ideWindowId: 42, tabRestoreWarning: "tabs failed"))

        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["select-project", "a"])

        XCTAssertEqual(exitCode, ApExitCode.ok.rawValue)
        XCTAssertEqual(output.stdout, ["Selected project: a"])
        XCTAssertEqual(output.stderr, ["warning: tabs failed"])
        XCTAssertEqual(manager.selectProjectCalls.count, 1)
        XCTAssertEqual(manager.selectProjectCalls[0].projectId, "a")
    }

    func testSelectProjectFailurePrintsErrorAndReturnsFailureExit() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: ["a"]))
        manager.captureCurrentFocusResult = CapturedFocus(windowId: 1, appBundleId: "app", workspace: "main")
        manager.selectProjectResult = .failure(.projectNotFound(projectId: "a"))

        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["select-project", "a"])

        XCTAssertEqual(exitCode, ApExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr, ["error: Project not found: a"])
    }

    func testSelectProjectConfigLoadFailurePrintsErrorAndReturnsFailureExit() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .failure(.parseFailed(detail: "bad toml"))

        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["select-project", "a"])

        XCTAssertEqual(exitCode, ApExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr, ["error: Failed to parse config: bad toml"])
    }

    func testSelectProjectConfigNotLoadedPrintsError() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: ["a"]))
        manager.captureCurrentFocusResult = CapturedFocus(windowId: 1, appBundleId: "app", workspace: "main")
        manager.selectProjectResult = .failure(.configNotLoaded)

        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["select-project", "a"])

        XCTAssertEqual(exitCode, ApExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr, ["error: Config not loaded"])
    }

    func testSelectProjectSuccessPrintsLayoutWarning() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: ["a"]))
        manager.captureCurrentFocusResult = CapturedFocus(windowId: 1, appBundleId: "app", workspace: "main")
        manager.selectProjectResult = .success(
            ProjectActivationSuccess(
                ideWindowId: 42,
                tabRestoreWarning: nil,
                layoutWarning: "layout not applied"
            )
        )

        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["select-project", "a"])

        XCTAssertEqual(exitCode, ApExitCode.ok.rawValue)
        XCTAssertEqual(output.stdout, ["Selected project: a"])
        XCTAssertEqual(output.stderr, ["warning: layout not applied"])
    }

    func testSelectProjectIdeLaunchFailedPrintsError() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: ["a"]))
        manager.captureCurrentFocusResult = CapturedFocus(windowId: 1, appBundleId: "app", workspace: "main")
        manager.selectProjectResult = .failure(.ideLaunchFailed(detail: "VS Code missing"))

        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["select-project", "a"])

        XCTAssertEqual(exitCode, ApExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr, ["error: IDE launch failed: VS Code missing"])
    }

    func testCloseProjectSuccessPrintsWarningIfPresent() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: ["a"]))
        manager.closeProjectResult = .success(ProjectCloseSuccess(tabCaptureWarning: "capture failed"))

        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["close-project", "a"])

        XCTAssertEqual(exitCode, ApExitCode.ok.rawValue)
        XCTAssertEqual(output.stdout, ["Closed project: a"])
        XCTAssertEqual(output.stderr, ["warning: capture failed"])
    }

    func testCloseProjectFailurePrintsErrorAndReturnsFailureExit() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: ["a"]))
        manager.closeProjectResult = .failure(.aeroSpaceError(detail: "boom"))

        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["close-project", "a"])

        XCTAssertEqual(exitCode, ApExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr, ["error: AeroSpace error: boom"])
    }

    func testCloseProjectChromeLaunchFailedPrintsError() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: ["a"]))
        manager.closeProjectResult = .failure(.chromeLaunchFailed(detail: "Chrome not installed"))

        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["close-project", "a"])

        XCTAssertEqual(exitCode, ApExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr, ["error: Chrome launch failed: Chrome not installed"])
    }

    func testCloseProjectNoActiveProjectPrintsError() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: ["a"]))
        manager.closeProjectResult = .failure(.noActiveProject)

        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["close-project", "a"])

        XCTAssertEqual(exitCode, ApExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr, ["error: No active project"])
    }

    func testCloseProjectConfigLoadFailurePrintsErrorAndReturnsFailureExit() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .failure(.fileNotFound(path: "/tmp/missing.toml"))

        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["close-project", "a"])

        XCTAssertEqual(exitCode, ApExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr, ["error: Config file not found: /tmp/missing.toml"])
    }

    func testReturnCommandSuccessPrintsMessage() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: []))
        manager.exitToNonProjectResult = .success(())

        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["return"])

        XCTAssertEqual(exitCode, ApExitCode.ok.rawValue)
        XCTAssertEqual(output.stdout, ["Returned to non-project space"])
        XCTAssertEqual(output.stderr, [])
    }

    func testReturnCommandFailurePrintsErrorAndReturnsFailureExit() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: []))
        manager.exitToNonProjectResult = .failure(.noPreviousWindow)

        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["return"])

        XCTAssertEqual(exitCode, ApExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr, ["error: No recent non-project window to return to"])
    }

    func testReturnCommandWindowNotFoundPrintsError() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: []))
        manager.exitToNonProjectResult = .failure(.windowNotFound(detail: "missing"))

        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["return"])

        XCTAssertEqual(exitCode, ApExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr, ["error: Window not found: missing"])
    }

    func testReturnCommandFocusUnstablePrintsError() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: []))
        manager.exitToNonProjectResult = .failure(.focusUnstable(detail: "did not stabilize"))

        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["return"])

        XCTAssertEqual(exitCode, ApExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr, ["error: Focus unstable: did not stabilize"])
    }

    func testReturnCommandConfigLoadFailurePrintsErrorAndReturnsFailureExit() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .failure(.readFailed(path: "/tmp/config.toml", detail: "permission denied"))

        let deps = ApCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = ApCLI(parser: ApArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["return"])

        XCTAssertEqual(exitCode, ApExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr, ["error: Failed to read config at /tmp/config.toml: permission denied"])
    }

    func testUsageTextHasUniqueContentPerHelpTopic() {
        XCTAssertTrue(usageText(for: .root).contains("Commands:"))
        XCTAssertTrue(usageText(for: .doctor).contains("ap doctor"))
        XCTAssertTrue(usageText(for: .showConfig).contains("show-config"))
        XCTAssertTrue(usageText(for: .listProjects).contains("list-projects"))
        XCTAssertTrue(usageText(for: .selectProject).contains("select-project"))
        XCTAssertTrue(usageText(for: .closeProject).contains("close-project"))
        XCTAssertTrue(usageText(for: .returnToWindow).contains("ap return"))
    }

    func testStandardOutputWritersExecute() {
        // Intentionally writes to stdout/stderr to cover the standard output sinks.
        ApCLIOutput.standard.stdout("stdout test")
        ApCLIOutput.standard.stderr("stderr test")
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

private func makeDoctorReport(hasFailures: Bool) -> DoctorReport {
    let metadata = DoctorMetadata(
        timestamp: "2024-01-01T00:00:00.000Z",
        agentPanelVersion: "test",
        macOSVersion: "macOS 15.7",
        aerospaceApp: "AVAILABLE",
        aerospaceCli: "AVAILABLE",
        errorContext: nil,
        durationMs: 0,
        sectionTimings: [:]
    )
    let findings = hasFailures
        ? [DoctorFinding(severity: .fail, title: "Failure")]
        : [DoctorFinding(severity: .pass, title: "Pass")]
    return DoctorReport(metadata: metadata, findings: findings)
}

private func makeConfig(projectIds: [String], warnings: [ConfigFinding] = []) -> ConfigLoadSuccess {
    let projects = projectIds.map { id in
        makeProject(id: id, name: id.uppercased(), path: "/tmp/\(id)")
    }
    return ConfigLoadSuccess(config: Config(projects: projects), warnings: warnings)
}

private func makeProject(id: String, name: String, path: String) -> ProjectConfig {
    ProjectConfig(
        id: id,
        name: name,
        remote: nil,
        path: path,
        color: "blue",
        useAgentLayer: false,
        chromePinnedTabs: [],
        chromeDefaultTabs: []
    )
}

private final class MockProjectManager: ProjectManaging {
    var loadConfigResult: Result<ConfigLoadSuccess, ConfigLoadError> = .success(ConfigLoadSuccess(config: Config(projects: [])))
    var sortedProjectsResult: [ProjectConfig] = []
    var sortedProjectsQueries: [String] = []
    var captureCurrentFocusResult: CapturedFocus?
    var selectProjectResult: Result<ProjectActivationSuccess, ProjectError> = .success(ProjectActivationSuccess(ideWindowId: 1, tabRestoreWarning: nil))
    var selectProjectCalls: [(projectId: String, focus: CapturedFocus)] = []
    var closeProjectResult: Result<ProjectCloseSuccess, ProjectError> = .success(ProjectCloseSuccess(tabCaptureWarning: nil))
    var closeProjectCalls: [String] = []
    var exitToNonProjectResult: Result<Void, ProjectError> = .success(())
    var exitCalls: Int = 0

    func loadConfig() -> Result<ConfigLoadSuccess, ConfigLoadError> {
        loadConfigResult
    }

    func sortedProjects(query: String) -> [ProjectConfig] {
        sortedProjectsQueries.append(query)
        return sortedProjectsResult
    }

    func captureCurrentFocus() -> CapturedFocus? {
        captureCurrentFocusResult
    }

    func selectProject(projectId: String, preCapturedFocus: CapturedFocus) async -> Result<ProjectActivationSuccess, ProjectError> {
        selectProjectCalls.append((projectId: projectId, focus: preCapturedFocus))
        return selectProjectResult
    }

    func closeProject(projectId: String) -> Result<ProjectCloseSuccess, ProjectError> {
        closeProjectCalls.append(projectId)
        return closeProjectResult
    }

    func exitToNonProjectWindow() -> Result<Void, ProjectError> {
        exitCalls += 1
        return exitToNonProjectResult
    }
}
