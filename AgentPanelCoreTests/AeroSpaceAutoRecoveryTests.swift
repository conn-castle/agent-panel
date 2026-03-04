import XCTest
@testable import AgentPanelCore

// MARK: - Auto-Recovery Integration Tests

final class AeroSpaceAutoRecoveryTests: XCTestCase {

    /// When breaker is open, process is dead, and processChecker is wired,
    /// auto-recovery should restart AeroSpace and retry the command.
    func testAutoRecoveryRestartsAeroSpaceWhenProcessDead() {
        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        let processChecker = CircuitBreakerMockProcessChecker(isRunning: false)

        // Trip the breaker
        breaker.recordTimeout()

        // Set up results for recovery: open -a AeroSpace, readiness probe, then retried command
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")),  // open -a AeroSpace
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")),  // aerospace --help (readiness)
            .success(ApCommandResult(exitCode: 0, stdout: "ws-1\n", stderr: ""))  // retried getWorkspaces
        ]

        let aero = ApAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
            circuitBreaker: breaker,
            processChecker: processChecker,
            startupTimeoutSeconds: 1.0,
            readinessCheckInterval: 0.05
        )

        // start() requires !Thread.isMainThread
        let expectation = expectation(description: "recovery completes")
        var result: Result<[String], ApCoreError>?
        DispatchQueue.global().async {
            result = aero.getWorkspaces()
            expectation.fulfill()
        }
        waitForExpectations(timeout: 5)

        if case .success(let workspaces) = result {
            XCTAssertEqual(workspaces, ["ws-1"])
        } else {
            XCTFail("Expected success after auto-recovery, got: \(String(describing: result))")
        }

        // Breaker should be closed after successful recovery
        XCTAssertEqual(breaker.currentState, .closed)
    }

    /// When processChecker is nil, no recovery is attempted — standard breaker error is returned.
    func testNoRecoveryWhenProcessCheckerIsNil() {
        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)

        // Trip the breaker
        breaker.recordTimeout()

        let aero = ApAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
            circuitBreaker: breaker
            // processChecker is nil (default)
        )

        let result = aero.getWorkspaces()
        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("circuit breaker"))
        } else {
            XCTFail("Expected circuit breaker error without process checker")
        }

        // Runner should not have been called at all
        XCTAssertEqual(runner.calls.count, 0)
    }

    /// When process is still running (hanging, not crashed), no recovery is attempted.
    func testNoRecoveryWhenProcessIsRunning() {
        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        let processChecker = CircuitBreakerMockProcessChecker(isRunning: true)

        // Trip the breaker
        breaker.recordTimeout()

        let aero = ApAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
            circuitBreaker: breaker,
            processChecker: processChecker
        )

        let result = aero.getWorkspaces()
        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("circuit breaker"))
        } else {
            XCTFail("Expected circuit breaker error when process is still running")
        }

        // Runner should not have been called
        XCTAssertEqual(runner.calls.count, 0)
    }

    /// When recovery fails (start() fails), it should fall back to breaker error and
    /// allow one more recovery attempt before exhausting the limit.
    func testRecoveryFailureFallsBackToBreakerError() {
        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        let processChecker = CircuitBreakerMockProcessChecker(isRunning: false)

        // Trip the breaker
        breaker.recordTimeout()

        // Start fails (open -a AeroSpace fails)
        runner.results = [
            .failure(ApCoreError(message: "Executable not found: open"))
        ]

        let aero = ApAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
            circuitBreaker: breaker,
            processChecker: processChecker,
            startupTimeoutSeconds: 1.0,
            readinessCheckInterval: 0.05
        )

        // Run off-main so recovery is synchronous and we can verify state immediately
        let expectation = expectation(description: "recovery completes")
        var result: Result<[String], ApCoreError>?
        DispatchQueue.global().async {
            result = aero.getWorkspaces()
            expectation.fulfill()
        }
        waitForExpectations(timeout: 5)

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("circuit breaker"))
        } else {
            XCTFail("Expected circuit breaker error after failed recovery")
        }

        // Recovery should have been attempted (start called open -a AeroSpace)
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls[0].arguments, ["-a", "AeroSpace"])

        // Should still allow one more recovery attempt
        XCTAssertTrue(breaker.shouldAttemptRecovery())
    }

    /// On the main thread, recovery fires asynchronously and the caller gets an
    /// immediate breaker error (no main-thread stall).
    func testMainThreadRecoveryFailsFastAndRecoversAsync() {
        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        let processChecker = CircuitBreakerMockProcessChecker(isRunning: false)

        breaker.recordTimeout()

        // Provide results for async recovery: open -a AeroSpace + readiness probe
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")),
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]

        let aero = ApAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
            circuitBreaker: breaker,
            processChecker: processChecker,
            startupTimeoutSeconds: 1.0,
            readinessCheckInterval: 0.05
        )

        // Call on main thread — should return immediately with breaker error
        let result = aero.getWorkspaces()
        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("circuit breaker"),
                "Main-thread caller should get immediate breaker error")
        } else {
            XCTFail("Expected immediate breaker error on main thread")
        }

        // Wait for async recovery to complete in background
        let recovered = expectation(description: "async recovery completes")
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            recovered.fulfill()
        }
        waitForExpectations(timeout: 5)

        // Breaker should now be closed from the async recovery
        XCTAssertEqual(breaker.currentState, .closed)
        XCTAssertFalse(breaker.isRecoveryInProgress)
    }

    /// After maxRecoveryAttempts failed recoveries, no more attempts are made.
    func testRecoveryExhaustedAfterMaxAttempts() {
        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        let processChecker = CircuitBreakerMockProcessChecker(isRunning: false)

        // Exhaust recovery attempts
        for _ in 0..<AeroSpaceCircuitBreaker.maxRecoveryAttempts {
            breaker.recordTimeout()
            _ = breaker.beginRecovery()
            breaker.endRecovery(success: false)
        }

        // Ensure breaker is still open
        breaker.recordTimeout()

        let aero = ApAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
            circuitBreaker: breaker,
            processChecker: processChecker
        )

        let result = aero.getWorkspaces()
        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("circuit breaker"))
        } else {
            XCTFail("Expected circuit breaker error after exhausted recovery")
        }

        // Runner should not have been called (recovery not attempted)
        XCTAssertEqual(runner.calls.count, 0)
    }
}
