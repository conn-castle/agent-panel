import XCTest

@testable import ProjectWorkspacesCore

final class AeroSpaceRetryTests: XCTestCase {
    func testStandardRetryPolicyMatchesSpecification() {
        let policy = AeroSpaceRetryPolicy.standard
        XCTAssertEqual(policy.maxAttempts, 20)
        XCTAssertEqual(policy.initialDelaySeconds, 0.05, accuracy: 0.000_1)
        XCTAssertEqual(policy.backoffMultiplier, 1.5, accuracy: 0.000_1)
        XCTAssertEqual(policy.maxDelaySeconds, 0.75, accuracy: 0.000_1)
        XCTAssertEqual(policy.totalCapSeconds, 5.0, accuracy: 0.000_1)
        XCTAssertEqual(policy.jitterFraction, 0.2, accuracy: 0.000_1)
    }

    func testNoRetryWhenProbeSucceeds() {
        let commandArgs = ["workspace", "pw-codex"]
        let probeArgs = ["list-workspaces", "--focused", "--count"]
        let commandResult = CommandResult(exitCode: 1, stdout: "", stderr: "err")
        let probeResult = CommandResult(exitCode: 0, stdout: "1", stderr: "")
        let runner = SequencedAeroSpaceCommandRunner(
            responses: [
                CommandSignature(arguments: commandArgs): [
                    .failure(.nonZeroExit(command: "cmd", result: commandResult))
                ],
                CommandSignature(arguments: probeArgs): [
                    .success(probeResult)
                ]
            ]
        )
        let clock = TestClock()
        let sleeper = TestSleeper(clock: clock)
        let jitter = TestJitterProvider(value: 0.5)
        let client = makeClient(
            runner: runner,
            clock: clock,
            sleeper: sleeper,
            jitter: jitter,
            retryPolicy: AeroSpaceRetryPolicy(
                maxAttempts: 3,
                initialDelaySeconds: 0.1,
                backoffMultiplier: 2,
                maxDelaySeconds: 1,
                totalCapSeconds: 2,
                jitterFraction: 0.2
            )
        )

        let outcome = client.switchWorkspace("pw-codex")

        switch outcome {
        case .success:
            XCTFail("Expected failure when probe succeeds")
        case .failure(let error):
            guard case .nonZeroExit = error else {
                XCTFail("Expected nonZeroExit, got \(error)")
                return
            }
        }
        XCTAssertEqual(runner.invocations.map(\.arguments), [commandArgs, probeArgs])
        XCTAssertTrue(sleeper.slept.isEmpty)
    }

    func testRetriesWhenProbeFailsThenSucceeds() {
        let commandArgs = ["workspace", "pw-codex"]
        let probeArgs = ["list-workspaces", "--focused", "--count"]
        let failedCommand = CommandResult(exitCode: 1, stdout: "", stderr: "err")
        let failedProbe = CommandResult(exitCode: 1, stdout: "", stderr: "err")
        let successCommand = CommandResult(exitCode: 0, stdout: "", stderr: "")
        let runner = SequencedAeroSpaceCommandRunner(
            responses: [
                CommandSignature(arguments: commandArgs): [
                    .failure(.nonZeroExit(command: "cmd", result: failedCommand)),
                    .success(successCommand)
                ],
                CommandSignature(arguments: probeArgs): [
                    .failure(.nonZeroExit(command: "probe", result: failedProbe))
                ]
            ]
        )
        let clock = TestClock()
        let sleeper = TestSleeper(clock: clock)
        let jitter = TestJitterProvider(value: 0.5)
        let policy = AeroSpaceRetryPolicy(
            maxAttempts: 3,
            initialDelaySeconds: 1.0,
            backoffMultiplier: 1.5,
            maxDelaySeconds: 2.0,
            totalCapSeconds: 5.0,
            jitterFraction: 0.2
        )
        let client = makeClient(
            runner: runner,
            clock: clock,
            sleeper: sleeper,
            jitter: jitter,
            retryPolicy: policy
        )

        let outcome = client.switchWorkspace("pw-codex")

        switch outcome {
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        case .success(let result):
            XCTAssertEqual(result.exitCode, 0)
        }
        XCTAssertEqual(runner.invocations.map(\.arguments), [commandArgs, probeArgs, commandArgs])
        XCTAssertEqual(sleeper.slept.count, 1)
        guard let firstSleep = sleeper.slept.first else {
            XCTFail("Expected a recorded sleep delay.")
            return
        }
        XCTAssertEqual(firstSleep, 1.0, accuracy: 0.000_1)
    }

    func testReturnsNotReadyWhenRetryBudgetExceeded() {
        let commandArgs = ["workspace", "pw-codex"]
        let probeArgs = ["list-workspaces", "--focused", "--count"]
        let failedCommand = CommandResult(exitCode: 1, stdout: "", stderr: "err")
        let failedProbe = CommandResult(exitCode: 1, stdout: "", stderr: "err")
        let runner = SequencedAeroSpaceCommandRunner(
            responses: [
                CommandSignature(arguments: commandArgs): [
                    .failure(.nonZeroExit(command: "cmd", result: failedCommand)),
                    .failure(.nonZeroExit(command: "cmd", result: failedCommand))
                ],
                CommandSignature(arguments: probeArgs): [
                    .failure(.nonZeroExit(command: "probe", result: failedProbe)),
                    .failure(.nonZeroExit(command: "probe", result: failedProbe))
                ]
            ]
        )
        let clock = TestClock()
        let sleeper = TestSleeper(clock: clock)
        let jitter = TestJitterProvider(value: 0.5)
        let policy = AeroSpaceRetryPolicy(
            maxAttempts: 2,
            initialDelaySeconds: 1.0,
            backoffMultiplier: 1.0,
            maxDelaySeconds: 1.0,
            totalCapSeconds: 2.0,
            jitterFraction: 0.2
        )
        let client = makeClient(
            runner: runner,
            clock: clock,
            sleeper: sleeper,
            jitter: jitter,
            retryPolicy: policy
        )

        let outcome = client.switchWorkspace("pw-codex")

        switch outcome {
        case .success:
            XCTFail("Expected notReady error")
        case .failure(let error):
            guard case .notReady(let payload) = error else {
                XCTFail("Expected notReady, got \(error)")
                return
            }
            XCTAssertEqual(payload.timeoutSeconds, 2.0, accuracy: 0.000_1)
            XCTAssertEqual(payload.lastCommand.exitCode, 1)
            XCTAssertEqual(payload.lastProbe.exitCode, 1)
        }
    }

    func testDoesNotRetryOnTimeout() {
        let commandArgs = ["workspace", "pw-codex"]
        let probeArgs = ["list-workspaces", "--focused", "--count"]
        let timeoutResult = CommandResult(exitCode: 15, stdout: "", stderr: "")
        let error = AeroSpaceCommandError.timedOut(
            command: "cmd",
            timeoutSeconds: 1,
            result: timeoutResult
        )
        let runner = SequencedAeroSpaceCommandRunner(
            responses: [
                CommandSignature(arguments: commandArgs): [
                    .failure(error)
                ],
                CommandSignature(arguments: probeArgs): []
            ]
        )
        let clock = TestClock()
        let sleeper = TestSleeper(clock: clock)
        let jitter = TestJitterProvider(value: 0.5)
        let client = makeClient(
            runner: runner,
            clock: clock,
            sleeper: sleeper,
            jitter: jitter,
            retryPolicy: AeroSpaceRetryPolicy.standard
        )

        let outcome = client.switchWorkspace("pw-codex")

        switch outcome {
        case .success:
            XCTFail("Expected timeout error")
        case .failure(let received):
            XCTAssertEqual(received, error)
        }
        XCTAssertEqual(runner.invocations.map(\.arguments), [commandArgs])
    }
}

private struct CommandSignature: Hashable {
    let arguments: [String]
}

private final class SequencedAeroSpaceCommandRunner: AeroSpaceCommandRunning {
    private var responses: [CommandSignature: [Result<CommandResult, AeroSpaceCommandError>]]
    private(set) var invocations: [CommandSignature] = []

    init(responses: [CommandSignature: [Result<CommandResult, AeroSpaceCommandError>]]) {
        self.responses = responses
    }

    func run(
        executable: URL,
        arguments: [String],
        timeoutSeconds: TimeInterval
    ) -> Result<CommandResult, AeroSpaceCommandError> {
        let signature = CommandSignature(arguments: arguments)
        invocations.append(signature)
        guard var queue = responses[signature], !queue.isEmpty else {
            preconditionFailure("Missing stub for arguments: \(arguments)")
        }
        let result = queue.removeFirst()
        responses[signature] = queue
        return result
    }
}

private final class TestClock: DateProviding {
    private var current: Date

    init(start: Date = Date(timeIntervalSince1970: 0)) {
        self.current = start
    }

    func now() -> Date {
        current
    }

    func advance(by seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
    }
}

private final class TestSleeper: AeroSpaceSleeping {
    private let clock: TestClock
    private(set) var slept: [TimeInterval] = []

    init(clock: TestClock) {
        self.clock = clock
    }

    func sleep(seconds: TimeInterval) {
        slept.append(seconds)
        clock.advance(by: seconds)
    }
}

private struct TestJitterProvider: AeroSpaceJitterProviding {
    let value: Double

    func nextUnit() -> Double {
        value
    }
}

private func makeClient(
    runner: AeroSpaceCommandRunning,
    clock: DateProviding,
    sleeper: AeroSpaceSleeping,
    jitter: AeroSpaceJitterProviding,
    retryPolicy: AeroSpaceRetryPolicy
) -> AeroSpaceClient {
    AeroSpaceClient(
        executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/aerospace"),
        commandRunner: runner,
        timeoutSeconds: 1,
        clock: clock,
        sleeper: sleeper,
        jitterProvider: jitter,
        retryPolicy: retryPolicy,
        windowDecoder: AeroSpaceWindowDecoder()
    )
}
