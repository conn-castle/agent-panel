import Foundation

/// Canonical filesystem locations and data access for AgentPanel.
///
/// Currently provides path resolution. Future: read/write APIs for config, state, and logs.
public struct DataStore: Sendable {
    /// User home directory used as the root for derived paths.
    public let homeDirectory: URL

    /// Creates a data store rooted at the provided home directory.
    /// - Parameter homeDirectory: Home directory as a file URL.
    public init(homeDirectory: URL) {
        precondition(homeDirectory.isFileURL, "homeDirectory must be a file URL")
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    /// Creates a data store rooted at the current user's home directory.
    /// - Parameter fileManager: File manager used to resolve the home directory.
    /// - Returns: A `DataStore` instance rooted at the user's home directory.
    public static func `default`(fileManager: FileManager = .default) -> DataStore {
        DataStore(homeDirectory: fileManager.homeDirectoryForCurrentUser)
    }

    // MARK: - Config paths

    /// Returns `~/.config/agent-panel/config.toml`.
    public var configFile: URL {
        configDirectory.appendingPathComponent("config.toml", isDirectory: false)
    }

    // MARK: - State paths

    /// Returns `~/.local/state/agent-panel/vscode`.
    public var vscodeWorkspaceDirectory: URL {
        stateDirectory.appendingPathComponent("vscode", isDirectory: true)
    }

    /// Returns `~/.local/state/agent-panel/vscode/<projectId>.code-workspace`.
    /// - Parameter projectId: Project identifier used to name the workspace file.
    /// - Returns: URL for the generated VS Code workspace file.
    public func vscodeWorkspaceFile(projectId: String) -> URL {
        vscodeWorkspaceDirectory.appendingPathComponent("\(projectId).code-workspace", isDirectory: false)
    }

    /// Returns `~/.local/state/agent-panel/state.json`.
    public var stateFile: URL {
        stateDirectory.appendingPathComponent("state.json", isDirectory: false)
    }

    // MARK: - Log paths

    /// Returns `~/.local/state/agent-panel/logs`.
    public var logsDirectory: URL {
        stateDirectory.appendingPathComponent("logs", isDirectory: true)
    }

    /// Returns `~/.local/state/agent-panel/logs/agent-panel.log`.
    public var primaryLogFile: URL {
        logsDirectory.appendingPathComponent("agent-panel.log", isDirectory: false)
    }

    // MARK: - Private

    private var configDirectory: URL {
        homeDirectory
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("agent-panel", isDirectory: true)
    }

    private var stateDirectory: URL {
        homeDirectory
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("state", isDirectory: true)
            .appendingPathComponent("agent-panel", isDirectory: true)
    }
}
