import XCTest
@testable import AgentPanelCore

final class ConfigLoaderTests: XCTestCase {

    func testLoadCreatesStarterConfigWhenMissing() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-panel-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configURL = tempRoot.appendingPathComponent("config.toml", isDirectory: false)

        XCTAssertFalse(FileManager.default.fileExists(atPath: configURL.path))

        let result = ConfigLoader.load(from: configURL)
        switch result {
        case .success:
            XCTFail("Expected load(from:) to fail when the file is missing (after creating starter config).")
        case .failure(let error):
            XCTAssertTrue(error.message.contains("Config file not found"), "Unexpected message: \(error.message)")
            XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path), "Starter config should be created.")

            let contents = try String(contentsOf: configURL, encoding: .utf8)
            XCTAssertTrue(contents.hasPrefix("# AgentPanel configuration"))
            XCTAssertTrue(contents.contains("[[project]]"))
            XCTAssertTrue(contents.contains("useAgentLayer"))
        }
    }

    func testLoadStarterConfigParsesButFailsValidation() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-panel-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configURL = tempRoot.appendingPathComponent("config.toml", isDirectory: false)

        _ = ConfigLoader.load(from: configURL)

        let second = ConfigLoader.load(from: configURL)
        switch second {
        case .failure(let error):
            XCTFail("Expected second load to succeed reading the starter file, got error: \(error.message)")
        case .success(let loadResult):
            XCTAssertNil(loadResult.config)
            XCTAssertTrue(loadResult.findings.contains {
                $0.severity == .fail && $0.title.contains("No [[project]] entries")
            })
        }
    }

    func testLoadInvalidTomlReturnsParseFinding() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-panel-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let configURL = tempRoot.appendingPathComponent("config.toml", isDirectory: false)
        try "invalid =".write(to: configURL, atomically: true, encoding: .utf8)

        let result = ConfigLoader.load(from: configURL)
        switch result {
        case .failure(let error):
            XCTFail("Expected load(from:) to succeed reading the file and return parse findings, got error: \(error.message)")
        case .success(let loadResult):
            XCTAssertNil(loadResult.config)
            XCTAssertTrue(loadResult.findings.contains {
                $0.severity == .fail && $0.title.contains("Config TOML parse error")
            })
        }
    }
}

// MARK: - Config.loadDefault() Tests

final class ConfigLoadDefaultTests: XCTestCase {
    // Note: Config.loadDefault() uses DataPaths.default() which reads from ~/.config/agentpanel.
    // These tests verify the error types and behavior, not the actual default path.

    private func makeTempConfigDirectory() throws -> URL {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-panel-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        return tempRoot
    }

    func testConfigLoadErrorEquatable() {
        // Test that ConfigLoadError cases are equatable
        let error1 = ConfigLoadError.fileNotFound(path: "/test")
        let error2 = ConfigLoadError.fileNotFound(path: "/test")
        let error3 = ConfigLoadError.fileNotFound(path: "/other")

        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)

        let readError1 = ConfigLoadError.readFailed(path: "/test", detail: "error")
        let readError2 = ConfigLoadError.readFailed(path: "/test", detail: "error")
        XCTAssertEqual(readError1, readError2)

        let parseError1 = ConfigLoadError.parseFailed(detail: "invalid")
        let parseError2 = ConfigLoadError.parseFailed(detail: "invalid")
        XCTAssertEqual(parseError1, parseError2)
    }

    func testConfigLoadErrorSendable() {
        // ConfigLoadError should be Sendable (compile-time check)
        let error: ConfigLoadError = .fileNotFound(path: "/test")
        let _: any Sendable = error
    }

    func testValidationFailedContainsFindings() {
        let findings = [
            ConfigFinding(severity: .fail, title: "Missing name"),
            ConfigFinding(severity: .fail, title: "Missing path")
        ]
        let error = ConfigLoadError.validationFailed(findings: findings)

        if case .validationFailed(let resultFindings) = error {
            XCTAssertEqual(resultFindings.count, 2)
            XCTAssertEqual(resultFindings[0].title, "Missing name")
            XCTAssertEqual(resultFindings[1].title, "Missing path")
        } else {
            XCTFail("Expected validationFailed case")
        }
    }
}

