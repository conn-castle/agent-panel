import Foundation

/// Filters project list items based on a text query.
public struct ProjectFilter: Sendable {
    /// Creates a project filter.
    public init() {}

    /// Filters projects by case-insensitive substring match on id or name.
    /// - Parameters:
    ///   - projects: Ordered list of project summaries.
    ///   - query: User-entered query string.
    /// - Returns: Filtered list preserving the original order.
    public func filter(projects: [ProjectListItem], query: String) -> [ProjectListItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return projects
        }

        let needle = trimmedQuery.lowercased()
        return projects.filter { project in
            project.id.lowercased().contains(needle)
                || project.name.lowercased().contains(needle)
        }
    }
}
