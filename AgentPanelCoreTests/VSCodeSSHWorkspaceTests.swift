import XCTest
@testable import AgentPanelCore

/// Tests that ApVSCodeLauncher generates correct workspace files for SSH and local paths.
///
/// These tests verify the workspace JSON contents (AP:<id> tag, remoteAuthority, folders).
/// The command runner uses a sandboxed resolver that cannot find 'code', so VS Code
/// is never actually launched — only the workspace file is inspected.
final class VSCodeSSHWorkspaceTests: XCTestCase {

    private var tempDir: URL!
    private var dataStore: DataPaths!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VSCodeSSHTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        dataStore = DataPaths(homeDirectory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - SSH workspace with remoteAuthority

    func testSSHPathGeneratesWorkspaceWithRemoteAuthority() {
        let launcher = makeSandboxedLauncher()

        // openNewWindow will fail (resolver can't find 'code') but writes workspace first
        _ = launcher.openNewWindow(
            identifier: "remote-ml",
            projectPath: "/Users/nconn/project",
            remoteAuthority: "ssh-remote+nconn@happy-mac.local"
        )

        let workspace = readWorkspaceJSON("remote-ml")
        XCTAssertNotNil(workspace, "Workspace file should exist")

        let remoteAuthority = workspace?["remoteAuthority"] as? String
        XCTAssertEqual(remoteAuthority, "ssh-remote+nconn@happy-mac.local")

        let folders = workspace?["folders"] as? [[String: String]]
        XCTAssertEqual(folders?.first?["uri"], "vscode-remote://ssh-remote+nconn@happy-mac.local/Users/nconn/project")
    }

    // MARK: - Non-SSH path has no remoteAuthority

    func testNonSSHPathGeneratesWorkspaceWithoutRemoteAuthority() {
        let launcher = makeSandboxedLauncher()

        _ = launcher.openNewWindow(
            identifier: "local-project",
            projectPath: "/Users/test/project"
        )

        let workspace = readWorkspaceJSON("local-project")
        XCTAssertNotNil(workspace, "Workspace file should exist")

        XCTAssertNil(workspace?["remoteAuthority"])

        let folders = workspace?["folders"] as? [[String: String]]
        XCTAssertEqual(folders?.first?["path"], "/Users/test/project")
    }

    // MARK: - AP:<id> tag preserved for SSH workspaces

    func testSSHWorkspacePreservesAPTag() {
        let launcher = makeSandboxedLauncher()

        _ = launcher.openNewWindow(
            identifier: "remote-ml",
            projectPath: "/remote/path",
            remoteAuthority: "ssh-remote+nconn@host"
        )

        let workspace = readWorkspaceJSON("remote-ml")
        let settings = workspace?["settings"] as? [String: String]
        let windowTitle = settings?["window.title"]
        XCTAssertNotNil(windowTitle)
        XCTAssertTrue(windowTitle?.hasPrefix("AP:remote-ml") == true,
                       "Window title should start with AP:remote-ml, got: \(windowTitle ?? "nil")")
    }

    func testSSHWorkspaceEncodesRemotePathSegmentsInURI() {
        let launcher = makeSandboxedLauncher()

        _ = launcher.openNewWindow(
            identifier: "remote-ml-encoded",
            projectPath: "/Users/nconn/my project#1",
            remoteAuthority: "ssh-remote+nconn@host"
        )

        let workspace = readWorkspaceJSON("remote-ml-encoded")
        XCTAssertNotNil(workspace, "Workspace file should exist")

        let remoteAuthority = workspace?["remoteAuthority"] as? String
        XCTAssertEqual(remoteAuthority, "ssh-remote+nconn@host")

        let folders = workspace?["folders"] as? [[String: String]]
        XCTAssertEqual(folders?.first?["uri"], "vscode-remote://ssh-remote+nconn@host/Users/nconn/my%20project%231")
    }

    // MARK: - Helpers

    /// Creates a launcher with a sandboxed resolver that cannot find 'code',
    /// preventing VS Code from actually launching during tests.
    private func makeSandboxedLauncher() -> ApVSCodeLauncher {
        let emptyFS = EmptyFileSystem()
        let resolver = ExecutableResolver(
            fileSystem: emptyFS,
            searchPaths: [],
            loginShellFallbackEnabled: false
        )
        let runner = ApSystemCommandRunner(executableResolver: resolver)
        return ApVSCodeLauncher(dataStore: dataStore, commandRunner: runner)
    }

    private func readWorkspaceJSON(_ identifier: String) -> [String: Any]? {
        let workspaceURL = dataStore.vscodeWorkspaceDirectory
            .appendingPathComponent("\(identifier).code-workspace")
        guard let data = try? Data(contentsOf: workspaceURL) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

/// File system stub that reports no files exist — prevents executable resolution.
private struct EmptyFileSystem: FileSystem {
    func fileExists(at url: URL) -> Bool { false }
    func isExecutableFile(at url: URL) -> Bool { false }
    func readFile(at url: URL) throws -> Data { throw NSError(domain: "stub", code: 1) }
    func createDirectory(at url: URL) throws {}
    func fileSize(at url: URL) throws -> UInt64 { 0 }
    func removeItem(at url: URL) throws {}
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {}
    func appendFile(at url: URL, data: Data) throws {}
    func writeFile(at url: URL, data: Data) throws {}
}
