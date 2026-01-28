import XCTest

@testable import ProjectWorkspacesCore

final class IdeLaunchEnvironmentTests: XCTestCase {
    func testBuildsRequiredEnvironmentAndPrependsPath() {
        let project = ProjectConfig(
            id: "codex",
            name: "Codex",
            path: "/Users/tester/src/codex",
            colorHex: "#7C3AED",
            repoUrl: "https://github.com/ORG/REPO",
            ide: .vscode,
            ideUseAgentLayerLauncher: true,
            ideCommand: "",
            chromeUrls: [],
            chromeProfileDirectory: nil
        )
        let paths = ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        let envBuilder = IdeLaunchEnvironment()
        let environment = envBuilder.build(
            baseEnvironment: ["PATH": "/usr/bin"],
            project: project,
            ide: .vscode,
            workspaceFile: paths.vscodeWorkspaceFile(projectId: "codex"),
            paths: paths,
            vscodeConfigAppPath: nil,
            vscodeConfigBundleId: nil
        )

        XCTAssertEqual(environment["PW_PROJECT_ID"], "codex")
        XCTAssertEqual(environment["PW_PROJECT_NAME"], "Codex")
        XCTAssertEqual(environment["PW_PROJECT_PATH"], "/Users/tester/src/codex")
        XCTAssertEqual(environment["PW_WORKSPACE_FILE"], "/Users/tester/.local/state/project-workspaces/vscode/codex.code-workspace")
        XCTAssertEqual(environment["PW_REPO_URL"], "https://github.com/ORG/REPO")
        XCTAssertEqual(environment["PW_COLOR_HEX"], "#7C3AED")
        XCTAssertEqual(environment["PW_IDE"], "vscode")
        XCTAssertEqual(environment["OPEN_VSCODE_NO_CLOSE"], "1")
        XCTAssertEqual(environment["PATH"], "/Users/tester/.local/share/project-workspaces/bin:/usr/bin")
    }

    func testRepoUrlDefaultsToEmptyString() {
        let project = ProjectConfig(
            id: "codex",
            name: "Codex",
            path: "/Users/tester/src/codex",
            colorHex: "#7C3AED",
            repoUrl: nil,
            ide: .vscode,
            ideUseAgentLayerLauncher: true,
            ideCommand: "",
            chromeUrls: [],
            chromeProfileDirectory: nil
        )
        let paths = ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        let envBuilder = IdeLaunchEnvironment()
        let environment = envBuilder.build(
            baseEnvironment: [:],
            project: project,
            ide: .vscode,
            workspaceFile: paths.vscodeWorkspaceFile(projectId: "codex"),
            paths: paths,
            vscodeConfigAppPath: nil,
            vscodeConfigBundleId: nil
        )

        XCTAssertEqual(environment["PW_REPO_URL"], "")
    }

    func testConfigValuesDoNotOverrideExplicitOverride() {
        let project = ProjectConfig(
            id: "codex",
            name: "Codex",
            path: "/Users/tester/src/codex",
            colorHex: "#7C3AED",
            repoUrl: nil,
            ide: .vscode,
            ideUseAgentLayerLauncher: true,
            ideCommand: "",
            chromeUrls: [],
            chromeProfileDirectory: nil
        )
        let paths = ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        let envBuilder = IdeLaunchEnvironment()
        let environment = envBuilder.build(
            baseEnvironment: ["PW_VSCODE_APP_PATH": "/Custom/VSCode.app"],
            project: project,
            ide: .vscode,
            workspaceFile: paths.vscodeWorkspaceFile(projectId: "codex"),
            paths: paths,
            vscodeConfigAppPath: "/Configured/VSCode.app",
            vscodeConfigBundleId: "com.microsoft.VSCode"
        )

        XCTAssertEqual(environment["PW_VSCODE_APP_PATH"], "/Custom/VSCode.app")
        XCTAssertEqual(environment["PW_VSCODE_CONFIG_APP_PATH"], "/Configured/VSCode.app")
        XCTAssertEqual(environment["PW_VSCODE_CONFIG_BUNDLE_ID"], "com.microsoft.VSCode")
    }
}
