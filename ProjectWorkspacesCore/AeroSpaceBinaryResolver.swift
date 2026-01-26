import Foundation

/// Error returned when AeroSpace CLI resolution fails.
public struct AeroSpaceBinaryResolutionError: Error, Equatable, Sendable {
    /// Default remediation guidance for AeroSpace CLI resolution failures.
    public static let defaultFix: String = "Install AeroSpace and ensure the `aerospace` CLI is installed, then re-run pwctl doctor."

    public let detail: String
    public let fix: String

    /// Creates a resolution error with detail and fix guidance.
    /// - Parameters:
    ///   - detail: Explanation of the resolution failure.
    ///   - fix: Actionable remediation guidance.
    public init(detail: String, fix: String = AeroSpaceBinaryResolutionError.defaultFix) {
        self.detail = detail
        self.fix = fix
    }
}

/// Resolves the AeroSpace CLI binary path.
public protocol AeroSpaceBinaryResolving {
    /// Resolves the AeroSpace CLI executable.
    /// - Returns: Resolved executable URL or a structured resolution error.
    func resolve() -> Result<URL, AeroSpaceBinaryResolutionError>
}

/// Default AeroSpace binary resolver with deterministic lookup behavior.
public struct DefaultAeroSpaceBinaryResolver: AeroSpaceBinaryResolving {
    private let fileSystem: FileSystem
    private let commandRunner: CommandRunning

    /// Creates a resolver with the provided dependencies.
    /// - Parameters:
    ///   - fileSystem: File system accessor.
    ///   - commandRunner: Command runner used for `which` lookup.
    public init(
        fileSystem: FileSystem = DefaultFileSystem(),
        commandRunner: CommandRunning = DefaultCommandRunner()
    ) {
        self.fileSystem = fileSystem
        self.commandRunner = commandRunner
    }

    /// Resolves the AeroSpace CLI executable using deterministic paths and a controlled `which` lookup.
    /// - Returns: Resolved executable URL or a structured resolution error.
    public func resolve() -> Result<URL, AeroSpaceBinaryResolutionError> {
        let candidatePaths = [
            "/opt/homebrew/bin/aerospace",
            "/usr/local/bin/aerospace"
        ]
        let controlledPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        let searchContext = "Checked /opt/homebrew/bin/aerospace, /usr/local/bin/aerospace, and `which aerospace` with PATH=\(controlledPath)."

        for candidatePath in candidatePaths {
            let candidateURL = URL(fileURLWithPath: candidatePath, isDirectory: false)
            if fileSystem.isExecutableFile(at: candidateURL) {
                return .success(candidateURL)
            }
        }

        let whichURL = URL(fileURLWithPath: "/usr/bin/which", isDirectory: false)

        guard fileSystem.isExecutableFile(at: whichURL) else {
            return .failure(
                AeroSpaceBinaryResolutionError(
                    detail: "Expected /usr/bin/which to be executable for lookup. \(searchContext)"
                )
            )
        }

        let result: CommandResult
        do {
            result = try commandRunner.run(
                command: whichURL,
                arguments: ["aerospace"],
                environment: ["PATH": controlledPath],
                workingDirectory: nil
            )
        } catch {
            return .failure(
                AeroSpaceBinaryResolutionError(
                    detail: "Failed to run /usr/bin/which: \(error). \(searchContext)"
                )
            )
        }

        if result.exitCode != 0 {
            return .failure(
                AeroSpaceBinaryResolutionError(
                    detail: result.failureDetail(prefix: "which aerospace failed") + " " + searchContext
                )
            )
        }

        let resolvedPath = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedPath.isEmpty else {
            return .failure(
                AeroSpaceBinaryResolutionError(
                    detail: "which aerospace returned empty output with PATH=\(controlledPath). \(searchContext)"
                )
            )
        }

        let resolvedURL = URL(fileURLWithPath: resolvedPath, isDirectory: false)
        guard fileSystem.isExecutableFile(at: resolvedURL) else {
            return .failure(
                AeroSpaceBinaryResolutionError(
                    detail: "Resolved path is not executable: \(resolvedPath). \(searchContext)"
                )
            )
        }

        return .success(resolvedURL)
    }
}
