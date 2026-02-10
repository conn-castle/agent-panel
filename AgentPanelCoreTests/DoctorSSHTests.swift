import XCTest
@testable import AgentPanelCore

final class DoctorSSHTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DoctorSSHTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - SSH exit 0 → PASS

    func testSSHProjectExitZeroPassesFinding() {
        let doctor = makeDoctor(
            sshResult: .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")),
            sshResolvable: true
        )

        let report = doctor.run()

        XCTAssertTrue(report.findings.contains {
            $0.severity == .pass && $0.title.contains("Remote project path exists: remote-ml")
        })
    }

    // MARK: - Default init coverage

    func testDoctorDefaultInitDoesNotCrash() {
        _ = Doctor(runningApplicationChecker: StubRunningAppChecker())
    }

    // MARK: - AeroSpace actions (install/start/reload)

    func testInstallAeroSpaceInvokesHealthInstallViaHomebrew() {
        let health = RecordingAeroSpaceHealth()
        let doctor = makeDoctor(
            sshResult: .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")),
            sshResolvable: true,
            aerospaceHealth: health
        )

        _ = doctor.installAeroSpace()

        XCTAssertEqual(health.installCalls, 1)
        XCTAssertEqual(health.startCalls, 0)
        XCTAssertEqual(health.reloadCalls, 0)
    }

    func testStartAeroSpaceInvokesHealthStart() {
        let health = RecordingAeroSpaceHealth()
        let doctor = makeDoctor(
            sshResult: .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")),
            sshResolvable: true,
            aerospaceHealth: health
        )

        _ = doctor.startAeroSpace()

        XCTAssertEqual(health.installCalls, 0)
        XCTAssertEqual(health.startCalls, 1)
        XCTAssertEqual(health.reloadCalls, 0)
    }

    func testReloadAeroSpaceConfigInvokesHealthReloadConfig() {
        let health = RecordingAeroSpaceHealth()
        let doctor = makeDoctor(
            sshResult: .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")),
            sshResolvable: true,
            aerospaceHealth: health
        )

        _ = doctor.reloadAeroSpaceConfig()

        XCTAssertEqual(health.installCalls, 0)
        XCTAssertEqual(health.startCalls, 0)
        XCTAssertEqual(health.reloadCalls, 1)
    }

    // MARK: - Doctor.run branch coverage (non-SSH)

    func testRunReportsHomebrewMissing() throws {
        let toml = """
        [[project]]
        name = "Local"
        path = "\(tempDir.path)"
        color = "blue"
        """
        let doctor = try makeDoctorForRun(
            toml: toml,
            allowedExecutables: [],
            runningAeroSpace: true,
            appDiscoveryInstalled: true
        )

        let report = doctor.run()

        XCTAssertTrue(report.findings.contains {
            $0.severity == .fail && $0.title.contains("Homebrew not found")
        })
    }

    func testRunReportsAeroSpaceNotInstalledAndCliUnavailable() throws {
        let toml = """
        [[project]]
        name = "Local"
        path = "\(tempDir.path)"
        color = "blue"
        """
        let health = RecordingAeroSpaceHealth()
        health.installStatusValue = AeroSpaceInstallStatus(isInstalled: false, appPath: nil)
        health.cliAvailableValue = false

        let doctor = try makeDoctorForRun(
            toml: toml,
            allowedExecutables: ["/usr/bin/brew"],
            runningAeroSpace: false,
            appDiscoveryInstalled: true,
            aerospaceHealth: health
        )

        let report = doctor.run()

        XCTAssertTrue(report.findings.contains {
            $0.severity == .fail && $0.title.contains("AeroSpace.app not found")
        })
        XCTAssertTrue(report.findings.contains {
            $0.severity == .fail && $0.title.contains("aerospace CLI not available")
        })
        XCTAssertTrue(report.findings.contains {
            $0.severity == .fail && $0.title.contains("Critical: AeroSpace setup incomplete")
        })
        XCTAssertTrue(report.actions.canInstallAeroSpace)
        XCTAssertFalse(report.actions.canStartAeroSpace)
        XCTAssertFalse(report.actions.canReloadAeroSpaceConfig)
    }

    func testRunReportsCompatibilityIncompatible() throws {
        let toml = """
        [[project]]
        name = "Local"
        path = "\(tempDir.path)"
        color = "blue"
        """
        let health = RecordingAeroSpaceHealth()
        health.installStatusValue = AeroSpaceInstallStatus(isInstalled: true, appPath: "/Applications/AeroSpace.app")
        health.cliAvailableValue = true
        health.compatibilityValue = .incompatible(detail: "missing flags")

        let doctor = try makeDoctorForRun(
            toml: toml,
            allowedExecutables: ["/usr/bin/brew"],
            runningAeroSpace: true,
            appDiscoveryInstalled: true,
            aerospaceHealth: health
        )

        let report = doctor.run()

        XCTAssertTrue(report.findings.contains {
            $0.severity == .fail && $0.title.contains("aerospace CLI compatibility issues")
        })
    }

    func testRunReportsVSCodeAndChromeMissing() throws {
        let toml = """
        [[project]]
        name = "Local"
        path = "\(tempDir.path)"
        color = "blue"
        """
        let doctor = try makeDoctorForRun(
            toml: toml,
            allowedExecutables: ["/usr/bin/brew"],
            runningAeroSpace: true,
            appDiscoveryInstalled: false
        )

        let report = doctor.run()

        XCTAssertTrue(report.findings.contains {
            $0.severity == .warn && $0.title.contains("VS Code not found")
        })
        XCTAssertTrue(report.findings.contains {
            $0.severity == .warn && $0.title.contains("Google Chrome not found")
        })
    }

    func testRunReportsAgentLayerCliMissingWhenRequiredByConfig() throws {
        let toml = """
        [[project]]
        name = "Local"
        path = "\(tempDir.path)"
        color = "blue"
        useAgentLayer = true
        """
        let doctor = try makeDoctorForRun(
            toml: toml,
            allowedExecutables: ["/usr/bin/brew"],
            runningAeroSpace: true,
            appDiscoveryInstalled: true
        )

        let report = doctor.run()

        XCTAssertTrue(report.findings.contains {
            $0.severity == .fail && $0.title.contains("Agent layer CLI (al) not found")
        })
    }

    func testRunReportsHotkeyStatusesWhenProviderPresent() throws {
        let toml = """
        [[project]]
        name = "Local"
        path = "\(tempDir.path)"
        color = "blue"
        """

        do {
            let doctor = try makeDoctorForRun(
                toml: toml,
                allowedExecutables: ["/usr/bin/brew"],
                runningAeroSpace: true,
                appDiscoveryInstalled: true,
                hotkeyStatusProvider: StubHotkeyStatusProvider(status: .registered)
            )
            let report = doctor.run()
            XCTAssertTrue(report.findings.contains {
                $0.severity == .pass && $0.title.contains("Hotkey registered")
            })
        }

        do {
            let doctor = try makeDoctorForRun(
                toml: toml,
                allowedExecutables: ["/usr/bin/brew"],
                runningAeroSpace: true,
                appDiscoveryInstalled: true,
                hotkeyStatusProvider: StubHotkeyStatusProvider(status: .failed(osStatus: -50))
            )
            let report = doctor.run()
            XCTAssertTrue(report.findings.contains {
                $0.severity == .warn && $0.title.contains("Hotkey registration failed")
            })
        }
    }

    func testRunReportsConfigFileErrorWhenMissing() throws {
        // Do not create config file at all.
        let dataStore = DataPaths(homeDirectory: tempDir)

        let resolver = ExecutableResolver(
            fileSystem: SelectiveFileSystem(executablePaths: ["/usr/bin/brew"]),
            searchPaths: ["/usr/bin"],
            loginShellFallbackEnabled: false
        )

        let doctor = Doctor(
            runningApplicationChecker: StubRunningAppChecker(),
            hotkeyStatusProvider: nil,
            dateProvider: StubDateProvider(),
            aerospaceHealth: StubAeroSpaceHealth(),
            appDiscovery: StubAppDiscovery(),
            executableResolver: resolver,
            commandRunner: StubCommandRunner(result: .failure(ApCoreError(message: "not used"))),
            dataStore: dataStore
        )

        let report = doctor.run()

        XCTAssertTrue(report.findings.contains {
            $0.severity == .fail && $0.title.contains("Config file error")
        })
        XCTAssertTrue(FileManager.default.fileExists(atPath: dataStore.configFile.path))
    }

    // MARK: - SSH exit 1 → FAIL (path missing)

    func testSSHProjectExitOneFailsFinding() {
        let doctor = makeDoctor(
            sshResult: .success(ApCommandResult(exitCode: 1, stdout: "", stderr: "")),
            sshResolvable: true
        )

        let report = doctor.run()

        XCTAssertTrue(report.findings.contains {
            $0.severity == .fail && $0.title.contains("Remote project path missing: remote-ml")
        })
    }

    // MARK: - SSH exit 255 → WARN (SSH connection failed)

    func testSSHProjectExit255WarnsConnectionFailed() {
        let doctor = makeDoctor(
            sshResult: .success(ApCommandResult(exitCode: 255, stdout: "", stderr: "Connection refused")),
            sshResolvable: true
        )

        let report = doctor.run()

        XCTAssertTrue(report.findings.contains {
            $0.severity == .warn && $0.title.contains("Cannot verify remote path: remote-ml")
        })
    }

    // MARK: - SSH other exit → WARN (unexpected)

    func testSSHProjectOtherExitWarnsUnexpected() {
        let doctor = makeDoctor(
            sshResult: .success(ApCommandResult(exitCode: 42, stdout: "", stderr: "something weird")),
            sshResolvable: true
        )

        let report = doctor.run()

        XCTAssertTrue(report.findings.contains {
            $0.severity == .warn && $0.title.contains("Unexpected SSH result (exit 42): remote-ml")
        })
    }

    // MARK: - ssh not found → WARN

    func testSSHProjectSSHNotFoundWarns() {
        let doctor = makeDoctor(
            sshResult: .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")),
            sshResolvable: false
        )

        let report = doctor.run()

        XCTAssertTrue(report.findings.contains {
            $0.severity == .warn && $0.title.contains("ssh not found")
        })
    }

    // MARK: - Command runner failure → WARN with verbatim message

    func testSSHProjectRunnerFailureWarnsWithMessage() {
        let doctor = makeDoctor(
            sshResult: .failure(ApCoreError(message: "Command timed out after 10.0s: ssh")),
            sshResolvable: true
        )

        let report = doctor.run()

        let finding = report.findings.first {
            $0.severity == .warn && $0.title.contains("Cannot verify remote path for remote-ml")
        }
        XCTAssertNotNil(finding)
    }

    // MARK: - Local project unchanged

    func testLocalProjectPathCheckUnchanged() {
        let toml = """
        [[project]]
        name = "Local Project"
        path = "/nonexistent/path/for/testing"
        color = "blue"
        """
        let doctor = makeDoctor(
            toml: toml,
            sshResult: .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")),
            sshResolvable: true
        )

        let report = doctor.run()

        let hasLocalPathFinding = report.findings.contains {
            $0.title.contains("Project path") && $0.title.contains("local-project")
        }
        XCTAssertTrue(hasLocalPathFinding)
        let hasSSHFinding = report.findings.contains {
            $0.title.contains("Remote project path") || $0.title.contains("ssh not found")
        }
        XCTAssertFalse(hasSSHFinding)
    }

    // MARK: - SSH project skips .agent-layer check

    func testSSHProjectSkipsAgentLayerDirCheck() {
        let doctor = makeDoctor(
            sshResult: .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")),
            sshResolvable: true
        )

        let report = doctor.run()

        let hasAgentLayerFinding = report.findings.contains {
            $0.title.contains("Agent layer exists") || $0.title.contains("Agent layer missing")
        }
        XCTAssertFalse(hasAgentLayerFinding)
    }

    // MARK: - Option terminator

    func testSSHCommandIncludesOptionTerminator() {
        let runner = StubCommandRunner(
            result: .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        )
        let doctor = makeDoctor(
            sshResult: .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")),
            sshResolvable: true,
            commandRunner: runner
        )

        _ = doctor.run()

        guard let args = runner.lastArguments else {
            XCTFail("Expected ssh command to have been called")
            return
        }
        // Verify "--" appears before the authority
        guard let terminatorIndex = args.firstIndex(of: "--") else {
            XCTFail("Expected '--' option terminator in ssh arguments: \(args)")
            return
        }
        let authorityIndex = terminatorIndex + 1
        XCTAssertTrue(authorityIndex < args.count, "Authority should follow '--'")
        XCTAssertEqual(args[authorityIndex], "nconn@happy-mac.local")
    }

    // MARK: - Helpers

    private static let sshConfigTOML = """
    [[project]]
    name = "Remote ML"
    remote = "ssh-remote+nconn@happy-mac.local"
    path = "/Users/nconn/project"
    color = "teal"
    useAgentLayer = false
    """

    private func makeDoctor(
        toml: String? = nil,
        sshResult: Result<ApCommandResult, ApCoreError>,
        sshResolvable: Bool,
        commandRunner: StubCommandRunner? = nil,
        aerospaceHealth: AeroSpaceHealthChecking = StubAeroSpaceHealth()
    ) -> Doctor {
        let configDir = tempDir.appendingPathComponent(".config/agent-panel", isDirectory: true)
        try! FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let configFile = configDir.appendingPathComponent("config.toml")
        try! (toml ?? Self.sshConfigTOML).write(to: configFile, atomically: true, encoding: .utf8)

        let dataStore = DataPaths(homeDirectory: tempDir)

        // Build a controlled ExecutableResolver:
        // - "brew" always found (avoids Doctor FAIL for Homebrew)
        // - "ssh" found only when sshResolvable is true
        // - Login shell fallback disabled so we fully control resolution
        let allowedExecutables: Set<String> = sshResolvable
            ? ["/usr/bin/brew", "/usr/bin/ssh"]
            : ["/usr/bin/brew"]
        let stubFS = SelectiveFileSystem(executablePaths: allowedExecutables)
        let resolver = ExecutableResolver(
            fileSystem: stubFS,
            searchPaths: ["/usr/bin"],
            loginShellFallbackEnabled: false
        )

        let runner = commandRunner ?? StubCommandRunner(result: sshResult)

        return Doctor(
            runningApplicationChecker: StubRunningAppChecker(),
            hotkeyStatusProvider: nil,
            dateProvider: StubDateProvider(),
            aerospaceHealth: aerospaceHealth,
            appDiscovery: StubAppDiscovery(),
            executableResolver: resolver,
            commandRunner: runner,
            dataStore: dataStore
        )
    }

    private func makeDoctorForRun(
        toml: String,
        allowedExecutables: Set<String>,
        runningAeroSpace: Bool,
        appDiscoveryInstalled: Bool,
        aerospaceHealth: AeroSpaceHealthChecking = StubAeroSpaceHealth(),
        hotkeyStatusProvider: HotkeyStatusProviding? = nil
    ) throws -> Doctor {
        let configDir = tempDir.appendingPathComponent(".config/agent-panel", isDirectory: true)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let configFile = configDir.appendingPathComponent("config.toml")
        try toml.write(to: configFile, atomically: true, encoding: .utf8)

        let dataStore = DataPaths(homeDirectory: tempDir)

        let resolver = ExecutableResolver(
            fileSystem: SelectiveFileSystem(executablePaths: allowedExecutables),
            searchPaths: ["/usr/bin"],
            loginShellFallbackEnabled: false
        )

        let runningChecker = StubRunningAppCheckerOverride(runningAeroSpace: runningAeroSpace)
        let appDiscovery: any AppDiscovering = appDiscoveryInstalled ? StubAppDiscovery() : NilAppDiscovery()

        // Fail loudly if SSH path verification is attempted in these tests.
        let runner = StubCommandRunner(result: .failure(ApCoreError(message: "unexpected ssh invocation")))

        return Doctor(
            runningApplicationChecker: runningChecker,
            hotkeyStatusProvider: hotkeyStatusProvider,
            dateProvider: StubDateProvider(),
            aerospaceHealth: aerospaceHealth,
            appDiscovery: appDiscovery,
            executableResolver: resolver,
            commandRunner: runner,
            dataStore: dataStore
        )
    }
}

// MARK: - Test Doubles

private struct StubRunningAppChecker: RunningApplicationChecking {
    func isApplicationRunning(bundleIdentifier: String) -> Bool {
        bundleIdentifier == "bobko.aerospace"
    }
}

private struct StubRunningAppCheckerOverride: RunningApplicationChecking {
    let runningAeroSpace: Bool

    func isApplicationRunning(bundleIdentifier: String) -> Bool {
        if bundleIdentifier == "bobko.aerospace" {
            return runningAeroSpace
        }
        return false
    }
}

private struct NilAppDiscovery: AppDiscovering {
    func applicationURL(bundleIdentifier: String) -> URL? { nil }
    func applicationURL(named appName: String) -> URL? { nil }
    func bundleIdentifier(forApplicationAt url: URL) -> String? { nil }
}

private struct StubHotkeyStatusProvider: HotkeyStatusProviding {
    let status: HotkeyRegistrationStatus?

    func hotkeyRegistrationStatus() -> HotkeyRegistrationStatus? { status }
}

private struct StubDateProvider: DateProviding {
    func now() -> Date { Date(timeIntervalSince1970: 1704067200) }
}

private struct StubAeroSpaceHealth: AeroSpaceHealthChecking {
    func installStatus() -> AeroSpaceInstallStatus {
        AeroSpaceInstallStatus(isInstalled: true, appPath: "/Applications/AeroSpace.app")
    }
    func isCliAvailable() -> Bool { true }
    func healthCheckCompatibility() -> AeroSpaceCompatibility { .compatible }
    func healthInstallViaHomebrew() -> Bool { true }
    func healthStart() -> Bool { true }
    func healthReloadConfig() -> Bool { true }
}

private final class RecordingAeroSpaceHealth: AeroSpaceHealthChecking {
    private(set) var installCalls: Int = 0
    private(set) var startCalls: Int = 0
    private(set) var reloadCalls: Int = 0
    var installStatusValue: AeroSpaceInstallStatus = AeroSpaceInstallStatus(isInstalled: true, appPath: "/Applications/AeroSpace.app")
    var cliAvailableValue: Bool = true
    var compatibilityValue: AeroSpaceCompatibility = .compatible

    func installStatus() -> AeroSpaceInstallStatus {
        installStatusValue
    }
    func isCliAvailable() -> Bool { cliAvailableValue }
    func healthCheckCompatibility() -> AeroSpaceCompatibility { compatibilityValue }

    func healthInstallViaHomebrew() -> Bool {
        installCalls += 1
        return true
    }

    func healthStart() -> Bool {
        startCalls += 1
        return true
    }

    func healthReloadConfig() -> Bool {
        reloadCalls += 1
        return true
    }
}

private struct StubAppDiscovery: AppDiscovering {
    func applicationURL(bundleIdentifier: String) -> URL? {
        URL(fileURLWithPath: "/Applications/Test.app")
    }
    func applicationURL(named appName: String) -> URL? {
        URL(fileURLWithPath: "/Applications/Test.app")
    }
    func bundleIdentifier(forApplicationAt url: URL) -> String? { nil }
}

/// File system stub that reports specific paths as executable.
private struct SelectiveFileSystem: FileSystem {
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

private class StubCommandRunner: CommandRunning {
    let result: Result<ApCommandResult, ApCoreError>
    private(set) var lastArguments: [String]?

    init(result: Result<ApCommandResult, ApCoreError>) {
        self.result = result
    }

    func run(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval?,
        workingDirectory: String?
    ) -> Result<ApCommandResult, ApCoreError> {
        lastArguments = arguments
        return result
    }
}
