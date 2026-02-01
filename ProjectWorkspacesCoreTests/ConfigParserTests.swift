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
        XCTAssertEqual(outcome.config?.global.globalChromeUrls, [])

        guard let project = outcome.config?.projects.first else {
            XCTFail("Expected at least one project")
            return
        }

        XCTAssertEqual(project.ide, .vscode)
        XCTAssertEqual(project.chromeUrls, [])
        XCTAssertTrue(outcome.effectiveIdeKinds.contains(.vscode))

        assertFinding(outcome.findings, severity: .warn, title: "Default applied: global.defaultIde = \"vscode\"")
        assertFinding(outcome.findings, severity: .warn, title: "Default applied: global.globalChromeUrls = []")
        assertFinding(outcome.findings, severity: .warn, title: "Default applied: project[0].ide = \"vscode\"")
        assertFinding(outcome.findings, severity: .warn, title: "Default applied: project[0].chromeUrls = []")
    }

    func testUnknownKeysAreReported() {
        let toml = """
        [global]
        defaultIde = "vscode"
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
        let body = unknownFinding?.bodyLines.joined(separator: "\n") ?? ""
        XCTAssertTrue(body.contains("global.extra"))
        XCTAssertTrue(body.contains("project[0].mystery"))
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

    func testMissingProjectsFails() {
        let toml = """
        [global]
        defaultIde = "vscode"
        """

        let outcome = ConfigParser().parse(toml: toml)

        XCTAssertNil(outcome.config)
        assertFinding(outcome.findings, severity: .fail, title: "No [[project]] entries")
    }

    func testReservedProjectIdFails() {
        let toml = """
        [[project]]
        id = "inbox"
        name = "Inbox"
        path = "/Users/tester/src/inbox"
        colorHex = "#7C3AED"
        """

        let outcome = ConfigParser().parse(toml: toml)

        XCTAssertNil(outcome.config)
        assertFinding(outcome.findings, severity: .fail, title: "project[0].id is reserved")
    }

    func testDuplicateProjectIdsFail() {
        let toml = """
        [[project]]
        id = "codex"
        name = "Codex"
        path = "/Users/tester/src/codex"
        colorHex = "#7C3AED"

        [[project]]
        id = "codex"
        name = "Codex Two"
        path = "/Users/tester/src/codex-two"
        colorHex = "#7C3AED"
        """

        let outcome = ConfigParser().parse(toml: toml)

        XCTAssertNil(outcome.config)
        assertFinding(outcome.findings, severity: .fail, title: "Duplicate project.id values")
    }

    func testInvalidColorHexFails() {
        let toml = """
        [[project]]
        id = "codex"
        name = "Codex"
        path = "/Users/tester/src/codex"
        colorHex = "#GGGGGG"
        """

        let outcome = ConfigParser().parse(toml: toml)

        XCTAssertNil(outcome.config)
        assertFinding(outcome.findings, severity: .fail, title: "project[0].colorHex is invalid")
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
