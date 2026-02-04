import XCTest
@testable import AgentPanelCLICore

final class ApArgumentParserTests: XCTestCase {

    func testRootHelpFlag() {
        let parser = ApArgumentParser()

        switch parser.parse(arguments: ["--help"]) {
        case .failure(let error):
            XCTFail("Unexpected parse error: \(error.message)")
        case .success(let command):
            if case .help(.root) = command {
                return
            }
            XCTFail("Expected root help, got \(command)")
        }
    }

    func testVersionFlag() {
        let parser = ApArgumentParser()

        switch parser.parse(arguments: ["--version"]) {
        case .failure(let error):
            XCTFail("Unexpected parse error: \(error.message)")
        case .success(let command):
            if case .version = command {
                return
            }
            XCTFail("Expected version command, got \(command)")
        }
    }

    func testDoctorHelp() {
        let parser = ApArgumentParser()

        switch parser.parse(arguments: ["doctor", "--help"]) {
        case .failure(let error):
            XCTFail("Unexpected parse error: \(error.message)")
        case .success(let command):
            if case .help(.doctor) = command {
                return
            }
            XCTFail("Expected doctor help, got \(command)")
        }
    }

    func testMissingArgumentReportsUsage() {
        let parser = ApArgumentParser()

        switch parser.parse(arguments: ["new-workspace"]) {
        case .success(let command):
            XCTFail("Expected parse error, got \(command)")
        case .failure(let error):
            XCTAssertEqual(error.message, "missing argument")
            XCTAssertEqual(error.usageTopic, .newWorkspace)
        }
    }

    func testUnknownCommandReportsUsage() {
        let parser = ApArgumentParser()

        switch parser.parse(arguments: ["nope"]) {
        case .success(let command):
            XCTFail("Expected parse error, got \(command)")
        case .failure(let error):
            XCTAssertEqual(error.message, "unknown command: nope")
            XCTAssertEqual(error.usageTopic, .root)
        }
    }

    func testMoveWindowRejectsNonIntegerWindowId() {
        let parser = ApArgumentParser()

        switch parser.parse(arguments: ["move-window", "workspace", "abc"]) {
        case .success(let command):
            XCTFail("Expected parse error, got \(command)")
        case .failure(let error):
            XCTAssertEqual(error.message, "window id must be an integer: abc")
            XCTAssertEqual(error.usageTopic, .moveWindow)
        }
    }

    func testFocusWindowRejectsNonIntegerArgument() {
        let parser = ApArgumentParser()

        switch parser.parse(arguments: ["focus-window", "abc"]) {
        case .success(let command):
            XCTFail("Expected parse error, got \(command)")
        case .failure(let error):
            XCTAssertEqual(error.message, "argument must be an integer: abc")
            XCTAssertEqual(error.usageTopic, .focusWindow)
        }
    }
}
