import Foundation

import ProjectWorkspacesCore

/// Exit codes used by `pwctl`.
private enum PwctlExitCode: Int32 {
    case ok = 0
    case failure = 1
    case usage = 64
}

/// Builds the `pwctl` usage string.
private func usageText() -> String {
    """
    pwctl (ProjectWorkspaces CLI) — \(ProjectWorkspacesCore.version)

    Usage:
      pwctl <command> [args]

    Commands (locked surface; not fully implemented yet):
      doctor
      list
      activate <projectId>
      close <projectId>
      logs

    Options:
      -h, --help   Show help
    """
}

/// Prints text to stderr.
private func printStderr(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

let args = Array(CommandLine.arguments.dropFirst())

if args.isEmpty || args.contains("-h") || args.contains("--help") {
    print(usageText())
    exit(PwctlExitCode.ok.rawValue)
}

let command = args[0]

switch command {
case "doctor", "list", "activate", "close", "logs":
    printStderr("error: `pwctl \(command)` is not implemented yet")
    exit(PwctlExitCode.failure.rawValue)
default:
    printStderr("error: unknown command: \(command)\n")
    printStderr(usageText())
    exit(PwctlExitCode.usage.rawValue)
}

