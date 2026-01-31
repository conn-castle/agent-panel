import Foundation

/// Versioned state schema for persisted window layouts and managed windows.
enum LayoutStateVersion: Int, Codable {
    case v1 = 1

    static let current: LayoutStateVersion = .v1
}

/// Root state payload stored in `state.json`.
struct LayoutState: Codable, Equatable {
    let version: LayoutStateVersion
    var projects: [String: ProjectState]

    /// Creates a layout state payload.
    /// - Parameters:
    ///   - version: Schema version.
    ///   - projects: Project state map keyed by project id.
    init(version: LayoutStateVersion = .current, projects: [String: ProjectState] = [:]) {
        self.version = version
        self.projects = projects
    }

    static func empty() -> LayoutState {
        LayoutState()
    }
}

/// State persisted for a single project.
struct ProjectState: Codable, Equatable {
    var managed: ManagedWindowState?
    var layouts: LayoutsByDisplayMode

    init(
        managed: ManagedWindowState? = nil,
        layouts: LayoutsByDisplayMode = LayoutsByDisplayMode()
    ) {
        self.managed = managed
        self.layouts = layouts
    }
}

/// Managed window identifiers persisted for a project.
struct ManagedWindowState: Codable, Equatable {
    let ideWindowId: Int?
    let chromeWindowId: Int?

    init(ideWindowId: Int?, chromeWindowId: Int?) {
        self.ideWindowId = ideWindowId
        self.chromeWindowId = chromeWindowId
    }
}

/// Layouts stored per display mode.
struct LayoutsByDisplayMode: Codable, Equatable {
    var laptop: ProjectLayout?
    var ultrawide: ProjectLayout?

    init(laptop: ProjectLayout? = nil, ultrawide: ProjectLayout? = nil) {
        self.laptop = laptop
        self.ultrawide = ultrawide
    }

    func layout(for mode: DisplayMode) -> ProjectLayout? {
        switch mode {
        case .laptop:
            return laptop
        case .ultrawide:
            return ultrawide
        }
    }

    mutating func setLayout(_ layout: ProjectLayout, for mode: DisplayMode) {
        switch mode {
        case .laptop:
            laptop = layout
        case .ultrawide:
            ultrawide = layout
        }
    }
}
