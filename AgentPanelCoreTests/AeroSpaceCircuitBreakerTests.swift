import XCTest
@testable import AgentPanelCore

// MARK: - Circuit Breaker Unit Tests

final class AeroSpaceCircuitBreakerTests: XCTestCase {

    func testInitialStateIsClosed() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 10)
        XCTAssertEqual(breaker.currentState, .closed)
        XCTAssertTrue(breaker.shouldAllow())
    }

    func testRecordTimeoutTripsBreaker() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 10)

        breaker.recordTimeout()

        XCTAssertFalse(breaker.shouldAllow())
        if case .open = breaker.currentState {} else {
            XCTFail("Expected open state after timeout")
        }
    }

    func testBreakerFailsFastWhenOpen() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)

        breaker.recordTimeout()

        // Multiple calls should all be rejected
        XCTAssertFalse(breaker.shouldAllow())
        XCTAssertFalse(breaker.shouldAllow())
        XCTAssertFalse(breaker.shouldAllow())
    }

    func testBreakerRecoverAfterCooldown() {
        // Use a tiny cooldown so the test doesn't sleep long
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 0.05)

        breaker.recordTimeout()
        XCTAssertFalse(breaker.shouldAllow())

        // Wait for cooldown to expire
        Thread.sleep(forTimeInterval: 0.1)

        XCTAssertTrue(breaker.shouldAllow())
        XCTAssertEqual(breaker.currentState, .closed)
    }

    func testRecordSuccessClosesBreaker() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)

        breaker.recordTimeout()
        XCTAssertFalse(breaker.shouldAllow())

        breaker.recordSuccess()
        XCTAssertTrue(breaker.shouldAllow())
        XCTAssertEqual(breaker.currentState, .closed)
    }

    func testResetClosesBreaker() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)

        breaker.recordTimeout()
        XCTAssertFalse(breaker.shouldAllow())

        breaker.reset()
        XCTAssertTrue(breaker.shouldAllow())
        XCTAssertEqual(breaker.currentState, .closed)
    }

    // MARK: - Recovery Tracking

    func testShouldAttemptRecoveryWhenOpenAndUnderLimit() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        breaker.recordTimeout()
        XCTAssertTrue(breaker.shouldAttemptRecovery())
    }

    func testShouldNotAttemptRecoveryWhenClosed() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        XCTAssertFalse(breaker.shouldAttemptRecovery())
    }

    func testShouldNotAttemptRecoveryAfterCooldownExpired() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 0.01)
        breaker.recordTimeout()
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertFalse(breaker.shouldAttemptRecovery())
    }

    func testBeginRecoveryReturnsTrueFirstTime() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        breaker.recordTimeout()
        XCTAssertTrue(breaker.beginRecovery())
        XCTAssertTrue(breaker.isRecoveryInProgress)
    }

    func testBeginRecoveryReturnsFalseWhenAlreadyInProgress() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        breaker.recordTimeout()
        XCTAssertTrue(breaker.beginRecovery())
        XCTAssertFalse(breaker.beginRecovery(), "Second concurrent recovery should be rejected")
    }

    func testBeginRecoveryReturnsFalseWhenClosed() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        XCTAssertFalse(breaker.beginRecovery())
    }

    func testEndRecoverySuccessResetsBreaker() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        breaker.recordTimeout()
        _ = breaker.beginRecovery()
        breaker.endRecovery(success: true)

        XCTAssertFalse(breaker.isRecoveryInProgress)
        XCTAssertEqual(breaker.currentState, .closed)
        XCTAssertTrue(breaker.shouldAllow())
    }

    func testEndRecoveryFailureIncrementsCount() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        breaker.recordTimeout()
        _ = breaker.beginRecovery()
        breaker.endRecovery(success: false)

        XCTAssertFalse(breaker.isRecoveryInProgress)
        // Should still allow one more attempt
        XCTAssertTrue(breaker.shouldAttemptRecovery())
    }

    func testEndRecoveryFailureReopensBreaker() {
        // When recovery fails (e.g., start() launched AeroSpace but readiness
        // timed out), start() may have reset the breaker to closed. endRecovery
        // must re-open it so subsequent calls continue to fail fast.
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        breaker.recordTimeout()
        _ = breaker.beginRecovery()

        // Simulate what start() does: reset breaker to closed mid-recovery
        breaker.reset()

        breaker.endRecovery(success: false)

        // Breaker must be open (not closed) to maintain fail-fast
        if case .open = breaker.currentState {} else {
            XCTFail("Expected breaker to be re-opened after failed recovery, got \(breaker.currentState)")
        }
        XCTAssertFalse(breaker.shouldAllow(), "Should fail fast after failed recovery")
    }

    func testMaxRecoveryAttemptsExhausted() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)

        // Exhaust all recovery attempts
        for _ in 0..<AeroSpaceCircuitBreaker.maxRecoveryAttempts {
            breaker.recordTimeout()
            XCTAssertTrue(breaker.beginRecovery())
            breaker.endRecovery(success: false)
        }

        // Should no longer attempt recovery
        XCTAssertFalse(breaker.shouldAttemptRecovery())
        XCTAssertFalse(breaker.beginRecovery())
    }

    func testRecordSuccessClearsRecoveryCount() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)

        // One failed recovery
        breaker.recordTimeout()
        _ = breaker.beginRecovery()
        breaker.endRecovery(success: false)

        // A normal success resets everything
        breaker.recordSuccess()

        // Trip again — recovery should be available from zero
        breaker.recordTimeout()
        XCTAssertTrue(breaker.shouldAttemptRecovery())
    }

    func testResetClearsRecoveryState() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        breaker.recordTimeout()
        _ = breaker.beginRecovery()

        breaker.reset()

        XCTAssertFalse(breaker.isRecoveryInProgress)
        XCTAssertEqual(breaker.currentState, .closed)
    }

    func testNewTripAfterCooldownResetsRecoveryBudget() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 0.01)

        // Exhaust recovery attempts on first trip
        breaker.recordTimeout()
        for _ in 0..<AeroSpaceCircuitBreaker.maxRecoveryAttempts {
            _ = breaker.beginRecovery()
            breaker.endRecovery(success: false)
        }
        XCTAssertFalse(breaker.shouldAttemptRecovery(), "Should be exhausted")

        // Wait for cooldown → breaker transitions back to closed
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertTrue(breaker.shouldAllow())

        // New trip should reset recovery budget
        breaker.recordTimeout()
        XCTAssertTrue(breaker.shouldAttemptRecovery(), "New trip should have fresh recovery budget")
    }

    func testRetripWhileOpenDoesNotResetRecoveryBudget() {
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)

        // First trip, exhaust one attempt
        breaker.recordTimeout()
        _ = breaker.beginRecovery()
        breaker.endRecovery(success: false)

        // Re-trip while still open (extends cooldown but same outage)
        breaker.recordTimeout()

        // Should still have only 1 attempt remaining, not reset to 2
        _ = breaker.beginRecovery()
        breaker.endRecovery(success: false)
        XCTAssertFalse(breaker.shouldAttemptRecovery(), "Re-trip while open should not reset budget")
    }

    func testMultipleTimeoutsExtendCooldown() {
        // Verify that a second recordTimeout() pushes the expiry forward,
        // proving cooldown is reset (not accumulated or ignored).
        // Uses state inspection instead of Thread.sleep to avoid CI flakiness.
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 10)

        breaker.recordTimeout()
        guard case .open(let firstExpiry) = breaker.currentState else {
            return XCTFail("Expected open state after first timeout")
        }

        // Small delay so Date() advances
        Thread.sleep(forTimeInterval: 0.01)

        breaker.recordTimeout()
        guard case .open(let secondExpiry) = breaker.currentState else {
            return XCTFail("Expected open state after second timeout")
        }

        XCTAssertGreaterThan(secondExpiry, firstExpiry,
            "Second timeout should push expiry forward, extending the cooldown")

        // Breaker should still be open (10s cooldown, we've waited ~0.01s)
        XCTAssertFalse(breaker.shouldAllow())
    }
}

// MARK: - Integration: Circuit Breaker in ApAeroSpace

/// Mock command runner for circuit breaker integration tests.
private final class MockCommandRunner: CommandRunning {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
    }

    var calls: [Call] = []
    var results: [Result<ApCommandResult, ApCoreError>] = []

    func run(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval?,
        workingDirectory: String?
    ) -> Result<ApCommandResult, ApCoreError> {
        calls.append(Call(executable: executable, arguments: arguments))
        guard !results.isEmpty else {
            return .failure(ApCoreError(message: "MockCommandRunner: no results left"))
        }
        return results.removeFirst()
    }
}

private struct StubAppDiscovery: AppDiscovering {
    func applicationURL(bundleIdentifier: String) -> URL? { nil }
    func applicationURL(named appName: String) -> URL? { nil }
    func bundleIdentifier(forApplicationAt url: URL) -> String? { nil }
}

/// Mock process checker that returns a configurable result.
private final class MockProcessChecker: RunningApplicationChecking {
    private let lock = NSLock()
    private var _isRunning: Bool

    init(isRunning: Bool) {
        self._isRunning = isRunning
    }

    var isRunning: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _isRunning }
        set { lock.lock(); _isRunning = newValue; lock.unlock() }
    }

    func isApplicationRunning(bundleIdentifier: String) -> Bool {
        return isRunning
    }
}

final class AeroSpaceCircuitBreakerIntegrationTests: XCTestCase {

    func testTimeoutTripsCircuitBreaker() {
        let runner = MockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)

        // First call times out
        runner.results = [
            .failure(ApCoreError(message: "Command timed out after 5.0s: aerospace list-workspaces --all"))
        ]
        let aero = ApAeroSpace(
            commandRunner: runner,
            appDiscovery: StubAppDiscovery(),
            circuitBreaker: breaker
        )

        let result1 = aero.getWorkspaces()
        if case .failure = result1 {} else {
            XCTFail("Expected failure from timeout")
        }

        // Second call should fail fast without hitting the runner
        runner.results = []
        let result2 = aero.getWorkspaces()
        if case .failure(let error) = result2 {
            XCTAssertTrue(error.message.contains("circuit breaker"), "Error should mention circuit breaker, got: \(error.message)")
        } else {
            XCTFail("Expected circuit breaker failure")
        }

        // Runner should only have been called once (the first timeout)
        XCTAssertEqual(runner.calls.count, 1)
    }

    func testNonTimeoutErrorDoesNotTripBreaker() {
        let runner = MockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)

        // First call fails but not a timeout
        runner.results = [
            .failure(ApCoreError(message: "Executable not found: aerospace")),
            // Second call succeeds
            .success(ApCommandResult(exitCode: 0, stdout: "ws-1\n", stderr: ""))
        ]
        let aero = ApAeroSpace(
            commandRunner: runner,
            appDiscovery: StubAppDiscovery(),
            circuitBreaker: breaker
        )

        let result1 = aero.getWorkspaces()
        if case .failure = result1 {} else {
            XCTFail("Expected failure")
        }

        // Breaker should still be closed, second call goes through
        let result2 = aero.getWorkspaces()
        if case .success(let workspaces) = result2 {
            XCTAssertEqual(workspaces, ["ws-1"])
        } else {
            XCTFail("Expected success on second call")
        }
        XCTAssertEqual(runner.calls.count, 2)
    }

    func testSuccessAfterCooldownResetsBreaker() {
        let runner = MockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 0.05)

        // Timeout trips the breaker
        runner.results = [
            .failure(ApCoreError(message: "Command timed out after 5.0s: aerospace list-workspaces --all"))
        ]
        let aero = ApAeroSpace(
            commandRunner: runner,
            appDiscovery: StubAppDiscovery(),
            circuitBreaker: breaker
        )

        _ = aero.getWorkspaces()
        XCTAssertFalse(breaker.shouldAllow())

        // Wait for cooldown
        Thread.sleep(forTimeInterval: 0.1)

        // Next call should go through and succeed
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "ws-1\n", stderr: ""))
        ]
        let result = aero.getWorkspaces()
        if case .success(let workspaces) = result {
            XCTAssertEqual(workspaces, ["ws-1"])
        } else {
            XCTFail("Expected success after cooldown")
        }

        XCTAssertEqual(breaker.currentState, .closed)
    }

    func testStartResetsCircuitBreaker() {
        let runner = MockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)

        // Trip the breaker
        breaker.recordTimeout()
        XCTAssertFalse(breaker.shouldAllow())

        // Simulate start(): open -a AeroSpace succeeds, then isCliAvailable probe succeeds
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")),  // open -a AeroSpace
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))   // aerospace --help (readiness)
        ]
        let aero = ApAeroSpace(
            commandRunner: runner,
            appDiscovery: StubAppDiscovery(),
            circuitBreaker: breaker
        )

        // start() runs on a background thread (guard !Thread.isMainThread)
        let expectation = expectation(description: "start completes")
        var startResult: Result<Void, ApCoreError>?
        DispatchQueue.global().async {
            startResult = aero.start()
            expectation.fulfill()
        }
        waitForExpectations(timeout: 15)

        if case .success = startResult {} else {
            XCTFail("Expected start to succeed, got: \(String(describing: startResult))")
        }

        // Breaker should be closed after start
        XCTAssertTrue(breaker.shouldAllow())
    }

    func testCascadePreventionMultipleMethods() {
        let runner = MockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)

        // First call times out
        runner.results = [
            .failure(ApCoreError(message: "Command timed out after 5.0s: aerospace list-workspaces --focused"))
        ]
        let aero = ApAeroSpace(
            commandRunner: runner,
            appDiscovery: StubAppDiscovery(),
            circuitBreaker: breaker
        )

        // Trip the breaker via listWorkspacesFocused
        _ = aero.listWorkspacesFocused()

        // All subsequent methods should fail fast without hitting the runner
        runner.results = []

        let r1 = aero.getWorkspaces()
        let r2 = aero.listWindowsFocusedMonitor()
        let r3 = aero.focusWorkspace(name: "test")
        let r4 = aero.isCliAvailable()

        if case .failure(let e) = r1 { XCTAssertTrue(e.message.contains("circuit breaker")) }
        else { XCTFail("Expected circuit breaker failure") }

        if case .failure(let e) = r2 { XCTAssertTrue(e.message.contains("circuit breaker")) }
        else { XCTFail("Expected circuit breaker failure") }

        if case .failure(let e) = r3 { XCTAssertTrue(e.message.contains("circuit breaker")) }
        else { XCTFail("Expected circuit breaker failure") }

        XCTAssertFalse(r4) // isCliAvailable returns false, doesn't expose error

        // Only 1 actual command was sent to the runner
        XCTAssertEqual(runner.calls.count, 1)
    }
}

// MARK: - Auto-Recovery Integration Tests

final class AeroSpaceAutoRecoveryTests: XCTestCase {

    /// When breaker is open, process is dead, and processChecker is wired,
    /// auto-recovery should restart AeroSpace and retry the command.
    func testAutoRecoveryRestartsAeroSpaceWhenProcessDead() {
        let runner = MockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        let processChecker = MockProcessChecker(isRunning: false)

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
            appDiscovery: StubAppDiscovery(),
            circuitBreaker: breaker,
            processChecker: processChecker
        )

        // start() requires !Thread.isMainThread
        let expectation = expectation(description: "recovery completes")
        var result: Result<[String], ApCoreError>?
        DispatchQueue.global().async {
            result = aero.getWorkspaces()
            expectation.fulfill()
        }
        waitForExpectations(timeout: 15)

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
        let runner = MockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)

        // Trip the breaker
        breaker.recordTimeout()

        let aero = ApAeroSpace(
            commandRunner: runner,
            appDiscovery: StubAppDiscovery(),
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
        let runner = MockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        let processChecker = MockProcessChecker(isRunning: true)

        // Trip the breaker
        breaker.recordTimeout()

        let aero = ApAeroSpace(
            commandRunner: runner,
            appDiscovery: StubAppDiscovery(),
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
        let runner = MockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        let processChecker = MockProcessChecker(isRunning: false)

        // Trip the breaker
        breaker.recordTimeout()

        // Start fails (open -a AeroSpace fails)
        runner.results = [
            .failure(ApCoreError(message: "Executable not found: open"))
        ]

        let aero = ApAeroSpace(
            commandRunner: runner,
            appDiscovery: StubAppDiscovery(),
            circuitBreaker: breaker,
            processChecker: processChecker
        )

        // Run off-main so recovery is synchronous and we can verify state immediately
        let expectation = expectation(description: "recovery completes")
        var result: Result<[String], ApCoreError>?
        DispatchQueue.global().async {
            result = aero.getWorkspaces()
            expectation.fulfill()
        }
        waitForExpectations(timeout: 15)

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
        let runner = MockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        let processChecker = MockProcessChecker(isRunning: false)

        breaker.recordTimeout()

        // Provide results for async recovery: open -a AeroSpace + readiness probe
        runner.results = [
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")),
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]

        let aero = ApAeroSpace(
            commandRunner: runner,
            appDiscovery: StubAppDiscovery(),
            circuitBreaker: breaker,
            processChecker: processChecker
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
        let runner = MockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        let processChecker = MockProcessChecker(isRunning: false)

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
            appDiscovery: StubAppDiscovery(),
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
