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

// Uses TestFileSystem from TestSupport.swift
