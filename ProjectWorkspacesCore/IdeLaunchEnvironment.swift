import Foundation

/// Builds the environment variables used for IDE launch commands.
public struct IdeLaunchEnvironment: Sendable {
    /// Creates an environment builder.
    public init() {}

    /// Builds environment variables for IDE launch commands.
    /// - Parameters:
    ///   - baseEnvironment: Base environment to extend.
    ///   - project: Project configuration entry.
    ///   - ide: Effective IDE for the project.
    ///   - workspaceFile: Workspace file URL.
    ///   - paths: ProjectWorkspaces filesystem paths.
    ///   - vscodeConfigAppPath: Optional configured VS Code app path.
    ///   - vscodeConfigBundleId: Optional configured VS Code bundle identifier.
    /// - Returns: Environment variables for the launch command.
    public func build(
        baseEnvironment: [String: String],
        project: ProjectConfig,
        ide: IdeKind,
        workspaceFile: URL,
        paths: ProjectWorkspacesPaths,
        vscodeConfigAppPath: String?,
        vscodeConfigBundleId: String?
    ) -> [String: String] {
        var environment = baseEnvironment
        environment["PW_PROJECT_ID"] = project.id
        environment["PW_PROJECT_NAME"] = project.name
        environment["PW_PROJECT_PATH"] = project.path
        environment["PW_WORKSPACE_FILE"] = workspaceFile.path
        environment["PW_REPO_URL"] = project.repoUrl ?? ""
        environment["PW_COLOR_HEX"] = project.colorHex
        environment["PW_IDE"] = ide.rawValue
        environment["OPEN_VSCODE_NO_CLOSE"] = "1"

        if let vscodeConfigAppPath, !vscodeConfigAppPath.isEmpty {
            environment["PW_VSCODE_CONFIG_APP_PATH"] = vscodeConfigAppPath
        }
        if let vscodeConfigBundleId, !vscodeConfigBundleId.isEmpty {
            environment["PW_VSCODE_CONFIG_BUNDLE_ID"] = vscodeConfigBundleId
        }

        let shimDirectory = paths.codeShimPath.deletingLastPathComponent().path
        let existingPath = environment["PATH"] ?? ""
        if existingPath.isEmpty {
            environment["PATH"] = shimDirectory
        } else if !existingPath.hasPrefix("\(shimDirectory):") {
            environment["PATH"] = "\(shimDirectory):\(existingPath)"
        }

        return environment
    }
}
