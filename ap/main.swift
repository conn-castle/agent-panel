import Foundation

import apcore

/// Help topics supported by the ap CLI.
private enum ApHelpTopic {
    case root
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
private enum ApCommand {
    case help(ApHelpTopic)
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
private struct ApParseError: Error {
    /// Human-readable error message.
    let message: String
    /// Usage topic to render after the error.
    let usageTopic: ApHelpTopic
}

/// Parses ap CLI arguments into commands.
private struct ApArgumentParser {
    /// Parses CLI arguments into an ap command.
    /// - Parameter arguments: Arguments excluding the process name.
    /// - Returns: Parsed command or a parse error.
    func parse(arguments: [String]) -> Result<ApCommand, ApParseError> {
        guard let first = arguments.first else {
            return .failure(
                ApParseError(message: "missing command", usageTopic: .root)
            )
        }

        if first == "-h" || first == "--help" {
            return .success(.help(.root))
        }

        switch first {
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
    /// - Parameters:
    ///   - command: Command to return on success.
    ///   - helpTopic: Topic to use when rendering usage.
    ///   - arguments: Remaining CLI arguments to validate.
    /// - Returns: Parsed command or a parse error.
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
    /// - Parameters:
    ///   - commandBuilder: Builds the command from the provided argument.
    ///   - helpTopic: Topic to use when rendering usage.
    ///   - arguments: Remaining CLI arguments to validate.
    /// - Returns: Parsed command or a parse error.
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
    /// - Parameters:
    ///   - commandBuilder: Builds the command from the provided arguments.
    ///   - helpTopic: Topic to use when rendering usage.
    ///   - arguments: Remaining CLI arguments to validate.
    /// - Returns: Parsed command or a parse error.
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
    /// - Parameters:
    ///   - commandBuilder: Builds the command from the provided argument.
    ///   - helpTopic: Topic to use when rendering usage.
    ///   - arguments: Remaining CLI arguments to validate.
    /// - Returns: Parsed command or a parse error.
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
private enum ApExitCode: Int32 {
    case ok = 0
    case failure = 1
    case usage = 64
}

/// Builds the `ap` usage string for a given help topic.
/// - Parameter topic: Command topic to render usage for.
/// - Returns: A usage string for the provided topic.
private func usageText(for topic: ApHelpTopic) -> String {
    switch topic {
    case .root:
        return """
        ap (AeroSpace test CLI)

        Usage:
          ap <command> [args]

        Commands:
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

/// Prints text to stderr.
/// - Parameter text: Text to write to stderr.
private func printStderr(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

let args = Array(CommandLine.arguments.dropFirst())
private let parser = ApArgumentParser()

switch parser.parse(arguments: args) {
case .success(let command):
    switch command {
    case .help(let topic):
        print(usageText(for: topic))
        exit(ApExitCode.ok.rawValue)
    case .listWorkspaces:
        switch ApConfig.loadDefault() {
        case .failure(let error):
            printStderr("error: \(error.message)")
            exit(ApExitCode.failure.rawValue)
        case .success(let config):
            let apcore = ApCore(config: config)
            switch apcore.listWorkspaces() {
            case .failure(let error):
                printStderr("error: \(error.message)")
                exit(ApExitCode.failure.rawValue)
            case .success:
                exit(ApExitCode.ok.rawValue)
            }
        }
    case .showConfig:
        switch ApConfig.loadDefault() {
        case .failure(let error):
            printStderr("error: \(error.message)")
            exit(ApExitCode.failure.rawValue)
        case .success(let config):
            let apcore = ApCore(config: config)
            switch apcore.showConfig() {
            case .failure(let error):
                printStderr("error: \(error.message)")
                exit(ApExitCode.failure.rawValue)
            case .success:
                exit(ApExitCode.ok.rawValue)
            }
        }
    case .newWorkspace(let name):
        switch ApConfig.loadDefault() {
        case .failure(let error):
            printStderr("error: \(error.message)")
            exit(ApExitCode.failure.rawValue)
        case .success(let config):
            let apcore = ApCore(config: config)
            switch apcore.newWorkspace(name: name) {
            case .failure(let error):
                printStderr("error: \(error.message)")
                exit(ApExitCode.failure.rawValue)
            case .success:
                exit(ApExitCode.ok.rawValue)
            }
        }
    case .newIde(let identifier):
        switch ApConfig.loadDefault() {
        case .failure(let error):
            printStderr("error: \(error.message)")
            exit(ApExitCode.failure.rawValue)
        case .success(let config):
            let apcore = ApCore(config: config)
            switch apcore.newIde(identifier: identifier) {
            case .failure(let error):
                printStderr("error: \(error.message)")
                exit(ApExitCode.failure.rawValue)
            case .success:
                exit(ApExitCode.ok.rawValue)
            }
        }
    case .newChrome(let identifier):
        switch ApConfig.loadDefault() {
        case .failure(let error):
            printStderr("error: \(error.message)")
            exit(ApExitCode.failure.rawValue)
        case .success(let config):
            let apcore = ApCore(config: config)
            switch apcore.newChrome(identifier: identifier) {
            case .failure(let error):
                printStderr("error: \(error.message)")
                exit(ApExitCode.failure.rawValue)
            case .success:
                exit(ApExitCode.ok.rawValue)
            }
        }
    case .listIde:
        switch ApConfig.loadDefault() {
        case .failure(let error):
            printStderr("error: \(error.message)")
            exit(ApExitCode.failure.rawValue)
        case .success(let config):
            let apcore = ApCore(config: config)
            switch apcore.listIdeWindows() {
            case .failure(let error):
                printStderr("error: \(error.message)")
                exit(ApExitCode.failure.rawValue)
            case .success(let windows):
                for window in windows {
                    print("\(window.windowId)\t\(window.appBundleId)\t\(window.workspace)\t\(window.windowTitle)")
                }
                exit(ApExitCode.ok.rawValue)
            }
        }
    case .listChrome:
        switch ApConfig.loadDefault() {
        case .failure(let error):
            printStderr("error: \(error.message)")
            exit(ApExitCode.failure.rawValue)
        case .success(let config):
            let apcore = ApCore(config: config)
            switch apcore.listChromeWindows() {
            case .failure(let error):
                printStderr("error: \(error.message)")
                exit(ApExitCode.failure.rawValue)
            case .success(let windows):
                for window in windows {
                    print("\(window.windowId)\t\(window.appBundleId)\t\(window.workspace)\t\(window.windowTitle)")
                }
                exit(ApExitCode.ok.rawValue)
            }
        }
    case .listWindows(let workspace):
        switch ApConfig.loadDefault() {
        case .failure(let error):
            printStderr("error: \(error.message)")
            exit(ApExitCode.failure.rawValue)
        case .success(let config):
            let apcore = ApCore(config: config)
            switch apcore.listWindowsWorkspace(workspace) {
            case .failure(let error):
                printStderr("error: \(error.message)")
                exit(ApExitCode.failure.rawValue)
            case .success(let windows):
                for window in windows {
                    print("\(window.windowId)\t\(window.appBundleId)\t\(window.workspace)\t\(window.windowTitle)")
                }
                exit(ApExitCode.ok.rawValue)
            }
        }
    case .focusedWindow:
        switch ApConfig.loadDefault() {
        case .failure(let error):
            printStderr("error: \(error.message)")
            exit(ApExitCode.failure.rawValue)
        case .success(let config):
            let apcore = ApCore(config: config)
            switch apcore.focusedWindow() {
            case .failure(let error):
                printStderr("error: \(error.message)")
                exit(ApExitCode.failure.rawValue)
            case .success(let window):
                print("\(window.windowId)\t\(window.appBundleId)\t\(window.workspace)\t\(window.windowTitle)")
                exit(ApExitCode.ok.rawValue)
            }
        }
    case .moveWindow(let workspace, let windowId):
        switch ApConfig.loadDefault() {
        case .failure(let error):
            printStderr("error: \(error.message)")
            exit(ApExitCode.failure.rawValue)
        case .success(let config):
            let apcore = ApCore(config: config)
            switch apcore.moveWindowToWorkspace(workspace: workspace, windowId: windowId) {
            case .failure(let error):
                printStderr("error: \(error.message)")
                exit(ApExitCode.failure.rawValue)
            case .success:
                exit(ApExitCode.ok.rawValue)
            }
        }
    case .focusWindow(let windowId):
        switch ApConfig.loadDefault() {
        case .failure(let error):
            printStderr("error: \(error.message)")
            exit(ApExitCode.failure.rawValue)
        case .success(let config):
            let apcore = ApCore(config: config)
            switch apcore.focusWindow(windowId: windowId) {
            case .failure(let error):
                printStderr("error: \(error.message)")
                exit(ApExitCode.failure.rawValue)
            case .success:
                exit(ApExitCode.ok.rawValue)
            }
        }
    case .closeWorkspace(let workspace):
        switch ApConfig.loadDefault() {
        case .failure(let error):
            printStderr("error: \(error.message)")
            exit(ApExitCode.failure.rawValue)
        case .success(let config):
            let apcore = ApCore(config: config)
            switch apcore.closeWorkspace(name: workspace) {
            case .failure(let error):
                printStderr("error: \(error.message)")
                exit(ApExitCode.failure.rawValue)
            case .success:
                exit(ApExitCode.ok.rawValue)
            }
        }
    }
case .failure(let error):
    printStderr("error: \(error.message)")
    printStderr(usageText(for: error.usageTopic))
    exit(ApExitCode.usage.rawValue)
}
