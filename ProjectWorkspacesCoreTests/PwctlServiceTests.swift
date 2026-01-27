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

// Uses TestFileSystem from TestSupport.swift
