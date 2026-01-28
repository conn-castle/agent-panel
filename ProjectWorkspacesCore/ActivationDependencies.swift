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
    ///   - expectedWorkspaceName: Target workspace name.
    ///   - windowToken: Deterministic token used to identify the Chrome window.
    ///   - globalChromeUrls: Global URLs to open when creating Chrome.
    ///   - project: Project configuration providing repo and project URLs.
    ///   - ideWindowIdToRefocus: IDE window id to refocus after Chrome creation.
    ///   - allowExistingWindows: Whether existing Chrome windows should satisfy the request.
    /// - Returns: Launch outcome or a structured error.
    func ensureWindow(
        expectedWorkspaceName: String,
        windowToken: ProjectWindowToken,
        globalChromeUrls: [String],
        project: ProjectConfig,
        ideWindowIdToRefocus: Int?,
        allowExistingWindows: Bool
    ) -> Result<ChromeLaunchOutcome, ChromeLaunchError>
}

extension IdeLauncher: IdeLaunching {}

extension ChromeLauncher: ChromeLaunching {}
