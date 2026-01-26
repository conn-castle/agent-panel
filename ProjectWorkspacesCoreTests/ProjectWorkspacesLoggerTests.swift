import XCTest

@testable import ProjectWorkspacesCore

final class ProjectWorkspacesLoggerTests: XCTestCase {
    func testLogWritesJsonLine() throws {
        let paths = ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        let fileSystem = TestFileSystem()
        let logger = ProjectWorkspacesLogger(
            paths: paths,
            fileSystem: fileSystem,
            maxLogSizeBytes: 1024,
            maxArchives: 2
        )

        let result = logger.log(
            event: "pwctl.command",
            level: .info,
            message: "ok",
            context: ["command": "list"]
        )

        switch result {
        case .success:
            break
        case .failure(let error):
            XCTFail("Expected log write success, got error: \(error.message)")
        }

        let data = try fileSystem.readFile(at: paths.primaryLogFile)
        guard let content = String(data: data, encoding: .utf8) else {
            XCTFail("Expected UTF-8 log output")
            return
        }

        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 1)

        let decoded = try JSONDecoder().decode(LogEntry.self, from: Data(lines[0].utf8))
        XCTAssertEqual(decoded.event, "pwctl.command")
        XCTAssertEqual(decoded.level, .info)
        XCTAssertEqual(decoded.message, "ok")
        XCTAssertEqual(decoded.context?["command"], "list")
        XCTAssertNotNil(parseTimestamp(decoded.timestamp))
    }

    func testLogRotatesArchives() throws {
        let paths = ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        let logURL = paths.primaryLogFile
        let archive1 = paths.logsDirectory.appendingPathComponent("workspaces.log.1", isDirectory: false)
        let archive2 = paths.logsDirectory.appendingPathComponent("workspaces.log.2", isDirectory: false)

        let originalLog = Data(repeating: 0x61, count: 50)
        let originalArchive1 = Data("first".utf8)
        let originalArchive2 = Data("second".utf8)

        let fileSystem = TestFileSystem(
            files: [
                logURL.path: originalLog,
                archive1.path: originalArchive1,
                archive2.path: originalArchive2
            ],
            directories: [paths.logsDirectory.path]
        )

        let logger = ProjectWorkspacesLogger(
            paths: paths,
            fileSystem: fileSystem,
            maxLogSizeBytes: 50,
            maxArchives: 2
        )

        let result = logger.log(event: "pwctl.command", context: ["command": "list"])
        switch result {
        case .success:
            break
        case .failure(let error):
            XCTFail("Expected log rotation success, got error: \(error.message)")
        }

        let rotatedArchive2 = try fileSystem.readFile(at: archive2)
        XCTAssertEqual(rotatedArchive2, originalArchive1)

        let rotatedArchive1 = try fileSystem.readFile(at: archive1)
        XCTAssertEqual(rotatedArchive1, originalLog)

        let newLogData = try fileSystem.readFile(at: logURL)
        XCTAssertNotEqual(newLogData, originalLog)
        XCTAssertFalse(newLogData.isEmpty)
    }

    /// Parses an ISO-8601 timestamp string.
    /// - Parameter value: Timestamp string to parse.
    /// - Returns: Parsed date or nil if invalid.
    private func parseTimestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}

/// File system stub for logger tests.
private final class TestFileSystem: FileSystem {
    private var files: [String: Data]
    private var directories: Set<String>
    private var executableFiles: Set<String>

    /// Creates a file system stub.
    /// - Parameters:
    ///   - files: Initial file contents keyed by path.
    ///   - directories: Initial directory paths.
    ///   - executableFiles: Initial executable file paths.
    init(
        files: [String: Data] = [:],
        directories: Set<String> = [],
        executableFiles: Set<String> = []
    ) {
        self.files = files
        self.directories = directories
        self.executableFiles = executableFiles
    }

    /// Returns true when a file exists at the given URL.
    /// - Parameter url: File URL to check.
    /// - Returns: True when the file exists in the stub.
    func fileExists(at url: URL) -> Bool {
        files[url.path] != nil
    }

    /// Returns true when a directory exists at the given URL.
    /// - Parameter url: Directory URL to check.
    /// - Returns: True when the directory exists in the stub.
    func directoryExists(at url: URL) -> Bool {
        directories.contains(url.path)
    }

    /// Returns true when an executable file exists at the given URL.
    /// - Parameter url: File URL to check.
    /// - Returns: True when the file is marked executable in the stub.
    func isExecutableFile(at url: URL) -> Bool {
        executableFiles.contains(url.path)
    }

    /// Reads file contents at the given URL.
    /// - Parameter url: File URL to read.
    /// - Returns: File contents as Data.
    /// - Throws: Error when the file is missing in the stub.
    func readFile(at url: URL) throws -> Data {
        if let data = files[url.path] {
            return data
        }
        throw NSError(domain: "TestFileSystem", code: 1)
    }

    /// Creates a directory at the given URL.
    /// - Parameter url: Directory URL to create.
    func createDirectory(at url: URL) throws {
        directories.insert(url.path)
    }

    /// Returns the file size in bytes at the given URL.
    /// - Parameter url: File URL to inspect.
    /// - Returns: File size in bytes.
    func fileSize(at url: URL) throws -> UInt64 {
        guard let data = files[url.path] else {
            throw NSError(domain: "TestFileSystem", code: 2)
        }
        return UInt64(data.count)
    }

    /// Removes the file or directory at the given URL.
    /// - Parameter url: File or directory URL to remove.
    func removeItem(at url: URL) throws {
        if files.removeValue(forKey: url.path) != nil {
            return
        }
        if directories.remove(url.path) != nil {
            return
        }
        throw NSError(domain: "TestFileSystem", code: 3)
    }

    /// Moves a file from source to destination.
    /// - Parameters:
    ///   - sourceURL: Existing file URL.
    ///   - destinationURL: Destination URL.
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        guard let data = files.removeValue(forKey: sourceURL.path) else {
            throw NSError(domain: "TestFileSystem", code: 4)
        }
        if files[destinationURL.path] != nil {
            throw NSError(domain: "TestFileSystem", code: 5)
        }
        files[destinationURL.path] = data
    }

    /// Appends data to a file at the given URL, creating it if needed.
    /// - Parameters:
    ///   - url: File URL to append to.
    ///   - data: Data to append.
    func appendFile(at url: URL, data: Data) throws {
        if var existing = files[url.path] {
            existing.append(data)
            files[url.path] = existing
        } else {
            files[url.path] = data
        }
    }

    func writeFile(at url: URL, data: Data) throws {
        files[url.path] = data
    }

    func syncFile(at url: URL) throws {
        if files[url.path] == nil {
            throw NSError(domain: "TestFileSystem", code: 6)
        }
    }
}
