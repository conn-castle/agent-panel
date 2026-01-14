import Foundation

import ProjectWorkspacesCore

/// Exit codes used by `pwctl`.
private enum PwctlExitCode: Int32 {
    case ok = 0
    case failure = 1
    case usage = 64
}

/// Builds the `pwctl` usage string for a given help topic.
/// - Parameter topic: Command topic to render usage for.
/// - Returns: A usage string for the provided topic.
private func usageText(for topic: PwctlHelpTopic) -> String {
    switch topic {
    case .root:
        return """
        pwctl (ProjectWorkspaces CLI) — \(ProjectWorkspacesCore.version)

        Usage:
          pwctl <command> [args]

        Commands (locked surface; doctor implemented, others in progress):
          doctor
          list
          activate <projectId>
          close <projectId>
          logs --tail <n>

        Options:
          -h, --help   Show help
        """
    case .doctor:
        return """
        Usage:
          pwctl doctor

        Options:
          -h, --help   Show help
        """
    case .list:
        return """
        Usage:
          pwctl list

        Options:
          -h, --help   Show help
        """
    case .activate:
        return """
        Usage:
          pwctl activate <projectId>

        Options:
          -h, --help   Show help
        """
    case .close:
        return """
        Usage:
          pwctl close <projectId>

        Options:
          -h, --help   Show help
        """
    case .logs:
        return """
        Usage:
          pwctl logs --tail <n>

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
let parser = PwctlArgumentParser()

switch parser.parse(arguments: args) {
case .success(let command):
    switch command {
    case .help(let topic):
        print(usageText(for: topic))
        exit(PwctlExitCode.ok.rawValue)
    case .doctor:
        let report = Doctor().run()
        print(report.rendered())
        exit(report.hasFailures ? PwctlExitCode.failure.rawValue : PwctlExitCode.ok.rawValue)
    case .list:
        printStderr("error: `pwctl list` is not implemented yet")
        exit(PwctlExitCode.failure.rawValue)
    case .activate(let projectId):
        printStderr("error: `pwctl activate \(projectId)` is not implemented yet")
        exit(PwctlExitCode.failure.rawValue)
    case .close(let projectId):
        printStderr("error: `pwctl close \(projectId)` is not implemented yet")
        exit(PwctlExitCode.failure.rawValue)
    case .logs(let tail):
        printStderr("error: `pwctl logs --tail \(tail)` is not implemented yet")
        exit(PwctlExitCode.failure.rawValue)
    }
case .failure(let error):
    printStderr("error: \(error.message)")
    printStderr(usageText(for: error.usageTopic))
    exit(PwctlExitCode.usage.rawValue)
}
