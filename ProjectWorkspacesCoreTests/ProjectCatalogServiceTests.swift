import XCTest

@testable import ProjectWorkspacesCore

final class ProjectCatalogServiceTests: XCTestCase {
    func testListProjectsReturnsEntriesAndWarnings() {
        let config = """
        [[project]]
        id = "alpha"
        name = "Alpha"
        path = "/Users/tester/src/alpha"
        colorHex = "#7C3AED"

        [[project]]
        id = "bravo"
        name = "Bravo"
        path = "/Users/tester/src/bravo"
        colorHex = "#22C55E"
        """

        let fileSystem = TestFileSystem(files: [
            "/Users/tester/.config/project-workspaces/config.toml": Data(config.utf8)
        ])

        let service = ProjectCatalogService(
            paths: ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true)),
            fileSystem: fileSystem
        )

        switch service.listProjects() {
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error.findings)")
        case .success(let result):
            XCTAssertEqual(result.projects, [
                ProjectListItem(id: "alpha", name: "Alpha", path: "/Users/tester/src/alpha", colorHex: "#7C3AED"),
                ProjectListItem(id: "bravo", name: "Bravo", path: "/Users/tester/src/bravo", colorHex: "#22C55E")
            ])
            XCTAssertFalse(result.warnings.isEmpty)
        }
    }

    func testListProjectsFailsWhenConfigMissing() {
        let fileSystem = TestFileSystem(files: [:])
        let service = ProjectCatalogService(
            paths: ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true)),
            fileSystem: fileSystem
        )

        switch service.listProjects() {
        case .failure(let error):
            XCTAssertTrue(error.findings.contains { $0.title == "Config file missing" })
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

        let service = ProjectCatalogService(
            paths: ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true)),
            fileSystem: fileSystem
        )

        switch service.listProjects() {
        case .failure(let error):
            XCTAssertTrue(error.findings.contains { $0.title == "project[0].id is invalid" })
        case .success:
            XCTFail("Expected failure when config is invalid.")
        }
    }
}

// Uses TestFileSystem from TestSupport.swift
