import Foundation

/// Time budget for multi-phase window detection.
struct LaunchDetectionTimeouts: Equatable {
    let workspaceMs: Int
    let focusedPrimaryMs: Int
    let focusedSecondaryMs: Int
}

/// Shared configuration for multi-phase window detection.
struct WindowDetectionConfiguration {
    let timeouts: LaunchDetectionTimeouts
    let workspaceSchedule: PollSchedule
    let focusedFastSchedule: PollSchedule
    let focusedSteadySchedule: PollSchedule

    /// Creates a configuration from poll and timeout inputs.
    /// - Parameters:
    ///   - pollIntervalMs: Base poll interval in milliseconds.
    ///   - pollTimeoutMs: Overall timeout in milliseconds.
    ///   - workspaceProbeTimeoutMs: Workspace-only probe timeout in milliseconds.
    ///   - focusedProbeTimeoutMs: Initial focused-window probe timeout in milliseconds.
    init(
        pollIntervalMs: Int,
        pollTimeoutMs: Int,
        workspaceProbeTimeoutMs: Int,
        focusedProbeTimeoutMs: Int
    ) {
        precondition(pollIntervalMs > 0, "pollIntervalMs must be positive")
        precondition(pollTimeoutMs > 0, "pollTimeoutMs must be positive")
        precondition(workspaceProbeTimeoutMs > 0, "workspaceProbeTimeoutMs must be positive")
        precondition(focusedProbeTimeoutMs > 0, "focusedProbeTimeoutMs must be positive")

        // Split the overall timeout into a workspace-first budget and focused-window fallback.
        // Workspace polling gets up to 50% of the total budget, but never exceeds its explicit cap.
        let overallTimeoutMs = pollTimeoutMs
        let workspaceMs = min(workspaceProbeTimeoutMs, max(1, overallTimeoutMs / 2))
        let remainingMs = max(0, overallTimeoutMs - workspaceMs)
        let focusedPrimaryMs = min(focusedProbeTimeoutMs, remainingMs)
        let focusedSecondaryMs = max(0, remainingMs - focusedPrimaryMs)
        self.timeouts = LaunchDetectionTimeouts(
            workspaceMs: workspaceMs,
            focusedPrimaryMs: focusedPrimaryMs,
            focusedSecondaryMs: focusedSecondaryMs
        )

        let fastPollIntervalMs = max(1, pollIntervalMs / 2)
        self.workspaceSchedule = PollSchedule(
            initialIntervalsMs: [fastPollIntervalMs],
            steadyIntervalMs: pollIntervalMs
        )
        self.focusedFastSchedule = PollSchedule(
            initialIntervalsMs: [],
            steadyIntervalMs: fastPollIntervalMs
        )
        self.focusedSteadySchedule = PollSchedule(
            initialIntervalsMs: [],
            steadyIntervalMs: pollIntervalMs
        )
    }

    /// Creates a detection pipeline with the configured schedules.
    /// - Parameter sleeper: Sleeper used between polling attempts.
    /// - Returns: Configured window detection pipeline.
    func pipeline(sleeper: AeroSpaceSleeping) -> WindowDetectionPipeline {
        WindowDetectionPipeline(
            sleeper: sleeper,
            workspaceSchedule: workspaceSchedule,
            focusedFastSchedule: focusedFastSchedule,
            focusedSteadySchedule: focusedSteadySchedule
        )
    }
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
        case .executionFailed, .decodingFailed, .unexpectedOutput:
            return false
        }
    }

    static func shouldRetryFocusedWindow(_ error: AeroSpaceCommandError) -> Bool {
        switch error {
        case .executionFailed(let executionError):
            switch executionError {
            case .nonZeroExit(let command, _):
                return command.contains("list-windows --focused")
            case .launchFailed:
                return false
            }
        case .unexpectedOutput(let command, _):
            return command.contains("list-windows --focused")
        case .timedOut, .notReady:
            return true
        case .decodingFailed:
            return false
        }
    }
}
