import Foundation

/// Configuration for AeroSpace command retry behavior.
struct AeroSpaceRetryPolicy: Sendable {
    let maxAttempts: Int
    let initialDelaySeconds: TimeInterval
    let backoffMultiplier: Double
    let maxDelaySeconds: TimeInterval
    let totalCapSeconds: TimeInterval
    let jitterFraction: Double

    static let standard = AeroSpaceRetryPolicy(
        maxAttempts: 20,
        initialDelaySeconds: 0.05,
        backoffMultiplier: 1.5,
        maxDelaySeconds: 0.75,
        totalCapSeconds: 5.0,
        jitterFraction: 0.2
    )
}

/// Abstraction for sleeping between retry attempts.
protocol AeroSpaceSleeping {
    func sleep(seconds: TimeInterval)
}

/// System-backed sleeper using Thread.sleep.
struct SystemAeroSpaceSleeper: AeroSpaceSleeping {
    func sleep(seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}

/// Abstraction for jitter generation in retry delays.
protocol AeroSpaceJitterProviding {
    /// Returns a value in the range [0, 1].
    func nextUnit() -> Double
}

/// System-backed jitter provider using random numbers.
struct SystemAeroSpaceJitterProvider: AeroSpaceJitterProviding {
    func nextUnit() -> Double {
        Double.random(in: 0...1)
    }
}

/// Mutable state tracked during retry attempts.
struct RetryContext {
    let commandDescription: String
    let probeDescription: String
    let startTime: Date
    var attempt: Int = 1
    var delaySeconds: TimeInterval
    var lastCommandResult: CommandResult?
    var lastProbeResult: CommandResult?
}

/// Decision returned by a polling attempt.
enum PollDecision<Success, Failure> {
    case success(Success)
    case failure(Failure)
    case keepWaiting
}

/// Outcome of a polling loop.
enum PollOutcome<Success, Failure> {
    case success(Success)
    case failure(Failure)
    case timedOut
}

/// Shared polling helper for repeated window detection loops.
struct Poller {
    /// Polls until success, failure, or timeout.
    /// - Parameters:
    ///   - intervalMs: Poll interval in milliseconds.
    ///   - timeoutMs: Total timeout in milliseconds.
    ///   - sleeper: Sleeper used between attempts.
    ///   - attempt: Closure that returns success, failure, or keep-waiting.
    /// - Returns: Success, failure, or timed-out outcome.
    static func poll<Success, Failure>(
        intervalMs: Int,
        timeoutMs: Int,
        sleeper: AeroSpaceSleeping,
        attempt: () -> PollDecision<Success, Failure>
    ) -> PollOutcome<Success, Failure> {
        precondition(intervalMs > 0, "intervalMs must be positive")
        precondition(timeoutMs > 0, "timeoutMs must be positive")
        let intervalSeconds = TimeInterval(intervalMs) / 1000.0
        let maxAttempts = max(1, Int(ceil(Double(timeoutMs) / Double(intervalMs))) + 1)

        for attemptIndex in 0..<maxAttempts {
            switch attempt() {
            case .success(let value):
                return .success(value)
            case .failure(let error):
                return .failure(error)
            case .keepWaiting:
                break
            }

            if attemptIndex < maxAttempts - 1 {
                sleeper.sleep(seconds: intervalSeconds)
            }
        }

        return .timedOut
    }
}
