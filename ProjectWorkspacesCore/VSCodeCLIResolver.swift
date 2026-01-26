import Foundation

/// Errors returned when resolving the VS Code CLI path.
public enum VSCodeCLIError: Error, Equatable, Sendable {
    case missingCLI(String)
}

/// Resolves the VS Code bundled CLI path.
public struct VSCodeCLIResolver {
    private let fileSystem: FileSystem

    /// Creates a CLI resolver.
    /// - Parameter fileSystem: File system accessor.
    public init(fileSystem: FileSystem = DefaultFileSystem()) {
        self.fileSystem = fileSystem
    }

    /// Resolves the bundled `code` CLI path inside the VS Code app bundle.
    /// - Parameter vscodeAppURL: VS Code `.app` URL.
    /// - Returns: CLI URL or an error.
    public func resolveCLIPath(vscodeAppURL: URL) -> Result<URL, VSCodeCLIError> {
        let cliURL = vscodeAppURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("app", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("code", isDirectory: false)

        guard fileSystem.isExecutableFile(at: cliURL) else {
            return .failure(.missingCLI(cliURL.path))
        }

        return .success(cliURL)
    }
}
