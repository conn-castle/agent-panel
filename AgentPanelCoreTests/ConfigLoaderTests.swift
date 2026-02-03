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

