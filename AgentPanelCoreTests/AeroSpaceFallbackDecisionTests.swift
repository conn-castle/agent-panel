import XCTest
@testable import AgentPanelCore

final class AeroSpaceFallbackDecisionTests: XCTestCase {

    func testFallbackDecisionIsFalseWhenPrimaryCommandSucceeds() {
        let primary = Result<ApCommandResult, ApCoreError>.success(
            ApCommandResult(exitCode: 0, stdout: "", stderr: "")
        )

        XCTAssertFalse(ApAeroSpace.shouldAttemptCompatibilityFallback(primary))
    }

    func testFallbackDecisionIsTrueWhenPrimaryCommandExitsNonZero() {
        let primary = Result<ApCommandResult, ApCoreError>.success(
            ApCommandResult(exitCode: 2, stdout: "", stderr: "unsupported flag")
        )

        XCTAssertTrue(ApAeroSpace.shouldAttemptCompatibilityFallback(primary))
    }

    func testFallbackDecisionIsFalseWhenPrimaryCommandFailsToRun() {
        let primary = Result<ApCommandResult, ApCoreError>.failure(
            ApCoreError(message: "Executable not found: aerospace")
        )

        XCTAssertFalse(ApAeroSpace.shouldAttemptCompatibilityFallback(primary))
    }
}
