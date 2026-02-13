import Foundation

/// Canonical filesystem paths for AgentPanel.
///
/// Provides path resolution for config, state, and logs. Does not perform I/O.
public struct DataPaths: Sendable {
    /// User home directory used as the root for derived paths.
    let homeDirectory: URL

    /// Creates a DataPaths rooted at the provided home directory.
    /// - Parameter homeDirectory: Home directory as a file URL.
    init(homeDirectory: URL) {
        precondition(homeDirectory.isFileURL, "homeDirectory must be a file URL")
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    /// Creates a DataPaths rooted at the current user's home directory.
    /// - Parameter fileManager: File manager used to resolve the home directory.
    /// - Returns: A `DataPaths` instance rooted at the user's home directory.
    public static func `default`(fileManager: FileManager = .default) -> DataPaths {
        DataPaths(homeDirectory: fileManager.homeDirectoryForCurrentUser)
    }

    // MARK: - Config paths

    /// Returns `~/.config/agent-panel/config.toml`.
    public var configFile: URL {
        configDirectory.appendingPathComponent("config.toml", isDirectory: false)
    }

    // MARK: - State paths

    /// Returns `~/.local/state/agent-panel/state.json`.
    var stateFile: URL {
        stateDirectory.appendingPathComponent("state.json", isDirectory: false)
    }

    /// Returns `~/.local/state/agent-panel/recent-projects.json`.
    var recentProjectsFile: URL {
        stateDirectory.appendingPathComponent("recent-projects.json", isDirectory: false)
    }

    /// Returns `~/.local/state/agent-panel/window-layouts.json`.
    var windowLayoutsFile: URL {
        stateDirectory.appendingPathComponent("window-layouts.json", isDirectory: false)
    }

    /// Returns `~/.local/state/agent-panel/chrome-tabs/`.
    var chromeTabsDirectory: URL {
        stateDirectory.appendingPathComponent("chrome-tabs", isDirectory: true)
    }

    /// Returns `~/.local/state/agent-panel/chrome-tabs/<projectId>.json`.
    /// - Parameter projectId: Project identifier used to name the snapshot file.
    /// - Returns: URL for the project's Chrome tab snapshot file.
    func chromeTabsFile(projectId: String) -> URL {
        chromeTabsDirectory.appendingPathComponent("\(projectId).json", isDirectory: false)
    }

    // MARK: - Log paths

    /// Returns `~/.local/state/agent-panel/logs`.
    var logsDirectory: URL {
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
