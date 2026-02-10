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

/// Global Chrome tab configuration.
public struct ChromeConfig: Equatable, Sendable {
    /// URLs always opened as leftmost tabs on every fresh Chrome window creation.
    public let pinnedTabs: [String]
    /// URLs opened when no tab history exists for a project.
    public let defaultTabs: [String]
    /// When true, auto-detect git remote URL and add it as an always-open tab.
    public let openGitRemote: Bool

    init(pinnedTabs: [String] = [], defaultTabs: [String] = [], openGitRemote: Bool = false) {
        self.pinnedTabs = pinnedTabs
        self.defaultTabs = defaultTabs
        self.openGitRemote = openGitRemote
    }
}

/// Global Agent Layer configuration.
public struct AgentLayerConfig: Equatable, Sendable {
    /// When true, projects default to using Agent Layer unless overridden per-project.
    public let enabled: Bool

    init(enabled: Bool = false) {
        self.enabled = enabled
    }
}

/// Full parsed configuration for AgentPanel.
public struct Config: Equatable, Sendable {
    public let projects: [ProjectConfig]
    public let chrome: ChromeConfig
    public let agentLayer: AgentLayerConfig

    init(projects: [ProjectConfig], chrome: ChromeConfig = ChromeConfig(), agentLayer: AgentLayerConfig = AgentLayerConfig()) {
        self.projects = projects
        self.chrome = chrome
        self.agentLayer = agentLayer
    }
}

/// Project-level configuration values.
public struct ProjectConfig: Equatable, Sendable {
    public let id: String
    public let name: String
    /// Optional VS Code remote authority (e.g., "ssh-remote+user@host") for SSH projects.
    ///
    /// When set, `path` is interpreted as a remote absolute path and VS Code is opened
    /// via a `vscode-remote://` folder URI.
    public let remote: String?
    public let path: String
    public let color: String
    public let useAgentLayer: Bool
    /// Per-project URLs always opened as leftmost tabs.
    public let chromePinnedTabs: [String]
    /// Per-project URLs opened when no tab history exists.
    public let chromeDefaultTabs: [String]

    /// Whether this project uses an SSH remote (Remote-SSH).
    public var isSSH: Bool { remote != nil }

    init(
        id: String,
        name: String,
        remote: String? = nil,
        path: String,
        color: String,
        useAgentLayer: Bool,
        chromePinnedTabs: [String] = [],
        chromeDefaultTabs: [String] = []
    ) {
        self.id = id
        self.name = name
        self.remote = remote
        self.path = path
        self.color = color
        self.useAgentLayer = useAgentLayer
        self.chromePinnedTabs = chromePinnedTabs
        self.chromeDefaultTabs = chromeDefaultTabs
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
# [agentLayer] (optional) — Global Agent Layer settings
# - enabled: default useAgentLayer value for all projects (default: false)
#
# [chrome] (optional) — Global Chrome tab settings
# - pinnedTabs: URLs always opened as leftmost tabs in every fresh Chrome window
# - defaultTabs: URLs opened when no tab history exists for a project
# - openGitRemote: auto-detect git remote URL and add it as an always-open tab (default: false)
#
# Each [[project]] entry describes one git repo (local or SSH remote).
# - name: Display name (id is derived by lowercasing and replacing non [a-z0-9] with '-')
# - remote: (optional) VS Code SSH remote authority (e.g., ssh-remote+user@host)
# - path: Absolute path to the repo (local when remote is absent, remote path when remote is set)
# - color: "#RRGGBB" or a named color (\(ProjectColorPalette.sortedNames.joined(separator: ", ")))
# - useAgentLayer: (optional) override the global agentLayer.enabled default per project
# - chromePinnedTabs: (optional) per-project URLs always opened as leftmost tabs
# - chromeDefaultTabs: (optional) per-project URLs opened when no tab history exists
#
# Example:
#
# [agentLayer]
# enabled = true
#
# [chrome]
# pinnedTabs = ["https://dashboard.example.com"]
# defaultTabs = ["https://docs.example.com"]
# openGitRemote = true
#
# [[project]]
# name = "AgentPanel"
# path = "/Users/you/src/agent-panel"
# color = "indigo"
# chromePinnedTabs = ["https://api.example.com"]
# chromeDefaultTabs = ["https://jira.example.com"]
#
# [[project]]
# name = "Remote ML"
# remote = "ssh-remote+nconn@happy-mac.local"
# path = "/Users/nconn/Documents/git-repos/local-ml"
# color = "teal"
# useAgentLayer = false
"""

    /// Loads and parses the default config file.
    static func loadDefault() -> Result<ConfigLoadResult, ConfigError> {
        loadDefault(dataStore: DataPaths.default())
    }

    /// Loads and parses the default config file using the provided data store.
    static func loadDefault(dataStore: DataPaths) -> Result<ConfigLoadResult, ConfigError> {
        load(from: dataStore.configFile)
    }

    /// Loads and parses a config file at the given URL.
    static func load(from url: URL, fileSystem: FileSystem = DefaultFileSystem()) -> Result<ConfigLoadResult, ConfigError> {
        let path = url.path
        if !fileSystem.fileExists(at: url) {
            do {
                try createStarterConfig(at: url, fileSystem: fileSystem)
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
            let data = try fileSystem.readFile(at: url)
            guard let decoded = String(data: data, encoding: .utf8) else {
                return .failure(ConfigError(
                    kind: .readFailed,
                    message: "Failed to read config at \(path): file is not valid UTF-8."
                ))
            }
            raw = decoded
        } catch {
            return .failure(ConfigError(
                kind: .readFailed,
                message: "Failed to read config at \(path): \(error.localizedDescription)"
            ))
        }

        return .success(ConfigParser.parse(toml: raw))
    }

    /// Writes a starter config template at the provided location.
    private static func createStarterConfig(at url: URL, fileSystem: FileSystem) throws {
        let directory = url.deletingLastPathComponent()
        try fileSystem.createDirectory(at: directory)
        guard let data = starterConfigTemplate.data(using: .utf8) else {
            throw NSError(domain: "ConfigLoader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode starter config as UTF-8"])
        }
        try fileSystem.writeFile(at: url, data: data)
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

        let chromeConfig = parseChromeSection(table: table, findings: &findings)
        let agentLayerConfig = parseAgentLayerSection(table: table, findings: &findings)
        let projectOutcomes = parseProjects(
            table: table,
            globalAgentLayerEnabled: agentLayerConfig.enabled,
            findings: &findings
        )
        let parsedProjects = projectOutcomes.compactMap { $0.config }

        let validationFailed = findings.contains { $0.severity == .fail }
        let config: Config? = validationFailed
            ? nil
            : Config(projects: parsedProjects, chrome: chromeConfig, agentLayer: agentLayerConfig)

        return ConfigLoadResult(
            config: config,
            findings: findings,
            projects: parsedProjects
        )
    }

    // MARK: - Chrome Section Parsing

    private static func parseChromeSection(
        table: TOMLTable,
        findings: inout [ConfigFinding]
    ) -> ChromeConfig {
        guard table.contains(key: "chrome") else {
            return ChromeConfig()
        }

        guard let chromeTable = try? table.table(forKey: "chrome") else {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "[chrome] must be a table",
                fix: "Use [chrome] as a TOML table section."
            ))
            return ChromeConfig()
        }

        let pinnedTabs = readOptionalStringArray(
            from: chromeTable, key: "pinnedTabs",
            label: "chrome.pinnedTabs", findings: &findings
        )
        validateURLs(pinnedTabs, label: "chrome.pinnedTabs", findings: &findings)

        let defaultTabs = readOptionalStringArray(
            from: chromeTable, key: "defaultTabs",
            label: "chrome.defaultTabs", findings: &findings
        )
        validateURLs(defaultTabs, label: "chrome.defaultTabs", findings: &findings)

        let openGitRemote = readOptionalBool(
            from: chromeTable, key: "openGitRemote",
            defaultValue: false,
            label: "chrome.openGitRemote", findings: &findings
        )

        return ChromeConfig(
            pinnedTabs: pinnedTabs,
            defaultTabs: defaultTabs,
            openGitRemote: openGitRemote
        )
    }

    // MARK: - Agent Layer Section Parsing

    private static func parseAgentLayerSection(
        table: TOMLTable,
        findings: inout [ConfigFinding]
    ) -> AgentLayerConfig {
        guard table.contains(key: "agentLayer") else {
            return AgentLayerConfig()
        }

        guard let agentLayerTable = try? table.table(forKey: "agentLayer") else {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "[agentLayer] must be a table",
                fix: "Use [agentLayer] as a TOML table section."
            ))
            return AgentLayerConfig()
        }

        let enabled = readOptionalBool(
            from: agentLayerTable, key: "enabled",
            defaultValue: false,
            label: "agentLayer.enabled", findings: &findings
        )

        return AgentLayerConfig(enabled: enabled)
    }

    // MARK: - Project Parsing

    private struct ProjectOutcome {
        let config: ProjectConfig?
    }

    private static func parseProjects(
        table: TOMLTable,
        globalAgentLayerEnabled: Bool,
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
                globalAgentLayerEnabled: globalAgentLayerEnabled,
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
        globalAgentLayerEnabled: Bool,
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
        let remote = readOptionalNonEmptyString(
            from: table,
            key: "remote",
            label: "project[\(index)].remote",
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
        let useAgentLayer = readOptionalBool(
            from: table,
            key: "useAgentLayer",
            defaultValue: globalAgentLayerEnabled,
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

        // Remote SSH validation (VS Code Remote-SSH)
        var normalizedRemote: String?
        if let remote {
            switch ApSSHHelpers.parseRemoteAuthority(remote) {
            case .success:
                normalizedRemote = remote
            case .failure(.missingPrefix):
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "project[\(index)].remote: SSH remote authority must start with 'ssh-remote+'",
                    fix: "Use format: remote = \"ssh-remote+user@host\""
                ))
                projectIsValid = false
            case .failure(.containsWhitespace):
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "project[\(index)].remote: SSH remote authority must not contain whitespace",
                    fix: "Use format: remote = \"ssh-remote+user@host\""
                ))
                projectIsValid = false
            case .failure(.missingTarget):
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "project[\(index)].remote: SSH remote authority is missing host (expected ssh-remote+user@host)",
                    fix: "Use format: remote = \"ssh-remote+user@host\""
                ))
                projectIsValid = false
            case .failure(.targetStartsWithDash):
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "project[\(index)].remote: SSH remote authority must not start with '-'",
                    fix: "Use format: remote = \"ssh-remote+user@host\""
                ))
                projectIsValid = false
            }
        }

        if normalizedRemote != nil {
            // SSH + Agent Layer mutual exclusion
            if useAgentLayer {
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "project[\(index)]: Agent Layer is not supported with SSH projects",
                    fix: "Set useAgentLayer = false for this project (SSH projects cannot use Agent Layer)."
                ))
                projectIsValid = false
            }

            // Remote path must be absolute
            if let path, !path.hasPrefix("/") {
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "project[\(index)].path: remote path must be an absolute path (starting with /)",
                    fix: "Use a remote absolute path, e.g. /Users/you/src/project"
                ))
                projectIsValid = false
            }
        } else if let path {
            if path.hasPrefix("ssh-remote+") {
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "project[\(index)].path: legacy SSH path format is not supported",
                    detail: "Found an ssh-remote+ prefix in project.path but project.remote is not set.",
                    fix: "Use remote = \"ssh-remote+user@host\" and path = \"/remote/absolute/path\""
                ))
                projectIsValid = false
            } else if !path.hasPrefix("/") {
                // Local path must be absolute
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "project[\(index)].path: local path must be an absolute path (starting with /)",
                    fix: "Use an absolute path, e.g. /Users/you/src/project"
                ))
                projectIsValid = false
            }
        }

        // Chrome tab fields (optional, default empty)
        let chromePinnedTabs = readOptionalStringArray(
            from: table, key: "chromePinnedTabs",
            label: "project[\(index)].chromePinnedTabs", findings: &findings
        )
        if !chromePinnedTabs.isEmpty {
            if !validateURLs(chromePinnedTabs, label: "project[\(index)].chromePinnedTabs", findings: &findings) {
                projectIsValid = false
            }
        }

        let chromeDefaultTabs = readOptionalStringArray(
            from: table, key: "chromeDefaultTabs",
            label: "project[\(index)].chromeDefaultTabs", findings: &findings
        )
        if !chromeDefaultTabs.isEmpty {
            if !validateURLs(chromeDefaultTabs, label: "project[\(index)].chromeDefaultTabs", findings: &findings) {
                projectIsValid = false
            }
        }

        guard let name, let path, let normalizedColor, let derivedId, projectIsValid else {
            return ProjectOutcome(config: nil)
        }

        let projectConfig = ProjectConfig(
            id: derivedId,
            name: name,
            remote: normalizedRemote,
            path: path,
            color: normalizedColor,
            useAgentLayer: useAgentLayer,
            chromePinnedTabs: chromePinnedTabs,
            chromeDefaultTabs: chromeDefaultTabs
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

    /// Reads an optional non-empty string value. Returns nil when key is absent.
    /// Records a failure if the value is present but not a string or empty.
    private static func readOptionalNonEmptyString(
        from table: TOMLTable,
        key: String,
        label: String,
        findings: inout [ConfigFinding]
    ) -> String? {
        guard table.contains(key: key) else {
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

    /// Reads an optional string array value. Returns empty array when key is absent.
    /// Records a failure if any element is not a string.
    private static func readOptionalStringArray(
        from table: TOMLTable,
        key: String,
        label: String,
        findings: inout [ConfigFinding]
    ) -> [String] {
        guard table.contains(key: key) else {
            return []
        }

        guard let array = try? table.array(forKey: key) else {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "\(label) must be an array of strings",
                fix: "Set \(label) to an array of strings, e.g. [\"https://example.com\"]."
            ))
            return []
        }

        var result: [String] = []
        for i in 0..<array.count {
            guard let value = try? array.string(atIndex: i) else {
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "\(label)[\(i)] must be a string",
                    fix: "Ensure all elements in \(label) are strings."
                ))
                continue
            }
            result.append(value)
        }
        return result
    }

    /// Reads an optional boolean value. Returns default when key is absent.
    private static func readOptionalBool(
        from table: TOMLTable,
        key: String,
        defaultValue: Bool,
        label: String,
        findings: inout [ConfigFinding]
    ) -> Bool {
        guard table.contains(key: key) else {
            return defaultValue
        }

        guard let value = try? table.bool(forKey: key) else {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "\(label) must be a boolean",
                fix: "Set \(label) to true or false."
            ))
            return defaultValue
        }

        return value
    }

    /// Validates that all URLs in the array start with http:// or https://.
    /// Returns true if all valid, false if any invalid (adds findings for invalids).
    @discardableResult
    private static func validateURLs(
        _ urls: [String],
        label: String,
        findings: inout [ConfigFinding]
    ) -> Bool {
        var allValid = true
        for (index, url) in urls.enumerated() {
            let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.hasPrefix("http://") && !trimmed.hasPrefix("https://") {
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "\(label)[\(index)] is not a valid URL",
                    detail: "Got \"\(trimmed)\". URLs must start with http:// or https://.",
                    fix: "Use a full URL starting with http:// or https://."
                ))
                allValid = false
            }
        }
        return allValid
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
        loadDefault(dataStore: DataPaths.default())
    }

    static func loadDefault(dataStore: DataPaths) -> Result<Config, ConfigLoadError> {
        let path = dataStore.configFile.path

        // Use ConfigLoader as single source of truth
        switch ConfigLoader.loadDefault(dataStore: dataStore) {
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
