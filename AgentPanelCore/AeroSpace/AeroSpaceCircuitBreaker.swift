//
//  AeroSpaceCircuitBreaker.swift
//  AgentPanelCore
//
//  Thread-safe circuit breaker for AeroSpace CLI commands.
//
//  When AeroSpace becomes unresponsive (crashes, socket dies), every subsequent
//  CLI command times out at 5s each. With 15-20 calls in a Doctor check, this
//  creates a ~90s freeze cascade. The circuit breaker detects the first timeout
//  and immediately fails subsequent calls for a cooldown period.
//

import Foundation

/// Thread-safe circuit breaker that prevents cascading timeouts when AeroSpace
/// becomes unresponsive.
///
/// States:
/// - **Closed**: Normal operation. All commands pass through.
/// - **Open**: Tripped by a timeout. All commands fail immediately until cooldown expires.
///
/// After cooldown, the breaker transitions back to closed and allows the next call
/// through as a probe. If it succeeds, normal operation resumes. If it times out
/// again, the breaker re-trips.
final class AeroSpaceCircuitBreaker {

    /// Process-wide shared instance for production use.
    static let shared = AeroSpaceCircuitBreaker()

    enum State: Equatable {
        /// Normal operation — commands pass through.
        case closed
        /// Tripped — fail fast until the specified date.
        case open(until: Date)
    }

    /// Cooldown period after a timeout trips the breaker (seconds).
    let cooldownSeconds: TimeInterval

    private var state: State = .closed
    private let lock = NSLock()

    /// Creates a circuit breaker.
    /// - Parameter cooldownSeconds: How long to fail fast after a timeout. Default 30s.
    init(cooldownSeconds: TimeInterval = 30) {
        self.cooldownSeconds = cooldownSeconds
    }

    /// Returns the current breaker state (thread-safe). For testing/diagnostics.
    var currentState: State {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    /// Returns true if calls should be allowed through.
    ///
    /// When the breaker is open and the cooldown has expired, it transitions
    /// back to closed (allowing the next call as a probe).
    func shouldAllow() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        switch state {
        case .closed:
            return true
        case .open(let until):
            if Date() >= until {
                state = .closed
                return true
            }
            return false
        }
    }

    /// Records a timeout failure, tripping the breaker to open state.
    func recordTimeout() {
        lock.lock()
        defer { lock.unlock() }
        state = .open(until: Date().addingTimeInterval(cooldownSeconds))
    }

    /// Records a successful call, closing the breaker.
    func recordSuccess() {
        lock.lock()
        defer { lock.unlock() }
        state = .closed
    }

    /// Resets the breaker to closed state.
    ///
    /// Called after a fresh AeroSpace start to clear any tripped state,
    /// and by tests to ensure clean state.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        state = .closed
    }
}
