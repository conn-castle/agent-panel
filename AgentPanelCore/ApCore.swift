import Foundation

/// AgentPanel version and identifiers.
public enum AgentPanel {
    /// Bundle identifier for the AgentPanel app.
    public static let appBundleIdentifier: String = "com.agentpanel.AgentPanel"

    /// A human-readable version identifier for diagnostic output.
    /// Reads from bundle when available, falls back to dev version for CLI.
    public static var version: String {
        if let bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           !bundleVersion.isEmpty {
            return bundleVersion
        }
        return "0.0.0-dev"
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
    /// Typed config for this ApCore instance.
    public let config: Config

    private let aerospace: ApAeroSpace
    private let ideLauncher: ApVSCodeLauncher
    private let chromeLauncher: ApChromeLauncher
    private let workspacePrefix = "ap-"

    /// Creates a new ApCore instance with default dependencies.
    /// - Parameter config: Typed config to associate with this instance.
    public init(config: Config) {
        self.config = config
        self.aerospace = ApAeroSpace()
        self.ideLauncher = ApVSCodeLauncher()
        self.chromeLauncher = ApChromeLauncher()
    }

    /// Creates an ApCore instance with full dependency injection (internal, for testing).
    /// - Parameters:
    ///   - config: Typed config to associate with this instance.
    ///   - aerospace: AeroSpace wrapper for workspace/window operations.
    ///   - ideLauncher: IDE launcher for opening new IDE windows.
    ///   - chromeLauncher: Chrome launcher for opening new browser windows.
    init(
        config: Config,
        aerospace: ApAeroSpace,
        ideLauncher: ApVSCodeLauncher,
        chromeLauncher: ApChromeLauncher
    ) {
        self.config = config
        self.aerospace = aerospace
        self.ideLauncher = ideLauncher
        self.chromeLauncher = chromeLauncher
    }

    /// Returns AeroSpace workspaces filtered by the `ap-` prefix.
    /// - Returns: Workspace names or an error.
    public func listWorkspaces() -> Result<[String], ApCoreError> {
        switch aerospace.getWorkspaces() {
        case .failure(let error):
            return .failure(error)
        case .success(let workspaces):
            let filtered = workspaces.filter { $0.hasPrefix(workspacePrefix) }
            return .success(filtered)
        }
    }

    /// Opens a new VS Code window tagged with the provided identifier.
    /// - Parameter identifier: Identifier embedded in the window title token.
    /// - Returns: Success or an error.
    public func newIde(identifier: String) -> Result<Void, ApCoreError> {
        ideLauncher.openNewWindow(identifier: identifier)
    }

    /// Opens a new Chrome window tagged with the provided identifier.
    /// - Parameter identifier: Identifier embedded in the window title token.
    /// - Returns: Success or an error.
    public func newChrome(identifier: String) -> Result<Void, ApCoreError> {
        chromeLauncher.openNewWindow(identifier: identifier)
    }

    /// Creates a new AeroSpace workspace with the ap- prefix.
    /// - Parameter name: Workspace name (without prefix). Normalized to lowercase with hyphens.
    /// - Returns: Success or an error.
    public func newWorkspace(name: String) -> Result<Void, ApCoreError> {
        // Normalize the name using the same rules as project IDs
        let normalized = IdNormalizer.normalize(name)
        guard !normalized.isEmpty else {
            return .failure(validationError("Workspace name cannot be empty after normalization."))
        }

        // Ensure prefix is applied (avoid double-prefix)
        let fullName: String
        if normalized.hasPrefix(workspacePrefix) {
            fullName = normalized
        } else {
            fullName = workspacePrefix + normalized
        }

        return aerospace.createWorkspace(fullName)
    }

    /// Lists all AP IDE windows.
    /// - Returns: Window data or an error.
    public func listIdeWindows() -> Result<[ApWindow], ApCoreError> {
        switch aerospace.listVSCodeWindowsOnFocusedMonitor() {
        case .failure(let error):
            return .failure(error)
        case .success(let windows):
            let filtered = windows.filter {
                $0.windowTitle.contains(ApIdeToken.prefix) &&
                    !$0.windowTitle.isEmpty
            }
            return .success(filtered)
        }
    }

    /// Lists all AP Chrome windows.
    /// - Returns: Window data or an error.
    public func listChromeWindows() -> Result<[ApWindow], ApCoreError> {
        switch aerospace.listChromeWindowsOnFocusedMonitor() {
        case .failure(let error):
            return .failure(error)
        case .success(let windows):
            let filtered = windows.filter {
                $0.windowTitle.contains(ApIdeToken.prefix) &&
                    !$0.windowTitle.isEmpty
            }
            return .success(filtered)
        }
    }

    /// Lists all windows in a workspace.
    /// - Parameter workspace: Workspace name to query.
    /// - Returns: Window data or an error.
    public func listWindowsWorkspace(_ workspace: String) -> Result<[ApWindow], ApCoreError> {
        aerospace.listWindowsWorkspace(workspace: workspace)
    }

    /// Returns the currently focused window.
    /// - Returns: Focused window data or an error.
    public func focusedWindow() -> Result<ApWindow, ApCoreError> {
        aerospace.focusedWindow()
    }

    /// Moves a window into the specified workspace.
    /// - Parameters:
    ///   - workspace: Destination workspace name.
    ///   - windowId: AeroSpace window id to move.
    /// - Returns: Success or an error.
    public func moveWindowToWorkspace(workspace: String, windowId: Int) -> Result<Void, ApCoreError> {
        aerospace.moveWindowToWorkspace(workspace: workspace, windowId: windowId)
    }

    /// Focuses a window by its AeroSpace window id.
    /// - Parameter windowId: AeroSpace window id to focus.
    /// - Returns: Success or an error.
    public func focusWindow(windowId: Int) -> Result<Void, ApCoreError> {
        aerospace.focusWindow(windowId: windowId)
    }

    /// Closes all windows in the specified workspace.
    /// - Parameter name: Workspace name to close windows in.
    /// - Returns: Success or an error.
    public func closeWorkspace(name: String) -> Result<Void, ApCoreError> {
        aerospace.closeWorkspace(name: name)
    }
}
