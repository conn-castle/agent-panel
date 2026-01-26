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

/// Prints text to stdout without adding a trailing newline.
/// - Parameter text: Text to write to stdout.
private func printStdout(_ text: String) {
    FileHandle.standardOutput.write(Data(text.utf8))
}

/// Result statuses recorded in pwctl logs.
private enum PwctlLogResult: String {
    case ok = "ok"
    case fail = "fail"
    case usage = "usage"
    case notImplemented = "not_implemented"

    /// Maps the result to a log severity level.
    var level: LogLevel {
        switch self {
        case .ok:
            return .info
        case .fail:
            return .error
        case .usage, .notImplemented:
            return .warn
        }
    }
}

/// Writes a structured log entry for a pwctl command invocation.
/// - Parameters:
///   - command: Command name for the invocation.
///   - result: Result classification for the command.
private func logCommand(_ command: String, result: PwctlLogResult) {
    let logger = ProjectWorkspacesLogger()
    let context = ["command": command, "result": result.rawValue]
    switch logger.log(event: "pwctl.command", level: result.level, context: context) {
    case .success:
        break
    case .failure(let error):
        printStderr("WARN: \(error.message)")
    }
}

/// Renders Doctor findings as a CLI-friendly text block.
/// - Parameter findings: Findings to render.
/// - Returns: Rendered lines without a trailing newline.
private func renderFindings(_ findings: [DoctorFinding]) -> String {
    let indexed = findings.enumerated()
    let sortedFindings = indexed.sorted { lhs, rhs in
        let leftOrder = lhs.element.severity.sortOrder
        let rightOrder = rhs.element.severity.sortOrder
        if leftOrder == rightOrder {
            return lhs.offset < rhs.offset
        }
        return leftOrder < rightOrder
    }.map { $0.element }

    var lines: [String] = []

    for finding in sortedFindings {
        if finding.title.isEmpty {
            for line in finding.bodyLines {
                lines.append(line)
            }
            continue
        }
        lines.append("\(finding.severity.rawValue)  \(finding.title)")
        for line in finding.bodyLines {
            lines.append(line)
        }
        if let snippet = finding.snippet, !snippet.isEmpty {
            lines.append("  Snippet:")
            lines.append("  ```toml")
            for line in snippet.split(separator: "\n", omittingEmptySubsequences: false) {
                lines.append("  \(line)")
            }
            lines.append("  ```")
        }
    }

    return lines.joined(separator: "\n")
}

let args = Array(CommandLine.arguments.dropFirst())
let parser = PwctlArgumentParser()
let pwctlService = PwctlService()

switch parser.parse(arguments: args) {
case .success(let command):
    switch command {
    case .help(let topic):
        print(usageText(for: topic))
        exit(PwctlExitCode.ok.rawValue)
    case .doctor:
        let report = Doctor().run()
        logCommand("doctor", result: report.hasFailures ? .fail : .ok)
        print(report.rendered())
        exit(report.hasFailures ? PwctlExitCode.failure.rawValue : PwctlExitCode.ok.rawValue)
    case .list:
        switch pwctlService.listProjects() {
        case .failure(let findings):
            logCommand("list", result: .fail)
            printStderr(renderFindings(findings))
            exit(PwctlExitCode.failure.rawValue)
        case .success(let entries, let warnings):
            if !warnings.isEmpty {
                printStderr(renderFindings(warnings))
            }
            for entry in entries {
                print("\(entry.id)\t\(entry.name)\t\(entry.path)")
            }
            logCommand("list", result: .ok)
            exit(PwctlExitCode.ok.rawValue)
        }
    case .activate(let projectId):
        logCommand("activate", result: .notImplemented)
        printStderr("error: `pwctl activate \(projectId)` is not implemented yet")
        exit(PwctlExitCode.failure.rawValue)
    case .close(let projectId):
        logCommand("close", result: .notImplemented)
        printStderr("error: `pwctl close \(projectId)` is not implemented yet")
        exit(PwctlExitCode.failure.rawValue)
    case .logs(let tail):
        switch pwctlService.tailLogs(lines: tail) {
        case .failure(let findings):
            printStderr(renderFindings(findings))
            exit(PwctlExitCode.failure.rawValue)
        case .success(let output, let warnings):
            if !warnings.isEmpty {
                printStderr(renderFindings(warnings))
            }
            if !output.isEmpty {
                printStdout(output)
            }
            exit(PwctlExitCode.ok.rawValue)
        }
    }
case .failure(let error):
    printStderr("error: \(error.message)")
    printStderr(usageText(for: error.usageTopic))
    exit(PwctlExitCode.usage.rawValue)
}
