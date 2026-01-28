import XCTest

@testable import ProjectWorkspacesCore

final class ProjectFilterTests: XCTestCase {
    func testFilterReturnsAllWhenQueryIsEmpty() {
        let projects = [
            ProjectListItem(id: "alpha", name: "Alpha", path: "/tmp/alpha", colorHex: "#000000"),
            ProjectListItem(id: "bravo", name: "Bravo", path: "/tmp/bravo", colorHex: "#111111")
        ]

        let filter = ProjectFilter()
        let result = filter.filter(projects: projects, query: " ")

        XCTAssertEqual(result, projects)
    }

    func testFilterMatchesIdOrNameCaseInsensitive() {
        let projects = [
            ProjectListItem(id: "alpha", name: "Alpha", path: "/tmp/alpha", colorHex: "#000000"),
            ProjectListItem(id: "bravo", name: "Bravo", path: "/tmp/bravo", colorHex: "#111111"),
            ProjectListItem(id: "charlie", name: "Design", path: "/tmp/charlie", colorHex: "#222222")
        ]

        let filter = ProjectFilter()

        XCTAssertEqual(filter.filter(projects: projects, query: "BR"), [projects[1]])
        XCTAssertEqual(filter.filter(projects: projects, query: "sign"), [projects[2]])
        XCTAssertEqual(filter.filter(projects: projects, query: "a"), projects)
    }
}
