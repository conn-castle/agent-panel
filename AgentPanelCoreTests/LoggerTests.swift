import XCTest
@testable import AgentPanelCore

final class LoggerTests: XCTestCase {

    func testLoggerInitWithCustomDataStoreWritesToDiskAtExpectedPath() throws {
        let tmpHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentpanel-logger-home-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmpHome) }
        try FileManager.default.createDirectory(at: tmpHome, withIntermediateDirectories: true)

        let dataStore = DataPaths(homeDirectory: tmpHome)
        let logger = AgentPanelLogger(dataStore: dataStore)

        switch logger.log(event: "disk.write.test") {
        case .failure(let error):
            XCTFail("Unexpected error: \(error)")
        case .success:
            break
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: dataStore.primaryLogFile.path))
    }

    func testLoggerLogWritesWithGeneratedTimestamp() throws {
        let fileSystem = InMemoryFileSystem()
        let dataStore = DataPaths(homeDirectory: URL(fileURLWithPath: "/Users/testuser", isDirectory: true))
        let logger = AgentPanelLogger(
            dataStore: dataStore,
            fileSystem: fileSystem,
            maxLogSizeBytes: 1024,
            maxArchives: 2
        )

        switch logger.log(event: "test.event", level: .warn, message: "hello", context: ["k": "v"]) {
        case .failure(let error):
            XCTFail("Unexpected error: \(error)")
        case .success:
            break
        }

        let logData = try fileSystem.readFile(at: dataStore.primaryLogFile)
        XCTAssertEqual(logData.last, 0x0A)

        let line = String(data: logData.dropLast(), encoding: .utf8)
        XCTAssertNotNil(line)

        let decoded = try JSONDecoder().decode(LogEntry.self, from: Data(line!.utf8))
        XCTAssertEqual(decoded.event, "test.event")
        XCTAssertEqual(decoded.level, .warn)
        XCTAssertEqual(decoded.message, "hello")
        XCTAssertEqual(decoded.context, ["k": "v"])
        XCTAssertTrue(decoded.timestamp.contains("T"), "Expected ISO-8601 timestamp")
        XCTAssertTrue(decoded.timestamp.hasSuffix("Z"), "Expected UTC timestamp ending in Z")
    }

    func testLogEntryRejectsEmptyEvent() {
        let fileSystem = InMemoryFileSystem()
        let dataStore = DataPaths(homeDirectory: URL(fileURLWithPath: "/Users/testuser", isDirectory: true))
        let logger = AgentPanelLogger(
            dataStore: dataStore,
            fileSystem: fileSystem,
            maxLogSizeBytes: 1024,
            maxArchives: 2
        )

        let entry = LogEntry(timestamp: "2024-01-01T00:00:00.000Z", level: .info, event: "  ")
        let result = logger.log(entry: entry)

        switch result {
        case .failure(.invalidEvent):
            break
        case .failure(let error):
            XCTFail("Expected invalidEvent, got \(error)")
        case .success:
            XCTFail("Expected failure for empty event")
        }
    }

    func testLogEntryAppendsJsonLine() throws {
        let fileSystem = InMemoryFileSystem()
        let dataStore = DataPaths(homeDirectory: URL(fileURLWithPath: "/Users/testuser", isDirectory: true))
        let logger = AgentPanelLogger(
            dataStore: dataStore,
            fileSystem: fileSystem,
            maxLogSizeBytes: 1024,
            maxArchives: 2
        )

        let entry = LogEntry(
            timestamp: "2024-01-01T00:00:00.000Z",
            level: .info,
            event: "test.event",
            message: "hello",
            context: ["k": "v"]
        )

        let result = logger.log(entry: entry)
        switch result {
        case .success:
            break
        case .failure(let error):
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(fileSystem.directories.contains(dataStore.logsDirectory.path))

        let logData = try fileSystem.readFile(at: dataStore.primaryLogFile)
        XCTAssertEqual(logData.last, 0x0A, "Expected newline-terminated JSON line.")

        let line = String(data: logData.dropLast(), encoding: .utf8)
        XCTAssertNotNil(line)

        let decoded = try JSONDecoder().decode(LogEntry.self, from: Data(line!.utf8))
        XCTAssertEqual(decoded, entry)
    }

    func testRotationShiftsArchivesAndMovesActiveLog() throws {
        let fileSystem = InMemoryFileSystem()
        let dataStore = DataPaths(homeDirectory: URL(fileURLWithPath: "/Users/testuser", isDirectory: true))

        // Small max size to force rotation deterministically.
        let logger = AgentPanelLogger(
            dataStore: dataStore,
            fileSystem: fileSystem,
            maxLogSizeBytes: 20,
            maxArchives: 2
        )

        let logURL = dataStore.primaryLogFile
        let archive1 = dataStore.logsDirectory.appendingPathComponent("agent-panel.log.1")
        let archive2 = dataStore.logsDirectory.appendingPathComponent("agent-panel.log.2")

        // Existing files before rotation.
        try fileSystem.writeFile(at: logURL, data: Data(repeating: 0x41, count: 15)) // "AAAA..."
        try fileSystem.writeFile(at: archive1, data: Data("old-1".utf8))
        try fileSystem.writeFile(at: archive2, data: Data("old-2".utf8))

        // This entry should trigger rotation.
        let entry = LogEntry(timestamp: "2024-01-01T00:00:00.000Z", level: .info, event: "rotate")
        switch logger.log(entry: entry) {
        case .success:
            break
        case .failure(let error):
            XCTFail("Unexpected error: \(error)")
        }

        // archive2 should now contain prior archive1 contents.
        let newArchive2 = try String(data: fileSystem.readFile(at: archive2), encoding: .utf8)
        XCTAssertEqual(newArchive2, "old-1")

        // archive1 should now contain prior active log contents (15 bytes of 'A').
        let newArchive1 = try fileSystem.readFile(at: archive1)
        XCTAssertEqual(newArchive1, Data(repeating: 0x41, count: 15))

        // active log should be recreated and contain the new entry.
        let newActive = try fileSystem.readFile(at: logURL)
        XCTAssertFalse(newActive.isEmpty)
        XCTAssertEqual(newActive.last, 0x0A)
    }

    func testCreateDirectoryFailureReturnsCreateDirectoryFailed() {
        let fileSystem = ConfigurableFileSystem()
        fileSystem.createDirectoryError = NSError(domain: "test", code: 1)

        let dataStore = DataPaths(homeDirectory: URL(fileURLWithPath: "/Users/testuser", isDirectory: true))
        let logger = AgentPanelLogger(
            dataStore: dataStore,
            fileSystem: fileSystem,
            maxLogSizeBytes: 1024,
            maxArchives: 2
        )

        let entry = LogEntry(timestamp: "2024-01-01T00:00:00.000Z", level: .info, event: "evt")
        switch logger.log(entry: entry) {
        case .success:
            XCTFail("Expected failure")
        case .failure(.createDirectoryFailed):
            break
        case .failure(let error):
            XCTFail("Expected createDirectoryFailed, got: \(error)")
        }
    }

    func testFileSizeFailureReturnsFileSizeFailed() throws {
        let fileSystem = ConfigurableFileSystem()
        let dataStore = DataPaths(homeDirectory: URL(fileURLWithPath: "/Users/testuser", isDirectory: true))

        // Ensure log file exists so rotateIfNeeded checks size.
        try fileSystem.writeFile(at: dataStore.primaryLogFile, data: Data(repeating: 0x41, count: 10))
        fileSystem.fileSizeError = NSError(domain: "test", code: 2)

        let logger = AgentPanelLogger(
            dataStore: dataStore,
            fileSystem: fileSystem,
            maxLogSizeBytes: 1,
            maxArchives: 2
        )

        let entry = LogEntry(timestamp: "2024-01-01T00:00:00.000Z", level: .info, event: "evt")
        switch logger.log(entry: entry) {
        case .success:
            XCTFail("Expected failure")
        case .failure(.fileSizeFailed):
            break
        case .failure(let error):
            XCTFail("Expected fileSizeFailed, got: \(error)")
        }
    }

    func testRotationFailureReturnsRotationFailed() throws {
        let fileSystem = ConfigurableFileSystem()
        let dataStore = DataPaths(homeDirectory: URL(fileURLWithPath: "/Users/testuser", isDirectory: true))

        // Ensure log file exists and size will exceed maxLogSizeBytes.
        try fileSystem.writeFile(at: dataStore.primaryLogFile, data: Data(repeating: 0x41, count: 10))
        fileSystem.moveItemError = NSError(domain: "test", code: 3)

        let logger = AgentPanelLogger(
            dataStore: dataStore,
            fileSystem: fileSystem,
            maxLogSizeBytes: 1,
            maxArchives: 2
        )

        let entry = LogEntry(timestamp: "2024-01-01T00:00:00.000Z", level: .info, event: "evt")
        switch logger.log(entry: entry) {
        case .success:
            XCTFail("Expected failure")
        case .failure(.rotationFailed):
            break
        case .failure(let error):
            XCTFail("Expected rotationFailed, got: \(error)")
        }
    }

    func testAppendFailureReturnsWriteFailed() {
        let fileSystem = ConfigurableFileSystem()
        fileSystem.appendFileError = NSError(domain: "test", code: 4)

        let dataStore = DataPaths(homeDirectory: URL(fileURLWithPath: "/Users/testuser", isDirectory: true))
        let logger = AgentPanelLogger(
            dataStore: dataStore,
            fileSystem: fileSystem,
            maxLogSizeBytes: 1024,
            maxArchives: 2
        )

        let entry = LogEntry(timestamp: "2024-01-01T00:00:00.000Z", level: .info, event: "evt")
        switch logger.log(entry: entry) {
        case .success:
            XCTFail("Expected failure")
        case .failure(.writeFailed):
            break
        case .failure(let error):
            XCTFail("Expected writeFailed, got: \(error)")
        }
    }

    func testLogWriteErrorMessageCoverage() {
        XCTAssertEqual(LogWriteError.invalidEvent.message, "Log event is empty.")
        XCTAssertTrue(LogWriteError.encodingFailed("x").message.contains("encode"))
        XCTAssertTrue(LogWriteError.createDirectoryFailed("x").message.contains("directory"))
        XCTAssertTrue(LogWriteError.fileSizeFailed("x").message.contains("size"))
        XCTAssertTrue(LogWriteError.rotationFailed("x").message.contains("rotate"))
        XCTAssertTrue(LogWriteError.writeFailed("x").message.contains("write"))
    }
}

// MARK: - Test Doubles

private final class InMemoryFileSystem: FileSystem {
    enum InMemoryError: Error {
        case missing(String)
    }

    private(set) var directories: Set<String> = []
    private var files: [String: Data] = [:]

    func fileExists(at url: URL) -> Bool {
        files[url.path] != nil
    }

    func directoryExists(at url: URL) -> Bool {
        directories.contains(url.path)
    }

    func isExecutableFile(at url: URL) -> Bool {
        false
    }

    func readFile(at url: URL) throws -> Data {
        guard let data = files[url.path] else {
            throw InMemoryError.missing(url.path)
        }
        return data
    }

    func createDirectory(at url: URL) throws {
        directories.insert(url.path)
    }

    func fileSize(at url: URL) throws -> UInt64 {
        guard let data = files[url.path] else {
            throw InMemoryError.missing(url.path)
        }
        return UInt64(data.count)
    }

    func removeItem(at url: URL) throws {
        files.removeValue(forKey: url.path)
        directories.remove(url.path)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        guard let data = files[sourceURL.path] else {
            throw InMemoryError.missing(sourceURL.path)
        }
        files[destinationURL.path] = data
        files.removeValue(forKey: sourceURL.path)
    }

    func appendFile(at url: URL, data: Data) throws {
        if let existing = files[url.path] {
            var merged = existing
            merged.append(data)
            files[url.path] = merged
        } else {
            files[url.path] = data
        }
    }

    func writeFile(at url: URL, data: Data) throws {
        files[url.path] = data
    }

    func syncFile(at url: URL) throws {}

    @discardableResult
    func replaceItemAt(_ originalURL: URL, withItemAt newItemURL: URL) throws -> URL? {
        files[originalURL.path] = files[newItemURL.path]
        files.removeValue(forKey: newItemURL.path)
        return originalURL
    }
}

private final class ConfigurableFileSystem: FileSystem {
    enum ConfigurableError: Error {
        case injected
    }

    private let base = InMemoryFileSystem()

    var createDirectoryError: Error?
    var fileSizeError: Error?
    var removeItemError: Error?
    var moveItemError: Error?
    var appendFileError: Error?

    func fileExists(at url: URL) -> Bool { base.fileExists(at: url) }
    func directoryExists(at url: URL) -> Bool { base.directoryExists(at: url) }
    func isExecutableFile(at url: URL) -> Bool { base.isExecutableFile(at: url) }
    func readFile(at url: URL) throws -> Data { try base.readFile(at: url) }

    func createDirectory(at url: URL) throws {
        if let createDirectoryError { throw createDirectoryError }
        try base.createDirectory(at: url)
    }

    func fileSize(at url: URL) throws -> UInt64 {
        if let fileSizeError { throw fileSizeError }
        return try base.fileSize(at: url)
    }

    func removeItem(at url: URL) throws {
        if let removeItemError { throw removeItemError }
        try base.removeItem(at: url)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        if let moveItemError { throw moveItemError }
        try base.moveItem(at: sourceURL, to: destinationURL)
    }

    func appendFile(at url: URL, data: Data) throws {
        if let appendFileError { throw appendFileError }
        try base.appendFile(at: url, data: data)
    }

    func writeFile(at url: URL, data: Data) throws { try base.writeFile(at: url, data: data) }
    func syncFile(at url: URL) throws { try base.syncFile(at: url) }

    @discardableResult
    func replaceItemAt(_ originalURL: URL, withItemAt newItemURL: URL) throws -> URL? {
        try base.replaceItemAt(originalURL, withItemAt: newItemURL)
    }
}
