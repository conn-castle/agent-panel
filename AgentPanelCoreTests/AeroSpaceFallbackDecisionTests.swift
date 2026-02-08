import XCTest
@testable import AgentPanelCore

final class AeroSpaceFallbackDecisionTests: XCTestCase {

    func testFallbackDecisionIsFalseWhenPrimaryCommandSucceeds() {
        let primary = Result<ApCommandResult, ApCoreError>.success(
            ApCommandResult(exitCode: 0, stdout: "", stderr: "")
        )

        XCTAssertFalse(ApAeroSpace.shouldAttemptCompatibilityFallback(primary))
    }

    func testFallbackDecisionIsTrueWhenOutputContainsUnknownOption() {
        let primary = Result<ApCommandResult, ApCoreError>.success(
            ApCommandResult(exitCode: 2, stdout: "", stderr: "error: unknown option '--focus-follows-window'")
        )

        XCTAssertTrue(ApAeroSpace.shouldAttemptCompatibilityFallback(primary))
    }

    func testFallbackDecisionIsTrueWhenOutputContainsUnrecognizedCommand() {
        let primary = Result<ApCommandResult, ApCoreError>.success(
            ApCommandResult(exitCode: 1, stdout: "", stderr: "unrecognized command: summon-workspace")
        )

        XCTAssertTrue(ApAeroSpace.shouldAttemptCompatibilityFallback(primary))
    }

    func testFallbackDecisionIsTrueWhenMandatoryOptionNotSpecified() {
        let primary = Result<ApCommandResult, ApCoreError>.success(
            ApCommandResult(exitCode: 1, stdout: "", stderr: "Mandatory option is not specified (--focused|--all|--monitor|--workspace)")
        )

        XCTAssertTrue(ApAeroSpace.shouldAttemptCompatibilityFallback(primary))
    }

    func testFallbackDecisionIsFalseForNonZeroExitWithoutCompatibilityIndicator() {
        let primary = Result<ApCommandResult, ApCoreError>.success(
            ApCommandResult(exitCode: 1, stdout: "", stderr: "workspace 'ap-test' not found")
        )

        XCTAssertFalse(ApAeroSpace.shouldAttemptCompatibilityFallback(primary))
    }

    func testFallbackDecisionIsFalseWhenPrimaryCommandFailsToRun() {
        let primary = Result<ApCommandResult, ApCoreError>.failure(
            ApCoreError(message: "Executable not found: aerospace")
        )

        XCTAssertFalse(ApAeroSpace.shouldAttemptCompatibilityFallback(primary))
    }
}
