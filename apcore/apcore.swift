import Foundation

/// Errors emitted by ApCore operations.
public struct ApCoreError: Error, Equatable {
    /// Human-readable error message.
    public let message: String

    /// Creates a new ApCoreError with the provided message.
    /// - Parameter message: Error message.
    public init(message: String) {
        self.message = message
    }
}

/// Shared IDE token prefix used to tag new IDE windows.
enum ApIdeToken {
    static let prefix = "AP:"
}

/// Minimal window data used by ap.
public struct ApWindow: Equatable {
    /// AeroSpace window id.
    public let windowId: Int
    /// App bundle identifier for the window.
    public let appBundleId: String
    /// Workspace name for the window.
    public let workspace: String
    /// Window title as reported by AeroSpace.
    public let windowTitle: String

    /// Creates a new window summary.
    /// - Parameters:
    ///   - windowId: AeroSpace window id.
    ///   - appBundleId: App bundle identifier for the window.
    ///   - workspace: Workspace name for the window.
    ///   - windowTitle: Window title as reported by AeroSpace.
    public init(windowId: Int, appBundleId: String, workspace: String, windowTitle: String) {
        self.windowId = windowId
        self.appBundleId = appBundleId
        self.workspace = workspace
        self.windowTitle = windowTitle
    }
}

/// Core library for the ap CLI.
public final class ApCore {
    /// Parsed config for this ApCore instance.
    public let config: ApConfig

    private let aerospace: ApAeroSpace
    private let ideLauncher: ApVSCodeLauncher
    private let chromeLauncher: ApChromeLauncher
    private let workspacePrefix = "ap-"

    /// Creates a new ApCore instance.
    /// - Parameter config: Parsed config to associate with this instance.
    public init(config: ApConfig) {
        self.config = config
        self.aerospace = ApAeroSpace()
        self.ideLauncher = ApVSCodeLauncher()
        self.chromeLauncher = ApChromeLauncher()
    }

    /// Prints AeroSpace workspaces filtered by the `ap-` prefix.
    /// - Returns: Success or an error.
    public func listWorkspaces() -> Result<Void, ApCoreError> {
        switch aerospace.get_workspaces() {
        case .failure(let error):
            return .failure(error)
        case .success(let workspaces):
            let filtered = workspaces.filter { $0.hasPrefix(workspacePrefix) }
            for workspace in filtered {
                print(workspace)
            }
            return .success(())
        }
    }

    /// Prints the raw config contents to stdout.
    /// - Returns: Success or an error.
    public func showConfig() -> Result<Void, ApCoreError> {
        if !config.raw.isEmpty {
            FileHandle.standardOutput.write(Data(config.raw.utf8))
        }
        return .success(())
    }

    /// Opens a new VS Code window tagged with the provided identifier.
    /// - Parameter identifier: Identifier embedded in the window title token.
    /// - Returns: Success or an error.
    public func newIde(identifier: String) -> Result<Void, ApCoreError> {
        ideLauncher.open_new_window(identifier: identifier)
    }

    /// Opens a new Chrome window tagged with the provided identifier.
    /// - Parameter identifier: Identifier embedded in the window title token.
    /// - Returns: Success or an error.
    public func newChrome(identifier: String) -> Result<Void, ApCoreError> {
        chromeLauncher.open_new_window(identifier: identifier)
    }

    /// Creates a new AeroSpace workspace.
    /// - Parameter name: Workspace name to create.
    /// - Returns: Success or an error.
    public func newWorkspace(name: String) -> Result<Void, ApCoreError> {
        aerospace.create_workspace(name)
    }

    /// Lists all AP IDE window titles.
    /// - Returns: Titles or an error.
    public func listIdeTitles() -> Result<[String], ApCoreError> {
        switch listIdeWindows() {
        case .failure(let error):
            return .failure(error)
        case .success(let windows):
            return .success(windows.map { $0.windowTitle })
        }
    }

    /// Lists all AP IDE windows.
    /// - Returns: Window data or an error.
    public func listIdeWindows() -> Result<[ApWindow], ApCoreError> {
        aerospace.list_ap_ide_windows()
    }

    /// Lists all AP Chrome windows.
    /// - Returns: Window data or an error.
    public func listChromeWindows() -> Result<[ApWindow], ApCoreError> {
        aerospace.list_ap_chrome_windows()
    }

    /// Moves a window into the specified workspace.
    /// - Parameters:
    ///   - workspace: Destination workspace name.
    ///   - windowId: AeroSpace window id to move.
    /// - Returns: Success or an error.
    public func moveWindowToWorkspace(workspace: String, windowId: Int) -> Result<Void, ApCoreError> {
        aerospace.move_window_to_workspace(workspace: workspace, windowId: windowId)
    }
}
