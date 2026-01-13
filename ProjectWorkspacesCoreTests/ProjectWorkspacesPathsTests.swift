import XCTest

@testable import ProjectWorkspacesCore

final class ProjectWorkspacesPathsTests: XCTestCase {
    func testPathsUseCanonicalLocations() {
        let homeDirectory = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let paths = ProjectWorkspacesPaths(homeDirectory: homeDirectory)

        XCTAssertEqual(paths.configFile.path, "/Users/tester/.config/project-workspaces/config.toml")
        XCTAssertEqual(paths.vscodeWorkspaceDirectory.path, "/Users/tester/.config/project-workspaces/vscode")
        XCTAssertEqual(
            paths.vscodeWorkspaceFile(projectId: "codex").path,
            "/Users/tester/.config/project-workspaces/vscode/codex.code-workspace"
        )
        XCTAssertEqual(paths.stateFile.path, "/Users/tester/.local/state/project-workspaces/state.json")
        XCTAssertEqual(paths.logsDirectory.path, "/Users/tester/.local/state/project-workspaces/logs")
        XCTAssertEqual(paths.primaryLogFile.path, "/Users/tester/.local/state/project-workspaces/logs/workspaces.log")
        XCTAssertEqual(paths.codeShimPath.path, "/Users/tester/.local/share/project-workspaces/bin/code")
    }
}
