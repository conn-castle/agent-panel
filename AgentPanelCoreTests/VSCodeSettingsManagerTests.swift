import XCTest
@testable import AgentPanelCore

/// Tests for `ApVSCodeSettingsManager`.
final class VSCodeSettingsManagerTests: XCTestCase {

    // MARK: - injectBlock: empty object

    func testInjectBlockIntoEmptyObject() throws {
        let result = try ApVSCodeSettingsManager.injectBlock(into: "{}\n", identifier: "my-proj").get()

        XCTAssertTrue(result.contains("// >>> agent-panel"))
        XCTAssertTrue(result.contains("// <<< agent-panel"))
        XCTAssertTrue(result.contains("\"window.title\": \"AP:my-proj"))
        XCTAssertTrue(result.hasPrefix("{"))
        XCTAssertTrue(result.hasSuffix("}"))
    }

    func testInjectBlockIntoMinimalEmptyObject() throws {
        let result = try ApVSCodeSettingsManager.injectBlock(into: "{}", identifier: "test").get()

        XCTAssertTrue(result.contains("// >>> agent-panel"))
        XCTAssertTrue(result.contains("AP:test"))
        XCTAssertTrue(result.hasPrefix("{"))
        XCTAssertTrue(result.hasSuffix("}"))
    }

    // MARK: - injectBlock: existing settings

    func testInjectBlockIntoObjectWithExistingSettings() throws {
        let content = """
        {
          "editor.fontSize": 14,
          "editor.tabSize": 2
        }
        """

        let result = try ApVSCodeSettingsManager.injectBlock(into: content, identifier: "proj").get()

        XCTAssertTrue(result.contains("// >>> agent-panel"))
        XCTAssertTrue(result.contains("AP:proj"))
        XCTAssertTrue(result.contains("\"editor.fontSize\": 14"))
        XCTAssertTrue(result.contains("\"editor.tabSize\": 2"))
    }

    // MARK: - injectBlock: replaces existing block

    func testInjectBlockReplacesExistingBlock() throws {
        let content = """
        {
          // >>> agent-panel
          // Managed by AgentPanel. Do not edit this block manually.
          "window.title": "AP:old-proj - ${dirty}${activeEditorShort}${separator}${rootName}${separator}${appName}",
          // <<< agent-panel
          "editor.fontSize": 14
        }
        """

        let result = try ApVSCodeSettingsManager.injectBlock(into: content, identifier: "new-proj").get()

        XCTAssertTrue(result.contains("AP:new-proj"))
        XCTAssertFalse(result.contains("AP:old-proj"))
        XCTAssertTrue(result.contains("\"editor.fontSize\": 14"))

        // Should have exactly one start marker and one end marker
        let startCount = result.components(separatedBy: "// >>> agent-panel").count - 1
        let endCount = result.components(separatedBy: "// <<< agent-panel").count - 1
        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(endCount, 1)
    }

    // MARK: - injectBlock: coexists with agent-layer block

    func testInjectBlockCoexistsWithAgentLayerBlock() throws {
        let content = """
        {
          // >>> agent-layer
          // Managed by Agent Layer.
          "some.setting": true,
          // <<< agent-layer
          "editor.fontSize": 14
        }
        """

        let result = try ApVSCodeSettingsManager.injectBlock(into: content, identifier: "proj").get()

        XCTAssertTrue(result.contains("// >>> agent-panel"))
        XCTAssertTrue(result.contains("// <<< agent-panel"))
        XCTAssertTrue(result.contains("// >>> agent-layer"))
        XCTAssertTrue(result.contains("// <<< agent-layer"))
        XCTAssertTrue(result.contains("AP:proj"))
        XCTAssertTrue(result.contains("\"some.setting\": true"))
    }

    // MARK: - injectBlock: malformed input (no brace)

    func testInjectBlockReturnsErrorForNoBrace() {
        let content = "not valid json"

        let result = ApVSCodeSettingsManager.injectBlock(into: content, identifier: "proj")

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("no opening '{'"))
        } else {
            XCTFail("Expected failure for content with no opening brace")
        }
    }

    // MARK: - injectBlock: unbalanced markers (safety)

    func testInjectBlockReturnsErrorWhenOnlyStartMarkerExists() {
        let content = """
        {
          // >>> agent-panel
          "window.title": "old value",
          "editor.fontSize": 14
        }
        """

        let result = ApVSCodeSettingsManager.injectBlock(into: content, identifier: "new-proj")

        switch result {
        case .success:
            XCTFail("Expected failure for unbalanced markers")
        case .failure(let error):
            XCTAssertTrue(error.message.contains("unbalanced"))
            XCTAssertTrue(error.message.contains("// >>> agent-panel"))
            XCTAssertTrue(error.message.contains("// <<< agent-panel"))
        }
    }

    func testInjectBlockReturnsErrorWhenOnlyEndMarkerExists() {
        let content = """
        {
          "editor.fontSize": 14,
          // <<< agent-panel
          "editor.tabSize": 2
        }
        """

        let result = ApVSCodeSettingsManager.injectBlock(into: content, identifier: "proj")

        switch result {
        case .success:
            XCTFail("Expected failure for unbalanced markers")
        case .failure(let error):
            XCTAssertTrue(error.message.contains("unbalanced"))
        }
    }

    // MARK: - writeLocalSettings: errors on unreadable file

    func testWriteLocalSettingsReturnsErrorWhenFileExistsButUnreadable() {
        let unreadableFS = SettingsUnreadableFileSystem()
        let manager = ApVSCodeSettingsManager(fileSystem: unreadableFS)

        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }

        let result = manager.writeLocalSettings(projectPath: tempDir.path, identifier: "test")

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("Failed to read existing .vscode/settings.json"))
        } else {
            XCTFail("Expected failure when file exists but is unreadable")
        }
    }

    // MARK: - injectBlock: window title format

    func testInjectBlockGeneratesCorrectWindowTitle() throws {
        let result = try ApVSCodeSettingsManager.injectBlock(into: "{}", identifier: "test-123").get()

        let expected = "AP:test-123 - ${dirty}${activeEditorShort}${separator}${rootName}${separator}${appName}"
        XCTAssertTrue(result.contains(expected), "Window title should match expected format, got: \(result)")
    }

    // MARK: - writeLocalSettings: creates .vscode directory

    func testWriteLocalSettingsCreatesVSCodeDirectory() {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }

        let manager = ApVSCodeSettingsManager()
        let result = manager.writeLocalSettings(projectPath: tempDir.path, identifier: "test")

        if case .failure(let error) = result {
            XCTFail("Expected success, got: \(error.message)")
            return
        }

        let vscodeDir = tempDir.appendingPathComponent(".vscode")
        var isDir = ObjCBool(false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: vscodeDir.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    // MARK: - writeLocalSettings: preserves existing content

    func testWriteLocalSettingsPreservesExistingContent() {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }

        let vscodeDir = tempDir.appendingPathComponent(".vscode")
        try! FileManager.default.createDirectory(at: vscodeDir, withIntermediateDirectories: true)
        let settingsURL = vscodeDir.appendingPathComponent("settings.json")
        try! """
        {
          "editor.fontSize": 14
        }
        """.write(to: settingsURL, atomically: true, encoding: .utf8)

        let manager = ApVSCodeSettingsManager()
        let result = manager.writeLocalSettings(projectPath: tempDir.path, identifier: "test")

        if case .failure(let error) = result {
            XCTFail("Expected success, got: \(error.message)")
            return
        }

        let content = try! String(contentsOf: settingsURL, encoding: .utf8)
        XCTAssertTrue(content.contains("// >>> agent-panel"))
        XCTAssertTrue(content.contains("\"editor.fontSize\": 14"))
    }

    // MARK: - writeLocalSettings: creates new file when missing

    func testWriteLocalSettingsCreatesNewFileWhenMissing() {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }

        let manager = ApVSCodeSettingsManager()
        let result = manager.writeLocalSettings(projectPath: tempDir.path, identifier: "new-proj")

        if case .failure(let error) = result {
            XCTFail("Expected success, got: \(error.message)")
            return
        }

        let settingsURL = tempDir.appendingPathComponent(".vscode/settings.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsURL.path))

        let content = try! String(contentsOf: settingsURL, encoding: .utf8)
        XCTAssertTrue(content.contains("AP:new-proj"))
    }

    // MARK: - writeLocalSettings: handles empty existing file

    func testWriteLocalSettingsHandlesEmptyExistingFile() {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }

        // Create an empty settings.json (0 bytes)
        let vscodeDir = tempDir.appendingPathComponent(".vscode", isDirectory: true)
        try! FileManager.default.createDirectory(at: vscodeDir, withIntermediateDirectories: true)
        let settingsURL = vscodeDir.appendingPathComponent("settings.json")
        FileManager.default.createFile(atPath: settingsURL.path, contents: Data())

        let manager = ApVSCodeSettingsManager()
        let result = manager.writeLocalSettings(projectPath: tempDir.path, identifier: "empty-file-proj")

        if case .failure(let error) = result {
            XCTFail("Expected success for empty file, got: \(error.message)")
            return
        }

        let content = try! String(contentsOf: settingsURL, encoding: .utf8)
        XCTAssertTrue(content.contains("// >>> agent-panel"), "Should inject block into empty file")
        XCTAssertTrue(content.contains("AP:empty-file-proj"), "Should contain project id")
    }

    // MARK: - writeLocalSettings: returns error on write failure

    func testWriteLocalSettingsReturnsErrorOnWriteFailure() {
        let failingFS = SettingsFailingFileSystem()
        let manager = ApVSCodeSettingsManager(fileSystem: failingFS)

        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }

        let result = manager.writeLocalSettings(projectPath: tempDir.path, identifier: "test")

        if case .success = result {
            XCTFail("Expected failure")
        }
        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("Failed to write .vscode/settings.json"))
        }
    }

    // MARK: - ApSSHHelpers: remote authority parsing

    func testParseRemoteAuthorityHappyPath() throws {
        let target = try ApSSHHelpers.parseRemoteAuthority("ssh-remote+user@host.com").get()
        XCTAssertEqual(target, "user@host.com")
    }

    func testParseRemoteAuthorityRejectsWrongPrefix() {
        let result = ApSSHHelpers.parseRemoteAuthority("dev-container+user@host")
        if case .failure(let error) = result {
            XCTAssertEqual(error, .missingPrefix)
        } else {
            XCTFail("Expected failure for wrong prefix")
        }
    }

    func testParseRemoteAuthorityRejectsWhitespace() {
        let result = ApSSHHelpers.parseRemoteAuthority("ssh-remote+user@host ")
        if case .failure(let error) = result {
            XCTAssertEqual(error, .containsWhitespace)
        } else {
            XCTFail("Expected failure for whitespace in authority")
        }
    }

    func testParseRemoteAuthorityRejectsEmptyTarget() {
        let result = ApSSHHelpers.parseRemoteAuthority("ssh-remote+")
        if case .failure(let error) = result {
            XCTAssertEqual(error, .missingTarget)
        } else {
            XCTFail("Expected failure for empty target")
        }
    }

    func testParseRemoteAuthorityRejectsDashPrefix() {
        let result = ApSSHHelpers.parseRemoteAuthority("ssh-remote+-flag")
        if case .failure(let error) = result {
            XCTAssertEqual(error, .targetStartsWithDash)
        } else {
            XCTFail("Expected failure for dash-prefixed target")
        }
    }

    // MARK: - ApSSHHelpers: shell escaping

    func testShellEscapeSimpleString() {
        XCTAssertEqual(ApSSHHelpers.shellEscape("hello"), "'hello'")
    }

    func testShellEscapeSingleQuote() {
        XCTAssertEqual(ApSSHHelpers.shellEscape("it's"), "'it'\\''s'")
    }

    func testShellEscapePathWithSpaces() {
        XCTAssertEqual(ApSSHHelpers.shellEscape("/path/to/my project"), "'/path/to/my project'")
    }

    func testShellEscapeMultipleSingleQuotes() {
        XCTAssertEqual(ApSSHHelpers.shellEscape("a'b'c"), "'a'\\''b'\\''c'")
    }

    // MARK: - injectBlock: workbench.colorCustomizations

    func testInjectBlockWithColorIncludesEmptyColorCustomizations() throws {
        let result = try ApVSCodeSettingsManager.injectBlock(
            into: "{}\n", identifier: "proj", color: "#8B5CF6"
        ).get()

        XCTAssertTrue(result.contains("\"workbench.colorCustomizations\": {}"))
    }

    func testInjectBlockWithoutColorExcludesColorCustomizations() throws {
        let result = try ApVSCodeSettingsManager.injectBlock(
            into: "{}\n", identifier: "proj"
        ).get()

        XCTAssertFalse(result.contains("workbench.colorCustomizations"))
    }

    func testInjectBlockPreservesExistingColorCustomizations() throws {
        let content = """
        {
          // >>> agent-panel
          // Managed by AgentPanel. Do not edit this block manually.
          "window.title": "AP:proj - ${dirty}${activeEditorShort}${separator}${rootName}${separator}${appName}",
          "peacock.color": "#8B5CF6",
          "peacock.remoteColor": "#8B5CF6",
          "workbench.colorCustomizations": {
            "statusBar.background": "#8b5cf6",
            "titleBar.activeBackground": "#8b5cf6"
          }
          // <<< agent-panel
        }
        """

        let result = try ApVSCodeSettingsManager.injectBlock(
            into: content, identifier: "proj", color: "#8B5CF6"
        ).get()

        XCTAssertTrue(result.contains("\"statusBar.background\": \"#8b5cf6\""))
        XCTAssertTrue(result.contains("\"titleBar.activeBackground\": \"#8b5cf6\""))
    }

    func testInjectBlockPreservesColorCustomizationsAcrossIdentifierChange() throws {
        let content = """
        {
          // >>> agent-panel
          // Managed by AgentPanel. Do not edit this block manually.
          "window.title": "AP:old-proj - ${dirty}${activeEditorShort}${separator}${rootName}${separator}${appName}",
          "peacock.color": "#8B5CF6",
          "peacock.remoteColor": "#8B5CF6",
          "workbench.colorCustomizations": {
            "statusBar.background": "#8b5cf6"
          }
          // <<< agent-panel
          "editor.fontSize": 14
        }
        """

        let result = try ApVSCodeSettingsManager.injectBlock(
            into: content, identifier: "new-proj", color: "#8B5CF6"
        ).get()

        XCTAssertTrue(result.contains("AP:new-proj"))
        XCTAssertFalse(result.contains("AP:old-proj"))
        XCTAssertTrue(result.contains("\"statusBar.background\": \"#8b5cf6\""))
        XCTAssertTrue(result.contains("\"editor.fontSize\": 14"))
    }

    // MARK: - injectBlock: trailing comma handling

    func testInjectBlockNoTrailingCommaWhenLastElement() throws {
        let result = try ApVSCodeSettingsManager.injectBlock(
            into: "{}\n", identifier: "proj", color: "#8B5CF6"
        ).get()

        // Last property should NOT have a trailing comma
        XCTAssertTrue(result.contains("\"workbench.colorCustomizations\": {}\n"))
        XCTAssertFalse(result.contains("\"workbench.colorCustomizations\": {},"))
    }

    func testInjectBlockTrailingCommaWhenNotLastElement() throws {
        let content = """
        {
          "editor.fontSize": 14
        }
        """

        let result = try ApVSCodeSettingsManager.injectBlock(
            into: content, identifier: "proj", color: "#8B5CF6"
        ).get()

        // Last property should have a trailing comma since content follows
        XCTAssertTrue(result.contains("\"workbench.colorCustomizations\": {},"))
    }

    func testInjectBlockNoTrailingCommaWithoutColorWhenLastElement() throws {
        let result = try ApVSCodeSettingsManager.injectBlock(
            into: "{}\n", identifier: "proj"
        ).get()

        // window.title is the last property and should NOT have a trailing comma
        XCTAssertFalse(result.contains("${appName}\","))
        XCTAssertTrue(result.contains("${appName}\""))
    }

    func testInjectBlockTrailingCommaWithoutColorWhenNotLastElement() throws {
        let content = """
        {
          "editor.fontSize": 14
        }
        """

        let result = try ApVSCodeSettingsManager.injectBlock(
            into: content, identifier: "proj"
        ).get()

        // window.title should have a trailing comma since content follows
        XCTAssertTrue(result.contains("${appName}\","))
    }

    func testInjectBlockPreservesMultiLineColorCustomizationsWithTrailingComma() throws {
        let content = """
        {
          // >>> agent-panel
          // Managed by AgentPanel. Do not edit this block manually.
          "window.title": "AP:proj - ${dirty}${activeEditorShort}${separator}${rootName}${separator}${appName}",
          "peacock.color": "#8B5CF6",
          "peacock.remoteColor": "#8B5CF6",
          "workbench.colorCustomizations": {
            "statusBar.background": "#8b5cf6",
            "titleBar.activeBackground": "#8b5cf6"
          }
          // <<< agent-panel
          "editor.fontSize": 14
        }
        """

        let result = try ApVSCodeSettingsManager.injectBlock(
            into: content, identifier: "proj", color: "#8B5CF6"
        ).get()

        // Multi-line value should have comma after closing } since content follows
        XCTAssertTrue(result.contains("\"titleBar.activeBackground\": \"#8b5cf6\""))
        XCTAssertTrue(result.contains("  },"))
    }

    // MARK: - extractColorCustomizations

    func testExtractColorCustomizationsReturnsEmptyObject() {
        let content = """
        {
          // >>> agent-panel
          // Managed by AgentPanel. Do not edit this block manually.
          "window.title": "AP:proj",
          "peacock.color": "#8B5CF6",
          "peacock.remoteColor": "#8B5CF6",
          "workbench.colorCustomizations": {}
          // <<< agent-panel
        }
        """

        let result = ApVSCodeSettingsManager.extractColorCustomizations(from: content)
        XCTAssertEqual(result, "{}")
    }

    func testExtractColorCustomizationsReturnsPopulatedObject() {
        let content = """
        {
          // >>> agent-panel
          // Managed by AgentPanel. Do not edit this block manually.
          "window.title": "AP:proj",
          "peacock.color": "#8B5CF6",
          "peacock.remoteColor": "#8B5CF6",
          "workbench.colorCustomizations": {
            "statusBar.background": "#8b5cf6",
            "titleBar.activeBackground": "#8b5cf6"
          }
          // <<< agent-panel
        }
        """

        let result = ApVSCodeSettingsManager.extractColorCustomizations(from: content)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("\"statusBar.background\": \"#8b5cf6\""))
        XCTAssertTrue(result!.contains("\"titleBar.activeBackground\": \"#8b5cf6\""))
        XCTAssertTrue(result!.hasPrefix("{"))
        XCTAssertTrue(result!.hasSuffix("}"))
    }

    func testExtractColorCustomizationsReturnsNilWhenKeyMissing() {
        let content = """
        {
          // >>> agent-panel
          // Managed by AgentPanel. Do not edit this block manually.
          "window.title": "AP:proj",
          "peacock.color": "#8B5CF6",
          "peacock.remoteColor": "#8B5CF6"
          // <<< agent-panel
        }
        """

        let result = ApVSCodeSettingsManager.extractColorCustomizations(from: content)
        XCTAssertNil(result)
    }

    func testExtractColorCustomizationsReturnsNilWhenNoBlock() {
        let content = """
        {
          "editor.fontSize": 14
        }
        """

        let result = ApVSCodeSettingsManager.extractColorCustomizations(from: content)
        XCTAssertNil(result)
    }

    func testExtractColorCustomizationsIgnoresKeyOutsideBlock() {
        let content = """
        {
          // >>> agent-panel
          // Managed by AgentPanel. Do not edit this block manually.
          "window.title": "AP:proj"
          // <<< agent-panel
          "workbench.colorCustomizations": {
            "statusBar.background": "#ff0000"
          }
        }
        """

        let result = ApVSCodeSettingsManager.extractColorCustomizations(from: content)
        XCTAssertNil(result)
    }

    // MARK: - Helpers

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsMgrTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }
}

// MARK: - Test Doubles

/// File system where the file exists but readFile throws (simulates permission error).
private struct SettingsUnreadableFileSystem: FileSystem {
    func fileExists(at url: URL) -> Bool { true }
    func directoryExists(at url: URL) -> Bool { true }
    func isExecutableFile(at url: URL) -> Bool { false }
    func readFile(at url: URL) throws -> Data {
        throw NSError(domain: "test", code: 13, userInfo: [NSLocalizedDescriptionKey: "Permission denied"])
    }
    func createDirectory(at url: URL) throws {}
    func fileSize(at url: URL) throws -> UInt64 { 0 }
    func removeItem(at url: URL) throws {}
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {}
    func appendFile(at url: URL, data: Data) throws {}
    func writeFile(at url: URL, data: Data) throws {}
}

private struct SettingsFailingFileSystem: FileSystem {
    func fileExists(at url: URL) -> Bool { false }
    func directoryExists(at url: URL) -> Bool { true }
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
