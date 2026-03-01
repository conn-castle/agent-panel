import Foundation

import AgentPanelCore

/// Minimal interface required by the CLI runner for project operations.
public protocol ProjectManaging {
    func loadConfig() -> Result<ConfigLoadSuccess, ConfigLoadError>
    func sortedProjects(query: String) -> [ProjectConfig]
    func captureCurrentFocus() -> CapturedFocus?
    func selectProject(projectId: String, preCapturedFocus: CapturedFocus) async -> Result<ProjectActivationSuccess, ProjectError>
    func closeProject(projectId: String) -> Result<ProjectCloseSuccess, ProjectError>
    func exitToNonProjectWindow() -> Result<Void, ProjectError>
}

extension ProjectManager: ProjectManaging {}

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

/// Dependencies for the CLI runner.
public struct ApCLIDependencies {
    public let version: () -> String
    public let projectManagerFactory: () -> any ProjectManaging
    public let doctorRunner: () -> DoctorReport

    public init(
        version: @escaping () -> String,
        projectManagerFactory: @escaping () -> any ProjectManaging,
        doctorRunner: @escaping () -> DoctorReport
    ) {
        self.version = version
        self.projectManagerFactory = projectManagerFactory
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
            let useColor = isatty(STDOUT_FILENO) != 0
                && ProcessInfo.processInfo.environment["NO_COLOR"] == nil
            output.stdout(report.rendered(colorize: useColor))
            return report.hasFailures ? ApExitCode.failure.rawValue : ApExitCode.ok.rawValue

        case .showConfig:
            let manager = dependencies.projectManagerFactory()
            switch manager.loadConfig() {
            case .failure(let error):
                output.stderr("error: \(formatConfigError(error))")
                return ApExitCode.failure.rawValue
            case .success(let success):
                for warning in success.warnings {
                    output.stderr("warning: \(warning.title)")
                }
                output.stdout(formatConfig(success.config))
                return ApExitCode.ok.rawValue
            }

        case .listProjects(let query):
            let manager = dependencies.projectManagerFactory()
            switch manager.loadConfig() {
            case .failure(let error):
                output.stderr("error: \(formatConfigError(error))")
                return ApExitCode.failure.rawValue
            case .success:
                let projects = manager.sortedProjects(query: query ?? "")
                for project in projects {
                    output.stdout(formatProjectLine(project))
                }
                return ApExitCode.ok.rawValue
            }

        case .selectProject(let projectId):
            let manager = dependencies.projectManagerFactory()
            switch manager.loadConfig() {
            case .failure(let error):
                output.stderr("error: \(formatConfigError(error))")
                return ApExitCode.failure.rawValue
            case .success:
                guard let capturedFocus = manager.captureCurrentFocus() else {
                    output.stderr("error: Could not capture current focus")
                    return ApExitCode.failure.rawValue
                }
                // Bridge async selectProject to sync CLI using semaphore with timeout
                let semaphore = DispatchSemaphore(value: 0)
                var result: Result<ProjectActivationSuccess, ProjectError>?
                Task {
                    result = await manager.selectProject(projectId: projectId, preCapturedFocus: capturedFocus)
                    semaphore.signal()
                }
                let timeoutResult = semaphore.wait(timeout: .now() + 30)
                if timeoutResult == .timedOut {
                    output.stderr("error: Project activation timed out after 30 seconds")
                    return ApExitCode.failure.rawValue
                }

                switch result {
                case .failure(let error):
                    output.stderr("error: \(formatProjectError(error))")
                    return ApExitCode.failure.rawValue
                case .success(let activation):
                    if let warning = activation.tabRestoreWarning {
                        output.stderr("warning: \(warning)")
                    }
                    if let warning = activation.layoutWarning {
                        output.stderr("warning: \(warning)")
                    }
                    output.stdout("Selected project: \(projectId)")
                    return ApExitCode.ok.rawValue
                case .none:
                    output.stderr("error: Unexpected nil result")
                    return ApExitCode.failure.rawValue
                }
            }

        case .closeProject(let projectId):
            let manager = dependencies.projectManagerFactory()
            switch manager.loadConfig() {
            case .failure(let error):
                output.stderr("error: \(formatConfigError(error))")
                return ApExitCode.failure.rawValue
            case .success:
                switch manager.closeProject(projectId: projectId) {
                case .failure(let error):
                    output.stderr("error: \(formatProjectError(error))")
                    return ApExitCode.failure.rawValue
                case .success(let closeResult):
                    if let warning = closeResult.tabCaptureWarning {
                        output.stderr("warning: \(warning)")
                    }
                    output.stdout("Closed project: \(projectId)")
                    return ApExitCode.ok.rawValue
                }
            }

        case .returnToWindow:
            let manager = dependencies.projectManagerFactory()
            switch manager.loadConfig() {
            case .failure(let error):
                output.stderr("error: \(formatConfigError(error))")
                return ApExitCode.failure.rawValue
            case .success:
                switch manager.exitToNonProjectWindow() {
                case .failure(let error):
                    output.stderr("error: \(formatProjectError(error))")
                    return ApExitCode.failure.rawValue
                case .success:
                    output.stdout("Returned to non-project space")
                    return ApExitCode.ok.rawValue
                }
            }
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
          doctor              Run diagnostic checks
          show-config         Show current configuration
          list-projects [q]   List projects (optionally filtered by query)
          select-project <id> Activate a project
          close-project <id>  Close a project and return to non-project space
          return              Return to most recent non-project window without closing project

        Options:
          -h, --help      Show help
          -v, --version   Show version
        """
    case .doctor:
        return """
        Usage:
          ap doctor

        Run diagnostic checks for AgentPanel dependencies.

        Options:
          -h, --help   Show help
        """
    case .showConfig:
        return """
        Usage:
          ap show-config

        Display the current AgentPanel configuration.

        Options:
          -h, --help   Show help
        """
    case .listProjects:
        return """
        Usage:
          ap list-projects [query]

        List all projects, optionally filtered by a search query.
        Projects are sorted by recency (most recently used first).

        Options:
          -h, --help   Show help
        """
    case .selectProject:
        return """
        Usage:
          ap select-project <project-id>

        Activate a project by its ID. This will:
        - Create/focus the project's workspace
        - Open Chrome and VS Code windows if needed
        - Move windows to the workspace
        - Focus the IDE window

        Options:
          -h, --help   Show help
        """
    case .closeProject:
        return """
        Usage:
          ap close-project <project-id>

        Close a project by its ID. This will:
        - Close all windows in the project's workspace
        - Return focus to non-project space

        Options:
          -h, --help   Show help
        """
    case .returnToWindow:
        return """
        Usage:
          ap return

        Return to the most recent non-project window without closing the current project.
        Use this to temporarily leave a project while keeping it open.

        Options:
          -h, --help   Show help
        """
    }
}

private func formatProjectLine(_ project: ProjectConfig) -> String {
    "\(project.id)\t\(project.name)\t\(project.path)"
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

private func formatConfigError(_ error: ConfigLoadError) -> String {
    switch error {
    case .fileNotFound(let path):
        return "Config file not found: \(path)"
    case .readFailed(let path, let detail):
        return "Failed to read config at \(path): \(detail)"
    case .parseFailed(let detail):
        return "Failed to parse config: \(detail)"
    case .validationFailed(let findings):
        let firstFail = findings.first { $0.severity == .fail }
        return firstFail?.title ?? "Config validation failed"
    }
}

private func formatProjectError(_ error: ProjectError) -> String {
    switch error {
    case .projectNotFound(let projectId):
        return "Project not found: \(projectId)"
    case .configNotLoaded:
        return "Config not loaded"
    case .aeroSpaceError(let detail):
        return "AeroSpace error: \(detail)"
    case .ideLaunchFailed(let detail):
        return "IDE launch failed: \(detail)"
    case .chromeLaunchFailed(let detail):
        return "Chrome launch failed: \(detail)"
    case .noActiveProject:
        return "No active project"
    case .noPreviousWindow:
        return "No recent non-project window to return to"
    case .windowNotFound(let detail):
        return "Window not found: \(detail)"
    case .focusUnstable(let detail):
        return "Focus unstable: \(detail)"
    }
}

/// Prints text to stderr.
private func printStderr(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}
