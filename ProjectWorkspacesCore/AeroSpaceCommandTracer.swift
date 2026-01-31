import Foundation

/// Captures AeroSpace CLI command output for activation logging.
struct TracingAeroSpaceCommandRunner: AeroSpaceCommandRunning {
    private let wrapped: AeroSpaceCommandRunning
    private let traceSink: (AeroSpaceCommandLog) -> Void
    private let windowDecoder: AeroSpaceWindowDecoder

    /// Creates a tracing command runner.
    /// - Parameters:
    ///   - wrapped: Underlying command runner.
    ///   - traceSink: Sink invoked after each command.
    ///   - windowDecoder: Decoder used to sanitize list-windows output.
    init(
        wrapped: AeroSpaceCommandRunning,
        traceSink: @escaping (AeroSpaceCommandLog) -> Void,
        windowDecoder: AeroSpaceWindowDecoder = AeroSpaceWindowDecoder()
    ) {
        self.wrapped = wrapped
        self.traceSink = traceSink
        self.windowDecoder = windowDecoder
    }

    /// Executes the underlying runner and traces the result.
    func run(
        executable: URL,
        arguments: [String],
        timeoutSeconds: TimeInterval
    ) -> Result<CommandResult, AeroSpaceCommandError> {
        let startedAt = Date()
        let result = wrapped.run(
            executable: executable,
            arguments: arguments,
            timeoutSeconds: timeoutSeconds
        )
        let endedAt = Date()
        traceSink(buildLog(
            executable: executable,
            arguments: arguments,
            result: result,
            startedAt: startedAt,
            endedAt: endedAt
        ))
        return result
    }

    private func buildLog(
        executable: URL,
        arguments: [String],
        result: Result<CommandResult, AeroSpaceCommandError>,
        startedAt: Date,
        endedAt: Date
    ) -> AeroSpaceCommandLog {
        let command = executable.path
        let isListWindows = arguments.first == "list-windows"
        let outcome = CommandOutcome(result: result)

        let stdout: String?
        if isListWindows, let raw = outcome.stdout {
            stdout = summarizeListWindows(raw)
        } else {
            stdout = outcome.stdout
        }

        let durationMs = max(0, Int(endedAt.timeIntervalSince(startedAt) * 1000))
        return AeroSpaceCommandLog(
            startedAt: makeTimestamp(startedAt),
            endedAt: makeTimestamp(endedAt),
            durationMs: durationMs,
            command: command,
            arguments: arguments,
            exitCode: outcome.exitCode,
            stdout: stdout,
            stderr: outcome.stderr,
            error: outcome.error
        )
    }

    private func summarizeListWindows(_ json: String) -> String {
        switch windowDecoder.decodeWindows(from: json) {
        case .success(let windows):
            let ids = windows.map { $0.windowId }.sorted()
            let bundleIds = Array(Set(windows.map { $0.appBundleId })).sorted()
            return "count=\(windows.count) ids=\(ids) bundleIds=\(bundleIds)"
        case .failure:
            let byteCount = json.utf8.count
            return "decodeFailed(bytes=\(byteCount))"
        }
    }

    private func makeTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

private struct CommandOutcome {
    let exitCode: Int32?
    let stdout: String?
    let stderr: String?
    let error: String?

    init(result: Result<CommandResult, AeroSpaceCommandError>) {
        switch result {
        case .success(let success):
            exitCode = success.exitCode
            stdout = success.stdout
            stderr = success.stderr
            error = nil
        case .failure(let error):
            exitCode = error.commandResult?.exitCode
            stdout = error.commandResult?.stdout
            stderr = error.commandResult?.stderr
            self.error = error.summary
        }
    }
}

private extension AeroSpaceCommandError {
    var commandResult: CommandResult? {
        switch self {
        case .nonZeroExit(_, let result):
            return result
        case .timedOut(_, _, let result):
            return result
        case .notReady(let notReady):
            return notReady.lastCommand
        case .launchFailed, .decodingFailed, .unexpectedOutput:
            return nil
        }
    }

    var summary: String {
        switch self {
        case .launchFailed(let command, let underlyingError):
            return "\(command): \(underlyingError)"
        case .nonZeroExit(let command, let result):
            return "\(command) exited \(result.exitCode)"
        case .timedOut(let command, let timeoutSeconds, _):
            return "\(command) timed out after \(timeoutSeconds)s"
        case .decodingFailed(_, let underlyingError):
            return "Decoding failed: \(underlyingError)"
        case .unexpectedOutput(let command, let detail):
            return "\(command): \(detail)"
        case .notReady(let notReady):
            return "AeroSpace not ready after \(notReady.timeoutSeconds)s"
        }
    }
}
