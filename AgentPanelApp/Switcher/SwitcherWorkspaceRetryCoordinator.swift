//
//  SwitcherWorkspaceRetryCoordinator.swift
//  AgentPanel
//
//  Manages the workspace-state retry loop for the switcher.
//  Schedules periodic retries when AeroSpace workspace queries fail
//  (e.g., circuit breaker open during recovery) and reports results
//  back to the controller via closures.
//

import Foundation

import AgentPanelCore

/// Coordinates workspace-state retry logic for the switcher panel.
///
/// Extracted from `SwitcherPanelController` to reduce controller size.
/// The coordinator owns retry state (timer, count, session guard) and
/// reports results through callbacks. The controller remains responsible
/// for UI updates and filter application.
final class SwitcherWorkspaceRetryCoordinator {

    // MARK: - Configuration

    static let defaultMaxAttempts = 5
    static let defaultRetryIntervalSeconds: TimeInterval = 2.0

    let maxAttempts: Int
    let retryIntervalSeconds: TimeInterval

    // MARK: - Dependencies

    private let projectManager: ProjectManager
    private let session: SwitcherSession

    // MARK: - Callbacks

    /// Called on the main thread when a retry succeeds.
    /// Parameter: the workspace state snapshot.
    var onRetrySucceeded: ((ProjectWorkspaceState) -> Void)?

    /// Called on the main thread when all retries are exhausted.
    /// Parameter: the last error encountered.
    var onRetryExhausted: ((ProjectError) -> Void)?

    // MARK: - State

    private var retryTimer: DispatchSourceTimer?
    private var retryCount: Int = 0
    private var retryGeneration: UInt64 = 0

    // MARK: - Init

    /// Creates a workspace retry coordinator.
    ///
    /// - Parameters:
    ///   - projectManager: Manager used to query workspace state.
    ///   - session: Switcher session for structured logging.
    ///   - maxAttempts: Maximum retry attempts before exhaustion. Defaults to `defaultMaxAttempts`.
    ///   - retryIntervalSeconds: Seconds between retries. Defaults to `defaultRetryIntervalSeconds`.
    init(
        projectManager: ProjectManager,
        session: SwitcherSession,
        maxAttempts: Int = defaultMaxAttempts,
        retryIntervalSeconds: TimeInterval = defaultRetryIntervalSeconds
    ) {
        self.projectManager = projectManager
        self.session = session
        self.maxAttempts = maxAttempts
        self.retryIntervalSeconds = retryIntervalSeconds
    }

    deinit {
        cancelRetry()
    }

    // MARK: - Public API

    /// Schedules a repeating timer to retry workspace state queries.
    ///
    /// Used when the circuit breaker is open and background AeroSpace recovery
    /// is in progress. Each tick retries `workspaceState()`; on success the
    /// `onRetrySucceeded` callback is invoked and the timer is canceled.
    /// After `maxAttempts` the `onRetryExhausted` callback is invoked.
    func scheduleRetry() {
        cancelRetry()
        retryCount = 0
        retryGeneration &+= 1

        let timerSessionId = session.sessionId
        let generation = retryGeneration

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        timer.schedule(
            deadline: .now() + retryIntervalSeconds,
            repeating: retryIntervalSeconds
        )
        timer.setEventHandler { [weak self] in
            self?.handleRetryTick(expectedSessionId: timerSessionId, expectedGeneration: generation)
        }
        timer.resume()
        retryTimer = timer

        session.logEvent(
            event: "switcher.workspace_retry.scheduled",
            context: ["max_attempts": "\(maxAttempts)"]
        )
    }

    /// Cancels the retry timer and resets retry state.
    func cancelRetry() {
        retryGeneration &+= 1
        retryTimer?.cancel()
        retryTimer = nil
    }

    // MARK: - Private

    /// Handles a single tick of the retry timer.
    ///
    /// The workspace query runs on the timer's background queue; all state
    /// reads/writes (generation, count, callbacks) happen on the main thread
    /// to avoid data races.
    private func handleRetryTick(expectedSessionId: String?, expectedGeneration: UInt64) {
        let result = projectManager.workspaceState()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard expectedSessionId == self.session.sessionId,
                  expectedGeneration == self.retryGeneration else { return }
            self.retryCount += 1

            switch result {
            case .success(let state):
                self.cancelRetry()
                self.session.logEvent(
                    event: "switcher.workspace_retry.succeeded",
                    context: ["attempt": "\(self.retryCount)"]
                )
                self.onRetrySucceeded?(state)

            case .failure(let error):
                if self.retryCount >= maxAttempts {
                    self.cancelRetry()
                    self.session.logEvent(
                        event: "switcher.workspace_retry.exhausted",
                        level: .warn,
                        message: "\(error)",
                        context: ["attempts": "\(self.retryCount)"]
                    )
                    self.onRetryExhausted?(error)
                } else {
                    self.session.logEvent(
                        event: "switcher.workspace_retry.pending",
                        context: [
                            "attempt": "\(self.retryCount)",
                            "remaining": "\(maxAttempts - self.retryCount)"
                        ]
                    )
                }
            }
        }
    }
}
