/// Project sorting and filtering for the switcher.
///
/// Sorting rules:
/// - Empty query: recency of activation (most recent first), then config order
/// - Non-empty query: name-prefix matches first, then recency, then config order
public enum ProjectSorter {

    /// Sorts and optionally filters projects based on search query and focus history.
    ///
    /// - Parameters:
    ///   - projects: All available projects (in config order)
    ///   - query: Search query (empty = no filter, just sort by recency)
    ///   - recentActivations: Focus events for projectActivated, newest first
    /// - Returns: Filtered (if query non-empty) and sorted projects
    public static func sortedProjects(
        _ projects: [ProjectConfig],
        query: String,
        recentActivations: [FocusEvent]
    ) -> [ProjectConfig] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Build recency map: projectId -> rank (0 = most recent)
        var recencyRank: [String: Int] = [:]
        for (index, event) in recentActivations.enumerated() {
            guard let projectId = event.projectId else { continue }
            // Only keep the first (most recent) occurrence
            if recencyRank[projectId] == nil {
                recencyRank[projectId] = index
            }
        }

        // Build config order map: projectId -> index
        var configOrder: [String: Int] = [:]
        for (index, project) in projects.enumerated() {
            configOrder[project.id] = index
        }

        // Sentinel values for projects without history (sort after all with history)
        let noHistoryRank = recentActivations.count

        if trimmedQuery.isEmpty {
            // No filter, just sort by recency then config order
            return projects.sorted { a, b in
                let rankA = recencyRank[a.id] ?? noHistoryRank
                let rankB = recencyRank[b.id] ?? noHistoryRank
                if rankA != rankB {
                    return rankA < rankB
                }
                // Fall back to config order
                let configA = configOrder[a.id] ?? Int.max
                let configB = configOrder[b.id] ?? Int.max
                return configA < configB
            }
        }

        // Filter and compute match type
        let matched = projects.compactMap { project -> (project: ProjectConfig, matchType: MatchType)? in
            let matchType = Self.matchType(project: project, query: trimmedQuery)
            guard matchType != .none else { return nil }
            return (project, matchType)
        }

        // Sort by: match type (prefix > infix), then recency, then config order
        let sorted = matched.sorted { a, b in
            // Prefix matches come before infix matches
            if a.matchType != b.matchType {
                return a.matchType.rawValue < b.matchType.rawValue
            }
            // Among equal match types, sort by recency
            let rankA = recencyRank[a.project.id] ?? noHistoryRank
            let rankB = recencyRank[b.project.id] ?? noHistoryRank
            if rankA != rankB {
                return rankA < rankB
            }
            // Fall back to config order
            let configA = configOrder[a.project.id] ?? Int.max
            let configB = configOrder[b.project.id] ?? Int.max
            return configA < configB
        }

        return sorted.map { $0.project }
    }

    // MARK: - Private

    private enum MatchType: Int {
        case namePrefix = 0  // Best match: name starts with query
        case idPrefix = 1    // Second: id starts with query
        case nameInfix = 2   // Third: name contains query (not prefix)
        case idInfix = 3     // Fourth: id contains query (not prefix)
        case none = 99       // No match
    }

    private static func matchType(project: ProjectConfig, query: String) -> MatchType {
        let nameLower = project.name.lowercased()
        let idLower = project.id.lowercased()

        if nameLower.hasPrefix(query) {
            return .namePrefix
        }
        if idLower.hasPrefix(query) {
            return .idPrefix
        }
        if nameLower.contains(query) {
            return .nameInfix
        }
        if idLower.contains(query) {
            return .idInfix
        }
        return .none
    }
}
