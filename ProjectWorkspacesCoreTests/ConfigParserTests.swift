import XCTest

@testable import ProjectWorkspacesCore

final class ConfigParserTests: XCTestCase {
    func testParseAppliesDefaults() {
        let toml = """
        [[project]]
        id = "codex"
        name = "Codex"
        path = "/Users/tester/src/codex"
        colorHex = "#7C3AED"
        """

        let outcome = ConfigParser().parse(toml: toml)

        XCTAssertNotNil(outcome.config)
        XCTAssertEqual(outcome.config?.global.defaultIde, .vscode)
        XCTAssertEqual(outcome.config?.global.globalChromeUrls ?? [], [])
        XCTAssertEqual(outcome.config?.display.ultrawideMinWidthPx, 5000)

        guard let project = outcome.config?.projects.first else {
            XCTFail("Expected at least one project")
            return
        }

        XCTAssertEqual(project.ide, .vscode)
        XCTAssertEqual(project.chromeUrls, [])
        XCTAssertEqual(project.ideUseAgentLayerLauncher, true)
        XCTAssertEqual(project.ideCommand, "")
        XCTAssertTrue(outcome.effectiveIdeKinds.contains(.vscode))

        assertFinding(outcome.findings, severity: .warn, title: "Default applied: global.defaultIde = \"vscode\"")
        assertFinding(outcome.findings, severity: .warn, title: "Default applied: display.ultrawideMinWidthPx = 5000")
        assertFinding(outcome.findings, severity: .warn, title: "Default applied: project[0].ide = \"vscode\"")
    }

    func testUnknownKeysAreReported() {
        let toml = """
        [global]
        defaultIde = "vscode"
        globalChromeUrls = []
        extra = "nope"

        [[project]]
        id = "codex"
        name = "Codex"
        path = "/Users/tester/src/codex"
        colorHex = "#7C3AED"
        mystery = 1
        """

        let outcome = ConfigParser().parse(toml: toml)

        let unknownFinding = outcome.findings.first { $0.title == "Unknown config keys" }
        XCTAssertNotNil(unknownFinding)
        XCTAssertTrue(unknownFinding?.detail?.contains("global.extra") ?? false)
        XCTAssertTrue(unknownFinding?.detail?.contains("project[0].mystery") ?? false)
    }

    func testInvalidProjectIdFails() {
        let toml = """
        [[project]]
        id = "Bad Id"
        name = "Codex"
        path = "/Users/tester/src/codex"
        colorHex = "#7C3AED"
        """

        let outcome = ConfigParser().parse(toml: toml)

        XCTAssertNil(outcome.config)
        assertFinding(outcome.findings, severity: .fail, title: "project[0].id is invalid")
    }

    private func assertFinding(
        _ findings: [DoctorFinding],
        severity: DoctorSeverity,
        title: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let match = findings.contains { $0.severity == severity && $0.title == title }
        if !match {
            XCTFail("Missing finding: \(severity.rawValue) \(title)", file: file, line: line)
        }
    }
}
