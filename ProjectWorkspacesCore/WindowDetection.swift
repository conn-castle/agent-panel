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
