import XCTest

@testable import ProjectWorkspacesCore

final class PwctlServiceTests: XCTestCase {
    func testListProjectsReturnsEntriesAndWarnings() {
        let config = """
        [[project]]
        id = "codex"
        name = "Codex"
        path = "/Users/tester/src/codex"
        colorHex = "#7C3AED"
        """

        let fileSystem = TestFileSystem(files: [
            "/Users/tester/.config/project-workspaces/config.toml": Data(config.utf8)
        ])

        let service = PwctlService(
            paths: ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true)),
            fileSystem: fileSystem
        )

        switch service.listProjects() {
        case .failure(let findings):
            XCTFail("Expected success, got failure: \(findings)")
        case .success(let entries, let warnings):
            XCTAssertEqual(entries, [
                PwctlListEntry(id: "codex", name: "Codex", path: "/Users/tester/src/codex")
            ])
            XCTAssertTrue(warnings.contains { $0.title.contains("Default applied") })
        }
    }

    func testListProjectsFailsWhenConfigMissing() {
        let fileSystem = TestFileSystem(files: [:])
        let service = PwctlService(
            paths: ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true)),
            fileSystem: fileSystem
        )

        switch service.listProjects() {
        case .failure(let findings):
            XCTAssertTrue(findings.contains { $0.title == "Config file missing" })
        case .success:
            XCTFail("Expected failure when config is missing.")
        }
    }

    func testListProjectsFailsWhenConfigInvalid() {
        let config = """
        [[project]]
        id = "Bad Id"
        name = "Codex"
        path = "/Users/tester/src/codex"
        colorHex = "#7C3AED"
        """

        let fileSystem = TestFileSystem(files: [
            "/Users/tester/.config/project-workspaces/config.toml": Data(config.utf8)
        ])

        let service = PwctlService(
            paths: ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true)),
            fileSystem: fileSystem
        )

        switch service.listProjects() {
        case .failure(let findings):
            XCTAssertTrue(findings.contains { $0.title == "project[0].id is invalid" })
        case .success:
            XCTFail("Expected failure when config is invalid.")
        }
    }

    func testTailLogsReturnsLastLines() {
        let logContents = """
        line-one
        line-two
        line-three
        """

        let fileSystem = TestFileSystem(files: [
            "/Users/tester/.local/state/project-workspaces/logs/workspaces.log": Data(logContents.utf8)
        ])

        let service = PwctlService(
            paths: ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true)),
            fileSystem: fileSystem
        )

        switch service.tailLogs(lines: 2) {
        case .failure(let findings):
            XCTFail("Expected success, got failure: \(findings)")
        case .success(let output, let warnings):
            XCTAssertTrue(warnings.isEmpty)
            XCTAssertEqual(output, "line-two\nline-three")
        }
    }

    func testTailLogsFailsWhenMissing() {
        let fileSystem = TestFileSystem(files: [:])
        let service = PwctlService(
            paths: ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true)),
            fileSystem: fileSystem
        )

        switch service.tailLogs(lines: 5) {
        case .failure(let findings):
            XCTAssertTrue(findings.contains { $0.title == "Log file missing" })
        case .success:
            XCTFail("Expected failure when log file is missing.")
        }
    }
}

/// File system stub for pwctl service tests.
private final class TestFileSystem: FileSystem {
    private var files: [String: Data]
    private var directories: Set<String>
    private var executableFiles: Set<String>

    /// Creates a file system stub with file contents keyed by path.
    /// - Parameter files: Map of file paths to file contents.
    init(files: [String: Data], directories: Set<String> = [], executableFiles: Set<String> = []) {
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
}
