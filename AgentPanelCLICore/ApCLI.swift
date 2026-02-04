import Foundation

import AgentPanelCore

/// Help topics supported by the ap CLI.
public enum ApHelpTopic: Equatable {
    case root
    case doctor
    case listWorkspaces
    case showConfig
    case newWorkspace
    case newIde
    case newChrome
    case listIde
    case listChrome
    case listWindows
    case focusedWindow
    case moveWindow
    case focusWindow
    case closeWorkspace
}

/// Commands supported by the ap CLI.
public enum ApCommand {
    case help(ApHelpTopic)
    case version
    case doctor
    case listWorkspaces
    case showConfig
    case newWorkspace(String)
    case newIde(String)
    case newChrome(String)
    case listIde
    case listChrome
    case listWindows(String)
    case focusedWindow
    case moveWindow(String, Int)
    case focusWindow(Int)
    case closeWorkspace(String)
}

/// Parse errors for ap CLI arguments.
public struct ApParseError: Error {
    /// Human-readable error message.
    public let message: String
    /// Usage topic to render after the error.
    public let usageTopic: ApHelpTopic

    public init(message: String, usageTopic: ApHelpTopic) {
        self.message = message
        self.usageTopic = usageTopic
    }
}

/// Parses ap CLI arguments into commands.
public struct ApArgumentParser {
    public init() {}

    /// Parses CLI arguments into an ap command.
    /// - Parameter arguments: Arguments excluding the process name.
    /// - Returns: Parsed command or a parse error.
    public func parse(arguments: [String]) -> Result<ApCommand, ApParseError> {
        guard let first = arguments.first else {
            return .failure(
                ApParseError(message: "missing command", usageTopic: .root)
            )
        }

        if first == "-h" || first == "--help" {
            return .success(.help(.root))
        }

        if first == "-v" || first == "--version" {
            return .success(.version)
        }

        switch first {
        case "doctor":
            return parseNoArgumentCommand(
                command: .doctor,
                helpTopic: .doctor,
                arguments: Array(arguments.dropFirst())
            )
        case "list-workspaces":
            return parseNoArgumentCommand(
                command: .listWorkspaces,
                helpTopic: .listWorkspaces,
                arguments: Array(arguments.dropFirst())
            )
        case "show-config":
            return parseNoArgumentCommand(
                command: .showConfig,
                helpTopic: .showConfig,
                arguments: Array(arguments.dropFirst())
            )
        case "new-workspace":
            return parseSingleArgumentCommand(
                commandBuilder: { .newWorkspace($0) },
                helpTopic: .newWorkspace,
                arguments: Array(arguments.dropFirst())
            )
        case "new-ide":
            return parseSingleArgumentCommand(
                commandBuilder: { .newIde($0) },
                helpTopic: .newIde,
                arguments: Array(arguments.dropFirst())
            )
        case "new-chrome":
            return parseSingleArgumentCommand(
                commandBuilder: { .newChrome($0) },
                helpTopic: .newChrome,
                arguments: Array(arguments.dropFirst())
            )
        case "list-ide":
            return parseNoArgumentCommand(
                command: .listIde,
                helpTopic: .listIde,
                arguments: Array(arguments.dropFirst())
            )
        case "list-chrome":
            return parseNoArgumentCommand(
                command: .listChrome,
                helpTopic: .listChrome,
                arguments: Array(arguments.dropFirst())
            )
        case "list-windows":
            return parseSingleArgumentCommand(
                commandBuilder: { .listWindows($0) },
                helpTopic: .listWindows,
                arguments: Array(arguments.dropFirst())
            )
        case "focused-window":
            return parseNoArgumentCommand(
                command: .focusedWindow,
                helpTopic: .focusedWindow,
                arguments: Array(arguments.dropFirst())
            )
        case "move-window":
            return parseTwoArgumentCommand(
                commandBuilder: { workspace, windowId in
                    .moveWindow(workspace, windowId)
                },
                helpTopic: .moveWindow,
                arguments: Array(arguments.dropFirst())
            )
        case "focus-window":
            return parseSingleIntArgumentCommand(
                commandBuilder: { .focusWindow($0) },
                helpTopic: .focusWindow,
                arguments: Array(arguments.dropFirst())
            )
        case "close-workspace":
            return parseSingleArgumentCommand(
                commandBuilder: { .closeWorkspace($0) },
                helpTopic: .closeWorkspace,
                arguments: Array(arguments.dropFirst())
            )
        default:
            return .failure(
                ApParseError(message: "unknown command: \(first)", usageTopic: .root)
            )
        }
    }

    /// Parses commands that accept no arguments (besides --help).
    private func parseNoArgumentCommand(
        command: ApCommand,
        helpTopic: ApHelpTopic,
        arguments: [String]
    ) -> Result<ApCommand, ApParseError> {
        if arguments.isEmpty {
            return .success(command)
        }

        if arguments.count == 1, let arg = arguments.first, arg == "-h" || arg == "--help" {
            return .success(.help(helpTopic))
        }

        return .failure(
            ApParseError(
                message: "unexpected arguments: \(arguments.joined(separator: " "))",
                usageTopic: helpTopic
            )
        )
    }

    /// Parses commands that require a single argument (besides --help).
    private func parseSingleArgumentCommand(
        commandBuilder: (String) -> ApCommand,
        helpTopic: ApHelpTopic,
        arguments: [String]
    ) -> Result<ApCommand, ApParseError> {
        if arguments.count == 1, let arg = arguments.first {
            if arg == "-h" || arg == "--help" {
                return .success(.help(helpTopic))
            }
            return .success(commandBuilder(arg))
        }

        if arguments.count == 0 {
            return .failure(
                ApParseError(message: "missing argument", usageTopic: helpTopic)
            )
        }

        return .failure(
            ApParseError(
                message: "unexpected arguments: \(arguments.joined(separator: " "))",
                usageTopic: helpTopic
            )
        )
    }

    /// Parses commands that require two arguments (besides --help).
    private func parseTwoArgumentCommand(
        commandBuilder: (String, Int) -> ApCommand,
        helpTopic: ApHelpTopic,
        arguments: [String]
    ) -> Result<ApCommand, ApParseError> {
        if arguments.count == 1, let arg = arguments.first, arg == "-h" || arg == "--help" {
            return .success(.help(helpTopic))
        }

        if arguments.count == 2 {
            let workspace = arguments[0]
            let windowIdRaw = arguments[1]
            guard let windowId = Int(windowIdRaw) else {
                return .failure(
                    ApParseError(
                        message: "window id must be an integer: \(windowIdRaw)",
                        usageTopic: helpTopic
                    )
                )
            }
            return .success(commandBuilder(workspace, windowId))
        }

        if arguments.count == 0 {
            return .failure(
                ApParseError(message: "missing arguments", usageTopic: helpTopic)
            )
        }

        return .failure(
            ApParseError(
                message: "unexpected arguments: \(arguments.joined(separator: " "))",
                usageTopic: helpTopic
            )
        )
    }

    /// Parses commands that require a single integer argument (besides --help).
    private func parseSingleIntArgumentCommand(
        commandBuilder: (Int) -> ApCommand,
        helpTopic: ApHelpTopic,
        arguments: [String]
    ) -> Result<ApCommand, ApParseError> {
        if arguments.count == 1, let arg = arguments.first {
            if arg == "-h" || arg == "--help" {
                return .success(.help(helpTopic))
            }
            guard let value = Int(arg) else {
                return .failure(
                    ApParseError(
                        message: "argument must be an integer: \(arg)",
                        usageTopic: helpTopic
                    )
                )
            }
            return .success(commandBuilder(value))
        }

        if arguments.count == 0 {
            return .failure(
                ApParseError(message: "missing argument", usageTopic: helpTopic)
            )
        }

        return .failure(
            ApParseError(
                message: "unexpected arguments: \(arguments.joined(separator: " "))",
                usageTopic: helpTopic
            )
        )
    }
}

/// Exit codes used by `ap`.
public enum ApExitCode: Int32 {
    case ok = 0
    case failure = 1
    case usage = 64
}

/// Output sink for the CLI.
public struct ApCLIOutput {
    public let stdout: (String) -> Void
    public let stderr: (String) -> Void

    public init(stdout: @escaping (String) -> Void, stderr: @escaping (String) -> Void) {
        self.stdout = stdout
        self.stderr = stderr
    }

    public static let standard = ApCLIOutput(
        stdout: { print($0) },
        stderr: { printStderr($0) }
    )
}

/// Interface for core command execution (testable abstraction).
public protocol ApCoreCommanding {
    var config: Config { get }
    func listWorkspaces() -> Result<[String], ApCoreError>
    func newWorkspace(name: String) -> Result<Void, ApCoreError>
    func newIde(identifier: String) -> Result<Void, ApCoreError>
    func newChrome(identifier: String) -> Result<Void, ApCoreError>
    func listIdeWindows() -> Result<[ApWindow], ApCoreError>
    func listChromeWindows() -> Result<[ApWindow], ApCoreError>
    func listWindowsWorkspace(_ workspace: String) -> Result<[ApWindow], ApCoreError>
    func focusedWindow() -> Result<ApWindow, ApCoreError>
    func moveWindowToWorkspace(workspace: String, windowId: Int) -> Result<Void, ApCoreError>
    func focusWindow(windowId: Int) -> Result<Void, ApCoreError>
    func closeWorkspace(name: String) -> Result<Void, ApCoreError>
}

extension ApCore: ApCoreCommanding {}

/// Dependencies for the CLI runner.
public struct ApCLIDependencies {
    public let version: () -> String
    public let configLoader: () -> Result<ConfigLoadResult, ConfigError>
    public let coreFactory: (Config) -> ApCoreCommanding
    public let doctorRunner: () -> DoctorReport

    public init(
        version: @escaping () -> String,
        configLoader: @escaping () -> Result<ConfigLoadResult, ConfigError>,
        coreFactory: @escaping (Config) -> ApCoreCommanding,
        doctorRunner: @escaping () -> DoctorReport
    ) {
        self.version = version
        self.configLoader = configLoader
        self.coreFactory = coreFactory
        self.doctorRunner = doctorRunner
    }
}

/// CLI runner that returns an exit code instead of calling exit().
public struct ApCLI {
    public let parser: ApArgumentParser
    public let dependencies: ApCLIDependencies
    public let output: ApCLIOutput

    public init(parser: ApArgumentParser, dependencies: ApCLIDependencies, output: ApCLIOutput) {
        self.parser = parser
        self.dependencies = dependencies
        self.output = output
    }

    public func run(arguments: [String]) -> Int32 {
        switch parser.parse(arguments: arguments) {
        case .success(let command):
            return run(command: command)
        case .failure(let error):
            output.stderr("error: \(error.message)")
            output.stderr(usageText(for: error.usageTopic))
            return ApExitCode.usage.rawValue
        }
    }

    private func run(command: ApCommand) -> Int32 {
        switch command {
        case .help(let topic):
            output.stdout(usageText(for: topic))
            return ApExitCode.ok.rawValue
        case .version:
            output.stdout("ap \(dependencies.version())")
            return ApExitCode.ok.rawValue
        case .doctor:
            let report = dependencies.doctorRunner()
            output.stdout(report.rendered())
            return report.hasFailures ? ApExitCode.failure.rawValue : ApExitCode.ok.rawValue
        case .listWorkspaces:
            return runCoreWorkspacesCommand { core in
                core.listWorkspaces()
            }
        case .showConfig:
            return runShowConfigCommand()
        case .newWorkspace(let name):
            return runCoreCommand { core in
                core.newWorkspace(name: name)
            }
        case .newIde(let identifier):
            return runCoreCommand { core in
                core.newIde(identifier: identifier)
            }
        case .newChrome(let identifier):
            return runCoreCommand { core in
                core.newChrome(identifier: identifier)
            }
        case .listIde:
            return runCoreWindowsCommand { core in
                core.listIdeWindows()
            }
        case .listChrome:
            return runCoreWindowsCommand { core in
                core.listChromeWindows()
            }
        case .listWindows(let workspace):
            return runCoreWindowsCommand { core in
                core.listWindowsWorkspace(workspace)
            }
        case .focusedWindow:
            return runCoreWindowCommand { core in
                core.focusedWindow()
            }
        case .moveWindow(let workspace, let windowId):
            return runCoreCommand { core in
                core.moveWindowToWorkspace(workspace: workspace, windowId: windowId)
            }
        case .focusWindow(let windowId):
            return runCoreCommand { core in
                core.focusWindow(windowId: windowId)
            }
        case .closeWorkspace(let workspace):
            return runCoreCommand { core in
                core.closeWorkspace(name: workspace)
            }
        }
    }

    private enum ConfigLoadFailure: Error {
        case message(String)

        var message: String {
            switch self {
            case .message(let value):
                return value
            }
        }
    }

    private func loadConfig() -> Result<Config, ConfigLoadFailure> {
        switch dependencies.configLoader() {
        case .failure(let error):
            return .failure(.message(error.message))
        case .success(let result):
            guard let config = result.config else {
                let firstFail = result.findings.first { $0.severity == .fail }
                let message = firstFail?.title ?? "Config validation failed"
                return .failure(.message(message))
            }
            return .success(config)
        }
    }

    private func runCoreCommand(_ execute: (ApCoreCommanding) -> Result<Void, ApCoreError>) -> Int32 {
        switch loadConfig() {
        case .failure(let error):
            output.stderr("error: \(error.message)")
            return ApExitCode.failure.rawValue
        case .success(let config):
            let core = dependencies.coreFactory(config)
            switch execute(core) {
            case .failure(let error):
                output.stderr("error: \(error.message)")
                return ApExitCode.failure.rawValue
            case .success:
                return ApExitCode.ok.rawValue
            }
        }
    }

    private func runCoreWindowsCommand(
        _ execute: (ApCoreCommanding) -> Result<[ApWindow], ApCoreError>
    ) -> Int32 {
        switch loadConfig() {
        case .failure(let error):
            output.stderr("error: \(error.message)")
            return ApExitCode.failure.rawValue
        case .success(let config):
            let core = dependencies.coreFactory(config)
            switch execute(core) {
            case .failure(let error):
                output.stderr("error: \(error.message)")
                return ApExitCode.failure.rawValue
            case .success(let windows):
                for window in windows {
                    output.stdout(formatWindowLine(window))
                }
                return ApExitCode.ok.rawValue
            }
        }
    }

    private func runCoreWindowCommand(
        _ execute: (ApCoreCommanding) -> Result<ApWindow, ApCoreError>
    ) -> Int32 {
        switch loadConfig() {
        case .failure(let error):
            output.stderr("error: \(error.message)")
            return ApExitCode.failure.rawValue
        case .success(let config):
            let core = dependencies.coreFactory(config)
            switch execute(core) {
            case .failure(let error):
                output.stderr("error: \(error.message)")
                return ApExitCode.failure.rawValue
            case .success(let window):
                output.stdout(formatWindowLine(window))
                return ApExitCode.ok.rawValue
            }
        }
    }

    private func runCoreWorkspacesCommand(
        _ execute: (ApCoreCommanding) -> Result<[String], ApCoreError>
    ) -> Int32 {
        switch loadConfig() {
        case .failure(let error):
            output.stderr("error: \(error.message)")
            return ApExitCode.failure.rawValue
        case .success(let config):
            let core = dependencies.coreFactory(config)
            switch execute(core) {
            case .failure(let error):
                output.stderr("error: \(error.message)")
                return ApExitCode.failure.rawValue
            case .success(let workspaces):
                for workspace in workspaces {
                    output.stdout(workspace)
                }
                return ApExitCode.ok.rawValue
            }
        }
    }

    private func runShowConfigCommand() -> Int32 {
        switch loadConfig() {
        case .failure(let error):
            output.stderr("error: \(error.message)")
            return ApExitCode.failure.rawValue
        case .success(let config):
            let core = dependencies.coreFactory(config)
            output.stdout(formatConfig(core.config))
            return ApExitCode.ok.rawValue
        }
    }
}

/// Builds the `ap` usage string for a given help topic.
func usageText(for topic: ApHelpTopic) -> String {
    switch topic {
    case .root:
        return """
        ap (AgentPanel CLI)

        Usage:
          ap <command> [args]

        Commands:
          doctor
          list-workspaces
          show-config
          new-workspace <name>
          new-ide <identifier>
          new-chrome <identifier>
          list-ide
          list-chrome
          list-windows <workspace>
          focused-window
          move-window <workspace> <window-id>
          focus-window <window-id>
          close-workspace <workspace>

        Options:
          -h, --help      Show help
          -v, --version   Show version
        """
    case .doctor:
        return """
        Usage:
          ap doctor

        Options:
          -h, --help   Show help
        """
    case .listWorkspaces:
        return """
        Usage:
          ap list-workspaces

        Options:
          -h, --help   Show help
        """
    case .showConfig:
        return """
        Usage:
          ap show-config

        Options:
          -h, --help   Show help
        """
    case .newWorkspace:
        return """
        Usage:
          ap new-workspace <name>

        Options:
          -h, --help   Show help
        """
    case .newIde:
        return """
        Usage:
          ap new-ide <identifier>

        Options:
          -h, --help   Show help
        """
    case .listIde:
        return """
        Usage:
          ap list-ide

        Options:
          -h, --help   Show help
        """
    case .newChrome:
        return """
        Usage:
          ap new-chrome <identifier>

        Options:
          -h, --help   Show help
        """
    case .listChrome:
        return """
        Usage:
          ap list-chrome

        Options:
          -h, --help   Show help
        """
    case .listWindows:
        return """
        Usage:
          ap list-windows <workspace>

        Options:
          -h, --help   Show help
        """
    case .focusedWindow:
        return """
        Usage:
          ap focused-window

        Options:
          -h, --help   Show help
        """
    case .moveWindow:
        return """
        Usage:
          ap move-window <workspace> <window-id>

        Options:
          -h, --help   Show help
        """
    case .focusWindow:
        return """
        Usage:
          ap focus-window <window-id>

        Options:
          -h, --help   Show help
        """
    case .closeWorkspace:
        return """
        Usage:
          ap close-workspace <workspace>

        Options:
          -h, --help   Show help
        """
    }
}

private func formatWindowLine(_ window: ApWindow) -> String {
    "\(window.windowId)\t\(window.appBundleId)\t\(window.workspace)\t\(window.windowTitle)"
}

private func formatConfig(_ config: Config) -> String {
    var lines: [String] = []
    lines.append("# AgentPanel Configuration")
    lines.append("")

    for project in config.projects {
        lines.append("[[project]]")
        lines.append("id = \"\(project.id)\"")
        lines.append("name = \"\(project.name)\"")
        lines.append("path = \"\(project.path)\"")
        lines.append("color = \"\(project.color)\"")
        lines.append("useAgentLayer = \(project.useAgentLayer)")
        lines.append("")
    }

    return lines.joined(separator: "\n")
}

/// Prints text to stderr.
private func printStderr(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

