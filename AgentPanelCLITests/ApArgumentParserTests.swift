import XCTest
@testable import AgentPanelCLICore

final class ApArgumentParserTests: XCTestCase {

    func testRootHelpFlag() {
        let parser = ApArgumentParser()

        switch parser.parse(arguments: ["--help"]) {
        case .failure(let error):
            XCTFail("Unexpected parse error: \(error.message)")
        case .success(let command):
            XCTAssertEqual(command, .help(.root))
        }
    }

    func testVersionFlag() {
        let parser = ApArgumentParser()

        switch parser.parse(arguments: ["--version"]) {
        case .failure(let error):
            XCTFail("Unexpected parse error: \(error.message)")
        case .success(let command):
            XCTAssertEqual(command, .version)
        }
    }

    func testDoctorHelp() {
        let parser = ApArgumentParser()

        switch parser.parse(arguments: ["doctor", "--help"]) {
        case .failure(let error):
            XCTFail("Unexpected parse error: \(error.message)")
        case .success(let command):
            XCTAssertEqual(command, .help(.doctor))
        }
    }

    func testDoctorCommand() {
        let parser = ApArgumentParser()

        switch parser.parse(arguments: ["doctor"]) {
        case .failure(let error):
            XCTFail("Unexpected parse error: \(error.message)")
        case .success(let command):
            XCTAssertEqual(command, .doctor)
        }
    }

    func testShowConfigCommand() {
        let parser = ApArgumentParser()

        switch parser.parse(arguments: ["show-config"]) {
        case .failure(let error):
            XCTFail("Unexpected parse error: \(error.message)")
        case .success(let command):
            XCTAssertEqual(command, .showConfig)
        }
    }

    func testListProjectsNoQuery() {
        let parser = ApArgumentParser()

        switch parser.parse(arguments: ["list-projects"]) {
        case .failure(let error):
            XCTFail("Unexpected parse error: \(error.message)")
        case .success(let command):
            XCTAssertEqual(command, .listProjects(nil))
        }
    }

    func testListProjectsWithQuery() {
        let parser = ApArgumentParser()

        switch parser.parse(arguments: ["list-projects", "foo"]) {
        case .failure(let error):
            XCTFail("Unexpected parse error: \(error.message)")
        case .success(let command):
            XCTAssertEqual(command, .listProjects("foo"))
        }
    }

    func testSelectProjectCommand() {
        let parser = ApArgumentParser()

        switch parser.parse(arguments: ["select-project", "my-project"]) {
        case .failure(let error):
            XCTFail("Unexpected parse error: \(error.message)")
        case .success(let command):
            XCTAssertEqual(command, .selectProject("my-project"))
        }
    }

    func testSelectProjectMissingArgument() {
        let parser = ApArgumentParser()

        switch parser.parse(arguments: ["select-project"]) {
        case .success(let command):
            XCTFail("Expected parse error, got \(command)")
        case .failure(let error):
            XCTAssertEqual(error.message, "missing argument")
            XCTAssertEqual(error.usageTopic, .selectProject)
        }
    }

    func testCloseProjectCommand() {
        let parser = ApArgumentParser()

        switch parser.parse(arguments: ["close-project", "my-project"]) {
        case .failure(let error):
            XCTFail("Unexpected parse error: \(error.message)")
        case .success(let command):
            XCTAssertEqual(command, .closeProject("my-project"))
        }
    }

    func testReturnCommand() {
        let parser = ApArgumentParser()

        switch parser.parse(arguments: ["return"]) {
        case .failure(let error):
            XCTFail("Unexpected parse error: \(error.message)")
        case .success(let command):
            XCTAssertEqual(command, .returnToWindow)
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

    func testMissingCommandReportsUsage() {
        let parser = ApArgumentParser()

        switch parser.parse(arguments: []) {
        case .success(let command):
            XCTFail("Expected parse error, got \(command)")
        case .failure(let error):
            XCTAssertEqual(error.message, "missing command")
            XCTAssertEqual(error.usageTopic, .root)
        }
    }
}
