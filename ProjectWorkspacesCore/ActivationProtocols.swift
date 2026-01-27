import Foundation

/// Abstraction for IDE launching during activation.
public protocol IdeLaunching {
    /// Launches the IDE for a project.
    /// - Parameters:
    ///   - project: Project configuration.
    ///   - ideConfig: Global IDE config values.
    /// - Returns: Launch success or failure.
    func launch(project: ProjectConfig, ideConfig: IdeConfig) -> Result<IdeLaunchSuccess, IdeLaunchError>
}

/// Abstraction for Chrome launch orchestration during activation.
public protocol ChromeLaunching {
    /// Ensures a Chrome window exists for the focused workspace.
    /// - Parameters:
    ///   - expectedWorkspaceName: Focused workspace name.
    ///   - globalChromeUrls: Global Chrome URL list.
    ///   - project: Project config.
    ///   - ideWindowIdToRefocus: IDE window id to refocus after creation.
    ///   - allowExistingWindows: Whether existing Chrome windows should satisfy the request.
    /// - Returns: Launch outcome or error.
    func ensureWindow(
        expectedWorkspaceName: String,
        globalChromeUrls: [String],
        project: ProjectConfig,
        ideWindowIdToRefocus: Int?,
        allowExistingWindows: Bool
    ) -> Result<ChromeLaunchOutcome, ChromeLaunchError>
}

extension IdeLauncher: IdeLaunching {}

extension ChromeLauncher: ChromeLaunching {}
