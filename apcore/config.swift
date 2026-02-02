import Foundation
import TOMLDecoder

// MARK: - Config Models

/// Supported IDE identifiers for AgentPanel.
public enum IdeKind: String, CaseIterable, Equatable, Sendable {
    case vscode
    case antigravity
}

/// Full parsed configuration for AgentPanel.
public struct Config: Equatable, Sendable {
    public let global: GlobalConfig
    public let ide: IdeConfig
    public let projects: [ProjectConfig]

    public init(global: GlobalConfig, ide: IdeConfig, projects: [ProjectConfig]) {
        self.global = global
        self.ide = ide
        self.projects = projects
    }
}

/// Global configuration values.
public struct GlobalConfig: Equatable, Sendable {
    public let defaultIde: IdeKind
    public let globalChromeUrls: [String]

    public init(defaultIde: IdeKind, globalChromeUrls: [String]) {
        self.defaultIde = defaultIde
        self.globalChromeUrls = globalChromeUrls
    }
}

/// IDE configuration values for supported IDEs.
public struct IdeConfig: Equatable, Sendable {
    public let vscode: IdeAppConfig?
    public let antigravity: IdeAppConfig?

    public init(vscode: IdeAppConfig?, antigravity: IdeAppConfig?) {
        self.vscode = vscode
        self.antigravity = antigravity
    }
}

/// IDE app configuration details.
public struct IdeAppConfig: Equatable, Sendable {
    public let appPath: String?
    public let bundleId: String?

    public init(appPath: String?, bundleId: String?) {
        self.appPath = appPath
        self.bundleId = bundleId
    }
}

/// Project-level configuration values.
public struct ProjectConfig: Equatable, Sendable {
    public let id: String
    public let name: String
    public let path: String
    public let colorHex: String
    public let ide: IdeKind
    public let chromeUrls: [String]
    public let chromeProfileDirectory: String?

    public init(
        id: String,
        name: String,
        path: String,
        colorHex: String,
        ide: IdeKind,
        chromeUrls: [String],
        chromeProfileDirectory: String?
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.colorHex = colorHex
        self.ide = ide
        self.chromeUrls = chromeUrls
        self.chromeProfileDirectory = chromeProfileDirectory
    }
}

// MARK: - Config Loading

/// Errors emitted by config loading operations.
public struct ConfigError: Error, Equatable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

/// Result of loading and parsing configuration.
public struct ConfigLoadResult: Equatable, Sendable {
    /// Parsed config when successful.
    public let config: Config?
    /// Findings from parsing (warnings and errors).
    public let findings: [ConfigFinding]
    /// IDE kinds actually used by projects.
    public let effectiveIdeKinds: Set<IdeKind>
    /// IDE config section (for app discovery).
    public let ideConfig: IdeConfig
    /// Parsed projects (may be partial on error).
    public let projects: [ProjectConfig]

    public init(
        config: Config?,
        findings: [ConfigFinding],
        effectiveIdeKinds: Set<IdeKind>,
        ideConfig: IdeConfig,
        projects: [ProjectConfig]
    ) {
        self.config = config
        self.findings = findings
        self.effectiveIdeKinds = effectiveIdeKinds
        self.ideConfig = ideConfig
        self.projects = projects
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
    public let detail: String?
    public let fix: String?

    public init(severity: ConfigFindingSeverity, title: String, detail: String? = nil, fix: String? = nil) {
        self.severity = severity
        self.title = title
        self.detail = detail
        self.fix = fix
    }
}

/// Loads and parses the AgentPanel configuration file.
public struct ConfigLoader {
    private static let configRelativePath = ".config/agent-panel/config.toml"

    /// Loads and parses the default config file.
    public static func loadDefault() -> Result<ConfigLoadResult, ConfigError> {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(configRelativePath)
        return load(from: url)
    }

    /// Loads and parses a config file at the given URL.
    public static func load(from url: URL) -> Result<ConfigLoadResult, ConfigError> {
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else {
            return .failure(ConfigError(message: "Config file not found at \(path)"))
        }

        let raw: String
        do {
            raw = try String(contentsOf: url, encoding: .utf8)
        } catch {
            return .failure(ConfigError(message: "Failed to read config at \(path): \(error.localizedDescription)"))
        }

        return .success(ConfigParser.parse(toml: raw))
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
                effectiveIdeKinds: [],
                ideConfig: IdeConfig(vscode: nil, antigravity: nil),
                projects: []
            )
        }
    }

    private static func parse(table: TOMLTable) -> ConfigLoadResult {
        var findings: [ConfigFinding] = []
        var effectiveIdeKinds = Set<IdeKind>()

        let globalOutcome = parseGlobal(table: table, findings: &findings)
        let ideOutcome = parseIdeConfig(table: table, findings: &findings)
        let projectOutcomes = parseProjects(
            table: table,
            defaultIde: globalOutcome.defaultIde,
            findings: &findings
        )

        for outcome in projectOutcomes {
            if let ide = outcome.effectiveIde {
                effectiveIdeKinds.insert(ide)
            }
        }

        let validationFailed = findings.contains { $0.severity == .fail }
        let parsedProjects = projectOutcomes.compactMap { $0.config }

        let config: Config?
        if validationFailed {
            config = nil
        } else if let global = globalOutcome.config {
            config = Config(global: global, ide: ideOutcome, projects: parsedProjects)
        } else {
            config = nil
            findings.append(ConfigFinding(
                severity: .fail,
                title: "Config defaults incomplete",
                detail: "Global defaults could not be resolved.",
                fix: "Ensure global.defaultIde is valid."
            ))
        }

        return ConfigLoadResult(
            config: config,
            findings: findings,
            effectiveIdeKinds: effectiveIdeKinds,
            ideConfig: ideOutcome,
            projects: parsedProjects
        )
    }

    // MARK: - Global Parsing

    private struct GlobalOutcome {
        let config: GlobalConfig?
        let defaultIde: IdeKind?
    }

    private static func parseGlobal(table: TOMLTable, findings: inout [ConfigFinding]) -> GlobalOutcome {
        var defaultIde: IdeKind?
        var globalChromeUrls: [String]?

        if table.contains(key: "global") {
            guard let globalTable = try? table.table(forKey: "global") else {
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "global must be a table",
                    fix: "Replace global with a TOML table: [global]"
                ))
                return GlobalOutcome(config: nil, defaultIde: nil)
            }

            if let rawDefaultIde = try? globalTable.string(forKey: "defaultIde") {
                if let ide = IdeKind(rawValue: rawDefaultIde) {
                    defaultIde = ide
                } else {
                    findings.append(ConfigFinding(
                        severity: .fail,
                        title: "global.defaultIde is invalid",
                        detail: "Value must be one of: vscode, antigravity.",
                        fix: "Set global.defaultIde to \"vscode\" or \"antigravity\"."
                    ))
                }
            } else if !globalTable.contains(key: "defaultIde") {
                defaultIde = .vscode
                findings.append(ConfigFinding(
                    severity: .warn,
                    title: "Default applied: global.defaultIde = \"vscode\"",
                    fix: "Add global.defaultIde to config.toml to make the default explicit."
                ))
            }

            if let array = try? globalTable.array(forKey: "globalChromeUrls") {
                var urls: [String] = []
                for i in 0..<array.count {
                    if let url = try? array.string(atIndex: i) {
                        urls.append(url)
                    }
                }
                globalChromeUrls = urls
            } else if !globalTable.contains(key: "globalChromeUrls") {
                globalChromeUrls = []
                findings.append(ConfigFinding(
                    severity: .warn,
                    title: "Default applied: global.globalChromeUrls = []",
                    fix: "Add global.globalChromeUrls to config.toml to make the default explicit."
                ))
            }
        } else {
            defaultIde = .vscode
            globalChromeUrls = []
            findings.append(ConfigFinding(
                severity: .warn,
                title: "Default applied: global.defaultIde = \"vscode\"",
                fix: "Add [global] with defaultIde to config.toml."
            ))
            findings.append(ConfigFinding(
                severity: .warn,
                title: "Default applied: global.globalChromeUrls = []",
                fix: "Add [global] with globalChromeUrls to config.toml."
            ))
        }

        let config: GlobalConfig?
        if let defaultIde, let globalChromeUrls {
            config = GlobalConfig(defaultIde: defaultIde, globalChromeUrls: globalChromeUrls)
        } else {
            config = nil
        }

        return GlobalOutcome(config: config, defaultIde: defaultIde)
    }

    // MARK: - IDE Config Parsing

    private static func parseIdeConfig(table: TOMLTable, findings: inout [ConfigFinding]) -> IdeConfig {
        var vscodeConfig: IdeAppConfig?
        var antigravityConfig: IdeAppConfig?

        if table.contains(key: "ide") {
            guard let ideTable = try? table.table(forKey: "ide") else {
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "ide must be a table",
                    fix: "Replace ide with a TOML table: [ide]"
                ))
                return IdeConfig(vscode: nil, antigravity: nil)
            }

            if ideTable.contains(key: "vscode") {
                vscodeConfig = parseIdeAppConfig(parent: ideTable, key: "vscode", prefix: "ide.vscode", findings: &findings)
            }

            if ideTable.contains(key: "antigravity") {
                antigravityConfig = parseIdeAppConfig(parent: ideTable, key: "antigravity", prefix: "ide.antigravity", findings: &findings)
            }
        }

        return IdeConfig(vscode: vscodeConfig, antigravity: antigravityConfig)
    }

    private static func parseIdeAppConfig(
        parent: TOMLTable,
        key: String,
        prefix: String,
        findings: inout [ConfigFinding]
    ) -> IdeAppConfig? {
        guard let appTable = try? parent.table(forKey: key) else {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "\(prefix) must be a table",
                fix: "Replace \(prefix) with a TOML table."
            ))
            return nil
        }

        let appPath = try? appTable.string(forKey: "appPath")
        let bundleId = try? appTable.string(forKey: "bundleId")

        return IdeAppConfig(appPath: appPath, bundleId: bundleId)
    }

    // MARK: - Project Parsing

    private struct ProjectOutcome {
        let config: ProjectConfig?
        let effectiveIde: IdeKind?
    }

    private static func parseProjects(
        table: TOMLTable,
        defaultIde: IdeKind?,
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
                outcomes.append(ProjectOutcome(config: nil, effectiveIde: nil))
                continue
            }

            let outcome = parseProject(
                table: projectTable,
                index: index,
                defaultIde: defaultIde,
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
        defaultIde: IdeKind?,
        seenIds: inout [String: Int],
        findings: inout [ConfigFinding]
    ) -> ProjectOutcome {
        var projectIsValid = true

        // Required fields
        let id = try? table.string(forKey: "id")
        let name = try? table.string(forKey: "name")
        let path = try? table.string(forKey: "path")
        let colorHex = try? table.string(forKey: "colorHex")

        // ID validation
        if let id {
            if id == "inbox" {
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "project[\(index)].id is reserved",
                    detail: "The id 'inbox' is reserved.",
                    fix: "Choose a different project id."
                ))
                projectIsValid = false
            } else if !isValidProjectId(id) {
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "project[\(index)].id is invalid",
                    detail: "Project ids must match ^[a-z0-9-]+$.",
                    fix: "Use lowercase letters, numbers, and hyphens only."
                ))
                projectIsValid = false
            } else if let existingIndex = seenIds[id] {
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "Duplicate project.id: \(id)",
                    detail: "Found at indexes \(existingIndex) and \(index).",
                    fix: "Ensure each project.id is unique."
                ))
                projectIsValid = false
            } else {
                seenIds[id] = index
            }
        } else {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "project[\(index)].id is missing",
                fix: "Set project.id to a unique value."
            ))
            projectIsValid = false
        }

        // Name validation
        if let name {
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "project[\(index)].name is empty",
                    fix: "Set project.name to a non-empty string."
                ))
                projectIsValid = false
            }
        } else {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "project[\(index)].name is missing",
                fix: "Set project.name to a non-empty string."
            ))
            projectIsValid = false
        }

        // Path validation
        if let path {
            if path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "project[\(index)].path is empty",
                    fix: "Set project.path to an existing directory."
                ))
                projectIsValid = false
            }
        } else {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "project[\(index)].path is missing",
                fix: "Set project.path to an existing directory."
            ))
            projectIsValid = false
        }

        // Color validation
        if let colorHex {
            if !isValidColorHex(colorHex) {
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "project[\(index)].colorHex is invalid",
                    detail: "Color must match #RRGGBB.",
                    fix: "Set project.colorHex to a valid hex color like #7C3AED."
                ))
                projectIsValid = false
            }
        } else {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "project[\(index)].colorHex is missing",
                fix: "Set project.colorHex to a valid hex color like #7C3AED."
            ))
            projectIsValid = false
        }

        // IDE resolution
        var resolvedIde: IdeKind?
        if let rawIde = try? table.string(forKey: "ide") {
            if let ide = IdeKind(rawValue: rawIde) {
                resolvedIde = ide
            } else {
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "project[\(index)].ide is invalid",
                    detail: "Value must be one of: vscode, antigravity.",
                    fix: "Set project.ide to \"vscode\" or \"antigravity\"."
                ))
                projectIsValid = false
            }
        } else if let defaultIde {
            resolvedIde = defaultIde
            findings.append(ConfigFinding(
                severity: .warn,
                title: "Default applied: project[\(index)].ide = \"\(defaultIde.rawValue)\"",
                fix: "Add project.ide to config.toml to make the default explicit."
            ))
        } else {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "project[\(index)].ide is unresolved",
                fix: "Set project.ide explicitly or ensure global.defaultIde is valid."
            ))
            projectIsValid = false
        }

        // Chrome URLs
        var chromeUrls: [String] = []
        if let array = try? table.array(forKey: "chromeUrls") {
            for i in 0..<array.count {
                if let url = try? array.string(atIndex: i) {
                    chromeUrls.append(url)
                }
            }
        } else if !table.contains(key: "chromeUrls") {
            findings.append(ConfigFinding(
                severity: .warn,
                title: "Default applied: project[\(index)].chromeUrls = []",
                fix: "Add project.chromeUrls to config.toml if you want to override."
            ))
        }

        // Chrome profile directory
        var chromeProfileDirectory: String?
        if let dir = try? table.string(forKey: "chromeProfileDirectory") {
            if dir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "project[\(index)].chromeProfileDirectory is empty",
                    fix: "Set project.chromeProfileDirectory to a non-empty value."
                ))
                projectIsValid = false
            } else {
                chromeProfileDirectory = dir
            }
        }

        // Build project config if valid
        if projectIsValid,
           let id,
           let name,
           let path,
           let colorHex,
           let resolvedIde {
            let projectConfig = ProjectConfig(
                id: id,
                name: name,
                path: path,
                colorHex: colorHex,
                ide: resolvedIde,
                chromeUrls: chromeUrls,
                chromeProfileDirectory: chromeProfileDirectory
            )
            return ProjectOutcome(config: projectConfig, effectiveIde: resolvedIde)
        }

        return ProjectOutcome(config: nil, effectiveIde: resolvedIde)
    }

    // MARK: - Validation Helpers

    private static func isValidProjectId(_ value: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        return !value.isEmpty && value.rangeOfCharacter(from: allowed.inverted) == nil
    }

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
}
