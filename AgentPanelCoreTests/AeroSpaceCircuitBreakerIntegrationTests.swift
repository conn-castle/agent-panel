import XCTest
@testable import AgentPanelCore

final class AeroSpaceCircuitBreakerIntegrationTests: XCTestCase {

    func testTimeoutTripsCircuitBreaker() {
        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)

        // First call times out
        runner.results = [
            .failure(ApCoreError(message: "Command timed out after 5.0s: aerospace list-workspaces --all"))
        ]
        let aero = ApAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
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
        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)

        // First call fails but not a timeout
        runner.results = [
            .failure(ApCoreError(message: "Executable not found: aerospace")),
            // Second call succeeds
            .success(ApCommandResult(exitCode: 0, stdout: "ws-1\n", stderr: ""))
        ]
        let aero = ApAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
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
        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 0.05)

        // Timeout trips the breaker
        runner.results = [
            .failure(ApCoreError(message: "Command timed out after 5.0s: aerospace list-workspaces --all"))
        ]
        let aero = ApAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
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
        let runner = CircuitBreakerMockCommandRunner()
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
            appDiscovery: CircuitBreakerStubAppDiscovery(),
            circuitBreaker: breaker,
            startupTimeoutSeconds: 1.0,
            readinessCheckInterval: 0.05
        )

        // start() runs on a background thread (guard !Thread.isMainThread)
        let expectation = expectation(description: "start completes")
        var startResult: Result<Void, ApCoreError>?
        DispatchQueue.global().async {
            startResult = aero.start()
            expectation.fulfill()
        }
        waitForExpectations(timeout: 5)

        if case .success = startResult {} else {
            XCTFail("Expected start to succeed, got: \(String(describing: startResult))")
        }

        // Breaker should be closed after start
        XCTAssertTrue(breaker.shouldAllow())
    }

    func testCascadePreventionMultipleMethods() {
        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)

        // First call times out
        runner.results = [
            .failure(ApCoreError(message: "Command timed out after 5.0s: aerospace list-workspaces --focused"))
        ]
        let aero = ApAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
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

