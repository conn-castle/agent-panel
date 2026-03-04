import Foundation
@testable import AgentPanelCore

// MARK: - Integration: Circuit Breaker in ApAeroSpace

/// Mock command runner for circuit breaker integration tests.
final class CircuitBreakerMockCommandRunner: CommandRunning {
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
            return .failure(ApCoreError(message: "CircuitBreakerMockCommandRunner: no results left"))
        }
        return results.removeFirst()
    }
}

struct CircuitBreakerStubAppDiscovery: AppDiscovering {
    func applicationURL(bundleIdentifier: String) -> URL? { nil }
    func applicationURL(named appName: String) -> URL? { nil }
    func bundleIdentifier(forApplicationAt url: URL) -> String? { nil }
}

/// Mock process checker that returns a configurable result.
final class CircuitBreakerMockProcessChecker: RunningApplicationChecking {
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

