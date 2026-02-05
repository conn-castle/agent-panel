import Foundation
import TOMLDecoder

// MARK: - ID Normalization

/// Normalizes identifiers (project names, workspace names) to a consistent format.
///
/// Used for deriving project IDs from names and normalizing workspace names.
/// Rules: lowercase, non-alphanumeric characters become hyphens, consecutive hyphens collapsed, trimmed.
enum IdNormalizer {
    /// Allowed characters in a normalized ID.
    private static let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")

    /// Normalizes a string to a valid identifier.
    /// - Parameter value: Raw string (e.g., project name, workspace name).
    /// - Returns: Normalized identifier (lowercase, hyphens for separators, no leading/trailing hyphens).
    static func normalize(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        var normalized = ""
        var previousWasHyphen = false

        for scalar in trimmed.lowercased().unicodeScalars {
            if allowedCharacters.contains(scalar) {
                normalized.unicodeScalars.append(scalar)
                previousWasHyphen = false
            } else if !previousWasHyphen {
                normalized.append("-")
                previousWasHyphen = true
            }
        }

        let hyphenSet = CharacterSet(charactersIn: "-")
        return normalized.trimmingCharacters(in: hyphenSet)
    }

    /// Checks if an identifier is valid (non-empty after normalization).
    /// - Parameter value: String to check.
    /// - Returns: True if the string normalizes to a non-empty identifier.
    static func isValid(_ value: String) -> Bool {
        !normalize(value).isEmpty
    }

    /// Reserved identifiers that cannot be used.
    static let reserved: Set<String> = ["inbox"]

    /// Checks if an identifier is reserved.
    /// - Parameter normalizedId: Already-normalized identifier.
    /// - Returns: True if the identifier is reserved.
    static func isReserved(_ normalizedId: String) -> Bool {
        reserved.contains(normalizedId)
    }
}

// MARK: - Config Models

/// Full parsed configuration for AgentPanel.
public struct Config: Equatable, Sendable {
    public let projects: [ProjectConfig]

    init(projects: [ProjectConfig]) {
        self.projects = projects
    }
}

/// Project-level configuration values.
public struct ProjectConfig: Equatable, Sendable {
    public let id: String
    public let name: String
    public let path: String
    public let color: String
    public let useAgentLayer: Bool

    init(id: String, name: String, path: String, color: String, useAgentLayer: Bool) {
        self.id = id
        self.name = name
        self.path = path
        self.color = color
        self.useAgentLayer = useAgentLayer
    }
}

/// RGB components for named project colors.
public struct ProjectColorRGB: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// Supported named colors for project color values.
public enum ProjectColorPalette {
    static let named: [String: ProjectColorRGB] = [
        "black": ProjectColorRGB(red: 0.0, green: 0.0, blue: 0.0),
        "blue": ProjectColorRGB(red: 0.0, green: 0.0, blue: 1.0),
        "brown": ProjectColorRGB(red: 0.6471, green: 0.1647, blue: 0.1647),
        "cyan": ProjectColorRGB(red: 0.0, green: 1.0, blue: 1.0),
        "gray": ProjectColorRGB(red: 0.5020, green: 0.5020, blue: 0.5020),
        "grey": ProjectColorRGB(red: 0.5020, green: 0.5020, blue: 0.5020),
        "green": ProjectColorRGB(red: 0.0, green: 0.5020, blue: 0.0),
        "indigo": ProjectColorRGB(red: 0.2941, green: 0.0, blue: 0.5098),
        "orange": ProjectColorRGB(red: 1.0, green: 0.6471, blue: 0.0),
        "pink": ProjectColorRGB(red: 1.0, green: 0.7529, blue: 0.7961),
        "purple": ProjectColorRGB(red: 0.5020, green: 0.0, blue: 0.5020),
        "red": ProjectColorRGB(red: 1.0, green: 0.0, blue: 0.0),
        "teal": ProjectColorRGB(red: 0.0, green: 0.5020, blue: 0.5020),
        "white": ProjectColorRGB(red: 1.0, green: 1.0, blue: 1.0),
        "yellow": ProjectColorRGB(red: 1.0, green: 1.0, blue: 0.0)
    ]

    static let sortedNames: [String] = named.keys.sorted()

    /// Resolves a color string (hex or named) to RGB components.
    /// - Parameter value: A hex color (#RRGGBB) or named color string.
    /// - Returns: RGB components if valid, nil otherwise.
    public static func resolve(_ value: String) -> ProjectColorRGB? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if let hex = parseHex(trimmed) {
            return hex
        }

        return named[trimmed.lowercased()]
    }

    /// Parses a hex color string (#RRGGBB) to RGB components.
    private static func parseHex(_ value: String) -> ProjectColorRGB? {
        guard value.count == 7, value.hasPrefix("#") else {
            return nil
        }

        let hexDigits = String(value.dropFirst())
        guard let intValue = Int(hexDigits, radix: 16) else {
            return nil
        }

        let red = Double((intValue >> 16) & 0xFF) / 255.0
        let green = Double((intValue >> 8) & 0xFF) / 255.0
        let blue = Double(intValue & 0xFF) / 255.0
        return ProjectColorRGB(red: red, green: green, blue: blue)
    }
}

// MARK: - Config Loading

/// Kind of config loading error for programmatic handling.
enum ConfigErrorKind: String, Equatable, Sendable {
    /// Config file does not exist (starter config was created).
    case fileNotFound
    /// Failed to create starter config file.
    case createFailed
    /// Failed to read existing config file.
    case readFailed
}

/// Errors emitted by config loading operations.
struct ConfigError: Error, Equatable {
    let kind: ConfigErrorKind
    let message: String

    init(kind: ConfigErrorKind, message: String) {
        self.kind = kind
        self.message = message
    }
}

/// Result of loading and parsing configuration.
struct ConfigLoadResult: Equatable, Sendable {
    /// Parsed config when successful.
    let config: Config?
    /// Findings from parsing (warnings and errors).
    let findings: [ConfigFinding]
    /// Parsed projects (may be partial on error).
    let projects: [ProjectConfig]
    /// True if the TOML could not be parsed (syntax error vs validation error).
    let hasParseError: Bool

    init(
        config: Config?,
        findings: [ConfigFinding],
        projects: [ProjectConfig] = [],
        hasParseError: Bool = false
    ) {
        self.config = config
        self.findings = findings
        self.projects = projects
        self.hasParseError = hasParseError
    }
}

/// Severity level for config findings.
public enum ConfigFindingSeverity: String, CaseIterable, Sendable {
    case pass = "PASS"
    case warn = "WARN"
    case fail = "FAIL"
}

/// A single finding from config parsing.
public struct ConfigFinding: Equatable, Sendable {
    public let severity: ConfigFindingSeverity
    public let title: String
    let detail: String?
    let fix: String?

    init(severity: ConfigFindingSeverity, title: String, detail: String? = nil, fix: String? = nil) {
        self.severity = severity
        self.title = title
        self.detail = detail
        self.fix = fix
    }
}

/// Loads and parses the AgentPanel configuration file.
struct ConfigLoader {
    private static let starterConfigTemplate = """
# AgentPanel configuration
#
# Each [[project]] entry describes one local git repo.
# - name: Display name (id is derived by lowercasing and replacing non [a-z0-9] with '-')
# - path: Absolute path to the repo on this machine
# - color: "#RRGGBB" or a named color (\(ProjectColorPalette.sortedNames.joined(separator: ", ")))
# - useAgentLayer: true if the repo uses an .agent-layer folder
#
# Example:
# [[project]]
# name = "AgentPanel"
# path = "/Users/you/src/agent-panel"
# color = "indigo"
# useAgentLayer = true
"""

    /// Loads and parses the default config file.
    static func loadDefault() -> Result<ConfigLoadResult, ConfigError> {
        let url = DataPaths.default().configFile
        return load(from: url)
    }

    /// Loads and parses a config file at the given URL.
    static func load(from url: URL) -> Result<ConfigLoadResult, ConfigError> {
        let path = url.path
        if !FileManager.default.fileExists(atPath: path) {
            do {
                try createStarterConfig(at: url)
            } catch {
                return .failure(ConfigError(
                    kind: .createFailed,
                    message: "Failed to create config at \(path): \(error.localizedDescription)"
                ))
            }
            return .failure(ConfigError(
                kind: .fileNotFound,
                message: "Config file not found. Created a starter config at \(path). Edit it to add projects."
            ))
        }

        let raw: String
        do {
            raw = try String(contentsOf: url, encoding: .utf8)
        } catch {
            return .failure(ConfigError(
                kind: .readFailed,
                message: "Failed to read config at \(path): \(error.localizedDescription)"
            ))
        }

        return .success(ConfigParser.parse(toml: raw))
    }

    /// Writes a starter config template at the provided location.
    private static func createStarterConfig(at url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try starterConfigTemplate.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - Config Parser

/// Parses TOML config into typed models with validation.
struct ConfigParser {
    static func parse(toml: String) -> ConfigLoadResult {
        do {
            let table = try TOMLTable(source: toml)
            return parse(table: table)
        } catch {
            return ConfigLoadResult(
                config: nil,
                findings: [
                    ConfigFinding(
                        severity: .fail,
                        title: "Config TOML parse error",
                        detail: String(describing: error),
                        fix: "Fix the TOML syntax in config.toml."
                    )
                ],
                hasParseError: true
            )
        }
    }

    private static func parse(table: TOMLTable) -> ConfigLoadResult {
        var findings: [ConfigFinding] = []

        let projectOutcomes = parseProjects(table: table, findings: &findings)
        let parsedProjects = projectOutcomes.compactMap { $0.config }

        let validationFailed = findings.contains { $0.severity == .fail }
        let config: Config? = validationFailed ? nil : Config(projects: parsedProjects)

        return ConfigLoadResult(
            config: config,
            findings: findings,
            projects: parsedProjects
        )
    }

    // MARK: - Project Parsing

    private struct ProjectOutcome {
        let config: ProjectConfig?
    }

    private static func parseProjects(
        table: TOMLTable,
        findings: inout [ConfigFinding]
    ) -> [ProjectOutcome] {
        guard table.contains(key: "project") else {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "No [[project]] entries",
                fix: "Add at least one [[project]] entry to config.toml."
            ))
            return []
        }

        guard let projectsArray = try? table.array(forKey: "project") else {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "project must be an array of tables",
                fix: "Use [[project]] entries in config.toml."
            ))
            return []
        }

        if projectsArray.count == 0 {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "No [[project]] entries",
                fix: "Add at least one [[project]] entry to config.toml."
            ))
            return []
        }

        var outcomes: [ProjectOutcome] = []
        var seenIds: [String: Int] = [:]

        for index in 0..<projectsArray.count {
            guard let projectTable = try? projectsArray.table(atIndex: index) else {
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "project[\(index)] must be a table",
                    fix: "Ensure each [[project]] entry is a TOML table."
                ))
                outcomes.append(ProjectOutcome(config: nil))
                continue
            }

            let outcome = parseProject(
                table: projectTable,
                index: index,
                seenIds: &seenIds,
                findings: &findings
            )
            outcomes.append(outcome)
        }

        return outcomes
    }

    private static func parseProject(
        table: TOMLTable,
        index: Int,
        seenIds: inout [String: Int],
        findings: inout [ConfigFinding]
    ) -> ProjectOutcome {
        var projectIsValid = true

        let name = readNonEmptyString(
            from: table,
            key: "name",
            label: "project[\(index)].name",
            findings: &findings
        )
        let path = readNonEmptyString(
            from: table,
            key: "path",
            label: "project[\(index)].path",
            findings: &findings
        )
        let color = readNonEmptyString(
            from: table,
            key: "color",
            label: "project[\(index)].color",
            findings: &findings
        )
        let useAgentLayer = readBool(
            from: table,
            key: "useAgentLayer",
            label: "project[\(index)].useAgentLayer",
            findings: &findings
        )

        // Name validation + id derivation
        var derivedId: String?
        if let name {
            let normalized = IdNormalizer.normalize(name)
            if normalized.isEmpty {
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "project[\(index)].name cannot derive an id",
                    detail: "Normalized id was empty after removing invalid characters.",
                    fix: "Use a name with letters or numbers so an id can be derived."
                ))
                projectIsValid = false
            } else if IdNormalizer.isReserved(normalized) {
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "project[\(index)].id is reserved",
                    detail: "The id '\(normalized)' is reserved.",
                    fix: "Choose a different project name so the derived id is not reserved."
                ))
                projectIsValid = false
            } else if let existingIndex = seenIds[normalized] {
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "Duplicate project.id: \(normalized)",
                    detail: "Derived from project indexes \(existingIndex) and \(index).",
                    fix: "Ensure project names normalize to unique ids."
                ))
                projectIsValid = false
            } else {
                derivedId = normalized
                seenIds[normalized] = index
            }
        } else {
            projectIsValid = false
        }

        // Color validation
        var normalizedColor: String?
        if let color {
            let trimmed = color.trimmingCharacters(in: .whitespacesAndNewlines)
            if isValidColorHex(trimmed) {
                normalizedColor = trimmed
            } else {
                let lowercased = trimmed.lowercased()
                if ProjectColorPalette.named.keys.contains(lowercased) {
                    normalizedColor = lowercased
                } else {
                    findings.append(ConfigFinding(
                        severity: .fail,
                        title: "project[\(index)].color is invalid",
                        detail: "Color must be #RRGGBB or a named color.",
                        fix: "Use a hex color or one of: \(ProjectColorPalette.sortedNames.joined(separator: ", "))."
                    ))
                    projectIsValid = false
                }
            }
        } else {
            projectIsValid = false
        }

        guard let name, let path, let normalizedColor, let useAgentLayer, let derivedId, projectIsValid else {
            return ProjectOutcome(config: nil)
        }

        let projectConfig = ProjectConfig(
            id: derivedId,
            name: name,
            path: path,
            color: normalizedColor,
            useAgentLayer: useAgentLayer
        )
        return ProjectOutcome(config: projectConfig)
    }

    // MARK: - Validation Helpers

    private static func isValidColorHex(_ value: String) -> Bool {
        guard value.count == 7, value.hasPrefix("#") else {
            return false
        }
        let hexDigits = value.dropFirst()
        return hexDigits.allSatisfy { char in
            switch char {
            case "0"..."9", "a"..."f", "A"..."F":
                return true
            default:
                return false
            }
        }
    }

    /// Reads a required non-empty string value or records a failure.
    private static func readNonEmptyString(
        from table: TOMLTable,
        key: String,
        label: String,
        findings: inout [ConfigFinding]
    ) -> String? {
        if !table.contains(key: key) {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "\(label) is missing",
                fix: "Set \(label) to a non-empty string."
            ))
            return nil
        }

        guard let value = try? table.string(forKey: key) else {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "\(label) must be a string",
                fix: "Set \(label) to a non-empty string."
            ))
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "\(label) is empty",
                fix: "Set \(label) to a non-empty string."
            ))
            return nil
        }

        return trimmed
    }

    /// Reads a required boolean value or records a failure.
    private static func readBool(
        from table: TOMLTable,
        key: String,
        label: String,
        findings: inout [ConfigFinding]
    ) -> Bool? {
        if !table.contains(key: key) {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "\(label) is missing",
                fix: "Set \(label) to true or false."
            ))
            return nil
        }

        guard let value = try? table.bool(forKey: key) else {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "\(label) must be a boolean",
                fix: "Set \(label) to true or false."
            ))
            return nil
        }

        return value
    }
}

// MARK: - ConfigLoadError

/// Errors that can occur when loading configuration via `Config.loadDefault()`.
///
/// This is the public error type for the simplified config loading API.
public enum ConfigLoadError: Error, Equatable, Sendable {
    /// Config file not found at the expected path.
    case fileNotFound(path: String)

    /// Config file exists but could not be read.
    case readFailed(path: String, detail: String)

    /// Config file could not be parsed as valid TOML.
    case parseFailed(detail: String)

    /// Config file parsed but failed validation.
    case validationFailed(findings: [ConfigFinding])
}

// MARK: - Config Public Loading API

extension Config {
    /// Loads and validates configuration from the default path.
    ///
    /// This is the recommended entry point for App to load configuration.
    /// It provides a simplified API that returns either a valid Config or
    /// a descriptive error. Uses `ConfigLoader` as the single source of truth.
    ///
    /// - Returns: Result with validated Config or ConfigLoadError.
    public static func loadDefault() -> Result<Config, ConfigLoadError> {
        let path = DataPaths.default().configFile.path

        // Use ConfigLoader as single source of truth
        switch ConfigLoader.loadDefault() {
        case .failure(let error):
            // Translate ConfigError to ConfigLoadError using the error kind.
            switch error.kind {
            case .fileNotFound:
                return .failure(.fileNotFound(path: path))
            case .createFailed, .readFailed:
                return .failure(.readFailed(path: path, detail: error.message))
            }

        case .success(let result):
            // Check for parse or validation errors
            let failures = result.findings.filter { $0.severity == .fail }
            if !failures.isEmpty || result.config == nil {
                // Use the explicit flag instead of string matching
                if result.hasParseError, let parseError = failures.first {
                    return .failure(.parseFailed(detail: parseError.detail ?? parseError.title))
                }
                return .failure(.validationFailed(findings: failures))
            }

            guard let config = result.config else {
                return .failure(.validationFailed(findings: result.findings))
            }

            return .success(config)
        }
    }
}
