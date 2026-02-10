import XCTest

@testable import AgentPanelAppKit

final class AppKitRunningApplicationCheckerTests: XCTestCase {
    func testIsApplicationRunningReturnsFalseForNonExistentBundleId() {
        let checker = AppKitRunningApplicationChecker()
        XCTAssertFalse(checker.isApplicationRunning(bundleIdentifier: "com.agentpanel.tests.nonexistent.bundle"))
    }
}

