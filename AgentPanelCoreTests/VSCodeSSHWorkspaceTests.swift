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

    // MARK: - openNewWindow command execution behavior

    func testOpenNewWindowFailsWhenCodeExitNonZeroAndStderrEmpty() throws {
        let launcher = try makeLauncherWithCodeStub(
            "#!/bin/sh\nexit 2\n"
        )

        let result = launcher.openNewWindow(
            identifier: "exit-empty-stderr",
            projectPath: "/Users/test/project"
        )

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertEqual(error.message, "code failed with exit code 2.")
        }
    }

    func testOpenNewWindowFailsWhenCodeExitNonZeroAndStderrIncluded() throws {
        let launcher = try makeLauncherWithCodeStub(
            "#!/bin/sh\necho boom 1>&2\nexit 3\n"
        )

        let result = launcher.openNewWindow(
            identifier: "exit-with-stderr",
            projectPath: "/Users/test/project"
        )

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertTrue(error.message.contains("exit code 3"))
            XCTAssertTrue(error.message.contains("\nboom"))
        }
    }

    func testOpenNewWindowSucceedsWhenCodeExitZero() throws {
        let launcher = try makeLauncherWithCodeStub(
            "#!/bin/sh\nexit 0\n"
        )

        let result = launcher.openNewWindow(
            identifier: "exit-zero",
            projectPath: "/Users/test/project"
        )

        switch result {
        case .failure(let error):
            XCTFail("Expected success, got: \(error.message)")
        case .success:
            break
        }
    }

    func testOpenNewWindowTrimsRemoteAuthorityAndProjectPathWhenWritingWorkspace() throws {
        let launcher = try makeLauncherWithCodeStub(
            "#!/bin/sh\nexit 0\n"
        )

        let result = launcher.openNewWindow(
            identifier: "trim-test",
            projectPath: " /Users/test/project ",
            remoteAuthority: "  ssh-remote+u@h  "
        )
        if case .failure(let error) = result {
            XCTFail("Expected success, got: \(error.message)")
            return
        }

        let workspace = readWorkspaceJSON("trim-test")
        XCTAssertNotNil(workspace, "Workspace file should exist")

        let remoteAuthority = workspace?["remoteAuthority"] as? String
        XCTAssertEqual(remoteAuthority, "ssh-remote+u@h")

        let folders = workspace?["folders"] as? [[String: String]]
        XCTAssertEqual(folders?.first?["uri"], "vscode-remote://ssh-remote+u@h/Users/test/project")
    }

    func testOpenNewWindowReturnsErrorWhenWorkspaceFileWriteFails() {
        let failingFS = FailingFileSystem()
        let resolver = ExecutableResolver(
            fileSystem: EmptyFileSystem(),
            searchPaths: [],
            loginShellFallbackEnabled: false
        )
        let runner = ApSystemCommandRunner(executableResolver: resolver)
        let launcher = ApVSCodeLauncher(dataStore: dataStore, commandRunner: runner, fileSystem: failingFS)

        let result = launcher.openNewWindow(
            identifier: "workspace-write-fails",
            projectPath: "/Users/test/project"
        )

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertTrue(error.message.contains("Failed to write workspace file"))
        }
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

    private func makeLauncherWithCodeStub(_ codeScript: String) throws -> ApVSCodeLauncher {
        let binDir = tempDir.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)

        let codeURL = binDir.appendingPathComponent("code", isDirectory: false)
        try codeScript.write(to: codeURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codeURL.path)

        let resolver = ExecutableResolver(
            searchPaths: [binDir.path],
            loginShellFallbackEnabled: false
        )
        let runner = ApSystemCommandRunner(executableResolver: resolver)
        return ApVSCodeLauncher(dataStore: dataStore, commandRunner: runner)
    }

    // MARK: - createWorkspaceFile with injected FileSystem

    func testCreateWorkspaceFileUsesInjectedFileSystem() {
        let recorder = RecordingFileSystem()

        let result = ApIdeToken.createWorkspaceFile(
            identifier: "injected-fs",
            folders: [["path": "/test/path"]],
            remoteAuthority: nil,
            dataStore: dataStore,
            fileSystem: recorder
        )

        if case .failure(let error) = result {
            XCTFail("Expected success, got: \(error.message)")
            return
        }
        XCTAssertEqual(recorder.createDirectoryCalls.count, 1)
        XCTAssertEqual(recorder.writeFileCalls.count, 1)
        XCTAssertTrue(recorder.writeFileCalls.first?.url.lastPathComponent == "injected-fs.code-workspace")
    }

    func testCreateWorkspaceFileReturnsErrorOnFileSystemFailure() {
        let failingFS = FailingFileSystem()

        let result = ApIdeToken.createWorkspaceFile(
            identifier: "fail-test",
            folders: [],
            remoteAuthority: nil,
            dataStore: dataStore,
            fileSystem: failingFS
        )

        if case .success = result {
            XCTFail("Expected failure from failing file system")
        }
        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("Failed to write workspace file"))
        }
    }

    func testCreateWorkspaceFileSlashInIdentifierFails() {
        let result = ApIdeToken.createWorkspaceFile(
            identifier: "bad/id",
            folders: [],
            remoteAuthority: nil,
            dataStore: dataStore
        )

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("cannot contain '/'"))
        } else {
            XCTFail("Expected failure for identifier with slash")
        }
    }

    func testCreateWorkspaceFileEmptyIdentifierFails() {
        let result = ApIdeToken.createWorkspaceFile(
            identifier: "   ",
            folders: [],
            remoteAuthority: nil,
            dataStore: dataStore
        )

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("cannot be empty"))
        } else {
            XCTFail("Expected failure for empty identifier")
        }
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

/// Records createDirectory and writeFile calls for verification.
private final class RecordingFileSystem: FileSystem {
    struct WriteCall {
        let url: URL
        let data: Data
    }
    var createDirectoryCalls: [URL] = []
    var writeFileCalls: [WriteCall] = []

    func fileExists(at url: URL) -> Bool { false }
    func isExecutableFile(at url: URL) -> Bool { false }
    func readFile(at url: URL) throws -> Data { throw NSError(domain: "stub", code: 1) }
    func createDirectory(at url: URL) throws { createDirectoryCalls.append(url) }
    func fileSize(at url: URL) throws -> UInt64 { 0 }
    func removeItem(at url: URL) throws {}
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {}
    func appendFile(at url: URL, data: Data) throws {}
    func writeFile(at url: URL, data: Data) throws { writeFileCalls.append(WriteCall(url: url, data: data)) }
}

/// File system that throws on write — for testing error handling.
private struct FailingFileSystem: FileSystem {
    func fileExists(at url: URL) -> Bool { false }
    func isExecutableFile(at url: URL) -> Bool { false }
    func readFile(at url: URL) throws -> Data { throw NSError(domain: "stub", code: 1) }
    func createDirectory(at url: URL) throws {
        throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Disk full"])
    }
    func fileSize(at url: URL) throws -> UInt64 { 0 }
    func removeItem(at url: URL) throws {}
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {}
    func appendFile(at url: URL, data: Data) throws {}
    func writeFile(at url: URL, data: Data) throws {
        throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Disk full"])
    }
}
