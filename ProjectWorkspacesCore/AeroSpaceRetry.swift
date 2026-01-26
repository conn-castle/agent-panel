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
