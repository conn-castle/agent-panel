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
        aerospaceCli: "AVAILABLE"
    )
    let findings = hasFailures
        ? [DoctorFinding(severity: .fail, title: "Failure")]
        : [DoctorFinding(severity: .pass, title: "Pass")]
    return DoctorReport(metadata: metadata, findings: findings)
}
