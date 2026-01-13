import Foundation

/// Supported help topics for the `pwctl` CLI.
public enum PwctlHelpTopic: String, CaseIterable, Equatable {
    case root
    case doctor
    case list
    case activate
    case close
    case logs
}

/// A parsed `pwctl` command and its required arguments.
public enum PwctlCommand: Equatable {
    case help(topic: PwctlHelpTopic)
    case doctor
    case list
    case activate(projectId: String)
    case close(projectId: String)
    case logs(tail: Int)
}

/// A structured parsing failure for `pwctl` arguments.
public struct PwctlParseError: Error, Equatable {
    public let message: String
    public let usageTopic: PwctlHelpTopic

    /// Creates a parsing error with a message and usage topic.
    /// - Parameters:
    ///   - message: Human-readable description of the parsing failure.
    ///   - usageTopic: Usage topic to display alongside the error.
    public init(message: String, usageTopic: PwctlHelpTopic) {
        self.message = message
        self.usageTopic = usageTopic
    }
}

/// Parses `pwctl` CLI arguments into a command or a structured error.
public struct PwctlArgumentParser {
    /// Creates a new parser instance.
    public init() {}

    /// Parses an argument list into a `PwctlCommand` or `PwctlParseError`.
    /// - Parameter arguments: CLI arguments excluding the executable name.
    /// - Returns: A `Result` containing the parsed command or an error.
    public func parse(arguments: [String]) -> Result<PwctlCommand, PwctlParseError> {
        guard !arguments.isEmpty else {
            return .success(.help(topic: .root))
        }

        if isHelpFlag(arguments[0]) {
            guard arguments.count == 1 else {
                return .failure(
                    PwctlParseError(
                        message: "unexpected arguments: \(arguments.dropFirst().joined(separator: " "))",
                        usageTopic: .root
                    )
                )
            }
            return .success(.help(topic: .root))
        }

        let command = arguments[0]
        let remainingArguments = Array(arguments.dropFirst())

        switch command {
        case "doctor":
            return parseNoArgumentCommand(
                arguments: remainingArguments,
                topic: .doctor,
                command: .doctor
            )
        case "list":
            return parseNoArgumentCommand(
                arguments: remainingArguments,
                topic: .list,
                command: .list
            )
        case "activate":
            return parseSingleArgumentCommand(
                arguments: remainingArguments,
                topic: .activate,
                argumentName: "projectId"
            ) { projectId in
                .activate(projectId: projectId)
            }
        case "close":
            return parseSingleArgumentCommand(
                arguments: remainingArguments,
                topic: .close,
                argumentName: "projectId"
            ) { projectId in
                .close(projectId: projectId)
            }
        case "logs":
            return parseLogsCommand(arguments: remainingArguments)
        default:
            return .failure(
                PwctlParseError(
                    message: "unknown command: \(command)",
                    usageTopic: .root
                )
            )
        }
    }

    /// Parses a command that accepts no arguments other than help flags.
    /// - Parameters:
    ///   - arguments: Remaining arguments after the command name.
    ///   - topic: Usage topic to use for help or errors.
    ///   - command: Command to return on success.
    /// - Returns: The parsed command or a structured error.
    private func parseNoArgumentCommand(
        arguments: [String],
        topic: PwctlHelpTopic,
        command: PwctlCommand
    ) -> Result<PwctlCommand, PwctlParseError> {
        if isHelpOnly(arguments) {
            return .success(.help(topic: topic))
        }

        guard arguments.isEmpty else {
            return .failure(
                PwctlParseError(
                    message: "unexpected arguments: \(arguments.joined(separator: " "))",
                    usageTopic: topic
                )
            )
        }

        return .success(command)
    }

    /// Parses a command that requires a single positional argument.
    /// - Parameters:
    ///   - arguments: Remaining arguments after the command name.
    ///   - topic: Usage topic to use for help or errors.
    ///   - argumentName: Human-readable name for the missing argument.
    ///   - builder: Closure that builds the command with the parsed argument.
    /// - Returns: The parsed command or a structured error.
    private func parseSingleArgumentCommand(
        arguments: [String],
        topic: PwctlHelpTopic,
        argumentName: String,
        builder: (String) -> PwctlCommand
    ) -> Result<PwctlCommand, PwctlParseError> {
        if isHelpOnly(arguments) {
            return .success(.help(topic: topic))
        }

        guard let argument = arguments.first else {
            return .failure(
                PwctlParseError(
                    message: "missing \(argumentName)",
                    usageTopic: topic
                )
            )
        }

        guard arguments.count == 1 else {
            return .failure(
                PwctlParseError(
                    message: "unexpected arguments: \(arguments.dropFirst().joined(separator: " "))",
                    usageTopic: topic
                )
            )
        }

        return .success(builder(argument))
    }

    /// Parses the `logs` command with the required `--tail <n>` argument.
    /// - Parameter arguments: Remaining arguments after the `logs` command.
    /// - Returns: The parsed logs command or a structured error.
    private func parseLogsCommand(arguments: [String]) -> Result<PwctlCommand, PwctlParseError> {
        if isHelpOnly(arguments) {
            return .success(.help(topic: .logs))
        }

        guard !arguments.isEmpty else {
            return .failure(
                PwctlParseError(
                    message: "missing --tail <n>",
                    usageTopic: .logs
                )
            )
        }

        guard arguments[0] == "--tail" else {
            return .failure(
                PwctlParseError(
                    message: "expected --tail <n>",
                    usageTopic: .logs
                )
            )
        }

        guard arguments.count >= 2 else {
            return .failure(
                PwctlParseError(
                    message: "missing value for --tail",
                    usageTopic: .logs
                )
            )
        }

        guard arguments.count == 2 else {
            return .failure(
                PwctlParseError(
                    message: "unexpected arguments: \(arguments.dropFirst(2).joined(separator: " "))",
                    usageTopic: .logs
                )
            )
        }

        guard let tail = Int(arguments[1]) else {
            return .failure(
                PwctlParseError(
                    message: "invalid value for --tail: \(arguments[1])",
                    usageTopic: .logs
                )
            )
        }

        guard tail > 0 else {
            return .failure(
                PwctlParseError(
                    message: "--tail must be a positive integer",
                    usageTopic: .logs
                )
            )
        }

        return .success(.logs(tail: tail))
    }

    /// Returns true when the arguments contain exactly one help flag.
    /// - Parameter arguments: Remaining arguments to evaluate.
    /// - Returns: True when the only argument is `-h` or `--help`.
    private func isHelpOnly(_ arguments: [String]) -> Bool {
        arguments.count == 1 && isHelpFlag(arguments[0])
    }

    /// Returns true when the argument is a help flag.
    /// - Parameter argument: The argument to evaluate.
    /// - Returns: True when the argument is `-h` or `--help`.
    private func isHelpFlag(_ argument: String) -> Bool {
        argument == "-h" || argument == "--help"
    }
}
