import Foundation
import XCTest

@testable import ProjectWorkspacesCore

final class AeroSpaceFocusVerifierTests: XCTestCase {
    func testVerifySucceedsOnFirstAttempt() {
        let query = TestFocusedWindowQuery(responses: [
            .success([
                AeroSpaceWindow(
                    windowId: 42,
                    workspace: "pw-codex",
                    appBundleId: "com.microsoft.VSCode",
                    appName: "Visual Studio Code",
                    windowTitle: "Window"
                )
            ])
        ])
        let sleeper = TestSleeper()
        let verifier = AeroSpaceFocusVerifier(
            focusedWindowQuery: query,
            sleeper: sleeper,
            attempts: 5,
            delayMs: 50
        )

        let result = verifier.verify(windowId: 42, workspaceName: "pw-codex")

        XCTAssertTrue(result.matches)
        XCTAssertEqual(result.actualWindowId, 42)
        XCTAssertEqual(result.actualWorkspace, "pw-codex")
        XCTAssertEqual(query.callCount, 1)
        XCTAssertTrue(sleeper.sleepCalls.isEmpty)
    }

    func testVerifySucceedsAfterRetries() {
        let query = TestFocusedWindowQuery(responses: [
            .success([
                AeroSpaceWindow(
                    windowId: 99,
                    workspace: "pw-other",
                    appBundleId: "com.microsoft.VSCode",
                    appName: "Visual Studio Code",
                    windowTitle: "Window"
                )
            ]),
            .success([
                AeroSpaceWindow(
                    windowId: 99,
                    workspace: "pw-other",
                    appBundleId: "com.microsoft.VSCode",
                    appName: "Visual Studio Code",
                    windowTitle: "Window"
                )
            ]),
            .success([
                AeroSpaceWindow(
                    windowId: 42,
                    workspace: "pw-codex",
                    appBundleId: "com.microsoft.VSCode",
                    appName: "Visual Studio Code",
                    windowTitle: "Window"
                )
            ])
        ])
        let sleeper = TestSleeper()
        let verifier = AeroSpaceFocusVerifier(
            focusedWindowQuery: query,
            sleeper: sleeper,
            attempts: 5,
            delayMs: 50
        )

        let result = verifier.verify(windowId: 42, workspaceName: "pw-codex")

        XCTAssertTrue(result.matches)
        XCTAssertEqual(result.actualWindowId, 42)
        XCTAssertEqual(result.actualWorkspace, "pw-codex")
        XCTAssertEqual(query.callCount, 3)
        XCTAssertEqual(sleeper.sleepCalls.count, 2)
        XCTAssertEqual(sleeper.sleepCalls[0], 0.05, accuracy: 0.001)
    }

    func testVerifyFailsAfterExhaustingAttempts() {
        let query = TestFocusedWindowQuery(responses: [
            .success([
                AeroSpaceWindow(
                    windowId: 99,
                    workspace: "pw-other",
                    appBundleId: "com.microsoft.VSCode",
                    appName: "Visual Studio Code",
                    windowTitle: "Window"
                )
            ]),
            .success([
                AeroSpaceWindow(
                    windowId: 99,
                    workspace: "pw-other",
                    appBundleId: "com.microsoft.VSCode",
                    appName: "Visual Studio Code",
                    windowTitle: "Window"
                )
            ]),
            .success([
                AeroSpaceWindow(
                    windowId: 99,
                    workspace: "pw-other",
                    appBundleId: "com.microsoft.VSCode",
                    appName: "Visual Studio Code",
                    windowTitle: "Window"
                )
            ])
        ])
        let sleeper = TestSleeper()
        let verifier = AeroSpaceFocusVerifier(
            focusedWindowQuery: query,
            sleeper: sleeper,
            attempts: 3,
            delayMs: 50
        )

        let result = verifier.verify(windowId: 42, workspaceName: "pw-codex")

        XCTAssertFalse(result.matches)
        XCTAssertEqual(result.actualWindowId, 99)
        XCTAssertEqual(result.actualWorkspace, "pw-other")
        XCTAssertEqual(query.callCount, 3)
        XCTAssertEqual(sleeper.sleepCalls.count, 2)
    }

    func testVerifyHandlesCommandFailureGracefully() {
        let error = AeroSpaceCommandError.nonZeroExit(
            command: "list-windows --focused",
            result: CommandResult(exitCode: 1, stdout: "", stderr: "error")
        )
        let query = TestFocusedWindowQuery(responses: [
            .failure(error),
            .failure(error),
            .failure(error)
        ])
        let sleeper = TestSleeper()
        let verifier = AeroSpaceFocusVerifier(
            focusedWindowQuery: query,
            sleeper: sleeper,
            attempts: 3,
            delayMs: 50
        )

        let result = verifier.verify(windowId: 42, workspaceName: "pw-codex")

        XCTAssertFalse(result.matches)
        XCTAssertNil(result.actualWindowId)
        XCTAssertNil(result.actualWorkspace)
        XCTAssertEqual(query.callCount, 3)
        XCTAssertEqual(sleeper.sleepCalls.count, 2)
    }
}
