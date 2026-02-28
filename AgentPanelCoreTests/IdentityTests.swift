import XCTest
@testable import AgentPanelCore

final class IdentityTests: XCTestCase {
    func testResolveDisplayNameFallsBackOutsideAppBundleContext() {
        XCTAssertEqual(
            AgentPanel.resolveDisplayName(
                bundleIdentifier: "com.agentpanel.cli",
                infoDictionary: ["CFBundleName": "ap"]
            ),
            "AgentPanel"
        )
    }

    func testResolveDisplayNameUsesDisplayNameForPrimaryAppBundle() {
        XCTAssertEqual(
            AgentPanel.resolveDisplayName(
                bundleIdentifier: "com.agentpanel.AgentPanel",
                infoDictionary: ["CFBundleDisplayName": "AgentPanel"]
            ),
            "AgentPanel"
        )
    }

    func testResolveDisplayNameUsesDisplayNameForDevAppBundle() {
        XCTAssertEqual(
            AgentPanel.resolveDisplayName(
                bundleIdentifier: "com.agentpanel.AgentPanel.dev",
                infoDictionary: ["CFBundleDisplayName": "AgentPanel Dev"]
            ),
            "AgentPanel Dev"
        )
    }

    func testResolveDisplayNameFallsBackForLookalikeBundleIdentifier() {
        XCTAssertEqual(
            AgentPanel.resolveDisplayName(
                bundleIdentifier: "com.agentpanel.AgentPanelCLI",
                infoDictionary: ["CFBundleDisplayName": "AgentPanel CLI"]
            ),
            "AgentPanel"
        )
    }

    func testResolveDisplayNameFallsBackToBundleNameWhenDisplayNameMissing() {
        XCTAssertEqual(
            AgentPanel.resolveDisplayName(
                bundleIdentifier: "com.agentpanel.AgentPanel",
                infoDictionary: ["CFBundleName": "AgentPanel Test"]
            ),
            "AgentPanel Test"
        )
    }

    func testResolveDisplayNameFallsBackWhenNamesAreEmpty() {
        XCTAssertEqual(
            AgentPanel.resolveDisplayName(
                bundleIdentifier: "com.agentpanel.AgentPanel.dev",
                infoDictionary: ["CFBundleDisplayName": "   ", "CFBundleName": ""]
            ),
            "AgentPanel"
        )
    }

    func testResolveDisplayNameFallsBackWhenBundleIdentifierIsNil() {
        XCTAssertEqual(
            AgentPanel.resolveDisplayName(
                bundleIdentifier: nil,
                infoDictionary: ["CFBundleDisplayName": "Something"]
            ),
            "AgentPanel"
        )
    }

    func testResolveDisplayNameFallsBackWhenInfoDictionaryIsNil() {
        XCTAssertEqual(
            AgentPanel.resolveDisplayName(
                bundleIdentifier: "com.agentpanel.AgentPanel",
                infoDictionary: nil
            ),
            "AgentPanel"
        )
    }
}
