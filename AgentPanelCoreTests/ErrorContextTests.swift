import XCTest
@testable import AgentPanelCore

final class ErrorContextTests: XCTestCase {

    // MARK: - Creation

    func testErrorContextCreation() {
        let ctx = ErrorContext(category: .command, message: "Failed to activate", trigger: "activation")

        XCTAssertEqual(ctx.category, .command)
        XCTAssertEqual(ctx.message, "Failed to activate")
        XCTAssertEqual(ctx.trigger, "activation")
    }

    // MARK: - isCritical

    func testActivationCommandIsCritical() {
        let ctx = ErrorContext(category: .command, message: "error", trigger: "activation")
        XCTAssertTrue(ctx.isCritical)
    }

    func testConfigLoadConfigurationIsCritical() {
        let ctx = ErrorContext(category: .configuration, message: "error", trigger: "configLoad")
        XCTAssertTrue(ctx.isCritical)
    }

    func testWorkspaceQueryIsNotCritical() {
        let ctx = ErrorContext(category: .command, message: "error", trigger: "workspaceQuery")
        XCTAssertFalse(ctx.isCritical)
    }

    func testCloseProjectIsNotCritical() {
        let ctx = ErrorContext(category: .command, message: "error", trigger: "closeProject")
        XCTAssertFalse(ctx.isCritical)
    }

    func testExitToPreviousIsNotCritical() {
        let ctx = ErrorContext(category: .command, message: "error", trigger: "exitToPrevious")
        XCTAssertFalse(ctx.isCritical)
    }

    func testCommandCategoryWithConfigLoadTriggerIsNotCritical() {
        // category .command + trigger "configLoad" is NOT critical (config errors use .configuration)
        let ctx = ErrorContext(category: .command, message: "error", trigger: "configLoad")
        XCTAssertFalse(ctx.isCritical)
    }

    func testConfigurationCategoryWithActivationTriggerIsNotCritical() {
        // category .configuration + trigger "activation" is NOT critical (activation errors use .command)
        let ctx = ErrorContext(category: .configuration, message: "error", trigger: "activation")
        XCTAssertFalse(ctx.isCritical)
    }

    func testWindowCategoryIsNotCritical() {
        let ctx = ErrorContext(category: .window, message: "error", trigger: "activation")
        XCTAssertFalse(ctx.isCritical)
    }

    func testFileSystemCategoryIsNotCritical() {
        let ctx = ErrorContext(category: .fileSystem, message: "error", trigger: "activation")
        XCTAssertFalse(ctx.isCritical)
    }

    // MARK: - Equatable

    func testErrorContextEquatable() {
        let a = ErrorContext(category: .command, message: "error", trigger: "activation")
        let b = ErrorContext(category: .command, message: "error", trigger: "activation")
        let c = ErrorContext(category: .command, message: "different", trigger: "activation")

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Doctor Context Integration

    func testDoctorRunAcceptsContext() {
        // Verify that Doctor.run(context:) accepts an ErrorContext and includes it in metadata
        let ctx = ErrorContext(category: .command, message: "activation failed", trigger: "activation")
        let doctor = makeDoctor()

        let report = doctor.run(context: ctx)

        // The report should render and include the context info
        let rendered = report.rendered()
        XCTAssertTrue(rendered.contains("Triggered by: activation"))
        XCTAssertTrue(rendered.contains("activation failed"))
    }

    func testDoctorRunWithoutContext() {
        let doctor = makeDoctor()

        let report = doctor.run()

        // Report should not contain "Triggered by:" when no context
        let rendered = report.rendered()
        XCTAssertFalse(rendered.contains("Triggered by:"))
    }

    // MARK: - Helper

    private func makeDoctor() -> Doctor {
        Doctor(
            runningApplicationChecker: StubRunningApplicationChecker(),
            hotkeyStatusProvider: StubHotkeyStatusProvider(),
            dateProvider: StubDateProvider(),
            aerospaceHealth: StubAeroSpaceHealth(),
            appDiscovery: StubAppDiscovery(),
            executableResolver: ExecutableResolver(
                fileSystem: StubFileSystem(),
                searchPaths: [],
                loginShellFallbackEnabled: false
            ),
            commandRunner: StubCommandRunner(),
            dataStore: DataPaths(homeDirectory: URL(fileURLWithPath: NSTemporaryDirectory()))
        )
    }
}

// MARK: - Test Stubs

private struct StubRunningApplicationChecker: RunningApplicationChecking {
    func isApplicationRunning(bundleIdentifier: String) -> Bool { false }
}

private struct StubHotkeyStatusProvider: HotkeyStatusProviding {
    var status: HotkeyRegistrationStatus? = .registered
    func hotkeyRegistrationStatus() -> HotkeyRegistrationStatus? { status }
}

private struct StubDateProvider: DateProviding {
    func now() -> Date { Date() }
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

private struct StubAppDiscovery: AppDiscovering {
    func applicationURL(bundleIdentifier: String) -> URL? {
        URL(fileURLWithPath: "/Applications/Test.app")
    }
    func applicationURL(named appName: String) -> URL? {
        URL(fileURLWithPath: "/Applications/Test.app")
    }
    func bundleIdentifier(forApplicationAt url: URL) -> String? { nil }
}

private struct StubFileSystem: FileSystem {
    func fileExists(at url: URL) -> Bool { false }
    func isExecutableFile(at url: URL) -> Bool { false }
    func readFile(at url: URL) throws -> Data { throw NSError(domain: "stub", code: 1) }
    func createDirectory(at url: URL) throws {}
    func fileSize(at url: URL) throws -> UInt64 { 0 }
    func removeItem(at url: URL) throws {}
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {}
    func appendFile(at url: URL, data: Data) throws {}
    func writeFile(at url: URL, data: Data) throws {}
}

private class StubCommandRunner: CommandRunning {
    func run(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval?,
        workingDirectory: String?
    ) -> Result<ApCommandResult, ApCoreError> {
        .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
    }
}
