import Foundation

/// Loads and parses the ProjectWorkspaces configuration file.
struct ConfigLoader {
    private let paths: ProjectWorkspacesPaths
    private let fileSystem: FileSystem
    private let parser: ConfigParser

    /// Creates a config loader with injected dependencies.
    /// - Parameters:
    ///   - paths: File system paths for ProjectWorkspaces.
    ///   - fileSystem: File system accessor.
    ///   - parser: TOML config parser.
    init(
        paths: ProjectWorkspacesPaths,
        fileSystem: FileSystem,
        parser: ConfigParser = ConfigParser()
    ) {
        self.paths = paths
        self.fileSystem = fileSystem
        self.parser = parser
    }

    /// Loads and parses config.toml, returning warnings or failure findings.
    /// - Returns: Parsed config outcome with warnings, or failure findings.
    func load() -> PwctlOutcome<ConfigParseOutcome> {
        let configURL = paths.configFile
        guard fileSystem.fileExists(at: configURL) else {
            return .failure(findings: [
                DoctorFinding(
                    severity: .fail,
                    title: "Config file missing",
                    detail: configURL.path,
                    fix: "Create config.toml at the expected path (see README for the schema)."
                )
            ])
        }

        let data: Data
        do {
            data = try fileSystem.readFile(at: configURL)
        } catch {
            return .failure(findings: [
                DoctorFinding(
                    severity: .fail,
                    title: "Config file could not be read",
                    detail: "\(configURL.path): \(error)",
                    fix: "Ensure config.toml is readable and retry."
                )
            ])
        }

        guard let toml = String(data: data, encoding: .utf8) else {
            return .failure(findings: [
                DoctorFinding(
                    severity: .fail,
                    title: "Config file is not valid UTF-8",
                    detail: configURL.path,
                    fix: "Ensure config.toml is saved as UTF-8 text."
                )
            ])
        }

        let outcome = parser.parse(toml: toml)
        guard outcome.config != nil else {
            return .failure(findings: outcome.findings)
        }

        let warnings = outcome.findings.filter { $0.severity == .warn }
        return .success(output: outcome, warnings: warnings)
    }
}
