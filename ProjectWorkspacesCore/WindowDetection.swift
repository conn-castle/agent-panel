import Foundation

/// Time budget for multi-phase window detection.
struct LaunchDetectionTimeouts: Equatable {
    let workspaceMs: Int
    let focusedPrimaryMs: Int
    let focusedSecondaryMs: Int
}

/// Shared multi-phase window detection pipeline.
struct WindowDetectionPipeline {
    let sleeper: AeroSpaceSleeping
    let workspaceSchedule: PollSchedule
    let focusedFastSchedule: PollSchedule
    let focusedSteadySchedule: PollSchedule

    /// Runs workspace → focused fast → focused steady detection.
    /// - Parameters:
    ///   - timeouts: Timeout budgets for each phase.
    ///   - workspaceAttempt: Attempt closure for workspace polling.
    ///   - focusedAttempt: Attempt closure for focused polling.
    /// - Returns: Success, failure, or timed-out outcome.
    func run<Success, Failure>(
        timeouts: LaunchDetectionTimeouts,
        workspaceAttempt: () -> PollDecision<Success, Failure>,
        focusedAttempt: () -> PollDecision<Success, Failure>
    ) -> PollOutcome<Success, Failure> {
        if timeouts.workspaceMs > 0 {
            let workspaceOutcome = Poller.poll(
                schedule: workspaceSchedule,
                timeoutMs: timeouts.workspaceMs,
                sleeper: sleeper,
                attempt: workspaceAttempt
            )
            switch workspaceOutcome {
            case .success, .failure:
                return workspaceOutcome
            case .timedOut:
                break
            }
        }

        if timeouts.focusedPrimaryMs > 0 {
            let focusedPrimaryOutcome = Poller.poll(
                schedule: focusedFastSchedule,
                timeoutMs: timeouts.focusedPrimaryMs,
                sleeper: sleeper,
                attempt: focusedAttempt
            )
            switch focusedPrimaryOutcome {
            case .success, .failure:
                return focusedPrimaryOutcome
            case .timedOut:
                break
            }
        }

        if timeouts.focusedSecondaryMs > 0 {
            return Poller.poll(
                schedule: focusedSteadySchedule,
                timeoutMs: timeouts.focusedSecondaryMs,
                sleeper: sleeper,
                attempt: focusedAttempt
            )
        }

        return .timedOut
    }
}

/// Shared retry decisions for AeroSpace polling attempts.
struct WindowDetectionRetryPolicy {
    static func shouldRetryPoll(_ error: AeroSpaceCommandError) -> Bool {
        switch error {
        case .timedOut, .notReady:
            return true
        case .launchFailed, .decodingFailed, .unexpectedOutput, .nonZeroExit:
            return false
        }
    }

    static func shouldRetryFocusedWindow(_ error: AeroSpaceCommandError) -> Bool {
        switch error {
        case .nonZeroExit(let command, _):
            return command.contains("list-windows --focused")
        case .unexpectedOutput(let command, _):
            return command.contains("list-windows --focused")
        case .timedOut, .notReady:
            return true
        case .launchFailed, .decodingFailed:
            return false
        }
    }
}
