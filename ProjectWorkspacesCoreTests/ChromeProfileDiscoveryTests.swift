import XCTest

@testable import ProjectWorkspacesCore

final class ChromeProfileDiscoveryTests: XCTestCase {
    func testDiscoverProfilesReadsLocalState() {
        let homeDirectory = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let paths = ProjectWorkspacesPaths(homeDirectory: homeDirectory)
        let localState = """
        {
          "profile": {
            "info_cache": {
              "Default": {
                "name": "Personal",
                "user_name": "nick@example.com"
              },
              "Profile 2": {
                "name": "Work"
              }
            }
          }
        }
        """
        let fileSystem = TestFileSystem(files: [
            paths.chromeLocalStateFile.path: Data(localState.utf8)
        ])

        let discovery = ChromeProfileDiscovery(paths: paths, fileSystem: fileSystem)
        let result = discovery.discoverProfiles()

        switch result {
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        case .success(let profiles):
            XCTAssertEqual(profiles.count, 2)
            XCTAssertEqual(profiles[0].directory, "Default")
            XCTAssertEqual(profiles[0].displayName, "Personal")
            XCTAssertEqual(profiles[0].userName, "nick@example.com")
            XCTAssertEqual(profiles[1].directory, "Profile 2")
            XCTAssertEqual(profiles[1].displayName, "Work")
            XCTAssertNil(profiles[1].userName)
        }
    }

    func testDiscoverProfilesFailsWhenLocalStateMissing() {
        let homeDirectory = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let paths = ProjectWorkspacesPaths(homeDirectory: homeDirectory)
        let fileSystem = TestFileSystem()
        let discovery = ChromeProfileDiscovery(paths: paths, fileSystem: fileSystem)

        let result = discovery.discoverProfiles()

        switch result {
        case .success:
            XCTFail("Expected failure when Local State is missing.")
        case .failure(let error):
            XCTAssertEqual(
                error,
                .localStateMissing(path: "/Users/tester/Library/Application Support/Google/Chrome/Local State")
            )
        }
    }
}
