import Foundation

/// Launches IDE windows according to ProjectWorkspaces rules.
public protocol IdeLaunching {
    /// Launches the IDE for the provided project.
    /// - Parameters:
    ///   - project: Project configuration entry.
    ///   - ideConfig: Global IDE configuration.
    /// - Returns: Success with warnings or a failure error.
    func launch(project: ProjectConfig, ideConfig: IdeConfig) -> Result<IdeLaunchSuccess, IdeLaunchError>
}

/// Launches or detects Chrome windows for a workspace.
public protocol ChromeLaunching {
    /// Ensures a Chrome window exists for the expected workspace.
    /// - Parameters:
    ///   - expectedWorkspaceName: Workspace that must already be focused.
    ///   - globalChromeUrls: Global URLs to open when creating Chrome.
    ///   - project: Project configuration providing repo and project URLs.
    ///   - ideWindowIdToRefocus: IDE window id to refocus after Chrome creation.
    ///   - allowFallbackDetection: Whether cross-workspace detection is allowed.
    /// - Returns: Launch outcome or a structured error.
    func ensureWindow(
        expectedWorkspaceName: String,
        globalChromeUrls: [String],
        project: ProjectConfig,
        ideWindowIdToRefocus: Int?,
        allowFallbackDetection: Bool
    ) -> Result<ChromeLaunchOutcome, ChromeLaunchError>
}

extension IdeLauncher: IdeLaunching {}
extension ChromeLauncher: ChromeLaunching {}
