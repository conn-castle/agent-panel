import XCTest

@testable import ProjectWorkspacesCore

final class PwctlArgumentParserTests: XCTestCase {
    private let parser = PwctlArgumentParser()

    func testParseHelpWhenNoArguments() {
        let result = parser.parse(arguments: [])

        XCTAssertEqual(result, .success(.help(topic: .root)))
    }

    func testParseRootHelpFlag() {
        let result = parser.parse(arguments: ["--help"])

        XCTAssertEqual(result, .success(.help(topic: .root)))
    }

    func testParseDoctorCommand() {
        let result = parser.parse(arguments: ["doctor"])

        XCTAssertEqual(result, .success(.doctor))
    }

    func testParseDoctorHelpFlag() {
        let result = parser.parse(arguments: ["doctor", "-h"])

        XCTAssertEqual(result, .success(.help(topic: .doctor)))
    }

    func testParseActivateRequiresProjectId() {
        let result = parser.parse(arguments: ["activate"])

        assertParseError(result, message: "missing projectId", usageTopic: .activate)
    }

    func testParseActivateAcceptsProjectId() {
        let result = parser.parse(arguments: ["activate", "codex"])

        XCTAssertEqual(result, .success(.activate(projectId: "codex")))
    }

    func testParseLogsRequiresTailFlag() {
        let result = parser.parse(arguments: ["logs"])

        assertParseError(result, message: "missing --tail <n>", usageTopic: .logs)
    }

    func testParseLogsHelpFlag() {
        let result = parser.parse(arguments: ["logs", "--help"])

        XCTAssertEqual(result, .success(.help(topic: .logs)))
    }

    func testParseLogsParsesTail() {
        let result = parser.parse(arguments: ["logs", "--tail", "200"])

        XCTAssertEqual(result, .success(.logs(tail: 200)))
    }

    func testParseLogsRejectsNonPositiveTail() {
        let result = parser.parse(arguments: ["logs", "--tail", "0"])

        assertParseError(result, message: "--tail must be a positive integer", usageTopic: .logs)
    }

    func testParseListRejectsExtraArguments() {
        let result = parser.parse(arguments: ["list", "extra"])

        assertParseError(result, message: "unexpected arguments: extra", usageTopic: .list)
    }

    func testParseUnknownCommandFails() {
        let result = parser.parse(arguments: ["whoami"])

        assertParseError(result, message: "unknown command: whoami", usageTopic: .root)
    }

    /// Asserts that a parsing result failed with the expected error details.
    /// - Parameters:
    ///   - result: Result to validate.
    ///   - message: Expected error message.
    ///   - usageTopic: Expected usage topic associated with the error.
    ///   - file: File used by XCTest for failure reporting.
    ///   - line: Line used by XCTest for failure reporting.
    private func assertParseError(
        _ result: Result<PwctlCommand, PwctlParseError>,
        message: String,
        usageTopic: PwctlHelpTopic,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch result {
        case .success(let command):
            XCTFail("Expected failure, got \(command)", file: file, line: line)
        case .failure(let error):
            XCTAssertEqual(error.message, message, file: file, line: line)
            XCTAssertEqual(error.usageTopic, usageTopic, file: file, line: line)
        }
    }
}
