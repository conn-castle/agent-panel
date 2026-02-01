import Foundation

/// Canonical filesystem locations used by ProjectWorkspaces.
public struct ProjectWorkspacesPaths: Sendable {
    /// User home directory used as the root for derived paths.
    public let homeDirectory: URL

    /// Creates a paths container rooted at the provided home directory.
    /// - Parameter homeDirectory: Home directory as a file URL.
    public init(homeDirectory: URL) {
        precondition(homeDirectory.isFileURL, "homeDirectory must be a file URL")
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    /// Creates a paths container rooted at the current user's home directory.
    /// - Parameter fileManager: File manager used to resolve the home directory.
    /// - Returns: A `ProjectWorkspacesPaths` instance rooted at the user's home directory.
    public static func defaultPaths(fileManager: FileManager = .default) -> ProjectWorkspacesPaths {
        ProjectWorkspacesPaths(homeDirectory: fileManager.homeDirectoryForCurrentUser)
    }

    /// Returns `~/.config/project-workspaces/config.toml`.
    public var configFile: URL {
        configDirectory.appendingPathComponent("config.toml", isDirectory: false)
    }

    /// Returns `~/.local/state/project-workspaces/vscode`.
    public var vscodeWorkspaceDirectory: URL {
        stateDirectory.appendingPathComponent("vscode", isDirectory: true)
    }

    /// Returns `~/.local/state/project-workspaces/vscode/<projectId>.code-workspace`.
    /// - Parameter projectId: Project identifier used to name the workspace file.
    /// - Returns: URL for the generated VS Code workspace file.
    public func vscodeWorkspaceFile(projectId: String) -> URL {
        vscodeWorkspaceDirectory.appendingPathComponent("\(projectId).code-workspace", isDirectory: false)
    }

    /// Returns `~/.local/state/project-workspaces/state.json`.
    public var stateFile: URL {
        stateDirectory.appendingPathComponent("state.json", isDirectory: false)
    }

    /// Returns `~/.local/state/project-workspaces/logs`.
    public var logsDirectory: URL {
        stateDirectory.appendingPathComponent("logs", isDirectory: true)
    }

    /// Returns `~/.local/state/project-workspaces/logs/workspaces.log`.
    public var primaryLogFile: URL {
        logsDirectory.appendingPathComponent("workspaces.log", isDirectory: false)
    }

    private var configDirectory: URL {
        homeDirectory
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("project-workspaces", isDirectory: true)
    }

    private var stateDirectory: URL {
        homeDirectory
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("state", isDirectory: true)
            .appendingPathComponent("project-workspaces", isDirectory: true)
    }
}
