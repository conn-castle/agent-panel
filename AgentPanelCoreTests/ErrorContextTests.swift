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
        let doctor = Doctor(
            runningApplicationChecker: StubRunningApplicationChecker(),
            hotkeyStatusProvider: StubHotkeyStatusProvider()
        )

        let report = doctor.run(context: ctx)

        // The report should render and include the context info
        let rendered = report.rendered()
        XCTAssertTrue(rendered.contains("Triggered by: activation"))
        XCTAssertTrue(rendered.contains("activation failed"))
    }

    func testDoctorRunWithoutContext() {
        let doctor = Doctor(
            runningApplicationChecker: StubRunningApplicationChecker(),
            hotkeyStatusProvider: StubHotkeyStatusProvider()
        )

        let report = doctor.run()

        // Report should not contain "Triggered by:" when no context
        let rendered = report.rendered()
        XCTAssertFalse(rendered.contains("Triggered by:"))
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
