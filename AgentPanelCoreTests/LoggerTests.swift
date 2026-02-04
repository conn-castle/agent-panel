import XCTest
@testable import AgentPanelCore

final class LoggerTests: XCTestCase {

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
