import XCTest
@testable import AgentPanelCore

/// Tests for `ApVSCodeSettingsManager.writeRemoteSettings` and `ensureAllSettingsBlocks`.
///
/// Verifies:
/// - SSH remote write round trip (read → inject → base64 → write)
/// - Error handling: SSH read/write failures, malformed authority, nil command runner
/// - SSH argument safety (option terminator `--`)
/// - `ensureAllSettingsBlocks` processes local + SSH projects independently
final class VSCodeSettingsManagerRemoteTests: XCTestCase {

    // MARK: - writeRemoteSettings

    func testWriteRemoteSettingsSuccessfulRoundTrip() {
        let runner = SequentialSSHRunner(results: [
            .success(ApCommandResult(exitCode: 0, stdout: "{}\n", stderr: "")),
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ])
        let manager = ApVSCodeSettingsManager(commandRunner: runner)

        let result = manager.writeRemoteSettings(
            remoteAuthority: "ssh-remote+user@host",
            remotePath: "/home/user/project",
            identifier: "my-proj"
        )

        if case .failure(let error) = result {
            XCTFail("Expected success, got: \(error.message)")
        }

        XCTAssertEqual(runner.calls.count, 2, "Should make SSH read + SSH write calls")

        // Verify read call
        let readCall = runner.calls[0]
        XCTAssertTrue(readCall.arguments.contains("--"), "Read call should include option terminator")
        XCTAssertTrue(readCall.arguments.contains("user@host"))

        // Verify write call
        let writeCall = runner.calls[1]
        XCTAssertTrue(writeCall.arguments.contains("--"), "Write call should include option terminator")
        XCTAssertTrue(writeCall.arguments.contains("user@host"))
        // The last argument should contain mkdir + base64 write
        let writeCommand = writeCall.arguments.last ?? ""
        XCTAssertTrue(writeCommand.contains("mkdir -p"), "Write command should mkdir")
        XCTAssertTrue(writeCommand.contains("base64"), "Write command should use base64")
    }

    func testWriteRemoteSettingsSSHReadFailureReturnsError() {
        let runner = SequentialSSHRunner(results: [
            .failure(ApCoreError(message: "Connection refused"))
        ])
        let manager = ApVSCodeSettingsManager(commandRunner: runner)

        let result = manager.writeRemoteSettings(
            remoteAuthority: "ssh-remote+user@host",
            remotePath: "/home/user/project",
            identifier: "test"
        )

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("SSH read failed"))
        } else {
            XCTFail("Expected failure when SSH read fails")
        }
    }

    func testWriteRemoteSettingsSSHReadNonZeroExitReturnsError() {
        let runner = SequentialSSHRunner(results: [
            .success(ApCommandResult(exitCode: 255, stdout: "", stderr: "Permission denied"))
        ])
        let manager = ApVSCodeSettingsManager(commandRunner: runner)

        let result = manager.writeRemoteSettings(
            remoteAuthority: "ssh-remote+user@host",
            remotePath: "/home/user/project",
            identifier: "test"
        )

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("SSH read failed with exit code 255"))
        } else {
            XCTFail("Expected failure for non-zero SSH read exit code")
        }
    }

    func testWriteRemoteSettingsSSHWriteFailureReturnsError() {
        let runner = SequentialSSHRunner(results: [
            .success(ApCommandResult(exitCode: 0, stdout: "{}\n", stderr: "")),
            .failure(ApCoreError(message: "Connection reset"))
        ])
        let manager = ApVSCodeSettingsManager(commandRunner: runner)

        let result = manager.writeRemoteSettings(
            remoteAuthority: "ssh-remote+user@host",
            remotePath: "/home/user/project",
            identifier: "test"
        )

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("SSH write failed"))
        } else {
            XCTFail("Expected failure when SSH write fails")
        }
    }

    func testWriteRemoteSettingsSSHWriteNonZeroExitReturnsError() {
        let runner = SequentialSSHRunner(results: [
            .success(ApCommandResult(exitCode: 0, stdout: "{}\n", stderr: "")),
            .success(ApCommandResult(exitCode: 1, stdout: "", stderr: "Permission denied"))
        ])
        let manager = ApVSCodeSettingsManager(commandRunner: runner)

        let result = manager.writeRemoteSettings(
            remoteAuthority: "ssh-remote+user@host",
            remotePath: "/home/user/project",
            identifier: "test"
        )

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("SSH write failed with exit code 1"))
        } else {
            XCTFail("Expected failure for non-zero SSH write exit code")
        }
    }

    func testWriteRemoteSettingsMalformedAuthorityReturnsError() {
        let runner = SequentialSSHRunner(results: [])
        let manager = ApVSCodeSettingsManager(commandRunner: runner)

        let result = manager.writeRemoteSettings(
            remoteAuthority: "invalid-format",
            remotePath: "/home/user/project",
            identifier: "test"
        )

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("Malformed SSH remote authority"))
        } else {
            XCTFail("Expected failure for malformed authority")
        }

        XCTAssertTrue(runner.calls.isEmpty, "No SSH calls should be made for malformed authority")
    }

    func testWriteRemoteSettingsNilCommandRunnerReturnsError() {
        let manager = ApVSCodeSettingsManager()

        let result = manager.writeRemoteSettings(
            remoteAuthority: "ssh-remote+user@host",
            remotePath: "/home/user/project",
            identifier: "test"
        )

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("Command runner not available"))
        } else {
            XCTFail("Expected failure when commandRunner is nil")
        }
    }

    func testWriteRemoteSettingsSSHArgsIncludeOptionTerminator() {
        let runner = SequentialSSHRunner(results: [
            .success(ApCommandResult(exitCode: 0, stdout: "{}\n", stderr: "")),
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ])
        let manager = ApVSCodeSettingsManager(commandRunner: runner)

        _ = manager.writeRemoteSettings(
            remoteAuthority: "ssh-remote+user@host",
            remotePath: "/home/user/project",
            identifier: "test"
        )

        for (index, call) in runner.calls.enumerated() {
            XCTAssertTrue(
                call.arguments.contains("--"),
                "Call \(index) should include -- option terminator"
            )
        }
    }

    func testWriteRemoteSettingsInjectsBlockIntoExistingContent() {
        let existingSettings = "{\n  \"editor.fontSize\": 14\n}\n"
        let runner = SequentialSSHRunner(results: [
            .success(ApCommandResult(exitCode: 0, stdout: existingSettings, stderr: "")),
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ])
        let manager = ApVSCodeSettingsManager(commandRunner: runner)

        _ = manager.writeRemoteSettings(
            remoteAuthority: "ssh-remote+user@host",
            remotePath: "/home/user/project",
            identifier: "test-proj"
        )

        // The write call's last argument contains the base64-encoded content
        XCTAssertEqual(runner.calls.count, 2)
        let writeCommand = runner.calls[1].arguments.last ?? ""
        // Extract the base64 string from: echo '<base64>' | base64 -d > ...
        // The command also contains an earlier `echo Remote project path missing: ...` guard,
        // so match the specific `| base64 -d` pattern.
        let pattern = #"echo '([A-Za-z0-9+/=]+)' \| base64 -d"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(writeCommand.startIndex..<writeCommand.endIndex, in: writeCommand)
        guard let match = regex.firstMatch(in: writeCommand, range: range),
              match.numberOfRanges > 1,
              let base64Range = Range(match.range(at: 1), in: writeCommand) else {
            XCTFail("Write command should contain base64 echo pattern, got: \(writeCommand)")
            return
        }

        let base64String = String(writeCommand[base64Range])
        guard let decoded = Data(base64Encoded: base64String),
              let content = String(data: decoded, encoding: .utf8) else {
            XCTFail("Failed to decode base64 content")
            return
        }

        XCTAssertTrue(content.contains("// >>> agent-panel"), "Decoded content should have marker")
        XCTAssertTrue(content.contains("AP:test-proj"), "Decoded content should have project id")
        XCTAssertTrue(content.contains("editor.fontSize"), "Decoded content should preserve existing settings")
    }

    // MARK: - ensureAllSettingsBlocks

    func testEnsureAllSettingsBlocksLocalProject() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EnsureTests-\(UUID().uuidString)", isDirectory: true)
        let projectDir = tempDir.appendingPathComponent("project", isDirectory: true)
        try? FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let project = ProjectConfig(
            id: "my-project", name: "My Project",
            path: projectDir.path, color: "blue", useAgentLayer: false
        )
        let manager = ApVSCodeSettingsManager()

        let results = manager.ensureAllSettingsBlocks(projects: [project])

        XCTAssertEqual(results.count, 1)
        if case .failure(let error) = results["my-project"] {
            XCTFail("Expected success, got: \(error.message)")
        }

        let settingsURL = projectDir.appendingPathComponent(".vscode/settings.json")
        let content = try? String(contentsOf: settingsURL, encoding: .utf8)
        XCTAssertNotNil(content, "settings.json should exist")
        XCTAssertTrue(content?.contains("// >>> agent-panel") == true)
        XCTAssertTrue(content?.contains("AP:my-project") == true)
    }

    func testEnsureAllSettingsBlocksSSHProject() {
        let runner = SequentialSSHRunner(results: [
            .success(ApCommandResult(exitCode: 0, stdout: "{}\n", stderr: "")),
            .success(ApCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ])
        let project = ProjectConfig(
            id: "remote-proj", name: "Remote Project",
            remote: "ssh-remote+user@host",
            path: "/home/user/project", color: "red", useAgentLayer: false
        )
        let manager = ApVSCodeSettingsManager(commandRunner: runner)

        let results = manager.ensureAllSettingsBlocks(projects: [project])

        XCTAssertEqual(results.count, 1)
        if case .failure(let error) = results["remote-proj"] {
            XCTFail("Expected success, got: \(error.message)")
        }
        XCTAssertEqual(runner.calls.count, 2, "Should make SSH read + write calls")
    }

    func testEnsureAllSettingsBlocksMixedProjectsIndependent() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EnsureMixed-\(UUID().uuidString)", isDirectory: true)
        let projectDir = tempDir.appendingPathComponent("local-proj", isDirectory: true)
        try? FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // SSH project will fail (connection refused)
        let runner = SequentialSSHRunner(results: [
            .failure(ApCoreError(message: "Connection refused"))
        ])
        let localProject = ProjectConfig(
            id: "local", name: "Local",
            path: projectDir.path, color: "blue", useAgentLayer: false
        )
        let sshProject = ProjectConfig(
            id: "remote", name: "Remote",
            remote: "ssh-remote+user@host",
            path: "/home/user/project", color: "red", useAgentLayer: false
        )
        let manager = ApVSCodeSettingsManager(commandRunner: runner)

        let results = manager.ensureAllSettingsBlocks(projects: [localProject, sshProject])

        XCTAssertEqual(results.count, 2)

        // Local should succeed despite SSH failure
        if case .failure(let error) = results["local"] {
            XCTFail("Local project should succeed, got: \(error.message)")
        }

        // SSH should fail
        if case .success = results["remote"] {
            XCTFail("SSH project should fail")
        }
    }

    func testEnsureAllSettingsBlocksEmptyProjects() {
        let manager = ApVSCodeSettingsManager()

        let results = manager.ensureAllSettingsBlocks(projects: [])

        XCTAssertTrue(results.isEmpty)
    }

    func testEnsureAllSettingsBlocksLocalWriteFails() {
        let failingFS = RemoteTestFailingFileSystem()
        let project = ProjectConfig(
            id: "fail-proj", name: "Fail Project",
            path: "/nonexistent/path", color: "blue", useAgentLayer: false
        )
        let manager = ApVSCodeSettingsManager(fileSystem: failingFS)

        let results = manager.ensureAllSettingsBlocks(projects: [project])

        XCTAssertEqual(results.count, 1)
        if case .success = results["fail-proj"] {
            XCTFail("Expected failure for failing file system")
        }
    }
}

// MARK: - Test Doubles

private final class SequentialSSHRunner: CommandRunning {
    struct Call {
        let executable: String
        let arguments: [String]
    }

    var calls: [Call] = []
    private var results: [Result<ApCommandResult, ApCoreError>]

    init(results: [Result<ApCommandResult, ApCoreError>]) {
        self.results = results
    }

    func run(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval?,
        workingDirectory: String?
    ) -> Result<ApCommandResult, ApCoreError> {
        calls.append(Call(executable: executable, arguments: arguments))
        guard !results.isEmpty else {
            return .failure(ApCoreError(message: "SequentialSSHRunner: no results left"))
        }
        return results.removeFirst()
    }
}

private struct RemoteTestFailingFileSystem: FileSystem {
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
