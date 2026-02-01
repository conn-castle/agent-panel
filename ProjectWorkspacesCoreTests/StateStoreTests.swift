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
        let state = makeState(projectId: "hydroponics")
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
        let state = makeState(projectId: "hydroponics")

        let result = store.save(state)
        switch result {
        case .success:
            break
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        }
        let data = try XCTUnwrap(fileSystem.fileData(atPath: paths.stateFile.path))
        let decoded = try JSONDecoder().decode(BindingState.self, from: data)
        XCTAssertEqual(decoded, state)
    }

    func testConsecutiveSavesSucceed() throws {
        let paths = ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        let fileSystem = TestFileSystem()
        let store = StateStore(paths: paths, fileSystem: fileSystem, dateProvider: FixedDateProvider())

        let state1 = makeState(projectId: "first-project")
        let result1 = store.save(state1)
        switch result1 {
        case .success:
            break
        case .failure(let error):
            XCTFail("First save failed: \(error)")
        }

        let state2 = makeState(projectId: "second-project")
        let result2 = store.save(state2)
        switch result2 {
        case .success:
            break
        case .failure(let error):
            XCTFail("Second save failed: \(error)")
        }

        let data = try XCTUnwrap(fileSystem.fileData(atPath: paths.stateFile.path))
        let decoded = try JSONDecoder().decode(BindingState.self, from: data)
        XCTAssertEqual(decoded, state2)
        XCTAssertNotNil(decoded.projects["second-project"])
        XCTAssertNil(decoded.projects["first-project"])
    }

    private func makeState(projectId: String) -> BindingState {
        let ideBinding = WindowBinding(
            windowId: 101,
            appBundleId: TestConstants.vscodeBundleId,
            role: .ide,
            titleAtBindTime: "PW:\(projectId)"
        )
        let chromeBinding = WindowBinding(
            windowId: 202,
            appBundleId: ChromeApp.bundleId,
            role: .chrome,
            titleAtBindTime: "PW:\(projectId)"
        )
        let projectState = ProjectBindings(
            ideBindings: [ideBinding],
            chromeBindings: [chromeBinding]
        )
        return BindingState(projects: [projectId: projectState])
    }
}
