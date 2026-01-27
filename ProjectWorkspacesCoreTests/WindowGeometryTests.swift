import Foundation
import XCTest

@testable import ProjectWorkspacesCore

final class WindowGeometryTests: XCTestCase {
    func testApplySkipsWhenFocusNotVerified() {
        let focusController = TestFocusController(result: .success(CommandResult(exitCode: 0, stdout: "", stderr: "")))
        let verifier = TestFocusVerifier(
            result: FocusVerificationResult(
                matches: false,
                actualWindowId: 99,
                actualWorkspace: "pw-other"
            )
        )
        let accessibility = TestAccessibilityApplier(result: .success(()))
        let applier = AXWindowGeometryApplier(
            focusController: focusController,
            focusVerifier: verifier,
            accessibilityApplier: accessibility
        )

        let outcome = applier.apply(
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            toWindowId: 42,
            inWorkspace: "pw-codex"
        )

        XCTAssertEqual(
            outcome,
            .skipped(
                reason: .focusNotVerified(
                    expectedWindowId: 42,
                    expectedWorkspace: "pw-codex",
                    actualWindowId: 99,
                    actualWorkspace: "pw-other"
                )
            )
        )
        XCTAssertEqual(accessibility.callCount, 0)
        XCTAssertEqual(focusController.calls, [42])
        XCTAssertEqual(verifier.callCount, 1)
    }

    func testApplyFailsWhenFocusCommandFails() {
        let error = AeroSpaceCommandError.nonZeroExit(
            command: "focus --window-id 42",
            result: CommandResult(exitCode: 1, stdout: "", stderr: "fail")
        )
        let focusController = TestFocusController(result: .failure(error))
        let verifier = TestFocusVerifier(
            result: FocusVerificationResult(matches: true, actualWindowId: 42, actualWorkspace: "pw-codex")
        )
        let accessibility = TestAccessibilityApplier(result: .success(()))
        let applier = AXWindowGeometryApplier(
            focusController: focusController,
            focusVerifier: verifier,
            accessibilityApplier: accessibility
        )

        let outcome = applier.apply(
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            toWindowId: 42,
            inWorkspace: "pw-codex"
        )

        XCTAssertEqual(outcome, .failed(error: .aeroSpaceFailed(error)))
        XCTAssertEqual(accessibility.callCount, 0)
        XCTAssertEqual(verifier.callCount, 0)
    }

    func testApplyInvokesAccessibilityWhenVerified() {
        let focusController = TestFocusController(result: .success(CommandResult(exitCode: 0, stdout: "", stderr: "")))
        let verifier = TestFocusVerifier(
            result: FocusVerificationResult(matches: true, actualWindowId: 42, actualWorkspace: "pw-codex")
        )
        let accessibility = TestAccessibilityApplier(result: .success(()))
        let applier = AXWindowGeometryApplier(
            focusController: focusController,
            focusVerifier: verifier,
            accessibilityApplier: accessibility
        )

        let outcome = applier.apply(
            frame: CGRect(x: 10, y: 20, width: 300, height: 400),
            toWindowId: 42,
            inWorkspace: "pw-codex"
        )

        XCTAssertEqual(outcome, .applied)
        XCTAssertEqual(accessibility.callCount, 1)
        XCTAssertEqual(focusController.calls, [42])
        XCTAssertEqual(verifier.callCount, 1)
    }
}
