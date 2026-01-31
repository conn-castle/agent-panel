import Foundation

/// Summary of a configured project used by the switcher UI.
public struct ProjectListItem: Equatable, Sendable {
    public let id: String
    public let name: String
    public let path: String
    public let colorHex: String

    /// Creates a project list item.
    /// - Parameters:
    ///   - id: Project identifier.
    ///   - name: Human-readable project name.
    ///   - path: Project path on disk.
    ///   - colorHex: Project color in `#RRGGBB` format.
    public init(id: String, name: String, path: String, colorHex: String) {
        self.id = id
        self.name = name
        self.path = path
        self.colorHex = colorHex
    }
}

/// Successful result from the project catalog loader.
public struct ProjectCatalogResult: Equatable, Sendable {
    public let projects: [ProjectListItem]
    public let warnings: [DoctorFinding]

    /// Creates a project catalog result.
    /// - Parameters:
    ///   - projects: Ordered list of project summaries (preserves config order).
    ///   - warnings: Non-fatal config warnings.
    public init(projects: [ProjectListItem], warnings: [DoctorFinding]) {
        self.projects = projects
        self.warnings = warnings
    }
}

/// Error returned when the project catalog cannot be loaded.
public struct ProjectCatalogError: Error, Equatable, Sendable {
    public let findings: [DoctorFinding]

    /// Creates a catalog error.
    /// - Parameter findings: Failure findings describing why the catalog could not be loaded.
    public init(findings: [DoctorFinding]) {
        self.findings = findings
    }
}

/// Loads the project catalog for the switcher UI.
public struct ProjectCatalogService {
    private let configLoader: ConfigLoader

    /// Creates a project catalog service.
    /// - Parameters:
    ///   - paths: File system paths for ProjectWorkspaces.
    ///   - fileSystem: File system accessor.
    public init(
        paths: ProjectWorkspacesPaths = .defaultPaths(),
        fileSystem: FileSystem = DefaultFileSystem()
    ) {
        self.configLoader = ConfigLoader(paths: paths, fileSystem: fileSystem)
    }

    /// Returns the ordered list of projects for the switcher UI.
    /// - Returns: Catalog result or failure findings when config cannot be loaded.
    public func listProjects() -> Result<ProjectCatalogResult, ProjectCatalogError> {
        switch configLoader.load() {
        case .failure(let findings):
            return .failure(ProjectCatalogError(findings: findings))
        case .success(let outcome, let warnings):
            guard let config = outcome.config else {
                return .failure(ProjectCatalogError(findings: outcome.findings))
            }
            let projects = config.projects.map { project in
                ProjectListItem(
                    id: project.id,
                    name: project.name,
                    path: project.path,
                    colorHex: project.colorHex
                )
            }
            return .success(ProjectCatalogResult(projects: projects, warnings: warnings))
        }
    }
}
