import Foundation
import XCTest

@testable import ProjectWorkspacesCore

final class ProjectWorkspacesStateStoreTests: XCTestCase {
    func testLoadMissingStateReturnsDefault() {
        let paths = ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        let fileSystem = InMemoryFileSystem(files: [:])
        let store = ProjectWorkspacesStateStore(
            paths: paths,
            fileSystem: fileSystem,
            logger: NoopLogger(),
            dateProvider: FixedDateProvider()
        )

        switch store.load() {
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        case .success(let result):
            XCTAssertEqual(result.state, ProjectWorkspacesState())
            XCTAssertTrue(result.warnings.isEmpty)
        }
    }

    func testLoadCorruptedStateBacksUpAndWarns() {
        let paths = ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        let statePath = paths.stateFile.path
        let fileSystem = InMemoryFileSystem(files: [statePath: Data("not-json".utf8)])
        let store = ProjectWorkspacesStateStore(
            paths: paths,
            fileSystem: fileSystem,
            logger: NoopLogger(),
            dateProvider: FixedDateProvider()
        )

        let result = store.load()
        switch result {
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        case .success(let loadResult):
            let backupPath = paths.stateFile
                .deletingLastPathComponent()
                .appendingPathComponent("state.json.bak.19700101-000000", isDirectory: false)
                .path
            XCTAssertEqual(loadResult.state, ProjectWorkspacesState())
            XCTAssertEqual(loadResult.warnings, [.stateRecovered(backupPath: backupPath)])
            XCTAssertFalse(fileSystem.fileExists(at: URL(fileURLWithPath: statePath)))
            XCTAssertTrue(fileSystem.fileExists(at: URL(fileURLWithPath: backupPath)))
        }
    }
}
