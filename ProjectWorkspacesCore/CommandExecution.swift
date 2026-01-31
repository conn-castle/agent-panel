import Foundation

/// Errors returned when executing external commands.
public enum CommandExecutionError: Error, Equatable, Sendable {
    case launchFailed(command: String, underlyingError: String)
    case nonZeroExit(command: String, result: CommandResult)
}

/// Executes shell commands and converts failures into structured errors.
protocol ProcessRunning {
    /// Runs a command and returns a structured result.
    /// - Parameters:
    ///   - executable: Executable file URL.
    ///   - arguments: Arguments passed to the command.
    ///   - environment: Environment variables to override; when nil, inherits current environment.
    ///   - workingDirectory: Optional working directory for the process.
    /// - Returns: Command execution result or structured error.
    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]?,
        workingDirectory: URL?
    ) -> Result<CommandResult, CommandExecutionError>
}

/// Default process runner backed by the shared `CommandRunning` implementation.
struct ProcessRunner: ProcessRunning {
    private let commandRunner: CommandRunning

    init(commandRunner: CommandRunning = DefaultCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]?,
        workingDirectory: URL?
    ) -> Result<CommandResult, CommandExecutionError> {
        let commandDescription = ([executable.path] + arguments).joined(separator: " ")
        do {
            let result = try commandRunner.run(
                command: executable,
                arguments: arguments,
                environment: environment,
                workingDirectory: workingDirectory
            )
            if result.exitCode != 0 {
                return .failure(.nonZeroExit(command: commandDescription, result: result))
            }
            return .success(result)
        } catch {
            return .failure(.launchFailed(command: commandDescription, underlyingError: String(describing: error)))
        }
    }
}
