import XCTest
@testable import AgentPanelCore

/// Tests for WorkspaceRouting canonical workspace naming and routing utility.
final class WorkspaceRoutingTests: XCTestCase {

    // MARK: - projectPrefix

    func testProjectPrefix_isAp() {
        XCTAssertEqual(WorkspaceRouting.projectPrefix, "ap-")
    }

    // MARK: - fallbackWorkspace

    func testFallbackWorkspace_isOne() {
        XCTAssertEqual(WorkspaceRouting.fallbackWorkspace, "1")
    }

    // MARK: - isProjectWorkspace

    func testIsProjectWorkspace_withProjectWorkspace_returnsTrue() {
        XCTAssertTrue(WorkspaceRouting.isProjectWorkspace("ap-myproject"))
    }

    func testIsProjectWorkspace_withPrefixOnly_returnsTrue() {
        // "ap-" alone still has the prefix — consumers use projectId(fromWorkspace:) for ID extraction
        XCTAssertTrue(WorkspaceRouting.isProjectWorkspace("ap-"))
    }

    func testIsProjectWorkspace_withNonProjectWorkspace_returnsFalse() {
        XCTAssertFalse(WorkspaceRouting.isProjectWorkspace("1"))
        XCTAssertFalse(WorkspaceRouting.isProjectWorkspace("main"))
        XCTAssertFalse(WorkspaceRouting.isProjectWorkspace("work"))
    }

    func testIsProjectWorkspace_withEmptyString_returnsFalse() {
        XCTAssertFalse(WorkspaceRouting.isProjectWorkspace(""))
    }

    func testIsProjectWorkspace_withPartialPrefix_returnsFalse() {
        XCTAssertFalse(WorkspaceRouting.isProjectWorkspace("ap"))
        XCTAssertFalse(WorkspaceRouting.isProjectWorkspace("a"))
    }

    // MARK: - projectId(fromWorkspace:)

    func testProjectId_withProjectWorkspace_returnsId() {
        XCTAssertEqual(WorkspaceRouting.projectId(fromWorkspace: "ap-myproject"), "myproject")
    }

    func testProjectId_withHyphenatedProjectId_returnsFullId() {
        XCTAssertEqual(WorkspaceRouting.projectId(fromWorkspace: "ap-my-fancy-project"), "my-fancy-project")
    }

    func testProjectId_withPrefixOnly_returnsNil() {
        XCTAssertNil(WorkspaceRouting.projectId(fromWorkspace: "ap-"))
    }

    func testProjectId_withNonProjectWorkspace_returnsNil() {
        XCTAssertNil(WorkspaceRouting.projectId(fromWorkspace: "1"))
        XCTAssertNil(WorkspaceRouting.projectId(fromWorkspace: "main"))
    }

    func testProjectId_withEmptyString_returnsNil() {
        XCTAssertNil(WorkspaceRouting.projectId(fromWorkspace: ""))
    }

    // MARK: - workspaceName(forProjectId:)

    func testWorkspaceName_returnsCorrectFormat() {
        XCTAssertEqual(WorkspaceRouting.workspaceName(forProjectId: "myproject"), "ap-myproject")
    }

    func testWorkspaceName_withHyphenatedId_returnsCorrectFormat() {
        XCTAssertEqual(WorkspaceRouting.workspaceName(forProjectId: "my-fancy-project"), "ap-my-fancy-project")
    }

    // MARK: - preferredNonProjectWorkspace

    func testPreferred_withNonProjectWorkspaceWithWindows_returnsIt() {
        let result = WorkspaceRouting.preferredNonProjectWorkspace(
            from: ["ap-proj1", "main", "ap-proj2"],
            hasWindows: { $0 == "main" }
        )
        XCTAssertEqual(result, "main")
    }

    func testPreferred_withMultipleNonProjectWorkspaces_prefersOneWithWindows() {
        let result = WorkspaceRouting.preferredNonProjectWorkspace(
            from: ["ap-proj", "empty-ws", "populated-ws"],
            hasWindows: { $0 == "populated-ws" }
        )
        XCTAssertEqual(result, "populated-ws")
    }

    func testPreferred_withNoWindowsInNonProject_returnsFirstNonProject() {
        let result = WorkspaceRouting.preferredNonProjectWorkspace(
            from: ["ap-proj", "empty-ws", "another-empty"],
            hasWindows: { _ in false }
        )
        XCTAssertEqual(result, "empty-ws")
    }

    func testPreferred_withOnlyProjectWorkspaces_returnsFallback() {
        let result = WorkspaceRouting.preferredNonProjectWorkspace(
            from: ["ap-proj1", "ap-proj2"],
            hasWindows: { _ in true }
        )
        XCTAssertEqual(result, WorkspaceRouting.fallbackWorkspace)
    }

    func testPreferred_withEmptyList_returnsFallback() {
        let result = WorkspaceRouting.preferredNonProjectWorkspace(
            from: [],
            hasWindows: { _ in true }
        )
        XCTAssertEqual(result, WorkspaceRouting.fallbackWorkspace)
    }

    func testPreferred_filtersOutProjectWorkspaces() {
        // "ap-proj" has windows but should be excluded
        let result = WorkspaceRouting.preferredNonProjectWorkspace(
            from: ["ap-proj", "2"],
            hasWindows: { $0 == "ap-proj" }
        )
        // Should pick "2" (non-project, no windows) rather than "ap-proj"
        XCTAssertEqual(result, "2")
    }

    func testPreferred_preservesInputOrder() {
        // When multiple non-project workspaces have windows, pick the first in list order
        let result = WorkspaceRouting.preferredNonProjectWorkspace(
            from: ["3", "2", "1"],
            hasWindows: { _ in true }
        )
        XCTAssertEqual(result, "3")
    }
}
