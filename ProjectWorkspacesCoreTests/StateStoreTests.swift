import Foundation
import XCTest

@testable import ProjectWorkspacesCore

final class StateStoreTests: XCTestCase {
    func testLoadReturnsMissingWhenFileAbsent() {
        let paths = ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        let fileSystem = TestFileSystem()
        let store = StateStore(paths: paths, fileSystem: fileSystem, dateProvider: FixedDateProvider())

        let result = store.load()

        XCTAssertEqual(result, .success(.missing))
    }

    func testLoadReturnsDecodedState() throws {
        let paths = ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        let fileSystem = TestFileSystem()
        let state = try makeState(projectId: "hydroponics")
        let data = try JSONEncoder().encode(state)
        fileSystem.addFile(at: paths.stateFile.path, data: data)

        let store = StateStore(paths: paths, fileSystem: fileSystem, dateProvider: FixedDateProvider())
        let result = store.load()

        XCTAssertEqual(result, .success(.loaded(state)))
    }

    func testLoadRecoversCorruptStateAndBacksUp() {
        let paths = ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        let fileSystem = TestFileSystem()
        fileSystem.addFile(at: paths.stateFile.path, content: "not-json")

        let store = StateStore(
            paths: paths,
            fileSystem: fileSystem,
            dateProvider: FixedDateProvider(date: Date(timeIntervalSince1970: 1234))
        )
        let result = store.load()

        let backupPath = paths.stateFile
            .deletingLastPathComponent()
            .appendingPathComponent("state.json.bak.1234", isDirectory: false)
            .path

        XCTAssertEqual(result, .success(.recovered(.empty(), backupPath: backupPath)))
        XCTAssertNil(fileSystem.fileData(atPath: paths.stateFile.path))
        XCTAssertNotNil(fileSystem.fileData(atPath: backupPath))
    }

    func testSaveWritesStateFile() throws {
        let paths = ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        let fileSystem = TestFileSystem()
        let store = StateStore(paths: paths, fileSystem: fileSystem, dateProvider: FixedDateProvider())
        let state = try makeState(projectId: "hydroponics")

        let result = store.save(state)
        switch result {
        case .success:
            break
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        }
        let data = try XCTUnwrap(fileSystem.fileData(atPath: paths.stateFile.path))
        let decoded = try JSONDecoder().decode(LayoutState.self, from: data)
        XCTAssertEqual(decoded, state)
    }

    func testConsecutiveSavesSucceed() throws {
        let paths = ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        let fileSystem = TestFileSystem()
        let store = StateStore(paths: paths, fileSystem: fileSystem, dateProvider: FixedDateProvider())

        // First save
        let state1 = try makeState(projectId: "first-project")
        let result1 = store.save(state1)
        switch result1 {
        case .success:
            break
        case .failure(let error):
            XCTFail("First save failed: \(error)")
        }

        // Second save (should succeed with replaceItemAt)
        let state2 = try makeState(projectId: "second-project")
        let result2 = store.save(state2)
        switch result2 {
        case .success:
            break
        case .failure(let error):
            XCTFail("Second save failed: \(error)")
        }

        // Verify the file contains the second state
        let data = try XCTUnwrap(fileSystem.fileData(atPath: paths.stateFile.path))
        let decoded = try JSONDecoder().decode(LayoutState.self, from: data)
        XCTAssertEqual(decoded, state2)
        XCTAssertNotNil(decoded.projects["second-project"])
        XCTAssertNil(decoded.projects["first-project"])
    }

    func testProjectLayoutUsesIdeAndChromeKeys() throws {
        let layout = ProjectLayout(
            ideRect: try NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            chromeRect: try NormalizedRect(x: 0, y: 0, width: 1, height: 1)
        )

        let data = try JSONEncoder().encode(layout)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNotNil(json["ide"])
        XCTAssertNotNil(json["chrome"])
        XCTAssertNil(json["ideRect"])
        XCTAssertNil(json["chromeRect"])
    }

    private func makeState(projectId: String) throws -> LayoutState {
        let ideRect = try NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)
        let chromeRect = try NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1)
        let layout = ProjectLayout(ideRect: ideRect, chromeRect: chromeRect)
        let projectState = ProjectState(
            managed: ManagedWindowState(ideWindowId: 101, chromeWindowId: 202),
            layouts: LayoutsByDisplayMode(laptop: layout, ultrawide: nil)
        )
        return LayoutState(projects: [projectId: projectState])
    }
}

private struct FixedDateProvider: DateProviding {
    let date: Date

    init(date: Date = Date(timeIntervalSince1970: 0)) {
        self.date = date
    }

    func now() -> Date {
        date
    }
}
