import XCTest
@testable import AgentPanelCore

final class ProjectSorterTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeProject(id: String, name: String) -> ProjectConfig {
        ProjectConfig(id: id, name: name, path: "/tmp/\(id)", color: "blue", useAgentLayer: false)
    }

    private func makeActivationEvent(projectId: String, hoursAgo: Int = 0) -> FocusEvent {
        let timestamp = Date().addingTimeInterval(TimeInterval(-hoursAgo * 3600))
        return FocusEvent(
            id: UUID(),
            kind: .projectActivated,
            timestamp: timestamp,
            projectId: projectId,
            windowId: nil,
            appBundleId: nil,
            metadata: nil
        )
    }

    // MARK: - Empty Query Tests

    func testEmptyQuery_NoHistory_ReturnsConfigOrder() {
        let projects = [
            makeProject(id: "zebra", name: "Zebra"),
            makeProject(id: "alpha", name: "Alpha"),
            makeProject(id: "beta", name: "Beta")
        ]

        let result = ProjectSorter.sortedProjects(projects, query: "", recentActivations: [])

        XCTAssertEqual(result.map { $0.id }, ["zebra", "alpha", "beta"])
    }

    func testEmptyQuery_WithHistory_RecentFirst() {
        let projects = [
            makeProject(id: "zebra", name: "Zebra"),
            makeProject(id: "alpha", name: "Alpha"),
            makeProject(id: "beta", name: "Beta")
        ]
        // Alpha activated most recently, then beta
        let activations = [
            makeActivationEvent(projectId: "alpha", hoursAgo: 1),
            makeActivationEvent(projectId: "beta", hoursAgo: 2)
        ]

        let result = ProjectSorter.sortedProjects(projects, query: "", recentActivations: activations)

        // Alpha (recent), Beta (older), Zebra (no history, config order)
        XCTAssertEqual(result.map { $0.id }, ["alpha", "beta", "zebra"])
    }

    func testEmptyQuery_WhitespaceOnly_TreatedAsEmpty() {
        let projects = [
            makeProject(id: "alpha", name: "Alpha"),
            makeProject(id: "beta", name: "Beta")
        ]
        let activations = [makeActivationEvent(projectId: "beta")]

        let result = ProjectSorter.sortedProjects(projects, query: "   \t\n  ", recentActivations: activations)

        // Treated as empty query: beta (recent) before alpha
        XCTAssertEqual(result.map { $0.id }, ["beta", "alpha"])
    }

    // MARK: - Search Query Tests

    func testQuery_NoMatches_ReturnsEmpty() {
        let projects = [
            makeProject(id: "alpha", name: "Alpha"),
            makeProject(id: "beta", name: "Beta")
        ]

        let result = ProjectSorter.sortedProjects(projects, query: "xyz", recentActivations: [])

        XCTAssertTrue(result.isEmpty)
    }

    func testQuery_CaseInsensitive() {
        let projects = [
            makeProject(id: "agent-panel", name: "AgentPanel")
        ]

        let result = ProjectSorter.sortedProjects(projects, query: "AGENT", recentActivations: [])

        XCTAssertEqual(result.map { $0.id }, ["agent-panel"])
    }

    func testQuery_MatchesName() {
        let projects = [
            makeProject(id: "ap", name: "AgentPanel"),
            makeProject(id: "other", name: "Other")
        ]

        let result = ProjectSorter.sortedProjects(projects, query: "agent", recentActivations: [])

        XCTAssertEqual(result.map { $0.id }, ["ap"])
    }

    func testQuery_MatchesId() {
        let projects = [
            makeProject(id: "agent-panel", name: "My Project")
        ]

        let result = ProjectSorter.sortedProjects(projects, query: "agent", recentActivations: [])

        XCTAssertEqual(result.map { $0.id }, ["agent-panel"])
    }

    func testQuery_NamePrefixBeforeInfix() {
        let projects = [
            makeProject(id: "my-agent", name: "My Agent Tool"),    // infix match on "agent"
            makeProject(id: "agent-panel", name: "AgentPanel")     // prefix match on "agent"
        ]

        let result = ProjectSorter.sortedProjects(projects, query: "agent", recentActivations: [])

        // Prefix match comes first
        XCTAssertEqual(result.map { $0.id }, ["agent-panel", "my-agent"])
    }

    func testQuery_IdPrefixBeforeIdInfix() {
        let projects = [
            makeProject(id: "my-agent", name: "Unrelated Name"),     // id infix
            makeProject(id: "agent-panel", name: "Other Name")       // id prefix
        ]

        let result = ProjectSorter.sortedProjects(projects, query: "agent", recentActivations: [])

        // ID prefix before ID infix
        XCTAssertEqual(result.map { $0.id }, ["agent-panel", "my-agent"])
    }

    func testQuery_NamePrefixBeforeIdPrefix() {
        let projects = [
            makeProject(id: "agent-id", name: "Unrelated"),     // id prefix only
            makeProject(id: "other", name: "AgentPanel")        // name prefix
        ]

        let result = ProjectSorter.sortedProjects(projects, query: "agent", recentActivations: [])

        // Name prefix beats id prefix
        XCTAssertEqual(result.map { $0.id }, ["other", "agent-id"])
    }

    // MARK: - Recency Tiebreaker Tests

    func testQuery_RecencyTiebreaker_AmongPrefixMatches() {
        let projects = [
            makeProject(id: "agent-one", name: "AgentOne"),
            makeProject(id: "agent-two", name: "AgentTwo")
        ]
        // agent-two activated more recently
        let activations = [
            makeActivationEvent(projectId: "agent-two", hoursAgo: 1),
            makeActivationEvent(projectId: "agent-one", hoursAgo: 2)
        ]

        let result = ProjectSorter.sortedProjects(projects, query: "agent", recentActivations: activations)

        // Both are prefix matches, so recency determines order
        XCTAssertEqual(result.map { $0.id }, ["agent-two", "agent-one"])
    }

    func testQuery_ConfigOrderTiebreaker_NoHistory() {
        let projects = [
            makeProject(id: "agent-zebra", name: "AgentZebra"),
            makeProject(id: "agent-alpha", name: "AgentAlpha")
        ]

        let result = ProjectSorter.sortedProjects(projects, query: "agent", recentActivations: [])

        // Both prefix matches, no history, so config order preserved
        XCTAssertEqual(result.map { $0.id }, ["agent-zebra", "agent-alpha"])
    }

    // MARK: - Edge Cases

    func testQuery_MultipleActivations_OnlyFirstCounts() {
        let projects = [
            makeProject(id: "alpha", name: "Alpha"),
            makeProject(id: "beta", name: "Beta")
        ]
        // Alpha activated twice, but beta's single activation is more recent
        let activations = [
            makeActivationEvent(projectId: "beta", hoursAgo: 1),
            makeActivationEvent(projectId: "alpha", hoursAgo: 2),
            makeActivationEvent(projectId: "alpha", hoursAgo: 3)
        ]

        let result = ProjectSorter.sortedProjects(projects, query: "", recentActivations: activations)

        // Beta is more recent (hoursAgo: 1 vs 2)
        XCTAssertEqual(result.map { $0.id }, ["beta", "alpha"])
    }

    func testQuery_ActivationForUnknownProject_Ignored() {
        let projects = [
            makeProject(id: "alpha", name: "Alpha")
        ]
        let activations = [
            makeActivationEvent(projectId: "deleted-project", hoursAgo: 1),
            makeActivationEvent(projectId: "alpha", hoursAgo: 2)
        ]

        let result = ProjectSorter.sortedProjects(projects, query: "", recentActivations: activations)

        // Only alpha in results, deleted-project activation ignored
        XCTAssertEqual(result.map { $0.id }, ["alpha"])
    }

    func testQuery_LeadingTrailingWhitespace_Trimmed() {
        let projects = [
            makeProject(id: "agent", name: "Agent")
        ]

        let result = ProjectSorter.sortedProjects(projects, query: "  agent  ", recentActivations: [])

        XCTAssertEqual(result.map { $0.id }, ["agent"])
    }

    func testEmptyProjects_ReturnsEmpty() {
        let result = ProjectSorter.sortedProjects([], query: "test", recentActivations: [])
        XCTAssertTrue(result.isEmpty)
    }
}
