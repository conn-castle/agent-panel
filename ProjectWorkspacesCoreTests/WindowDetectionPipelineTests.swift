import Foundation
import XCTest

@testable import ProjectWorkspacesCore

final class WindowDetectionPipelineTests: XCTestCase {
    func testWorkspaceSuccessSkipsFocusedPhase() {
        let pipeline = WindowDetectionPipeline(
            sleeper: TestSleeper(),
            workspaceSchedule: PollSchedule(initialIntervalsMs: [], steadyIntervalMs: 1),
            focusedFastSchedule: PollSchedule(initialIntervalsMs: [], steadyIntervalMs: 1),
            focusedSteadySchedule: PollSchedule(initialIntervalsMs: [], steadyIntervalMs: 1)
        )

        var workspaceCalls = 0
        var focusedCalls = 0

        let outcome: PollOutcome<String, Never> = pipeline.run(
            timeouts: LaunchDetectionTimeouts(workspaceMs: 1, focusedPrimaryMs: 1, focusedSecondaryMs: 1),
            workspaceAttempt: {
                workspaceCalls += 1
                return .success("workspace")
            },
            focusedAttempt: {
                focusedCalls += 1
                return .success("focused")
            }
        )

        switch outcome {
        case .success(let value):
            XCTAssertEqual(value, "workspace")
        case .failure, .timedOut:
            XCTFail("Expected workspace success")
        }
        XCTAssertEqual(workspaceCalls, 1)
        XCTAssertEqual(focusedCalls, 0)
    }

    func testFocusedPhaseRunsAfterWorkspaceTimeout() {
        let pipeline = WindowDetectionPipeline(
            sleeper: TestSleeper(),
            workspaceSchedule: PollSchedule(initialIntervalsMs: [], steadyIntervalMs: 1),
            focusedFastSchedule: PollSchedule(initialIntervalsMs: [], steadyIntervalMs: 1),
            focusedSteadySchedule: PollSchedule(initialIntervalsMs: [], steadyIntervalMs: 1)
        )

        var workspaceCalls = 0
        var focusedCalls = 0

        let outcome: PollOutcome<String, Never> = pipeline.run(
            timeouts: LaunchDetectionTimeouts(workspaceMs: 1, focusedPrimaryMs: 1, focusedSecondaryMs: 0),
            workspaceAttempt: {
                workspaceCalls += 1
                return .keepWaiting
            },
            focusedAttempt: {
                focusedCalls += 1
                return .success("focused")
            }
        )

        switch outcome {
        case .success(let value):
            XCTAssertEqual(value, "focused")
        case .failure, .timedOut:
            XCTFail("Expected focused success")
        }
        XCTAssertEqual(workspaceCalls, 1)
        XCTAssertEqual(focusedCalls, 1)
    }
}
