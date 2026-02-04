import XCTest
@testable import AgentPanelCore

final class DataPathsTests: XCTestCase {

    func testPathsAreDerivedFromHomeDirectory() {
        let home = URL(fileURLWithPath: "/Users/testuser", isDirectory: true)
        let store = DataPaths(homeDirectory: home)

        XCTAssertEqual(store.configFile.path, "/Users/testuser/.config/agent-panel/config.toml")

        XCTAssertEqual(store.logsDirectory.path, "/Users/testuser/.local/state/agent-panel/logs")
        XCTAssertEqual(store.primaryLogFile.path, "/Users/testuser/.local/state/agent-panel/logs/agent-panel.log")

        XCTAssertEqual(store.stateFile.path, "/Users/testuser/.local/state/agent-panel/state.json")

        XCTAssertEqual(store.vscodeWorkspaceDirectory.path, "/Users/testuser/.local/state/agent-panel/vscode")
        XCTAssertEqual(
            store.vscodeWorkspaceFile(projectId: "my-project").path,
            "/Users/testuser/.local/state/agent-panel/vscode/my-project.code-workspace"
        )
    }
}

