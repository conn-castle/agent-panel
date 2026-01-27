import Foundation

/// Logs AeroSpace command output for activation.
struct LoggingAeroSpaceCommandRunner: AeroSpaceCommandRunning {
    private let baseRunner: AeroSpaceCommandRunning
    private let logger: ProjectWorkspacesLogging
    private let projectId: String
    private let workspaceName: String

    /// Creates a logging wrapper for AeroSpace commands.
    /// - Parameters:
    ///   - baseRunner: Underlying command runner.
    ///   - logger: Logger used for command output.
    ///   - projectId: Active project id for context.
    ///   - workspaceName: Active workspace name for context.
    init(
        baseRunner: AeroSpaceCommandRunning,
        logger: ProjectWorkspacesLogging,
        projectId: String,
        workspaceName: String
    ) {
        self.baseRunner = baseRunner
        self.logger = logger
        self.projectId = projectId
        self.workspaceName = workspaceName
    }

    /// Executes a command and logs stdout/stderr.
    func run(
        executable: URL,
        arguments: [String],
        timeoutSeconds: TimeInterval
    ) -> Result<CommandResult, AeroSpaceCommandError> {
        let result = baseRunner.run(executable: executable, arguments: arguments, timeoutSeconds: timeoutSeconds)
        log(result: result, executable: executable, arguments: arguments)
        return result
    }

    private func log(
        result: Result<CommandResult, AeroSpaceCommandError>,
        executable: URL,
        arguments: [String]
    ) {
        let command = ([executable.path] + arguments).joined(separator: " ")
        var context: [String: String] = [
            "command": command,
            "projectId": projectId,
            "workspace": workspaceName
        ]
        let level: LogLevel

        switch result {
        case .success(let output):
            level = .info
            context["exitCode"] = String(output.exitCode)
            context["stdout"] = output.stdout
            context["stderr"] = output.stderr
        case .failure(let error):
            level = .warn
            switch error {
            case .nonZeroExit(_, let output):
                context["exitCode"] = String(output.exitCode)
                context["stdout"] = output.stdout
                context["stderr"] = output.stderr
            case .timedOut(_, let timeout, let output):
                context["exitCode"] = String(output.exitCode)
                context["stdout"] = output.stdout
                context["stderr"] = output.stderr
                context["timeoutSeconds"] = String(timeout)
            case .launchFailed(_, let underlyingError):
                context["error"] = underlyingError
            case .decodingFailed(let payload, let underlyingError):
                context["stdout"] = payload
                context["error"] = underlyingError
            case .unexpectedOutput(let commandDescription, let detail):
                context["command"] = commandDescription
                context["error"] = detail
            case .notReady(let payload):
                context["error"] = "AeroSpace not ready"
                context["lastCommand"] = payload.lastCommandDescription
                context["lastProbe"] = payload.lastProbeDescription
            }
        }

        _ = logger.log(event: "activation.aerospace.command", level: level, message: nil, context: context)
    }
}
