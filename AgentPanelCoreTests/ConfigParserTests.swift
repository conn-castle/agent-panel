import XCTest
@testable import AgentPanelCore

final class ConfigParserTests: XCTestCase {

    func testParseValidProject() {
        let toml = """
        [[project]]
        name = "Test Project"
        path = "/Users/test/project"
        color = "blue"
        useAgentLayer = true
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.projects.count, 1)
        XCTAssertEqual(result.projects.first?.id, "test-project")
        XCTAssertEqual(result.projects.first?.name, "Test Project")
        XCTAssertEqual(result.projects.first?.color, "blue")
        XCTAssertEqual(result.projects.first?.useAgentLayer, true)
    }

    func testParseMultipleProjects() {
        let toml = """
        [[project]]
        name = "Project One"
        path = "/path/one"
        color = "blue"
        useAgentLayer = true

        [[project]]
        name = "Project Two"
        path = "/path/two"
        color = "red"
        useAgentLayer = false
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.projects.count, 2)
        XCTAssertEqual(result.projects[0].id, "project-one")
        XCTAssertEqual(result.projects[1].id, "project-two")
    }

    func testParseMissingRequiredField() {
        let toml = """
        [[project]]
        name = "Test"
        # missing path and color (useAgentLayer is optional)
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains { $0.severity == .fail })
    }

    func testParseEmptyName() {
        let toml = """
        [[project]]
        name = ""
        path = "/test"
        color = "blue"
        useAgentLayer = false
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains { $0.severity == .fail && $0.title.contains("name") })
    }

    func testParseReservedIdRejected() {
        let toml = """
        [[project]]
        name = "Inbox"
        path = "/test"
        color = "blue"
        useAgentLayer = false
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.lowercased().contains("reserved")
        })
    }

    func testParseDuplicateIdRejected() {
        let toml = """
        [[project]]
        name = "Test"
        path = "/path/one"
        color = "blue"
        useAgentLayer = false

        [[project]]
        name = "Test"
        path = "/path/two"
        color = "red"
        useAgentLayer = false
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.lowercased().contains("duplicate")
        })
    }

    func testParseHexColor() {
        let toml = """
        [[project]]
        name = "Hex Color Test"
        path = "/test"
        color = "#FF5500"
        useAgentLayer = false
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.projects.first?.color, "#FF5500")
    }

    // MARK: - Agent Layer Config Defaults

    func testNoAgentLayerSectionDefaultsFalse() {
        let toml = """
        [[project]]
        name = "Test"
        path = "/test"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.config?.agentLayer.enabled, false)
        XCTAssertEqual(result.projects.first?.useAgentLayer, false)
    }

    func testAgentLayerGlobalTrueDefaultsProjectsTrue() {
        let toml = """
        [agentLayer]
        enabled = true

        [[project]]
        name = "Test"
        path = "/test"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.config?.agentLayer.enabled, true)
        XCTAssertEqual(result.projects.first?.useAgentLayer, true)
    }

    func testAgentLayerGlobalTrueProjectOverrideFalse() {
        let toml = """
        [agentLayer]
        enabled = true

        [[project]]
        name = "Test"
        path = "/test"
        color = "blue"
        useAgentLayer = false
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.projects.first?.useAgentLayer, false)
    }

    func testAgentLayerGlobalFalseProjectOverrideTrue() {
        let toml = """
        [[project]]
        name = "Test"
        path = "/test"
        color = "blue"
        useAgentLayer = true
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.config?.agentLayer.enabled, false)
        XCTAssertEqual(result.projects.first?.useAgentLayer, true)
    }

    func testAgentLayerNotATableFails() {
        let toml = """
        agentLayer = "not a table"

        [[project]]
        name = "Test"
        path = "/test"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("[agentLayer] must be a table")
        })
    }

    func testUseAgentLayerOmittedWithGlobalFalse() {
        let toml = """
        [[project]]
        name = "Test"
        path = "/test"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.projects.first?.useAgentLayer, false)
    }

    // MARK: - SSH Project Validation

    func testSSHProjectValid() {
        let toml = """
        [[project]]
        name = "Remote ML"
        remote = "ssh-remote+nconn@happy-mac.local"
        path = "/Users/nconn/project"
        color = "teal"
        useAgentLayer = false
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.projects.first?.isSSH, true)
        XCTAssertEqual(result.projects.first?.remote, "ssh-remote+nconn@happy-mac.local")
        XCTAssertEqual(result.projects.first?.path, "/Users/nconn/project")
    }

    func testSSHProjectOmittedUseAgentLayerWithGlobalFalse() {
        let toml = """
        [[project]]
        name = "Remote ML"
        remote = "ssh-remote+nconn@host"
        path = "/remote/path"
        color = "teal"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.projects.first?.useAgentLayer, false)
    }

    func testSSHRemoteMissingPrefixFails() {
        let toml = """
        [[project]]
        name = "Remote ML"
        remote = "nconn@host"
        path = "/remote/path"
        color = "teal"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("must start with 'ssh-remote+'")
        })
    }

    func testSSHRemoteContainsWhitespaceFails() {
        let toml = """
        [[project]]
        name = "Remote ML"
        remote = "ssh-remote+nconn@host extra"
        path = "/remote/path"
        color = "teal"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("must not contain whitespace")
        })
    }

    func testSSHRemoteEmptyAuthorityFails() {
        let toml = """
        [[project]]
        name = "Remote ML"
        remote = "ssh-remote+"
        path = "/remote/path"
        color = "teal"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("missing host")
        })
    }

    func testSSHRemoteAuthorityStartingWithDashRejected() {
        let toml = """
        [[project]]
        name = "Remote ML"
        remote = "ssh-remote+-V"
        path = "/tmp"
        color = "teal"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("must not start with '-'")
        })
    }

    func testSSHRemoteAuthorityStartingWithDoubleDashRejected() {
        let toml = """
        [[project]]
        name = "Remote ML"
        remote = "ssh-remote+--option"
        path = "/tmp"
        color = "teal"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("must not start with '-'")
        })
    }

    func testSSHRemotePathNonAbsoluteRejected() {
        let toml = """
        [[project]]
        name = "Remote ML"
        remote = "ssh-remote+nconn@host"
        path = "relative/path"
        color = "teal"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("remote path must be an absolute path")
        })
    }

    func testSSHProjectWithUseAgentLayerTrueFails() {
        let toml = """
        [[project]]
        name = "Remote ML"
        remote = "ssh-remote+nconn@host"
        path = "/remote/path"
        color = "teal"
        useAgentLayer = true
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("Agent Layer is not supported with SSH")
        })
    }

    func testSSHProjectWithGlobalAgentLayerTrueAndNoOverrideFails() {
        let toml = """
        [agentLayer]
        enabled = true

        [[project]]
        name = "Remote ML"
        remote = "ssh-remote+nconn@host"
        path = "/remote/path"
        color = "teal"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("Agent Layer is not supported with SSH")
        })
    }

    func testSSHProjectWithGlobalAgentLayerTrueAndExplicitFalsePasses() {
        let toml = """
        [agentLayer]
        enabled = true

        [[project]]
        name = "Remote ML"
        remote = "ssh-remote+nconn@host"
        path = "/remote/path"
        color = "teal"
        useAgentLayer = false
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.projects.first?.useAgentLayer, false)
        XCTAssertEqual(result.projects.first?.isSSH, true)
    }

    func testLegacySSHPathFormatFails() {
        let toml = """
        [[project]]
        name = "Remote ML"
        path = "ssh-remote+nconn@host /remote/path"
        color = "teal"
        useAgentLayer = false
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("legacy SSH path format")
        })
    }

    func testNonSSHPathIsSSHFalse() {
        let toml = """
        [[project]]
        name = "Local"
        path = "/Users/test/project"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.projects.first?.isSSH, false)
    }

    // MARK: - Local path validation

    func testLocalRelativePathRejected() {
        let toml = """
        [[project]]
        name = "Local"
        path = "relative/path"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("local path must be an absolute path")
        })
    }

    func testLocalDotRelativePathRejected() {
        let toml = """
        [[project]]
        name = "Local"
        path = "./src/project"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("local path must be an absolute path")
        })
    }

    func testLocalAbsolutePathAccepted() {
        let toml = """
        [[project]]
        name = "Local"
        path = "/Users/test/project"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.projects.first?.path, "/Users/test/project")
    }

    // MARK: - Config Edge Cases

    func testNameNormalizesToEmptyFails() {
        let toml = """
        [[project]]
        name = "---"
        path = "/Users/test/project"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("cannot derive an id")
        })
    }

    func testInvalidColorFails() {
        let toml = """
        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "not-a-color"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("color is invalid")
        })
    }

    func testChromeNotATableFails() {
        let toml = """
        chrome = "not-a-table"

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("[chrome] must be a table")
        })
    }

    func testNameWrongTypeFails() {
        let toml = """
        [[project]]
        name = 123
        path = "/Users/test/project"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("must be a string")
        })
    }

    func testProjectKeyNotAnArrayFails() {
        let toml = """
        [project]
        name = "Test"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("project must be an array")
        })
    }

    func testMissingProjectKeyFails() {
        let toml = """
        [chrome]
        pinnedTabs = ["https://example.com"]
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("No [[project]] entries")
        })
    }

    func testEmptyProjectArrayFails() {
        let toml = """
        project = []
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("No [[project]] entries")
        })
    }

    func testProjectArrayElementNotATableFails() {
        let toml = """
        project = [1]
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("project[0] must be a table")
        })
    }

    func testOptionalRemoteWrongTypeFails() {
        let toml = """
        [[project]]
        name = "Remote ML"
        remote = 123
        path = "/remote/path"
        color = "teal"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("project[0].remote must be a string")
        })
    }

    func testOptionalRemoteEmptyFails() {
        let toml = """
        [[project]]
        name = "Remote ML"
        remote = ""
        path = "/remote/path"
        color = "teal"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("project[0].remote is empty")
        })
    }

    func testChromePinnedTabsWrongTypeFails() {
        let toml = """
        [chrome]
        pinnedTabs = "not-an-array"

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("chrome.pinnedTabs must be an array of strings")
        })
    }

    func testChromePinnedTabsElementWrongTypeFails() {
        let toml = """
        [chrome]
        pinnedTabs = [123]

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("chrome.pinnedTabs[0] must be a string")
        })
    }

    func testAgentLayerEnabledWrongTypeFails() {
        let toml = """
        [agentLayer]
        enabled = "yes"

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("agentLayer.enabled must be a boolean")
        })
    }

    func testChromeOpenGitRemoteWrongTypeFails() {
        let toml = """
        [chrome]
        openGitRemote = "true"

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("chrome.openGitRemote must be a boolean")
        })
    }

    // MARK: - Unrecognized Config Key Tests

    func testUnrecognizedTopLevelKey() {
        let toml = """
        bogusKey = "unexpected"

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config, "Config should be nil when unrecognized keys produce FAIL findings")
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("Unrecognized top-level config key: bogusKey")
        })
    }

    func testUnrecognizedChromeKey() {
        let toml = """
        [chrome]
        pinnedTabs = ["https://example.com"]
        bogusOption = true

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config, "Config should be nil when unrecognized keys produce FAIL findings")
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("Unrecognized [chrome] config key: bogusOption")
        })
    }

    func testUnrecognizedAgentLayerKey() {
        let toml = """
        [agentLayer]
        enabled = true
        unknownSetting = "value"

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        useAgentLayer = true
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config, "Config should be nil when unrecognized keys produce FAIL findings")
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("Unrecognized [agentLayer] config key: unknownSetting")
        })
    }

    func testUnrecognizedProjectKey() {
        let toml = """
        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        typoField = "oops"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config, "Config should be nil when unrecognized keys produce FAIL findings")
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("Unrecognized [[project]] config key: typoField")
        })
    }

    func testMultipleUnrecognizedKeysAreSorted() {
        let toml = """
        [chrome]
        zebra = true
        alpha = "test"
        pinnedTabs = ["https://example.com"]

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        let unknownFindings = result.findings.filter {
            $0.severity == .fail && $0.title.contains("Unrecognized [chrome] config key")
        }
        XCTAssertEqual(unknownFindings.count, 2)
        XCTAssertTrue(unknownFindings[0].title.contains("alpha"))
        XCTAssertTrue(unknownFindings[1].title.contains("zebra"))
    }

    func testValidConfigHasNoUnrecognizedKeyFindings() {
        let toml = """
        [chrome]
        pinnedTabs = ["https://example.com"]
        defaultTabs = ["https://docs.example.com"]
        openGitRemote = true

        [agentLayer]
        enabled = false

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        useAgentLayer = false
        remote = "ssh-remote+user@host"
        chromePinnedTabs = ["https://api.example.com"]
        chromeDefaultTabs = ["https://jira.example.com"]
        """

        let result = ConfigParser.parse(toml: toml)

        let unknownFindings = result.findings.filter {
            $0.title.contains("Unrecognized")
        }
        XCTAssertTrue(unknownFindings.isEmpty, "Valid config should have no unrecognized key findings, got: \(unknownFindings)")
    }

    func testUnrecognizedKeyFixIncludesKnownKeys() {
        let toml = """
        [agentLayer]
        enabeld = true

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        let finding = result.findings.first {
            $0.title.contains("Unrecognized [agentLayer] config key: enabeld")
        }
        XCTAssertNotNil(finding)
        XCTAssertTrue(finding?.fix?.contains("enabled") == true, "Fix should list known keys")
    }
}
