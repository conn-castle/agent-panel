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
        XCTAssertEqual(store.recentProjectsFile.path, "/Users/testuser/.local/state/agent-panel/recent-projects.json")

        XCTAssertEqual(store.chromeTabsDirectory.path, "/Users/testuser/.local/state/agent-panel/chrome-tabs")
        XCTAssertEqual(
            store.chromeTabsFile(projectId: "my-project").path,
            "/Users/testuser/.local/state/agent-panel/chrome-tabs/my-project.json"
        )
    }

    func testHomeDirectoryIsStandardized() {
        let home = URL(fileURLWithPath: "/Users/testuser/../testuser", isDirectory: true)
        let store = DataPaths(homeDirectory: home)

        XCTAssertEqual(store.configFile.path, "/Users/testuser/.config/agent-panel/config.toml")
    }
}
