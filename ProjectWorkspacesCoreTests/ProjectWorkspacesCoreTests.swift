import XCTest

@testable import ProjectWorkspacesCore

final class ProjectWorkspacesCoreTests: XCTestCase {
    func testVersion_isNonEmpty() {
        XCTAssertFalse(ProjectWorkspacesCore.version.isEmpty)
    }
}

