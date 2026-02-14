import XCTest
@testable import AgentPanelCore

final class WindowPositionStoreTests: XCTestCase {

    private var tempDir: URL!
    private var filePath: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ap-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        filePath = tempDir.appendingPathComponent("window-layouts.json", isDirectory: false)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeStore() -> WindowPositionStore {
        WindowPositionStore(filePath: filePath)
    }

    private let sampleFrames = SavedWindowFrames(
        ide: SavedFrame(x: 100, y: 200, width: 900, height: 800),
        chrome: SavedFrame(x: 1050, y: 200, width: 900, height: 800)
    )

    private let otherFrames = SavedWindowFrames(
        ide: SavedFrame(x: 0, y: 25, width: 1440, height: 875),
        chrome: SavedFrame(x: 0, y: 25, width: 1440, height: 875)
    )

    // MARK: - Load

    func testLoadMissingFileReturnsNil() {
        let store = makeStore()
        let result = store.load(projectId: "test", mode: .wide)

        if case .success(let frames) = result {
            XCTAssertNil(frames)
        } else {
            XCTFail("Expected .success(nil), got \(result)")
        }
    }

    func testLoadMissingProjectReturnsNil() {
        let store = makeStore()
        _ = store.save(projectId: "other", mode: .wide, frames: sampleFrames)

        let result = store.load(projectId: "nonexistent", mode: .wide)
        if case .success(let frames) = result {
            XCTAssertNil(frames)
        } else {
            XCTFail("Expected .success(nil), got \(result)")
        }
    }

    func testLoadWrongModeReturnsNil() {
        let store = makeStore()
        _ = store.save(projectId: "test", mode: .wide, frames: sampleFrames)

        let result = store.load(projectId: "test", mode: .small)
        if case .success(let frames) = result {
            XCTAssertNil(frames)
        } else {
            XCTFail("Expected .success(nil), got \(result)")
        }
    }

    func testLoadCorruptFileReturnsFailure() {
        try! "not valid json".data(using: .utf8)!.write(to: filePath)

        let store = makeStore()
        let result = store.load(projectId: "test", mode: .wide)

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("decode"), "Error: \(error.message)")
        } else {
            XCTFail("Expected .failure for corrupt file, got \(result)")
        }
    }

    // MARK: - Save and Load Round-Trip

    func testSaveAndLoadRoundTrip() {
        let store = makeStore()

        let saveResult = store.save(projectId: "test", mode: .wide, frames: sampleFrames)
        if case .failure(let error) = saveResult {
            XCTFail("Save failed: \(error)")
            return
        }

        let loadResult = store.load(projectId: "test", mode: .wide)
        if case .success(let frames) = loadResult {
            XCTAssertEqual(frames, sampleFrames)
        } else {
            XCTFail("Expected .success(frames), got \(loadResult)")
        }
    }

    func testSaveSmallAndWideModesIndependent() {
        let store = makeStore()

        _ = store.save(projectId: "test", mode: .wide, frames: sampleFrames)
        _ = store.save(projectId: "test", mode: .small, frames: otherFrames)

        if case .success(let wideFrames) = store.load(projectId: "test", mode: .wide) {
            XCTAssertEqual(wideFrames, sampleFrames)
        } else {
            XCTFail("Wide load failed")
        }

        if case .success(let smallFrames) = store.load(projectId: "test", mode: .small) {
            XCTAssertEqual(smallFrames, otherFrames)
        } else {
            XCTFail("Small load failed")
        }
    }

    func testSaveMultipleProjectsIndependent() {
        let store = makeStore()

        _ = store.save(projectId: "project-a", mode: .wide, frames: sampleFrames)
        _ = store.save(projectId: "project-b", mode: .wide, frames: otherFrames)

        if case .success(let aFrames) = store.load(projectId: "project-a", mode: .wide) {
            XCTAssertEqual(aFrames, sampleFrames)
        } else {
            XCTFail("Project A load failed")
        }

        if case .success(let bFrames) = store.load(projectId: "project-b", mode: .wide) {
            XCTAssertEqual(bFrames, otherFrames)
        } else {
            XCTFail("Project B load failed")
        }
    }

    func testSaveOverwritesPrevious() {
        let store = makeStore()

        _ = store.save(projectId: "test", mode: .wide, frames: sampleFrames)
        _ = store.save(projectId: "test", mode: .wide, frames: otherFrames)

        if case .success(let frames) = store.load(projectId: "test", mode: .wide) {
            XCTAssertEqual(frames, otherFrames)
        } else {
            XCTFail("Load after overwrite failed")
        }
    }

    // MARK: - Save Errors

    func testSaveToUnwritablePathFails() {
        let store = WindowPositionStore(
            filePath: URL(fileURLWithPath: "/nonexistent/dir/layouts.json"),
            fileSystem: StubUnwritableFileSystem()
        )

        let result = store.save(projectId: "test", mode: .wide, frames: sampleFrames)
        if case .failure = result {
            // Expected
        } else {
            XCTFail("Expected .failure for unwritable path")
        }
    }

    // MARK: - SavedFrame Conversion

    func testSavedFrameCGRectRoundTrip() {
        let rect = CGRect(x: 123.5, y: 456.7, width: 800.0, height: 600.0)
        let frame = SavedFrame(rect: rect)
        let converted = frame.cgRect

        XCTAssertEqual(converted.origin.x, rect.origin.x, accuracy: 0.001)
        XCTAssertEqual(converted.origin.y, rect.origin.y, accuracy: 0.001)
        XCTAssertEqual(converted.width, rect.width, accuracy: 0.001)
        XCTAssertEqual(converted.height, rect.height, accuracy: 0.001)
    }

    // MARK: - File Schema Version

    func testFileContainsVersionField() {
        let store = makeStore()
        _ = store.save(projectId: "test", mode: .wide, frames: sampleFrames)

        let data = try! Data(contentsOf: filePath)
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["version"] as? Int, 1)
    }
}

// MARK: - Test Stubs

private struct StubUnwritableFileSystem: FileSystem {
    func fileExists(at url: URL) -> Bool { false }
    func directoryExists(at url: URL) -> Bool { false }
    func isExecutableFile(at url: URL) -> Bool { false }
    func readFile(at url: URL) throws -> Data { throw NSError(domain: "Test", code: 1) }
    func createDirectory(at url: URL) throws { throw NSError(domain: "Test", code: 1) }
    func fileSize(at url: URL) throws -> UInt64 { throw NSError(domain: "Test", code: 1) }
    func removeItem(at url: URL) throws { throw NSError(domain: "Test", code: 1) }
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws { throw NSError(domain: "Test", code: 1) }
    func appendFile(at url: URL, data: Data) throws { throw NSError(domain: "Test", code: 1) }
    func writeFile(at url: URL, data: Data) throws { throw NSError(domain: "Test", code: 1) }
}
